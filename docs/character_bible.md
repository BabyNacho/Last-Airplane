# Character Bible — ELIAS VANE

> Fictional character. Photorealistic, never presented as a real human.
> Machine-readable lock: [`config/character.json`](../config/character.json). This document explains it; the JSON is what every prompt is built from. If the two disagree, fix the JSON and regenerate the reference sheet.

## 1. Identity lock

| Trait | Locked value |
|---|---|
| Public name | Elias Vane (handle candidates: `@eliasvane`, `@elias.vane`, `@eliasvane____` — check availability manually) |
| Age | 29 (reads 28–31) |
| Skin | Fair, realistic texture, faint pores. Never airbrushed. |
| Hair | Short dark brown-black, textured top, shorter sides, natural hairline. Often damp. **Never changes style.** |
| Eyes | Dark brown, slightly hooded, intense; lash line naturally shadowed (not makeup). |
| Brows | Thick, straight, dark. |
| Nose / jaw | Straight narrow nose; strong defined jaw; subtle five-o'clock shadow (stubble may vary slightly). |
| Build | ~188 cm impression, broad shoulders, lean athletic, narrow waist. Not a bodybuilder. |
| Posture | Upright, controlled, still. Hands relaxed, never fidgeting. |
| Signature visual | Dark hair + sharp eyes + broad shoulders + black clothing + controlled expression. |

### Signature accessories (do not rotate randomly)
- **Watch** — steel case, plain black dial, black leather strap, no branding, left wrist. Always.
- **Ring** — simple matte black band, right ring finger. Always.
- **Chain** — thin silver curb chain. Occasional.
- **Sunglasses** — black rectangular acetate. Occasional, daytime.
- **Helmet** — matte black full-face, smoked visor, no graphics.

### Wardrobe codes
`W01` black fitted shirt + tailored trousers · `W02` black suit, black shirt, no tie · `W03` white/cream shirt, sleeves rolled · `W04` dark leather jacket · `W05` premium plain tee · `W06` charcoal knit · `W07` relaxed travel · `W08` motorcycle gear · `W09` long black overcoat · `W10` black tuxedo.
No visible logos, ever. Luxury is fit, fabric and setting.

## 2. Personality

Calm. Observant. Private. Disciplined. Protective. Intelligent. Controlled arrogance. Romantic only when alone with her. Occasionally dark. Never needy.

**Shown, not told.** He enters quietly, doesn't explain, rarely looks at the lens, leaves without saying where.

**He never:** begs for follows · calls himself handsome/rich · brags about money · posts daily motivation · plays an "alpha" parody · insults women · glorifies violence · acts toxic for engagement · explains his life.

**Camera behaviour rule:** direct eye contact is *rare* and therefore powerful (Day 1, then withheld until Day 87). Default is looking away, partial, or unaware.

## 3. Mystery rules

Never establish: nationality · hometown · address · employer · family · her identity · relationship timeline.
Locations are ambiguous: no location tags, no readable signs, no famous landmarks. Departure boards and keys are always obscured.
Mystery comes from **content** (objects, absences, callbacks), not from cryptic captions. Cryptic captions max ~1 in 5 posts.

## 4. The girlfriend — "M" (internal codename only, never published)

| Trait | Locked value |
|---|---|
| Hair | Dark brown, medium-long, soft natural waves |
| Style | Elegant, understated; cream, camel, black; minimal makeup |
| Silhouette | Slim, graceful, ~168 cm |
| Signatures | **Thin gold chain bracelet with a small oval charm (left wrist)** · **tan structured leather bag** · later: **cream open-face helmet** |

She is a person, not a prop: she teases him, laughs first, takes the photos, leaves when she's upset, chooses when to come back. Visibility ladder used in the calendar (`girlfriend` field):
`none → absent (object only) → hand → silhouette → back → behind_camera → partial`.
**Her face is never fully identifiable in the 90-day arc.** No sexualised framing.

## 5. The motorcycle

Matte black café-racer style, single round headlight, brown leather single seat, black spoked wheels, brushed dark exhaust, **no badges or logos**. Same bike every time (reference `EV_REF_MOTO_01–04`). Motorcycle is part of him, not the account's topic: ~1 post in 10.

## 6. Recurring objects (the clue system)

| Object | First seen | Returns |
|---|---|---|
| Green cloth-bound book, no title | D4 | D13, D22, D36, D45, D58, D69, D81 |
| Black restaurant matchbook | D10 | D26, D42, D49, D64, D86, D89, D90 |
| Table for two at "the" restaurant | D10 | D49 (both empty), D64 (both full), D90 |
| Two coffees, café terrace | D16 | D66 (both hands), D82 (one cold) |
| Her gold bracelet | D17 | D45 & D85 (on *his* wrist), D58 (bookmark), D90 (on the chair) |
| Old photo of a coastal road | D53 | D68 (they are *there*), D89 (a second photo, opposite direction) |
| Cream second helmet | D67 | D90 |
| Hotel key | D57 | D79, D81 |
| Distant tower / postcard | D77 | D86 |

Callbacks are stored in the `callback` field of `data/calendar.json`. Never explain a callback; let comments find it.

## 7. Arc summary

1. **Who is he?** (1–15) identity, street, bike, black, café, hotel, first empty chair.
2. **There is someone** (16–30) two coffees, her hand, her silhouette, she films him, she enters frame.
3. **The life** (31–45) groceries, laptop, gym, bike maintenance, airport, normal days.
4. **The dark side** (46–60) unread message, empty chair, rain, old photograph, disappearance → return. Dark ≠ violent; no fake tragedy.
5. **The relationship** (61–75) flowers, laughter, the coastal road from the photo, a silent argument, reconciliation.
6. **The myth** (76–90) he travels alone, her bracelet on his wrist, a postcard, someone following, the first direct look in weeks, and Day 90: the table for two, her bracelet and helmet on the empty chair, a hand on his shoulder — cut to black.

## 8. Never

Never copy the face, biography or signature style of a real person or creator. The inspiration is the *format* (fictional personality + recurring character + lifestyle + mystery + story), not anyone's identity.
