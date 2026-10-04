"""Asset naming convention.

  EV_D009_REEL_MOTO_gloves-ignition_v02.mp4      single asset
  EV_D022_CARO_ROMANCE_quiet-day_s03_v01.jpg     carousel slide 3
  EV_D009_REEL_MOTO_gloves-ignition_s01_v01.png  reel start frame (beat 1)
  EV_D012_STORY_01_v01.jpg                       story frame
  EV_REF_ELIAS_FACE_03_v01.png                   reference sheet image
"""
import re

FORMAT_CODES = {"photo": "PHOT", "reel": "REEL", "carousel": "CARO", "story": "STORY"}
REF_SUBJECTS = {"ELIAS_FACE", "ELIAS_HAIR", "ELIAS_BODY", "ELIAS_JACKET", "ELIAS_RIDER", "ELIAS_CASUAL",
                "ELIAS_FORMAL", "ELIAS_ROMANTIC", "ELIAS_NIGHT", "ELIAS_CANDID", "GF", "MOTO", "OBJECT"}
PATTERN = re.compile(
    r"^EV_(?:"
    r"D(?P<day>\d{3})_(?:STORY_(?P<story>\d{2})|(?P<fmt>PHOT|REEL|CARO)_(?P<pillar>[A-Z]+)_(?P<slug>[a-z0-9-]+)(?:_s(?P<slide>\d{2}))?)"
    r"|REF_(?P<ref>[A-Z_]+?)_(?P<refn>\d{2})"
    r")_v(?P<ver>\d{2})\.(?P<ext>jpg|jpeg|png|webp|mp4|mov)$"
)


def slugify(text, max_words=3):
    words = re.findall(r"[a-z0-9]+", text.lower())
    stop = {"the", "a", "an", "and", "of", "with", "on", "in", "at", "to", "his", "her", "for"}
    words = [w for w in words if w not in stop][:max_words]
    return "-".join(words) or "untitled"


def asset_name(day, fmt, pillar, slug, version=1, slide=None, ext="jpg"):
    code = FORMAT_CODES[fmt]
    if fmt == "story":
        return f"EV_D{day:03d}_STORY_{(slide or 1):02d}_v{version:02d}.{ext}"
    s = f"_s{slide:02d}" if slide else ""
    return f"EV_D{day:03d}_{code}_{pillar}_{slugify(slug)}{s}_v{version:02d}.{ext}"


def ref_name(subject, n, version=1, ext="png"):
    subject = subject.upper()
    if subject not in REF_SUBJECTS:
        raise ValueError(f"subject must be one of {sorted(REF_SUBJECTS)}")
    return f"EV_REF_{subject}_{n:02d}_v{version:02d}.{ext}"


def parse(name):
    m = PATTERN.match(name)
    if not m:
        return None
    out = {k: v for k, v in m.groupdict().items() if v is not None}
    for k in ("day", "slide", "ver", "refn", "story"):
        if k in out:
            out[k] = int(out[k])
    return out


def day_folder(day):
    return f"day_{day:03d}"
