"""Publishing queue with a mandatory human approval step.

draft -> ready (all assets QA-passed + hosted) -> approved (human) -> published
Any edit after approval drops the item back to draft, so nothing unapproved goes live."""
import hashlib
import json
from datetime import datetime

from elias import calendar, captions, naming, qa, store

PATH = lambda: store.WORKSPACE / "queue.json"  # noqa: E731


class QueueError(Exception):
    pass


def _load():
    return store.load(PATH(), default=[])


def _save(items):
    store.save(PATH(), items)


def get(item_id):
    for it in _load():
        if it["id"] == item_id:
            return it
    raise QueueError(f"no queue item {item_id}")


def _update(item):
    items = _load()
    for i, it in enumerate(items):
        if it["id"] == item["id"]:
            items[i] = item
            _save(items)
            return item
    raise QueueError(f"no queue item {item['id']}")


def fingerprint(item):
    payload = {k: item[k] for k in ("caption", "hashtags", "alt_text", "assets", "media_type", "scheduled_for")}
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def full_caption(item):
    tags = " ".join(item["hashtags"])
    return f"{item['caption']}\n\n{tags}".strip() if tags else item["caption"]


def final_assets(d):
    if d["format"] == "reel":
        return [naming.asset_name(d["day"], "reel", d["pillar"], d["slug"], ext="mp4")]
    if d["format"] == "carousel":
        return [naming.asset_name(d["day"], "carousel", d["pillar"], d["slug"], slide=i)
                for i in range(1, len(d["beats"]) + 1)]
    return [naming.asset_name(d["day"], "photo", d["pillar"], d["slug"])]


def build(day):
    d = calendar.get(day)
    item_id = f"D{day:03d}"
    if any(it["id"] == item_id for it in _load()):
        raise QueueError(f"{item_id} already queued")
    s = store.settings()
    sug = captions.suggest(d)
    item = {
        "id": item_id,
        "day": day,
        "media_type": {"reel": "REELS", "carousel": "CAROUSEL", "photo": "IMAGE"}[d["format"]],
        "assets": [{"name": n, "public_url": None} for n in final_assets(d)],
        "caption": sug["captions"][0] if sug["captions"] else "",
        "caption_options": sug["captions"],
        "on_image_text_options": sug["on_image_text"],
        "hashtags": captions.hashtags(d),
        "alt_text": captions.alt_text(d),
        "scheduled_for": f"{calendar.date_for(day, s).isoformat()}T{s['post_time_local']}",
        "status": "draft",
        "approval": None,
        "published": None,
        "history": [],
    }
    items = _load()
    items.append(item)
    items.sort(key=lambda x: x["id"])
    _save(items)
    calendar.set_status(day, "queued")
    return item


def add_story(day, asset, url, n=1):
    item_id = f"D{day:03d}-S{n:02d}"
    items = _load()
    if any(it["id"] == item_id for it in items):
        raise QueueError(f"{item_id} already queued")
    s = store.settings()
    item = {"id": item_id, "day": day, "media_type": "STORIES",
            "assets": [{"name": asset, "public_url": url}], "caption": "", "caption_options": [],
            "on_image_text_options": [], "hashtags": [], "alt_text": "",
            "scheduled_for": f"{calendar.date_for(day, s).isoformat()}T{s['post_time_local']}",
            "status": "draft", "approval": None, "published": None, "history": []}
    items.append(item)
    items.sort(key=lambda x: x["id"])
    _save(items)
    return item


def _edit(item, what):
    if item["status"] == "published":
        raise QueueError("already published; edit it in the Instagram app")
    if item["status"] in ("approved", "ready"):
        item["history"].append({"at": _now(), "event": f"{what}; approval cleared"})
    item["status"] = "draft"
    item["approval"] = None
    return item


def _now():
    return datetime.now().isoformat(timespec="seconds")


def set_caption(item_id, caption, force=False):
    issues = captions.lint(caption)
    if issues and not force:
        raise QueueError("caption breaks the voice rules: " + "; ".join(issues))
    item = _edit(get(item_id), "caption edited")
    item["caption"] = caption
    return _update(item)


def set_hashtags(item_id, tags):
    item = _edit(get(item_id), "hashtags edited")
    item["hashtags"] = [t if t.startswith("#") else f"#{t}" for t in tags]
    return _update(item)


def set_url(item_id, asset, url):
    if not url.startswith("https://"):
        raise QueueError("Instagram fetches media from a public https:// URL")
    item = get(item_id)
    for a in item["assets"]:
        if a["name"] == asset:
            item = _edit(item, f"url set for {asset}")
            a["public_url"] = url
            return _update(item)
    raise QueueError(f"{asset} is not an asset of {item_id}: {[a['name'] for a in item['assets']]}")


def readiness(item):
    problems = []
    for a in item["assets"]:
        if not a["public_url"]:
            problems.append(f"{a['name']}: no public_url")
        if item["media_type"] != "STORIES" and not qa.passed(a["name"]):
            e = qa.latest(a["name"])
            problems.append(f"{a['name']}: QA {'missing' if not e else e['verdict']}")
    issues = captions.lint(item["caption"])
    if issues:
        problems.append("caption: " + "; ".join(issues))
    if item["media_type"] == "CAROUSEL" and not 2 <= len(item["assets"]) <= 10:
        problems.append("carousel needs 2-10 items")
    return problems


def mark_ready(item_id):
    item = get(item_id)
    problems = readiness(item)
    if problems:
        raise QueueError("not ready:\n  " + "\n  ".join(problems))
    item["status"] = "ready"
    item["history"].append({"at": _now(), "event": "ready for approval"})
    return _update(item)


def approve(item_id, by, ai_label_confirmed=False):
    s = store.settings()
    item = get(item_id)
    if item["status"] != "ready":
        raise QueueError(f"{item_id} is {item['status']}; run 'queue ready' first")
    if by not in s["approvers"]:
        raise QueueError(f"{by!r} is not an approver (settings.approvers)")
    if s["disclosure"]["require_ai_label_confirmation"] and not ai_label_confirmed:
        raise QueueError("confirm the AI disclosure: bio states the character is fictional/AI and the "
                         "Instagram AI label will be applied (--ai-label)")
    problems = readiness(item)
    if problems:
        raise QueueError("no longer ready:\n  " + "\n  ".join(problems))
    item["status"] = "approved"
    item["approval"] = {"by": by, "at": _now(), "ai_label_confirmed": True, "fingerprint": fingerprint(item)}
    item["history"].append({"at": _now(), "event": f"approved by {by}"})
    return _update(item)


def reject(item_id, by, reason):
    item = _edit(get(item_id), f"rejected by {by}: {reason}")
    return _update(item)


def approval_valid(item):
    a = item.get("approval")
    return bool(item["status"] == "approved" and a and a["fingerprint"] == fingerprint(item))


def mark_published(item_id, media_id, permalink):
    item = get(item_id)
    item["status"] = "published"
    item["published"] = {"media_id": media_id, "permalink": permalink, "at": _now()}
    item["history"].append({"at": _now(), "event": "published"})
    _update(item)
    captions.mark_used(item["caption"], item["day"])
    if item["media_type"] != "STORIES":
        calendar.set_status(item["day"], "published")
    return item


def items(status=None):
    return [it for it in _load() if status is None or it["status"] == status]
