"""The 90-day content database (data/calendar.json)."""
import re
from collections import Counter
from datetime import date, timedelta

from elias import store

FORMATS = {"photo", "reel", "carousel"}
PILLARS = {"STREET", "MOTO", "MODEL", "LUX", "ROMANCE", "DARK", "THOUGHTS", "TRAVEL", "EVERYDAY"}
STATUSES = {"planned", "in_production", "ready", "queued", "published", "skipped"}
GF_LEVELS = {"none", "absent", "hand", "silhouette", "back", "partial", "behind_camera"}
BUCKET_OF = {"MOTO": "MOTO", "STREET": "STREET", "MODEL": "MODEL",
             "LUX": "LUX+TRAVEL+EVERYDAY", "TRAVEL": "LUX+TRAVEL+EVERYDAY", "EVERYDAY": "LUX+TRAVEL+EVERYDAY",
             "ROMANCE": "ROMANCE", "DARK": "DARK+THOUGHTS", "THOUGHTS": "DARK+THOUGHTS"}
BUCKET_TOLERANCE_DAYS = 2
JACKET_OUTFITS = {"W04", "W08", "W11"}
JACKET_SHARE = (0.35, 0.40)      # of posts where Elias is in frame
JACKET_MIN_PER_WEEK = 2
JACKET_MAX_RUN = 3               # consecutive in-frame posts wearing the jacket
MOTO_SHARE = (0.12, 0.18)        # posts with the motorcycle in frame (~15 %)
MOTO_MAX_PER_WEEK = 3
# Bad boy = attitude, never criminality or unsafe riding. Checked against concept + beats.
FORBIDDEN_TERMS = ["fight", "fighting", "punch", "punching", "brawl", "blood", "bloody", "police", "cop", "cops",
                   "arrest", "gun", "knife", "weapon", "drug", "drugs", "stolen", "steal", "speeding", "wheelie",
                   "street race", "racing", "no helmet", "without a helmet", "helmetless", "drunk", "bribe", "cash stack"]
WEEKLY_TARGET = {"reel": (3, 4), "photo": (2, 3), "carousel": (1, 1)}
PATH = store.DATA / "calendar.json"


def load():
    return store.load(PATH)


def days():
    return load()["days"]


def get(day):
    for d in days():
        if d["day"] == day:
            return d
    raise KeyError(f"Day {day} is not in the calendar")


def set_status(day, status):
    if status not in STATUSES:
        raise ValueError(f"unknown status {status!r}")
    db = load()
    for d in db["days"]:
        if d["day"] == day:
            d["status"] = status
            store.save(PATH, db)
            return d
    raise KeyError(day)


def date_for(day, settings=None):
    settings = settings or store.settings()
    return date.fromisoformat(settings["start_date"]) + timedelta(days=day - 1)


def day_for(on_date, settings=None):
    settings = settings or store.settings()
    return (on_date - date.fromisoformat(settings["start_date"])).days + 1


def in_frame(d):
    return d["face"] != "none"


def wears_jacket(d):
    return in_frame(d) and d["outfit"] in JACKET_OUTFITS


def weeks(ds):
    return [ds[i:i + 7] for i in range(0, len(ds), 7)]


def balance_report(ds=None):
    """Numbers behind the identity constraints, used by validate() and `python -m elias balance`."""
    ds = ds if ds is not None else days()
    targets = store.character()["content_balance"]
    n = len(ds)
    buckets = Counter(BUCKET_OF[d["pillar"]] for d in ds)
    frame = [d for d in ds if in_frame(d)]
    jacket = [d["day"] for d in frame if d["outfit"] in JACKET_OUTFITS]
    run = longest = 0
    for d in frame:
        run = run + 1 if d["outfit"] in JACKET_OUTFITS else 0
        longest = max(longest, run)
    moto = [d["day"] for d in ds if d["motorcycle"]]
    return {
        "buckets": {b: {"days": buckets[b], "share": buckets[b] / n, "target_days": round(t * n, 1)} for b, t in targets.items()},
        "in_frame": len(frame),
        "jacket_days": jacket,
        "jacket_share": len(jacket) / len(frame) if frame else 0,
        "jacket_per_week": [sum(wears_jacket(d) for d in w) for w in weeks(ds)],
        "jacket_longest_run": longest,
        "moto_days": moto,
        "moto_share": len(moto) / n,
        "moto_per_week": [sum(d["motorcycle"] for d in w) for w in weeks(ds)],
    }


