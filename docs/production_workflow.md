# Production Workflow

Everything runs from the repo root with Python 3.10+ and no dependencies:

```bash
python -m elias init        # creates workspace/settings.json — set start_date, post time, approvers
python -m elias validate    # checks the 90-day database
python -m elias today       # what to make today + the checklist
```

## A. First build order (do this before any daily production)

| # | Step | Command / output | Exit criteria |
|---|---|---|---|
| 1 | Character identity sheet | `docs/character_bible.md`, `config/character.json` | Owner signs off the lock |
| 2 | 15 Elias reference images | `python -m elias refs` → face ×4, hair, body ×2, jacket ×2, rider, casual, formal, romantic, night, candid | Same person in all 15 at a glance; QA 1–5 pass |
| 3 | Girlfriend reference | `EV_REF_GF_01..05` (no fully readable face) | Bracelet + hair + silhouette consistent |
| 4 | Motorcycle reference | `EV_REF_MOTO_01..04` | Identical geometry, no badges |
| 5 | Lock identity in your tool | Train a LoRA on the approved 24 refs (trigger `elsvn man`) *or* use the tool's character/omni-reference with the FACE set attached | 9/10 test generations recognisable |
| 6 | 10 test posts | `python -m elias prompts <day>` for days 1–10 | — |
| 7 | Evaluate consistency | `qa record` each; side-by-side contact sheet with the refs | ≥ 8/10 pass |
| 8 | Refine prompts | Edit `config/character.json` (never per-post text) | — |
| 9 | Final content for days 1–14 | Daily loop below | 14 items approved |
| 10 | Publish & learn | `analytics report` after ~10 posts | — |
| 11 | Days 15–90 | Re-plan each fortnight from real data | — |

**Do not produce 90 finished posts up front.** Produce ~1 week ahead of publishing at most.

Store approved references in `assets/references/` (gitignored, back them up). Rejected references are deleted, not kept "for later".

## B. Daily loop (≈ 60–90 min per post)

1. **Brief** — `python -m elias today` (or `day N`). Read the concept, beats, callback.
2. **Prompts** — `python -m elias prompts N > workspace/prompts/day_NNN.json`.
   Each shot lists: image prompt, negative prompt, which reference set to attach, LoRA trigger, and for Reels an image-to-video motion prompt that starts from the approved still.
   *Rule: every image is generated with the identity reference attached. No reference → don't generate.*
3. **Generate** — 3–6 candidates per shot. Reels: approve the start frame first, then animate it; edit to `edit.target_length_s` (5–20 s), first second already moving, loopable last frame.
4. **Name** — save finals as the printed `asset` names (`python -m elias name --day N` if unsure). `python -m elias check-assets` flags bad names. Folder: `assets/day_NNN/{raw,final}/`.
5. **Quality gate** — for every final asset:
   `python -m elias qa record --asset <name> --day N --fail <failed criteria numbers>`
   - 0 fails → **pass**
   - 1 soft fail → **fix** (retouch/re-edit) then record again
   - ≥ 2 fails, or any of **1 face · 3 hands · 10 logos · 11 text** → **regenerate**
   (`python -m elias qa criteria` lists all 15.)
6. **Queue** — `python -m elias queue build N` drafts caption (from the unused bank), hashtags (0–5), alt text and schedule time. Change with `queue set-caption` (linted) / `queue set-hashtags`.
   Quote posts: pick an `on_image_text_options` line and add it to the image in post-production (never let the model render text).
7. **Host** — upload finals to any public HTTPS media host (S3/R2/GCS…). `python -m elias queue set-url DNNN <asset> <url>`.
8. **Ready** — `python -m elias queue ready DNNN` (blocks unless every asset passed QA, is hosted, and the caption passes the linter).
9. **Human approval** — the owner previews the media and caption on a phone, then:
   `python -m elias queue approve DNNN --by owner --ai-label`
   `--ai-label` confirms the bio disclosure is live and the AI label will be applied (see `disclosure_and_compliance.md`). **Any later edit revokes approval automatically.**
10. **Publish** — `python -m elias publish DNNN` (dry run shows the exact API calls) → `python -m elias publish DNNN --live`, or `publish due --live` from a scheduler. Or post manually in the app — the queue is still the record.
11. **Stories** — 2–4 casual frames: `python -m elias stories N`. `queue add-story` if publishing them via API.
12. **Community (30 min after posting)** — reply to 3–10 selected comments: `python -m elias reply <category>`.
13. **Measure (24–48 h later)** — `python -m elias analytics fetch N` (API metrics) and `analytics add N retention_3s=.. completion_rate=.. replays=..` (from in-app Insights). Daily: `analytics account <date> followers=.. profile_visits=.. follows=.. story_views=..`.

## C. Weekly loop (Sunday, 45 min)

1. `python -m elias analytics report` — best format, pillar, face visibility, girlfriend level, camera style, caption style, hook.
2. Read the **diagnosis**: watch-but-no-follow → fix profile/bio/grid/mystery; follow-but-stop-watching → fix the content.
3. Evaluate last week's experiment: `python -m elias exp evaluate E0N`.
4. Plan next week's single variable: `python -m elias exp plan <variable> --week W --hypothesis "..."` (`exp variables` lists them). The planner reads which days of that week fall in arm A vs B; if the split is lopsided, adjust one or two calendar days — change only the variable under test.
5. Edit the next two weeks of `data/calendar.json` from what you learned; `python -m elias validate`.

## D. Roles

| Role | Does | Can approve? |
|---|---|---|
| Producer (human or Claude) | prompts, generation, naming, QA, queue drafts | No |
| Owner (human, listed in `settings.approvers`) | final review, approval, AI label, replies | **Yes** |

Claude may prepare everything up to `queue ready`. Only a person in `approvers` can approve; nothing reaches Instagram without that approval.

## E. Publishing setup (official API)

1. Instagram **professional account** (Creator or Business).
2. A Meta developer app using the *Instagram API with Instagram Login* (host `graph.instagram.com`) or *with Facebook Login* (host `graph.facebook.com`, account linked to a Facebook Page). Set `graph_api.host`/`version` in settings.
3. Permission to publish content (`instagram_business_content_publish`, or `instagram_content_publish` with Facebook Login) and insights read access.
4. Export `IG_USER_ID` and `IG_ACCESS_TOKEN` in the environment (never commit them).
5. The publisher follows Meta's container flow: create container (`/media`) → poll `status_code` → `/media_publish`. Carousels create child containers first. API publishing is rate-limited per 24 h (well above 1/day).

Not supported via API at the time of writing (do in-app): music selection on Reels, collaborators/tag people beyond what the API exposes, and anything Meta's docs don't list. Check Meta's current docs before relying on a field.
