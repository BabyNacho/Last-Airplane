"""Caption voice: suggestions from the bank, a linter for the voice rules, hashtags,
alt text and in-character comment replies."""
import hashlib
import random
import re
from datetime import datetime

from elias import store

LOG = lambda: store.WORKSPACE / "caption_log.json"  # noqa: E731
QUOTE_CATEGORY_BY_PHASE = {1: "self_respect", 2: "love", 3: "discipline", 4: "dark", 5: "love", 6: "dark"}


def bank():
    return store.load(store.DATA / "captions.json")


def lint(caption):
    """Return a list of rule violations (empty list = OK)."""
    b = bank()
    issues = []
    text = caption.strip()
    if not text:
        return issues
    low = text.lower()
    for term in b["banned_terms"]:
        if re.search(r"(?<![\w#])" + re.escape(term) + r"(?!\w)", low):
            issues.append(f"banned term: {term!r}")
    body = re.sub(r"#\w+", "", text).strip()
    sentences = [s for s in re.split(r"(?<=[.!?])\s+", body) if s.strip()]
    if len(sentences) > b["max_sentences"]:
        issues.append(f"{len(sentences)} sentences (max {b['max_sentences']})")
    if len(body) > b["max_chars"]:
        issues.append(f"{len(body)} chars (max {b['max_chars']})")
    if body.count("!") > 0:
        issues.append("exclamation marks break the controlled voice")
    if re.search(r"\b(i'?m|i am) (so )?(handsome|rich|wealthy|hot)\b", low):
        issues.append("self-praise")
    return issues


def used():
    return {e["caption"] for e in store.load(LOG(), default=[])}


def mark_used(caption, day):
    if not caption.strip():
        return
    log = store.load(LOG(), default=[])
    log.append({"caption": caption, "day": day, "at": datetime.now().isoformat(timespec="seconds")})
    store.save(LOG(), log)


def _rng(day, salt=""):
    return random.Random(int(hashlib.sha256(f"{day}{salt}".encode()).hexdigest(), 16))


def suggest(d, n=3):
    """Return {'captions': [...], 'on_image_text': [...]} for a calendar day."""
    b, seen = bank(), used()
    style = d["caption_style"]
    out = {"style": style, "captions": [], "on_image_text": []}
    if style == "quote_text":
        cat = QUOTE_CATEGORY_BY_PHASE[d["phase"]]
        lines = [q for q in b["quote_text"][cat] if q not in seen]
        _rng(d["day"]).shuffle(lines)
        out["on_image_text"] = lines[:n]
        out["captions"] = ["", *[c for c in b["styles"]["one_word"] if c not in seen][:n - 1]]
        return out
    pool = [c for c in b["styles"][style] if c not in seen or c == ""]
    if not pool:
        pool = [c for c in b["styles"]["statement"] if c not in seen]
    _rng(d["day"]).shuffle(pool)
    out["captions"] = pool[:n]
    if style != "none":
        out["captions"].append("")  # always offer "no caption"
    return out


def hashtags(d):
    """0-5 relevant tags; ~30% of posts get none (the no-tag share is itself an experiment)."""
    h = store.load(store.DATA / "hashtags.json")
    rng = _rng(d["day"], "tags")
    if rng.random() < h["no_tag_ratio"]:
        return []
    tags = list(h["sets"][d["pillar"]])
    rng.shuffle(tags)
    k = rng.randint(3, h["max_per_post"])
    return [t for t in tags[:k] if t not in h["always_avoid"]]


def alt_text(d):
    """Plain descriptive alt text (accessibility + search). Discloses nothing the post doesn't."""
    beat = d["beats"][0].split(":", 1)[-1].strip()
    lead = "Photo of a dark-haired man. " if d["face"] != "none" else "Photo. "
    return f"{lead}{beat[0].upper() + beat[1:]}."[:300]


def reply_options(category):
    r = store.load(store.DATA / "comment_replies.json")
    if category not in r["categories"]:
        raise KeyError(f"categories: {', '.join(r['categories'])}")
    return r["categories"][category], r["rules"]
