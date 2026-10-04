"""python -m elias <command>  —  run `python -m elias -h` for the list."""
import argparse
import json
import shutil
import sys
from datetime import date

from elias import analytics, calendar, captions, experiments, naming, prompts, publisher, qa, queue, store


def _print(obj):
    print(json.dumps(obj, indent=2, ensure_ascii=False) if not isinstance(obj, str) else obj)


def cmd_init(a):
    dst = store.WORKSPACE / "settings.json"
    if dst.exists():
        print(f"{dst} already exists")
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(store.CONFIG / "settings.example.json", dst)
    print(f"created {dst}. Set start_date, timezone, post_time_local and approvers.")


def cmd_validate(a):
    errors, warnings = calendar.validate()
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"ERROR: {e}")
    print(f"{len(errors)} errors, {len(warnings)} warnings")
    return 1 if errors else 0


def cmd_balance(a):
    r = calendar.balance_report()
    print("Buckets (90 days):")
    for b, v in r["buckets"].items():
        print(f"  {b:<22} {v['days']:>3} days  {v['share']:>6.1%}  (target {v['target_days']})")
    print(f"Jacket: {len(r['jacket_days'])}/{r['in_frame']} in-frame posts = {r['jacket_share']:.1%}; "
          f"per week {r['jacket_per_week']}; longest run {r['jacket_longest_run']}")
    print(f"Motorcycle: {len(r['moto_days'])}/90 = {r['moto_share']:.1%}; per week {r['moto_per_week']}")


def _day_summary(d):
    s = store.settings()
    return (f"Day {d['day']} ({calendar.date_for(d['day'], s)}) · Phase {d['phase']} {d['phase_name']} · "
            f"{d['format'].upper()} · {d['pillar']} · status {d['status']}\n"
            f"  {d['concept']}\n"
            f"  outfit {d['outfit']} · camera {d['camera']} · face {d['face']} · girlfriend {d['girlfriend']}"
            f"{' · motorcycle' if d['motorcycle'] else ''}{' · hook ' + d['hook'] if d.get('hook') else ''}"
            f"{' · callback ' + d['callback'] if d.get('callback') else ''}")


def cmd_calendar(a):
    for d in calendar.days():
        if a.phase and d["phase"] != a.phase:
            continue
        if a.status and d["status"] != a.status:
            continue
        print(f"D{d['day']:02d} P{d['phase']} {d['format']:<8} {d['pillar']:<8} {d['status']:<13} {d['concept']}")


def cmd_day(a):
    d = calendar.get(a.day)
    print(_day_summary(d))
    for i, b in enumerate(d["beats"], 1):
        print(f"  beat {i}: {b}")


def cmd_today(a):
    on = date.fromisoformat(a.date) if a.date else date.today()
    n = calendar.day_for(on)
    print(f"# {on} → Day {n}\n")
    if not 1 <= n <= len(calendar.days()):
        print("Outside the 90-day calendar.")
        return
    d = calendar.get(n)
    print(_day_summary(d))
    print("\nToday's production checklist (docs/production_workflow.md):")
    steps = [
        f"python -m elias prompts {n} > workspace/prompts/day_{n:03d}.json  # generate with reference images attached",
        "Generate 3-6 candidates per shot; keep the best; name files with the printed asset names",
        f"python -m elias qa record --asset <name> --day {n} --fail <ids or nothing>   # every final asset",
        f"python -m elias queue build {n}   # caption, hashtags, alt text, schedule",
        "Upload finals to your media host; python -m elias queue set-url D%03d <asset> <https-url>" % n,
        "python -m elias queue ready D%03d" % n,
        "HUMAN: review in-app preview; python -m elias queue approve D%03d --by <you> --ai-label" % n,
        "python -m elias publish D%03d --live   (or publish manually in the app)" % n,
        "Stories: 2-4 casual frames (python -m elias stories %d)" % n,
        "24-48h later: python -m elias analytics add %d ..." % n,
    ]
    for i, s in enumerate(steps, 1):
        print(f"  {i:>2}. {s}")
    t = n + 1
    if t <= len(calendar.days()):
        print("\nTomorrow:\n" + _day_summary(calendar.get(t)))


