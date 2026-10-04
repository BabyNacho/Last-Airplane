"""Weekly one-variable experiments (spec section 17)."""
from datetime import datetime

from elias import analytics, calendar, store

PATH = lambda: store.WORKSPACE / "experiments.json"  # noqa: E731
# variable -> (calendar field, function mapping a value to arm "A"/"B"/None)
VARIABLES = {
    "face_visible": ("face", lambda v: "A" if v in ("full", "direct") else "B" if v in ("partial", "back", "none") else None),
    "moto_vs_romance": ("pillar", lambda v: {"MOTO": "A", "ROMANCE": "B"}.get(v)),
    "dark_vs_romance": ("pillar", lambda v: {"DARK": "A", "ROMANCE": "B"}.get(v)),
    "candid_vs_pro": ("camera", lambda v: "A" if v in ("iphone_candid", "gf_pov", "street", "handheld_video", "mirror", "pov")
                      else "B" if v in ("editorial", "cinematic_night") else None),
    "photo_vs_reel": ("format", lambda v: {"photo": "A", "reel": "B"}.get(v)),
    "caption_vs_none": ("caption_style", lambda v: "B" if v == "none" else "A"),
    "direct_vs_away": ("face", lambda v: {"direct": "A", "away": "B"}.get(v)),
    "gf_visible_vs_hidden": ("girlfriend", lambda v: "A" if v in ("hand", "silhouette", "back", "partial")
                             else "B" if v in ("absent", "behind_camera") else None),
    "day_vs_night": ("time_of_day", lambda v: "A" if v in ("morning", "day", "golden")
                     else "B" if v in ("dusk", "night", "late_night", "rain_night") else None),
}
DEFAULT_METRIC = "follows_per_1k_views"


def _load():
    return store.load(PATH(), default=[])


def plan(variable, week, metric=DEFAULT_METRIC, hypothesis=""):
    if variable not in VARIABLES:
        raise KeyError(f"variables: {', '.join(VARIABLES)}")
    field, arm = VARIABLES[variable]
    days = [d for d in calendar.days() if (d["day"] - 1) // 7 + 1 == week]
    a = [d["day"] for d in days if arm(d[field]) == "A"]
    b = [d["day"] for d in days if arm(d[field]) == "B"]
    exps = _load()
    exp = {"id": f"E{len(exps) + 1:02d}", "week": week, "variable": variable, "metric": metric,
           "hypothesis": hypothesis, "arm_a_days": a, "arm_b_days": b, "result": None,
           "created": datetime.now().isoformat(timespec="seconds")}
    exps.append(exp)
    store.save(PATH(), exps)
    return exp


def evaluate(exp_id):
    exps = _load()
    exp = next((e for e in exps if e["id"] == exp_id), None)
    if not exp:
        raise KeyError(exp_id)
    rows = {int(r["day"]): r for r in analytics.enriched_rows()}

    def mean(days):
        vals = [rows[d][exp["metric"]] for d in days if d in rows and exp["metric"] in rows[d]]
        return (sum(vals) / len(vals), len(vals)) if vals else (None, 0)

    (ma, na), (mb, nb) = mean(exp["arm_a_days"]), mean(exp["arm_b_days"])
    res = {"a_mean": ma, "a_n": na, "b_mean": mb, "b_n": nb, "evaluated": datetime.now().isoformat(timespec="seconds")}
    if ma is not None and mb is not None:
        res["winner"] = "A" if ma > mb else "B" if mb > ma else "tie"
        res["lift"] = (ma - mb) / mb if mb else None
        res["confidence"] = "low" if min(na, nb) < 3 else "directional"
    exp["result"] = res
    store.save(PATH(), exps)
    return exp


def all_experiments():
    return _load()