def validate():
    """Return (errors, warnings). Errors break the pipeline; warnings are editorial."""
    char, sty = store.character(), store.styles()
    errors, warnings = [], []
    ds = days()
    if [d["day"] for d in ds] != list(range(1, len(ds) + 1)):
        errors.append("days must be numbered 1..N without gaps")
    for d in ds:
        tag = f"Day {d['day']}"
        if d["format"] not in FORMATS:
            errors.append(f"{tag}: bad format {d['format']}")
        if d["pillar"] not in PILLARS:
            errors.append(f"{tag}: bad pillar {d['pillar']}")
        if d["status"] not in STATUSES:
            errors.append(f"{tag}: bad status {d['status']}")
        if d["outfit"] not in char["wardrobe"]:
            errors.append(f"{tag}: unknown outfit {d['outfit']}")
        if d["camera"] not in sty["camera"]:
            errors.append(f"{tag}: unknown camera {d['camera']}")
        if d["time_of_day"] not in sty["time_of_day"]:
            errors.append(f"{tag}: unknown time_of_day {d['time_of_day']}")
        if d["face"] not in sty["face"]:
            errors.append(f"{tag}: unknown face {d['face']}")
        if d["girlfriend"] not in GF_LEVELS:
            errors.append(f"{tag}: unknown girlfriend level {d['girlfriend']}")
        for obj in d.get("objects", []):
            if obj not in char["recurring_objects"]:
                errors.append(f"{tag}: unknown recurring object {obj}")
        if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", d.get("slug", "")):
            errors.append(f"{tag}: slug must be lowercase-hyphenated")
        if not d["beats"]:
            errors.append(f"{tag}: needs at least one beat")
        if d["format"] == "reel" and not d.get("hook"):
            errors.append(f"{tag}: reels need a hook id")
        if d["format"] == "carousel" and not 2 <= len(d["beats"]) <= 10:
            errors.append(f"{tag}: carousels need 2-10 beats (slides)")
        text = (d["concept"] + " " + " ".join(d["beats"])).lower()
        for term in FORBIDDEN_TERMS:
            if re.search(r"\b" + re.escape(term) + r"\b", text):
                errors.append(f"{tag}: '{term}' implies criminality/violence/unsafe riding")
        if d["pillar"] == "MOTO" and not d["motorcycle"]:
            errors.append(f"{tag}: MOTO pillar but motorcycle not in frame")
        cb = d.get("callback")
        if cb and not (re.fullmatch(r"D\d+", cb) and 1 <= int(cb[1:]) < d["day"]):
            errors.append(f"{tag}: callback {cb} must point to an earlier day")
        if d["phase"] == 1 and d["girlfriend"] not in {"none", "absent"}:
            warnings.append(f"{tag}: girlfriend appears before Phase 2")
    if not errors:
        errors += _identity_constraints(ds)
    for start in range(0, len(ds), 7):
        week = ds[start:start + 7]
        if len(week) < 7:
            continue
        mix = Counter(d["format"] for d in week)
        for fmt, (lo, hi) in WEEKLY_TARGET.items():
            if not lo <= mix[fmt] <= hi:
                warnings.append(f"Week {start // 7 + 1}: {mix[fmt]} {fmt}(s), target {lo}-{hi}")
        pillars = Counter(d["pillar"] for d in week)
        top, n = pillars.most_common(1)[0]
        if n >= 6 and not any(x["phase"] in (2, 5) for x in week):
            warnings.append(f"Week {start // 7 + 1}: {n}/7 posts are {top}")
    return errors, warnings


def _identity_constraints(ds):
    errors = []
    r = balance_report(ds)
    for b, v in r["buckets"].items():
        if abs(v["days"] - v["target_days"]) > BUCKET_TOLERANCE_DAYS:
            errors.append(f"balance: {b} has {v['days']} days, target {v['target_days']} ±{BUCKET_TOLERANCE_DAYS}")
    lo, hi = JACKET_SHARE
    if not lo <= r["jacket_share"] <= hi:
        errors.append(f"jacket: {r['jacket_share']:.1%} of in-frame posts, target {lo:.0%}-{hi:.0%}")
    for i, n in enumerate(r["jacket_per_week"], 1):
        if n < JACKET_MIN_PER_WEEK:
            errors.append(f"jacket: week {i} has {n} in-frame jacket posts (min {JACKET_MIN_PER_WEEK})")
    if r["jacket_longest_run"] > JACKET_MAX_RUN:
        errors.append(f"jacket: {r['jacket_longest_run']} consecutive in-frame jacket posts (max {JACKET_MAX_RUN})")
    lo, hi = MOTO_SHARE
    if not lo <= r["moto_share"] <= hi:
        errors.append(f"motorcycle: in {r['moto_share']:.1%} of posts, target {lo:.0%}-{hi:.0%}")
    for i, n in enumerate(r["moto_per_week"], 1):
        if n > MOTO_MAX_PER_WEEK:
            errors.append(f"motorcycle: week {i} has {n} posts (max {MOTO_MAX_PER_WEEK})")
    return errors