def cmd_prompts(a):
    _print(prompts.build(calendar.get(a.day)))


def cmd_refs(a):
    _print(prompts.reference_sheet())


def cmd_captions(a):
    d = calendar.get(a.day)
    _print({**captions.suggest(d, a.n), "hashtags": captions.hashtags(d), "alt_text": captions.alt_text(d)})


def cmd_lint(a):
    issues = captions.lint(a.text)
    print("OK" if not issues else "\n".join(issues))
    return 1 if issues else 0


def cmd_reply(a):
    opts, rules = captions.reply_options(a.category)
    print("\n".join(opts) if opts else "(do not reply)")
    print("\nRules:\n- " + "\n- ".join(rules))


def cmd_stories(a):
    d = calendar.get(a.day)
    s = store.load(store.DATA / "stories.json")
    _print({"phase": d["phase"], "ideas": s["phases"][str(d["phase"])], "general": s["general"]})


def cmd_name(a):
    if a.ref:
        print(naming.ref_name(a.ref, a.n or 1, a.version, a.ext or "png"))
        return
    d = calendar.get(a.day)
    fmt = a.format or d["format"]
    print(naming.asset_name(d["day"], fmt, d["pillar"], a.slug or d["slug"], a.version, a.slide, a.ext or "jpg"))


def cmd_check_assets(a):
    bad = 0
    for p in sorted(store.ASSETS.rglob("*")):
        if p.is_file() and p.name not in (".gitkeep", "README.md"):
            if naming.parse(p.name) is None:
                print(f"bad name: {p.relative_to(store.ROOT)}")
                bad += 1
    print(f"{bad} badly named files")
    return 1 if bad else 0


def cmd_qa(a):
    if a.qa_cmd == "criteria":
        for k, v in qa.CRITERIA.items():
            print(f"{k:>2}. {v}{'  (hard: 1 fail = regenerate)' if k in qa.HARD else ''}")
    elif a.qa_cmd == "record":
        e = qa.record(a.asset, a.day, a.fail or [], a.reviewer, a.notes or "")
        print(f"{e['asset']}: {e['verdict'].upper()}" + (f"  failed: {', '.join(e['failed_names'])}" if e["failed"] else ""))
        return 0 if e["verdict"] == "pass" else 2
    elif a.qa_cmd == "show":
        _print(qa.latest(a.asset) or "no QA record")


def cmd_queue(a):
    c = a.queue_cmd
    if c == "list":
        for it in queue.items(a.status):
            print(f"{it['id']:<10} {it['media_type']:<9} {it['status']:<9} {it['scheduled_for']}  {it['caption']!r}")
    elif c == "show":
        it = queue.get(a.id)
        _print({**it, "full_caption": queue.full_caption(it), "readiness": queue.readiness(it)})
    elif c == "build":
        _print(queue.build(a.day))
    elif c == "add-story":
        _print(queue.add_story(a.day, a.asset, a.url, a.n))
    elif c == "set-url":
        queue.set_url(a.id, a.asset, a.url)
        print("ok")
    elif c == "set-caption":
        queue.set_caption(a.id, a.caption, force=a.force)
        print("ok")
    elif c == "set-hashtags":
        queue.set_hashtags(a.id, a.tags)
        print("ok")
    elif c == "ready":
        queue.mark_ready(a.id)
        print(f"{a.id} ready for human approval")
    elif c == "approve":
        queue.approve(a.id, a.by, a.ai_label)
        print(f"{a.id} approved by {a.by}")
    elif c == "reject":
        queue.reject(a.id, a.by, a.reason)
        print(f"{a.id} back to draft")


