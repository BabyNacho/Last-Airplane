import io
import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        from elias import store
        self._ws = store.WORKSPACE
        store.WORKSPACE = Path(self.tmp.name)
        # calendar statuses are written by the queue; work on a copy
        self._cal = store.DATA / "calendar.json"
        self._cal_backup = self._cal.read_text(encoding="utf-8")
        settings = json.loads((store.CONFIG / "settings.example.json").read_text())
        settings["start_date"] = "2026-01-01"
        store.save(store.WORKSPACE / "settings.json", settings)

    def tearDown(self):
        from elias import store
        self._cal.write_text(self._cal_backup, encoding="utf-8")
        store.WORKSPACE = self._ws
        self.tmp.cleanup()


class CalendarTests(Base):
    def test_calendar_valid(self):
        from elias import calendar
        errors, warnings = calendar.validate()
        self.assertEqual(errors, [])
        self.assertEqual(len(calendar.days()), 90)

    def test_dates(self):
        from elias import calendar
        self.assertEqual(calendar.date_for(1).isoformat(), "2026-01-01")
        self.assertEqual(calendar.day_for(datetime(2026, 1, 10).date()), 10)


class NamingTests(unittest.TestCase):
    def test_roundtrip(self):
        from elias import naming
        n = naming.asset_name(9, "reel", "MOTO", "gloves-ignition", version=2, ext="mp4")
        self.assertEqual(n, "EV_D009_REEL_MOTO_gloves-ignition_v02.mp4")
        self.assertEqual(naming.parse(n)["day"], 9)
        s = naming.asset_name(22, "carousel", "ROMANCE", "quiet-day", slide=3)
        self.assertEqual(naming.parse(s)["slide"], 3)
        self.assertEqual(naming.parse(naming.ref_name("ELIAS_FACE", 3))["ref"], "ELIAS_FACE")
        self.assertIsNone(naming.parse("IMG_1234.jpg"))


class PromptTests(Base):
    def test_every_day_builds_with_identity_lock(self):
        from elias import calendar, prompts, store
        lock = store.character()["elias"]["short_lock"]
        for d in calendar.days():
            plan = prompts.build(d)
            self.assertEqual(len(plan["shots"]), len(d["beats"]))
            for shot in plan["shots"]:
                self.assertIn("photorealistic", shot["image_prompt"])
                if d["face"] != "none":
                    self.assertTrue(lock in shot["image_prompt"] or store.character()["elias"]["face"] in shot["image_prompt"])
            if d["format"] == "reel":
                self.assertIn("video", plan["shots"][0])
                self.assertLessEqual(plan["edit"]["target_length_s"], 20)

    def test_girlfriend_never_fully_revealed(self):
        from elias import calendar
        self.assertFalse(any(d["girlfriend"] == "full" for d in calendar.days()))

    def test_reference_sheet_size(self):
        from elias import prompts
        refs = prompts.reference_sheet()
        self.assertGreaterEqual(sum(r["asset"].startswith("EV_REF_ELIAS") for r in refs), 10)


class CaptionTests(Base):
    def test_lint(self):
        from elias import captions
        self.assertEqual(captions.lint("Quiet nights."), [])
        self.assertEqual(captions.lint("Parking garage. Looking around."), [])  # no false 'king' hit
        self.assertTrue(captions.lint("Alpha energy. King mode. Follow me."))
        self.assertTrue(captions.lint("Wow!"))

    def test_bank_passes_own_linter(self):
        from elias import captions
        b = captions.bank()
        for style in b["styles"].values():
            for c in style:
                self.assertEqual(captions.lint(c), [], c)

    def test_hashtags_limits(self):
        from elias import calendar, captions
        for d in calendar.days():
            self.assertLessEqual(len(captions.hashtags(d)), 5)


class QATests(Base):
    def test_verdicts(self):
        from elias import qa
        self.assertEqual(qa.verdict([]), "pass")
        self.assertEqual(qa.verdict([14]), "fix")
        self.assertEqual(qa.verdict([5, 6]), "regenerate")
        self.assertEqual(qa.verdict([3]), "regenerate")  # hands are a hard fail


