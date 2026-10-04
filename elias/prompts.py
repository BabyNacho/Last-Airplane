"""Prompt builder. Every prompt is assembled from the identity lock in config/character.json
so no post is ever generated from a free-floating description.

Tool-agnostic: the output names the reference images to attach. Map them to your tool's
identity control (LoRA trigger word, character/omni reference, IP-Adapter/InstantID, or an
approved start frame for image-to-video)."""
from elias import naming, store

# 24 reference images. (subject, n, establishes, shot description, outfit)
REFERENCE_SHEET = [
    ("ELIAS_FACE", 1, "face identity", "front-facing neutral headshot, even soft studio light, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 2, "face identity", "three-quarter left headshot, soft studio light, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 3, "face identity", "strict right profile headshot, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 4, "face identity / expression", "tight close-up of the eyes and brows, controlled dominant stare into the lens, side light", "W05"),
    ("ELIAS_HAIR", 1, "signature hair", "three-quarter back-of-head and side view showing the short dark wet-look cut, hairline and texture, window light", "W05"),
    ("ELIAS_BODY", 1, "body proportions", "full-body standing front view, arms relaxed, plain studio", "W05"),
    ("ELIAS_BODY", 2, "body proportions", "full-body side view, plain studio", "W05"),
    ("ELIAS_JACKET", 1, "leather-jacket silhouette + hands", "waist-up front view, jacket half-zipped, hands visible with ring and watch, plain dark studio", "W04"),
    ("ELIAS_JACKET", 2, "leather-jacket silhouette from behind", "full-body three-quarter back view walking away, jacket shoulders and cut clearly readable, plain dark studio", "W04"),
    ("ELIAS_RIDER", 1, "Elias + motorcycle identity", "full-body standing beside the motorcycle holding the helmet, concrete garage, even light", "W08"),
    ("ELIAS_CASUAL", 1, "casual look", "candid morning in a minimal kitchen, coffee in hand, relaxed", "W05"),
    ("ELIAS_FORMAL", 1, "formal / luxury look", "standing in a grand hotel lobby, hands in pockets, warm brass light", "W02"),
    ("ELIAS_ROMANTIC", 1, "romantic look", "seated at a candle-lit dinner table, soft rare half-smile toward someone off-frame", "W11"),
    ("ELIAS_NIGHT", 1, "dark / night look", "rainy night street, face half-lit by a shop light, wet hair", "W04"),
    ("ELIAS_CANDID", 1, "candid / street look", "long-lens street candid, walking mid-stride, unaware of the camera, daylight", "W09"),
]
GF_SHEET = [
    ("GF", 1, "girlfriend identity (silhouette)", "seen from behind walking, hair and silhouette clear"),
    ("GF", 2, "girlfriend identity (profile)", "partial profile, face mostly out of focus, cream knit"),
    ("GF", 3, "girlfriend continuity (bracelet)", "close-up of her left hand and wrist with the gold bracelet"),
    ("GF", 4, "girlfriend continuity (bag + outfit)", "three-quarter back view, face turned away, camel coat, holding the tan bag"),
    ("GF", 5, "girlfriend continuity (with him)", "from behind, her hand on the shoulder of a man in a black leather motorcycle jacket; neither face visible"),
]
MOTO_SHEET = [
    ("MOTO", 1, "motorcycle identity", "full side profile, plain concrete studio, even light"),
    ("MOTO", 2, "motorcycle identity", "front three-quarter view, headlight and running lights on, night garage"),
    ("MOTO", 3, "motorcycle continuity", "rear three-quarter view showing tail, exhaust and tank shape, daylight"),
    ("MOTO", 4, "motorcycle continuity (gear)", "the black full-face helmet and black gloves on the seat, cream second helmet hanging from the bar"),
]
REEL_SECONDS = {1: 6, 2: 8, 3: 10, 4: 12, 5: 14, 6: 15}


def _join(parts):
    return ", ".join(p.strip().rstrip(".") for p in parts if p and p.strip()) + "."


def _elias_lock(char, full=False):
    e = char["elias"]
    if full:
        return _join([e["age"] + " man", e["face"], e["hair"], e["body"]])
    return e["short_lock"]


def _outfit(char, code):
    text = char["wardrobe"][code]
    key = "the signature black leather motorcycle jacket"
    if key in text:
        detail = char["signature_jacket"]["lock"].split(": ", 1)[1]
        text = text.replace(key, f"his signature black leather motorcycle jacket ({detail})")
    return text


JACKET_OUTFITS = {"W04", "W08", "W11"}
LOOK_BY_PILLAR = {"LUX": "FORMAL", "ROMANCE": "ROMANTIC", "DARK": "NIGHT", "STREET": "CANDID", "EVERYDAY": "CASUAL", "TRAVEL": "CANDID"}


def shot_prompt(d, beat, char=None, sty=None):
    char, sty = char or store.character(), sty or store.styles()
    in_frame = d["face"] != "none"
    accessories = [char["accessories"][a] for a in char["default_accessories"]]
    if d["motorcycle"]:
        accessories.append(char["accessories"]["helmet"])
    parts = [
        sty["camera"][d["camera"]],
        beat,
        f"subject: {_elias_lock(char, full=d['face'] in ('full', 'direct'))}" if in_frame
        else "only his hands and forearms are visible (" + char["elias"]["short_lock"].split(",")[1].strip() + ")",
        f"wearing {_outfit(char, d['outfit'])}",
        "accessories: " + "; ".join(accessories),
        sty["face"][d["face"]],
        char["elias"]["expression_default"] if in_frame else "",
        f"setting: {d['location']}",
        sty["time_of_day"][d["time_of_day"]],
    ]
    if d["girlfriend"] not in ("none",):
        vis = char["girlfriend"]["visibility"][d["girlfriend"]]
        if d["girlfriend"] in ("absent", "behind_camera"):
            parts.append(vis)
        else:
            parts.append(f"with {char['girlfriend']['lock']}; {vis}")
    if d["motorcycle"]:
        parts.append("motorcycle: " + char["motorcycle"]["lock"])
        if d["girlfriend"] != "none":
            parts.append("second helmet: " + char["motorcycle"]["second_helmet"])
    for obj in d.get("objects", []):
        parts.append(char["recurring_objects"][obj])
    parts.append(char["realism_suffix"])
    return _join(parts)


def references_for(d, char=None):
    """Which approved reference images to attach for this day's shots."""
    e = "EV_REF_ELIAS"
    refs = []
    if d["face"] in ("full", "direct", "partial"):
        refs += [f"{e}_FACE_01-04", f"{e}_HAIR_01"]
    elif d["face"] in ("away", "back"):
        refs += [f"{e}_FACE_02-03", f"{e}_HAIR_01", f"{e}_BODY_01-02"]
    else:
        refs.append(f"{e}_JACKET_01 (hands, ring, watch)")
    if d["outfit"] in JACKET_OUTFITS and d["face"] != "none":
        refs.append(f"{e}_JACKET_01-02")
    if d["motorcycle"]:
        refs += [f"{e}_RIDER_01", "EV_REF_MOTO_01-04"]
    look = LOOK_BY_PILLAR.get(d["pillar"])
    if look and d["face"] != "none":
        refs.append(f"{e}_{look}_01")
    if d["girlfriend"] not in ("none", "absent", "behind_camera"):
        refs.append("EV_REF_GF_01-05")
    return list(dict.fromkeys(refs))


def build(d, char=None, sty=None):
    """Return the production shot list for a calendar day."""
    char, sty = char or store.character(), sty or store.styles()
    refs = references_for(d, char)
    shots = []
    n = len(d["beats"])
    per_clip = max(2, round(REEL_SECONDS.get(n, 15) / n))
    for i, beat in enumerate(d["beats"], start=1):
        slide = i if n > 1 else None
        still = naming.asset_name(d["day"], d["format"], d["pillar"], d["slug"], slide=slide, ext="png" if d["format"] == "reel" else "jpg")
        shot = {
            "beat": i,
            "asset": still,
            "image_prompt": shot_prompt(d, beat, char, sty),
            "negative_prompt": char["negative_prompt"],
            "references": refs,
            "lora_trigger": char["elias"]["lora_trigger"] if d["face"] != "none" else None,
        }
        if d["format"] == "reel":
            shot["video"] = {
                "mode": "image-to-video from the approved still above",
                "seconds": per_clip,
                "motion_prompt": _join([
                    beat,
                    "natural handheld camera movement" if "handheld" in d["camera"] or d["camera"] in ("gf_pov", "pov", "iphone_candid") else "slow deliberate camera movement",
                    "identity, face and clothing stay identical to the start frame",
                    "realistic physics, no morphing, no extra limbs",
                ]),
            }
        shots.append(shot)
    plan = {"day": d["day"], "format": d["format"], "concept": d["concept"], "shots": shots}
    if d["format"] == "reel":
        hook = store.load(store.DATA / "hooks.json")["hooks"][d["hook"]]
        plan["edit"] = {
            "hook": f"{d['hook']} {hook['name']}: {hook['first_second']}",
            "target_length_s": per_clip * n,
            "final_asset": naming.asset_name(d["day"], "reel", d["pillar"], d["slug"], ext="mp4"),
            "notes": [
                "First second must already be moving.",
                "End on a frame that cuts cleanly back to the first frame (loop).",
                "Ambient sound + one licensed/trending track picked in-app; no voiceover revealing facts.",
                "Vertical 9:16, 1080x1920.",
            ],
        }
    return plan


def reference_sheet(char=None, sty=None):
    char, sty = char or store.character(), sty or store.styles()
    out = []
    for subject, n, purpose, desc, outfit in REFERENCE_SHEET:
        parts = ["character reference photograph, neutral colour grade, 85mm lens", desc,
                 _elias_lock(char, full=True), f"wearing {_outfit(char, outfit)}",
                 "; ".join(char["accessories"][a] for a in char["default_accessories"]),
                 char["elias"]["expression_default"]]
        if subject == "ELIAS_RIDER":
            parts += ["motorcycle: " + char["motorcycle"]["lock"], char["accessories"]["helmet"], char["accessories"]["gloves"]]
        out.append({"asset": naming.ref_name(subject, n), "establishes": purpose,
                    "image_prompt": _join(parts + [char["realism_suffix"]]),
                    "negative_prompt": char["negative_prompt"]})
    g = char["girlfriend"]
    for subject, n, purpose, desc in GF_SHEET:
        extra = [char["signature_jacket"]["lock"]] if n == 5 else []
        out.append({"asset": naming.ref_name(subject, n), "establishes": purpose,
                    "image_prompt": _join(["character reference photograph, neutral colour grade", desc,
                                           g["hair"], g["style"], g["body"], g["signatures"], *extra,
                                           "her face is never fully identifiable", char["realism_suffix"]]),
                    "negative_prompt": char["negative_prompt"].replace("long hair, ", "")})
    m = char["motorcycle"]
    for subject, n, purpose, desc in MOTO_SHEET:
        extra = [char["accessories"]["helmet"], char["accessories"]["gloves"], m["second_helmet"]] if n == 4 else []
        out.append({"asset": naming.ref_name(subject, n), "establishes": purpose,
                    "image_prompt": _join(["product reference photograph", desc, m["lock"], *extra,
                                           "photorealistic, physically plausible lighting and reflections, no text, no logos, no watermark"]),
                    "negative_prompt": "readable brand logos, badges, readable text, cafe racer, cruiser, chopper, dirt bike, "
                                       "spoked wheels, chrome, colour paint, deformed wheels, extra mirrors, cartoon, 3d render"})
    return out