def cmd_publish(a):
    ids = [it["id"] for it in publisher.due()] if a.id == "due" else [a.id]
    if not ids:
        print("nothing approved and due")
    for i in ids:
        _print(publisher.publish(i, live=a.live, ignore_schedule=a.now))
    if not a.live:
        print("\n(dry run — add --live to publish through the Instagram API)")


def cmd_analytics(a):
    if a.an_cmd == "add":
        metrics = dict(kv.split("=", 1) for kv in a.metrics)
        _print(analytics.upsert_post(a.day, **metrics))
    elif a.an_cmd == "account":
        metrics = dict(kv.split("=", 1) for kv in a.metrics)
        _print(analytics.upsert_account(a.date, **metrics))
    elif a.an_cmd == "fetch":
        it = queue.get(f"D{a.day:03d}")
        if not it.get("published"):
            raise SystemExit("not published yet")
        client = publisher.GraphClient.from_settings()
        _print(analytics.fetch(a.day, client, it["published"]["media_id"], it["media_type"]))
    elif a.an_cmd == "report":
        print(analytics.report())


def cmd_exp(a):
    if a.exp_cmd == "plan":
        _print(experiments.plan(a.variable, a.week, a.metric, a.hypothesis or ""))
    elif a.exp_cmd == "evaluate":
        _print(experiments.evaluate(a.id))
    elif a.exp_cmd == "list":
        for e in experiments.all_experiments():
            r = e["result"] or {}
            print(f"{e['id']} week {e['week']} {e['variable']:<22} A{e['arm_a_days']} B{e['arm_b_days']} → {r.get('winner', '—')} ({r.get('confidence', 'pending')})")
    elif a.exp_cmd == "variables":
        print("\n".join(experiments.VARIABLES))


