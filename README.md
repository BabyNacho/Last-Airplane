# Last Airplane — Project MYSTERY MODEL

Operating system for **ELIAS VANE**, a fictional, photorealistic character on Instagram: identity lock, 90-day story database, prompt builder, caption voice, quality gate, human-approved publishing through Meta's official API, analytics and experiments.

Python 3.10+, standard library only. No installation needed.

```bash
python -m elias init                 # workspace/settings.json (start date, post time, approvers)
python -m elias validate             # 90-day database check
python -m elias refs                 # reference-sheet prompts: Elias ×15, girlfriend ×5, motorcycle ×4
python -m elias today                # today's brief + production checklist
python -m elias prompts 9            # image + image-to-video prompts for Day 9, identity-locked
python -m elias captions 9           # caption options (unused), hashtags, alt text
python -m elias qa record --asset EV_D009_REEL_MOTO_gloves-ignition_v01.mp4 --day 9 --fail
python -m elias queue build 9        # draft → set-url → ready → approve (human) → publish
python -m elias publish D009         # dry run; add --live to publish via the Graph API
python -m elias analytics report     # what works: format, pillar, face, girlfriend, hook, caption style
python -m elias exp plan face_visible --week 3
python -m unittest discover -s tests # 18 tests
```

## Layout

| Path | What |
|---|---|
| `docs/character_bible.md` | Who Elias is, the girlfriend, the bike, the clue system, the arc |
| `docs/production_workflow.md` | First-build order, daily loop, weekly loop, roles, API setup |
| `docs/voice_and_community.md` | Caption rules, hashtag/keyword strategy, comment replies |
| `docs/disclosure_and_compliance.md` | AI disclosure, no impersonation, no fake engagement |
| `config/character.json` | **Identity lock** — every prompt is assembled from it |
| `config/styles.json` | Camera styles (candid / girlfriend-POV / editorial / cinematic…), light, face visibility |
| `config/settings.example.json` | Start date, posting time, API host/version, approvers |
| `data/calendar.json` | The 90 days: phase, pillar, format, outfit, camera, face, girlfriend level, hook, callback, beats, status |
| `data/captions.json` | Caption bank + banned terms + on-image quote lines |
| `data/hooks.json` · `hashtags.json` · `stories.json` · `comment_replies.json` | Reel hooks, tag sets, story ideas, in-character replies |
| `elias/` | CLI (`python -m elias -h`) |
| `workspace/` | Runtime state, gitignored: settings, queue, QA log, caption log, analytics CSVs, experiments |
| `assets/` | Media, gitignored. Naming convention in `assets/README.md` |

## Spec → implementation

| Spec task | Where |
|---|---|
| Project structure | this repo |
| Content database / calendar | `data/calendar.json`, `python -m elias calendar / day / validate` |
| Character bible | `docs/character_bible.md`, `config/character.json` |
| Image/video prompt templates | `elias/prompts.py` (`prompts`, `refs`) |
| Asset naming convention | `elias/naming.py`, `assets/README.md` (`name`, `check-assets`) |
| Post metadata | queue items: caption, hashtags, alt text, schedule, assets, approval, permalink |
| Caption generator | `elias/captions.py` (`captions`, `lint`) — never repeats a caption |
| Hashtag/keyword strategy | `data/hashtags.json`, `docs/voice_and_community.md` |
| Publishing queue | `elias/queue.py` |
| Human approval | `queue approve --by <approver> --ai-label`; edits revoke approval |
| Official publishing | `elias/publisher.py` — Instagram Content Publishing API, dry-run by default |
| Analytics tracker | `elias/analytics.py` — follow conversion, follows/1k views, saves, shares, retention, by trait |
| Experiment/hook tracker | `elias/experiments.py`, `data/hooks.json` |
| Daily production workflow | `docs/production_workflow.md`, `python -m elias today` |
| Quality gate | `elias/qa.py` — 15 criteria; ≥2 fails or a hard fail (face/hands/logos/text) → regenerate |

## Non-negotiables built into the code

- Nothing publishes without a valid human approval, and any edit after approval clears it.
- Approval requires confirming the AI disclosure (bio line + Instagram AI label).
- No asset can be queued as ready without a passing QA record.
- Only Meta's official API; no scraping, bots, fake engagement or CAPTCHA tricks.
- The character is fictional; sincere "is he real?" questions get an honest answer.
