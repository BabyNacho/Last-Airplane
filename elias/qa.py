"""Content quality gate (spec section 14)."""
from datetime import datetime

from elias import store

CRITERIA = {
    1: "Same face",
    2: "Same body proportions",
    3: "Hands correct",
    4: "Eyes natural",
    5: "Skin realistic",
    6: "Lighting physically plausible",
    7: "Reflections correct",
    8: "Motorcycle consistent (or N/A)",
    9: "Clothing physically correct",
    10: "No accidental logos",
    11: "No accidental text artifacts",
    12: "No obvious AI generation artifacts",
    13: "Character personality matches Elias",
    14: "Post adds something new",
    15: "Makes someone curious about the next post",
}
# One failure on any of these is enough to regenerate: they break identity or trust.
HARD = {1, 3, 10, 11}
LOG = lambda: store.WORKSPACE / "qa_log.json"  # noqa: E731


def verdict(failed):
    failed = set(failed)
    unknown = failed - set(CRITERIA)
    if unknown:
        raise ValueError(f"unknown criteria: {sorted(unknown)}")
    if len(failed) >= 2 or failed & HARD:
        return "regenerate"
    if failed:
        return "fix"
    return "pass"


def record(asset, day, failed, reviewer, notes=""):
    entry = {
        "asset": asset,
        "day": day,
        "failed": sorted(set(failed)),
        "failed_names": [CRITERIA[c] for c in sorted(set(failed))],
        "verdict": verdict(failed),
        "reviewer": reviewer,
        "notes": notes,
        "at": datetime.now().isoformat(timespec="seconds"),
    }
    log = store.load(LOG(), default=[])
    log.append(entry)
    store.save(LOG(), log)
    return entry


def latest(asset):
    for e in reversed(store.load(LOG(), default=[])):
        if e["asset"] == asset:
            return e
    return None


def passed(asset):
    e = latest(asset)
    return bool(e and e["verdict"] == "pass")
