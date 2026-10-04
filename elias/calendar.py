"""The 90-day content database (data/calendar.json)."""
import re
from collections import Counter
from datetime import date, timedelta

from elias import store

FORMATS = {"photo", "reel", "carousel"}
PILLARS = {"STREET", "MOTO", "LUX", "ROMANCE", "DARK", "THOUGHTS", "TRAVEL", "EVERYDAY"}
STATUSES = {"planned", "in_production", "ready", "queued", "published", "skipped"}
GF_LEVELS = {"none", "absent", "hand", "silhouette", "back", "partial", "behind_camera"}
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
        if d["phase"] == 1 and d["girlfriend"] not in {"none", "absent"}:
            warnings.append(f"{tag}: girlfriend appears before Phase 2")
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