def build_parser():
    p = argparse.ArgumentParser(prog="python -m elias", description="Elias Vane content operations")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("init", help="create workspace/settings.json").set_defaults(fn=cmd_init)
    sub.add_parser("validate", help="validate the calendar database").set_defaults(fn=cmd_validate)
    sub.add_parser("balance", help="content balance, jacket and motorcycle frequency").set_defaults(fn=cmd_balance)
    s = sub.add_parser("calendar", help="list the 90 days")
    s.add_argument("--phase", type=int)
    s.add_argument("--status")
    s.set_defaults(fn=cmd_calendar)
    s = sub.add_parser("day", help="show one day")
    s.add_argument("day", type=int)
    s.set_defaults(fn=cmd_day)
    s = sub.add_parser("today", help="what to produce today")
    s.add_argument("--date")
    s.set_defaults(fn=cmd_today)
    s = sub.add_parser("prompts", help="image/video prompts for a day")
    s.add_argument("day", type=int)
    s.set_defaults(fn=cmd_prompts)
    sub.add_parser("refs", help="reference-sheet prompts (Elias, girlfriend, motorcycle)").set_defaults(fn=cmd_refs)
    s = sub.add_parser("captions", help="caption/hashtag/alt-text suggestions")
    s.add_argument("day", type=int)
    s.add_argument("-n", type=int, default=3)
    s.set_defaults(fn=cmd_captions)
    s = sub.add_parser("lint", help="check a caption against the voice rules")
    s.add_argument("text")
    s.set_defaults(fn=cmd_lint)
    s = sub.add_parser("reply", help="in-character comment replies")
    s.add_argument("category")
    s.set_defaults(fn=cmd_reply)
    s = sub.add_parser("stories", help="story ideas for a day")
    s.add_argument("day", type=int)
    s.set_defaults(fn=cmd_stories)
    s = sub.add_parser("name", help="asset file name")
    s.add_argument("--day", type=int)
    s.add_argument("--ref", help="reference subject, e.g. ELIAS_FACE")
    s.add_argument("--n", type=int)
    s.add_argument("--format", choices=list(naming.FORMAT_CODES))
    s.add_argument("--slug")
    s.add_argument("--slide", type=int)
    s.add_argument("--version", type=int, default=1)
    s.add_argument("--ext")
    s.set_defaults(fn=cmd_name)
    sub.add_parser("check-assets", help="validate file names under assets/").set_defaults(fn=cmd_check_assets)

    s = sub.add_parser("qa", help="quality gate")
    qs = s.add_subparsers(dest="qa_cmd", required=True)
    qs.add_parser("criteria")
    r = qs.add_parser("record")
    r.add_argument("--asset", required=True)
    r.add_argument("--day", type=int, required=True)
    r.add_argument("--fail", type=int, nargs="*", help="criterion numbers that failed")
    r.add_argument("--reviewer", default="owner")
    r.add_argument("--notes")
    r = qs.add_parser("show")
    r.add_argument("asset")
    s.set_defaults(fn=cmd_qa)

    s = sub.add_parser("queue", help="publishing queue + approval")
    qs = s.add_subparsers(dest="queue_cmd", required=True)
    r = qs.add_parser("list")
    r.add_argument("--status")
    r = qs.add_parser("show")
    r.add_argument("id")
    r = qs.add_parser("build")
    r.add_argument("day", type=int)
    r = qs.add_parser("add-story")
    r.add_argument("day", type=int)
    r.add_argument("asset")
    r.add_argument("url")
    r.add_argument("--n", type=int, default=1)
    r = qs.add_parser("set-url")
    r.add_argument("id")
    r.add_argument("asset")
    r.add_argument("url")
    r = qs.add_parser("set-caption")
    r.add_argument("id")
    r.add_argument("caption")
    r.add_argument("--force", action="store_true")
    r = qs.add_parser("set-hashtags")
    r.add_argument("id")
    r.add_argument("tags", nargs="*")
    r = qs.add_parser("ready")
    r.add_argument("id")
    r = qs.add_parser("approve")
    r.add_argument("id")
    r.add_argument("--by", required=True)
    r.add_argument("--ai-label", action="store_true", help="confirm AI disclosure is in place")
    r = qs.add_parser("reject")
    r.add_argument("id")
    r.add_argument("--by", required=True)
    r.add_argument("--reason", required=True)
    s.set_defaults(fn=cmd_queue)

    s = sub.add_parser("publish", help="publish an approved item (dry run unless --live)")
    s.add_argument("id", help="queue id, or 'due' for everything approved and due")
    s.add_argument("--live", action="store_true")
    s.add_argument("--now", action="store_true", help="ignore scheduled time")
    s.set_defaults(fn=cmd_publish)

    s = sub.add_parser("analytics", help="metrics tracker")
    qs = s.add_subparsers(dest="an_cmd", required=True)
    r = qs.add_parser("add", help="e.g. analytics add 9 views=12000 follows=40 profile_visits=600")
    r.add_argument("day", type=int)
    r.add_argument("metrics", nargs="+")
    r = qs.add_parser("account", help="e.g. analytics account 2026-10-12 followers=120 story_views=80")
    r.add_argument("date")
    r.add_argument("metrics", nargs="+")
    r = qs.add_parser("fetch", help="pull insights for a published day via the API")
    r.add_argument("day", type=int)
    qs.add_parser("report")
    s.set_defaults(fn=cmd_analytics)

    s = sub.add_parser("exp", help="one-variable experiments")
    qs = s.add_subparsers(dest="exp_cmd", required=True)
    r = qs.add_parser("plan")
    r.add_argument("variable")
    r.add_argument("--week", type=int, required=True)
    r.add_argument("--metric", default=experiments.DEFAULT_METRIC)
    r.add_argument("--hypothesis")
    r = qs.add_parser("evaluate")
    r.add_argument("id")
    qs.add_parser("list")
    qs.add_parser("variables")
    s.set_defaults(fn=cmd_exp)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        return args.fn(args) or 0
    except (queue.QueueError, publisher.PublishError, KeyError, ValueError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
