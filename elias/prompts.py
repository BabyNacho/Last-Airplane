"""Prompt builder. Every prompt is assembled from the identity lock in config/character.json
so no post is ever generated from a free-floating description.

Tool-agnostic: the output names the reference images to attach. Map them to your tool's
identity control (LoRA trigger word, character/omni reference, IP-Adapter/InstantID, or an
approved start frame for image-to-video)."""
from elias import naming, store

REFERENCE_SHEET = [
    # (subject, n, shot description, outfit)
    ("ELIAS_FACE", 1, "front-facing neutral headshot, even soft studio light, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 2, "three-quarter left headshot, soft studio light, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 3, "three-quarter right headshot, soft studio light, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 4, "strict left profile headshot, plain grey backdrop", "W05"),
    ("ELIAS_FACE", 5, "close-up of the eyes and brows, calm intense look, natural light", "W05"),
    ("ELIAS_FACE", 6, "headshot with damp hair after a shower, window light", "W05"),
    ("ELIAS_FACE", 7, "headshot with slightly heavier stubble, window light", "W05"),
    ("ELIAS_FACE", 8, "rare genuine half-smile, window light", "W05"),
    ("ELIAS_BODY", 1, "full-body standing front view, neutral pose, plain studio", "W01"),
    ("ELIAS_BODY", 2, "full-body side view, plain studio", "W02"),
    ("ELIAS_BODY", 3, "full-body walking mid-stride, plain studio", "W04"),
    ("ELIAS_BODY", 4, "waist-up, arms relaxed, hands clearly visible with ring and watch", "W03"),
    ("ELIAS_OUTFIT", 1, "full-body in motorcycle gear holding the helmet", "W08"),
    ("ELIAS_OUTFIT", 2, "full-body in long black overcoat", "W09"),
    ("ELIAS_OUTFIT", 3, "full-body in black evening tuxedo", "W10"),
]
GF_SHEET = [
    ("GF", 1, "seen from behind walking, hair and silhouette clear"),
    ("GF", 2, "close-up of her left hand and wrist with the gold bracelet"),
    ("GF", 3, "three-quarter back view, face turned away, holding the tan bag"),
    ("GF", 4, "soft silhouette against a bright window"),
    ("GF", 5, "partial profile, face mostly out of focus, cream knit"),
]
MOTO_SHEET = [
    ("MOTO", 1, "full side view, plain concrete garage, even light"),
    ("MOTO", 2, "front three-quarter view, headlight on, night garage"),
    ("MOTO", 3, "detail of seat, tank and handlebars"),
    ("MOTO", 4, "the black helmet resting on the seat; the cream second helmet beside it"),
]
REEL_SECONDS = {1: 6, 2: 8, 3: 10, 4: 12, 5: 14, 6: 15}


def _join(parts):
    return ", ".join(p.strip().rstrip(".") for p in parts if p and p.strip()) + "."


def _elias_lock(char, full=False):
    e = char["elias"]
    if full:
        return _join([e["age"] + " man", e["face"], e["hair"], e["body"]])
    return e["short_lock"]


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
        f"wearing {char['wardrobe'][d['outfit']]}",
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
    char = char or store.character()
    refs = []
    if d["face"] != "none":
        refs.append(char["elias"]["ref_token"] + ("_FACE" if d["face"] in ("full", "direct", "partial") else "_BODY"))
    else:
        refs.append(char["elias"]["ref_token"] + "_BODY_04 (hands)")
    if d["girlfriend"] not in ("none", "absent", "behind_camera"):
        refs.append(char["girlfriend"]["ref_token"])
    if d["motorcycle"]:
        refs.append(char["motorcycle"]["ref_token"])
    return refs


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
    for subject, n, desc, outfit in REFERENCE_SHEET:
        out.append({
            "asset": naming.ref_name(subject, n),
            "image_prompt": _join([
                "character reference photograph, neutral colour grade, 85mm lens",
                desc, _elias_lock(char, full=True), f"wearing {char['wardrobe'][outfit]}",
                "; ".join(char["accessories"][a] for a in char["default_accessories"]),
                char["realism_suffix"]]),
            "negative_prompt": char["negative_prompt"],
        })
    for subject, n, desc in GF_SHEET:
        g = char["girlfriend"]
        out.append({
            "asset": naming.ref_name(subject, n),
            "image_prompt": _join(["character reference photograph, neutral colour grade", desc,
                                   g["hair"], g["style"], g["body"], g["signatures"], char["realism_suffix"]]),
            "negative_prompt": char["negative_prompt"].replace("long hair, ", ""),
        })
    for subject, n, desc in MOTO_SHEET:
        m = char["motorcycle"]
        extra = [char["accessories"]["helmet"], m["second_helmet"]] if n == 4 else []
        out.append({
            "asset": naming.ref_name(subject, n),
            "image_prompt": _join(["product reference photograph", desc, m["lock"], *extra, char["realism_suffix"]]),
            "negative_prompt": "brand logos, badges, readable text, deformed wheels, extra mirrors, cartoon, 3d render",
        })
    return out
