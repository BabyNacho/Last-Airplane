# Assets (gitignored — back up separately)

```
assets/
  references/                 EV_REF_ELIAS_FACE_01_v01.png, EV_REF_GF_02_v01.png, EV_REF_MOTO_01_v01.png …
  day_009/raw/                generation candidates (any name)
  day_009/final/              EV_D009_REEL_MOTO_gloves-ignition_s01_v02.png   (reel start frame, beat 1)
                              EV_D009_REEL_MOTO_gloves-ignition_v01.mp4       (edited reel)
  day_022/final/              EV_D022_CARO_ROMANCE_quiet-day_s01_v01.jpg …    (carousel slides)
  day_012/stories/            EV_D012_STORY_01_v01.jpg
```

Pattern: `EV_D{day:3}_{PHOT|REEL|CARO}_{PILLAR}_{slug}[_s{slide:2}]_v{version:2}.{ext}`.
Bump `v` on every regeneration; QA records are per file name, so a new version needs a new QA pass.
`python -m elias name --day N [--slide K] [--version V] [--ext mp4]` prints the right name; `python -m elias check-assets` lists bad names.
