# Caption Voice, Hashtags & Community

## Captions
- 0–2 sentences, ≤ 140 characters. One-word captions and *no caption* are normal.
- No exclamation marks. No "alpha / sigma / king / high value", no "follow me", no money talk, no self-praise.
- Never explain the image. Cryptic lines ≤ 1 in 5 posts — mystery comes from the content.
- Every caption is used once (`workspace/caption_log.json`). Add new lines to `data/captions.json`; tests check the bank against the linter.
- Styles in the calendar: `none`, `one_word`, `statement`, `cryptic`, `question`, `she_line`, `quote_text` (line written on the image, caption usually empty).

Check any caption: `python -m elias lint "Different city. Same silence."`

## Hashtags & keywords (no spam)
- 0–5 relevant, low-to-mid volume tags per post from the pillar set in `data/hashtags.json`; ~30 % of posts use none (that's an experiment, not laziness).
- Never: follow-for-follow tags, unrelated trending tags, banned tags, the same block on every post, tags in comments.
- Discoverability lives in the **name field** ("Elias Vane"), **alt text** (auto-drafted per post, plain description) and a clean bio — not in long captions.

## Comments
Reply in character to a handful of comments per post, within the first hour. Short:
"Maybe." · "She knows." · "Not telling." · "You noticed." · "Wrong city." · "Long story." · "Some things stay private."
Sometimes answer sincerely — that's what makes him human.

`python -m elias reply who_is_she` (categories: who_is_she, where_is_this, what_does_he_do, noticed_detail, where_did_you_go, compliment, sincere_question, is_he_real, hostile).

### "Is he real?"
The mystery is *who he is*, never *whether he exists*. If someone sincerely asks whether he's a real person or AI, the answer is honest, still in voice:
"He's fictional. The story isn't finished." · "Not a real person. A real story, though." · "Created, not born. Stay anyway?"
Never deny being AI, never imply a real model is behind the face.

### Never
Fake accounts, fake fan pages, fake testimonials, bought followers/likes/comments, engagement pods, mass-follow/unfollow, automated DMs, replying to hostile or sexual comments (hide/restrict instead).
