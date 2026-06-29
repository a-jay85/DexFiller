# DexFiller

Export your Pokémon GO collection to CSV. DexFiller processes screen recordings
of your Pokémon info and appraisal screens, extracts every field via on-device
OCR and image analysis, and writes a flat CSV you actually own — for custom
analysis, team-building, and goal tracking.

> **Status: early prototype.** The pipeline builds and the core logic is unit
> tested, but the OCR extractors use heuristic pixel regions that have **not yet
> been validated against real Pokémon GO screenshots**. Treat output as
> unverified until the Phase 0 accuracy gate (below) is met.

## Why

Existing OCR tools (PokéGenie, CalcyIV) lock your data inside their own UIs.
DexFiller's only job is extraction — it hands you a plain CSV and gets out of
the way.

**ToS note:** DexFiller never touches the Pokémon GO client, Niantic's servers,
or live game data. It processes video files after the fact, the same approach as
existing screenshot-based OCR tools.

## How it works

```
Video (.mov/.mp4)
  → Frame Sampler        sample ~2 fps, streaming (never loads full video)
  → Screen Classifier    info screen / appraisal overlay / skip
  → Frame Grouper        collapse consecutive frames, keep the sharpest
  → Data Extractor       OCR text fields + IV-bar analysis
  → Pokémon Linker       pair each appraisal with its info screen
  → Deduplicator         drop repeats (match on species + CP + HP + weight)
  → CSV Writer           export with per-row confidence scores
  → Review (UI)          optionally correct low-confidence rows
```

Everything runs on-device via Apple's Vision and Core Graphics — no cloud, no
data leaves your Mac.

## CSV columns

```
species, nickname, cp, hp, level, attack_iv, defense_iv, stamina_iv,
iv_percentage, fast_move, charged_move_1, charged_move_2, catch_date,
catch_location, weight, height, shiny, lucky, shadow, purified, confidence
```

- `level` — derived from stardust power-up cost via lookup table
- `iv_percentage` — `(attack + defense + stamina) / 45`
- `confidence` — `0.0–1.0`, the minimum confidence across that row's fields

## Project layout

| Path | What |
|------|------|
| `Sources/DexFillerCore/` | Platform-agnostic processing library (the pipeline) |
| `Sources/DexFiller/` | SwiftUI macOS app (import, progress, review, export) |
| `Tests/DexFillerCoreTests/` | Unit tests for dedup, CSV, stardust→level, records |

## Build & test

Requires Swift 6 / Xcode 16, macOS 14+.

```sh
swift build      # build the library and app
swift test       # run the unit suite
```

## Roadmap

- **Phase 0 — IV bar prototype (current gate):** validate appraisal-bar reading
  to >95% accuracy on real screenshots before trusting any extraction.
- **Phase 1 — Core OCR pipeline:** end-to-end video → accurate CSV.
- **Phase 2 — Robustness & review:** multiple screen sizes, transitions,
  confidence scoring, visual tags (shiny/lucky/shadow/purified), pause/resume.
- **Phase 3 — App Store polish:** onboarding, sandboxing, privacy policy.
- **Phase 4 — iOS port:** share the core package, mobile UI, TestFlight.

## License

[MIT](LICENSE) © 2026 A-Jay Nicolas
