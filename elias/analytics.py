"""Analytics tracker. Rows are joined with calendar attributes so every report can answer
'which trait / format / caption style / hook works best'."""
import csv
from collections import defaultdict

from elias import calendar, store

POST_FIELDS = ["day", "media_id", "date", "views", "reach", "likes", "comments", "shares", "saves",
               "profile_visits", "follows", "avg_watch_s", "completion_rate", "retention_3s", "replays"]
ACCOUNT_FIELDS = ["date", "followers", "profile_visits", "follows", "story_views", "returning_viewers"]
DIMENSIONS = ["format", "pillar", "face", "girlfriend", "camera", "caption_style", "time_of_day", "hook", "phase"]
POST_CSV = lambda: store.WORKSPACE / "analytics" / "post_metrics.csv"  # noqa: E731
ACCOUNT_CSV = lambda: store.WORKSPACE / "analytics" / "account_metrics.csv"  # noqa: E731
# Insights requested from the official API. Availability varies by media type and API version;
# anything the API does not provide (3s retention, completion, replays) is entered manually
# from the in-app Insights screen.
API_METRICS = {
    "REELS": ["views", "reach", "likes", "comments", "shares", "saved", "ig_reels_avg_watch_time"],
    "IMAGE": ["views", "reach", "likes", "comments", "shares", "saved", "profile_visits", "follows"],
    "CAROUSEL": ["views", "reach", "likes", "comments", "shares", "saved"],
}
API_TO_FIELD = {"saved": "saves", "ig_reels_avg_watch_time": "avg_watch_s"}


def _read(path, fields):
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _write(path, fields, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in fields})


def upsert_post(day, **metrics):
    unknown = set(metrics) - set(POST_FIELDS)
    if unknown:
        raise ValueError(f"unknown metrics {sorted(unknown)}; allowed: {POST_FIELDS}")
    rows = _read(POST_CSV(), POST_FIELDS)
    row = next((r for r in rows if int(r["day"]) == day), None)
    if row is None:
        row = {"day": str(day), "date": calendar.date_for(day).isoformat()}
        rows.append(row)
    row.update({k: str(v) for k, v in metrics.items() if v is not None})
    rows.sort(key=lambda r: int(r["day"]))
    _write(POST_CSV(), POST_FIELDS, rows)
    return row


def upsert_account(date, **metrics):
    rows = _read(ACCOUNT_CSV(), ACCOUNT_FIELDS)
    row = next((r for r in rows if r["date"] == date), None)
    if row is None:
        row = {"date": date}
        rows.append(row)
    row.update({k: str(v) for k, v in metrics.items() if v is not None})
    rows.sort(key=lambda r: r["date"])
    _write(ACCOUNT_CSV(), ACCOUNT_FIELDS, rows)
    return row


def fetch(day, client, media_id, media_type):
    data = client.insights(media_id, API_METRICS[media_type])
    values = {}
    for m in data.get("data", []):
        v = m.get("values", [{}])[0].get("value", m.get("total_value", {}).get("value"))
        if v is not None:
            field = API_TO_FIELD.get(m["name"], m["name"])
            if field == "avg_watch_s":
                v = round(float(v) / 1000, 2)  # API returns milliseconds
            if field in POST_FIELDS:
                values[field] = v
    return upsert_post(day, media_id=media_id, **values)


def _f(row, key):
    try:
        return float(row.get(key) or "")
    except ValueError:
        return None


def rates(row):
    views, visits, follows = _f(row, "views"), _f(row, "profile_visits"), _f(row, "follows")
    reach = _f(row, "reach") or views
    out = {}
    if visits and follows is not None:
        out["follow_conversion"] = follows / visits
    if views and follows is not None:
        out["follows_per_1k_views"] = 1000 * follows / views
    for k in ("saves", "shares", "comments"):
        v = _f(row, k)
        if reach and v is not None:
            out[f"{k}_rate"] = v / reach
    for k in ("retention_3s", "completion_rate", "avg_watch_s"):
        v = _f(row, k)
        if v is not None:
            out[k] = v
    return out


def enriched_rows():
    rows = []
    for r in _read(POST_CSV(), POST_FIELDS):
        d = calendar.get(int(r["day"]))
        raw = {k: v for k, v in r.items() if v != ""}
        rows.append({**{k: d.get(k) for k in DIMENSIONS}, **raw, **rates(r)})
    return rows


def breakdown(dimension, metric, rows=None):
    groups = defaultdict(list)
    for r in rows if rows is not None else enriched_rows():
        if isinstance(r.get(metric), float) and r.get(dimension) is not None:
            groups[str(r[dimension])].append(r[metric])
    return sorted(((k, sum(v) / len(v), len(v)) for k, v in groups.items()), key=lambda x: -x[1])


def diagnose(rows):
    """Spec section 16: watch-but-don't-follow vs follow-but-stop-watching."""
    acc = _read(ACCOUNT_CSV(), ACCOUNT_FIELDS)
    notes = []
    conv = [r["follow_conversion"] for r in rows if "follow_conversion" in r]
    per_k = [r["follows_per_1k_views"] for r in rows if "follows_per_1k_views" in r]
    if conv and sum(conv) / len(conv) < 0.05:
        notes.append("Follow conversion < 5%: people visit but don't follow. Improve the profile grid, "
                     "bio, pinned posts and the mystery hook (who is he?), not the volume.")
    if per_k and sum(per_k) / len(per_k) < 1:
        notes.append("< 1 follow per 1,000 views: reach isn't converting. Make the character, not the image, the subject.")
    if len(acc) >= 14:
        def sv(r):
            return _f(r, "story_views") or 0
        early, late = acc[-14:-7], acc[-7:]
        e, l = sum(map(sv, early)) / 7, sum(map(sv, late)) / 7
        f0, f1 = _f(acc[-14], "followers") or 0, _f(acc[-1], "followers") or 0
        if f1 > f0 and e and l < e * 0.9:
            notes.append("Followers up but story views down >10% week over week: followers are losing interest. Improve the content and the arc.")
    return notes


def report():
    rows = enriched_rows()
    lines = [f"# Analytics report ({len(rows)} posts)", ""]
    if not rows:
        return "\n".join(lines + ["No data yet. Add rows with `python -m elias analytics add`."])
    for metric in ("follow_conversion", "follows_per_1k_views", "saves_rate", "shares_rate", "retention_3s", "avg_watch_s"):
        if not any(metric in r for r in rows):
            continue
        lines.append(f"## {metric}")
        for dim in DIMENSIONS:
            b = breakdown(dim, metric, rows)
            if len(b) > 1:
                best = b[0]
                lines.append(f"- best {dim}: **{best[0]}** ({best[1]:.4g}, n={best[2]})  |  " +
                             ", ".join(f"{k} {v:.3g} (n={n})" for k, v, n in b))
        lines.append("")
    notes = diagnose(rows)
    if notes:
        lines += ["## Diagnosis", *[f"- {n}" for n in notes]]
    lines.append("\n_Small samples (n<3) are anecdotes, not findings._")
    return "\n".join(lines)