class FakeGraph:
    def __init__(self):
        self.calls = []
        self.n = 0

    def __call__(self, req):
        self.calls.append((req.get_method(), req.full_url, req.data))
        self.n += 1
        url = req.full_url
        if "fields=status_code" in url:
            body = {"status_code": "FINISHED"}
        elif "fields=permalink" in url:
            body = {"permalink": "https://www.instagram.com/p/x/"}
        else:
            body = {"id": f"id{self.n}"}

        class R(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False
        return R(json.dumps(body).encode())


class QueueAndPublishTests(Base):
    def _ready_item(self, day):
        from elias import qa, queue
        item = queue.build(day)
        for a in item["assets"]:
            qa.record(a["name"], day, [], "owner")
            queue.set_url(item["id"], a["name"], f"https://cdn.example.com/{a['name']}")
        queue.mark_ready(item["id"])
        return item["id"]

    def test_cannot_ready_without_qa(self):
        from elias import queue
        item = queue.build(1)
        queue.set_url(item["id"], item["assets"][0]["name"], "https://cdn.example.com/a.jpg")
        with self.assertRaises(queue.QueueError):
            queue.mark_ready(item["id"])

    def test_approval_requires_ai_label_and_approver(self):
        from elias import queue
        i = self._ready_item(1)
        with self.assertRaises(queue.QueueError):
            queue.approve(i, "owner", ai_label_confirmed=False)
        with self.assertRaises(queue.QueueError):
            queue.approve(i, "stranger", ai_label_confirmed=True)
        queue.approve(i, "owner", ai_label_confirmed=True)
        self.assertTrue(queue.approval_valid(queue.get(i)))

    def test_edit_after_approval_revokes_it(self):
        from elias import publisher, queue
        i = self._ready_item(1)
        queue.approve(i, "owner", True)
        queue.set_caption(i, "Quiet.")
        self.assertEqual(queue.get(i)["status"], "draft")
        with self.assertRaises(publisher.PublishError):
            publisher.publish(i, ignore_schedule=True)

    def test_unapproved_never_publishes(self):
        from elias import publisher
        i = self._ready_item(1)
        with self.assertRaises(publisher.PublishError):
            publisher.publish(i, live=True, client=object(), ignore_schedule=True)

    def test_schedule_respected(self):
        from elias import publisher, queue
        i = self._ready_item(2)
        queue.approve(i, "owner", True)
        with self.assertRaises(publisher.PublishError):
            publisher.publish(i, now=datetime(2025, 12, 31))

    def test_live_carousel_call_sequence(self):
        from elias import calendar, publisher, queue
        i = self._ready_item(4)  # carousel, 3 slides
        queue.approve(i, "owner", True)
        fake = FakeGraph()
        client = publisher.GraphClient("https://graph.instagram.com", "v23.0", "TOKEN", "123", opener=fake, sleep=lambda s: None)
        res = publisher.publish(i, live=True, client=client, ignore_schedule=True)
        posts = [c for c in fake.calls if c[0] == "POST"]
        self.assertEqual(len(posts), 5)  # 3 children + parent + media_publish
        self.assertIn(b"is_carousel_item=true", posts[0][2])
        self.assertIn(b"media_type=CAROUSEL", posts[3][2])
        self.assertTrue(posts[4][1].endswith("/123/media_publish"))
        self.assertEqual(res["permalink"], "https://www.instagram.com/p/x/")
        self.assertEqual(queue.get(i)["status"], "published")
        self.assertEqual(calendar.get(4)["status"], "published")

    def test_reel_dry_run(self):
        from elias import publisher, queue
        i = self._ready_item(3)
        queue.approve(i, "owner", True)
        res = publisher.publish(i, ignore_schedule=True)
        self.assertTrue(res["dry_run"])
        self.assertEqual(res["calls"][0]["params"]["media_type"], "REELS")


class AnalyticsTests(Base):
    def test_rates_and_report(self):
        from elias import analytics, experiments
        analytics.upsert_post(1, views=10000, reach=8000, profile_visits=400, follows=40, saves=80, shares=40)
        analytics.upsert_post(2, views=10000, reach=8000, profile_visits=400, follows=10, saves=20, shares=10)
        rows = analytics.enriched_rows()
        self.assertAlmostEqual(rows[0]["follow_conversion"], 0.1)
        self.assertAlmostEqual(rows[0]["follows_per_1k_views"], 4.0)
        self.assertIn("follow_conversion", analytics.report())
        exp = experiments.plan("direct_vs_away", week=1)
        self.assertIn(1, exp["arm_a_days"])
        self.assertIn(2, exp["arm_b_days"])
        res = experiments.evaluate(exp["id"])["result"]
        self.assertEqual(res["winner"], "A")
        self.assertEqual(res["confidence"], "low")


if __name__ == "__main__":
    unittest.main()


class IdentityConstraintTests(Base):
    def _days(self):
        import copy
        from elias import calendar
        return copy.deepcopy(calendar.days())

    def test_current_calendar_meets_constraints(self):
        from elias import calendar
        self.assertEqual(calendar._identity_constraints(calendar.days()), [])
        r = calendar.balance_report()
        self.assertTrue(0.35 <= r["jacket_share"] <= 0.40)
        self.assertTrue(0.12 <= r["moto_share"] <= 0.18)

    def test_bucket_drift_detected(self):
        from elias import calendar
        ds = self._days()
        for d in ds:
            if d["pillar"] == "ROMANCE":
                d["pillar"] = "MOTO"
                d["motorcycle"] = True
        errs = calendar._identity_constraints(ds)
        self.assertTrue(any(e.startswith("balance: MOTO") for e in errs))
        self.assertTrue(any(e.startswith("motorcycle:") for e in errs))

    def test_jacket_rules_detected(self):
        from elias import calendar
        ds = self._days()
        for d in ds[:7]:
            if d["outfit"] in calendar.JACKET_OUTFITS:
                d["outfit"] = "W05"
        self.assertTrue(any("week 1" in e for e in calendar._identity_constraints(ds)))
        ds = self._days()
        for d in ds[:14]:
            d["outfit"] = "W04"
        errs = calendar._identity_constraints(ds)
        self.assertTrue(any("consecutive" in e for e in errs))

    def test_forbidden_terms_detected(self):
        from unittest import mock
        from elias import calendar
        ds = self._days()
        ds[2]["beats"] = ["he does a wheelie past the police"]
        with mock.patch.object(calendar, "days", return_value=ds):
            errors, _ = calendar.validate()
        self.assertTrue(any("wheelie" in e for e in errors))
        self.assertTrue(any("police" in e for e in errors))

    def test_jacket_lock_in_prompts(self):
        from elias import calendar, prompts
        plan = prompts.build(calendar.get(1))
        self.assertIn("asymmetric zip", plan["shots"][0]["image_prompt"])
        plan = prompts.build(calendar.get(9))
        self.assertIn("naked sport motorcycle", plan["shots"][0]["image_prompt"])
