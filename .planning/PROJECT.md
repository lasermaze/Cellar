# Cellar

## What This Is

An open-source macOS app that turns old Windows game files into working, repeatable, one-click launchers. Cellar sits above Wine as a recipe and repair layer — it manages per-game Wine bottles, applies known or AI-generated configuration recipes, and helps users get old PC games running on Apple silicon Macs without needing to understand Wine internals.

## Core Value

Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Import game files and identify the game
- [ ] Create isolated per-game Wine bottles
- [ ] Apply configuration recipes (known or AI-generated)
- [ ] Launch games with one click
- [ ] Detect and guide installation of dependencies (Homebrew, Wine)
- [ ] AI-powered log interpretation and recipe generation (API-first)
- [ ] User-confirmed launch validation ("Did the game reach the menu?")
- [ ] Save working recipes for reuse and community sharing
- [ ] Native SwiftUI Mac interface

### Out of Scope

- Storefront or game purchasing — Cellar launches games you already own
- Cloud streaming — everything runs locally
- Large compatibility database on day one — start with one game family
- Custom graphics translation layer — rely on Wine and existing translation
- Wine fork — use upstream Wine via Homebrew
- Steam/Epic integration — not a store launcher
- Mobile or non-Mac platforms — macOS only

## Context

**The problem:** Old Windows games on Mac fail not because the EXE can't run, but because every game needs a slightly different combination of bottle settings, graphics behavior, installer handling, config edits, and launch quirks. The setup work is repetitive, manual, and frustrating.

**The landscape:**
- Wine is active and releasing current builds in 2026 (LGPL v2.1)
- Whisky demonstrated demand for a clean macOS Wine wrapper but is no longer actively maintained
- Heroic is a broader launcher but its macOS path leans on CrossOver, not open Wine
- Apple's GPTK is positioned as evaluation/porting toolkit, not a consumer launcher

**The wedge:** Old strategy / management / turn-based PC games on Apple silicon Macs. Starting with Cossacks: European Wars as the flagship test case. These games matter to a dedicated audience, are less demanding than modern AAA titles, and typically fail for configuration reasons rather than anti-cheat or cutting-edge graphics.

**AI role:** AI is a compatibility operator, not marketing. Useful AI jobs: game identification (EXE metadata, hashes, directory structure), recipe generation (Wine build + bottle template + config flags), log interpretation (translate runtime errors into likely causes), and recipe refinement (save what works with confidence scores).

**Target user:** Wine-naive — people who just want to play an old game and don't know what Wine is. Cellar should guide them through the entire process including dependency installation.

## Constraints

- **Tech stack**: Native macOS — Swift/SwiftUI for the launcher UI
- **Wine distribution**: Homebrew — Cellar guides users through installing Homebrew and Wine rather than bundling or managing its own Wine builds
- **AI inference**: API-first (Claude/OpenAI) — simpler to build, requires internet for AI features
- **Launch validation**: User-confirmed — ask the user if the game reached the menu, no automated screenshot analysis in v1
- **Recipe storage**: Local + Git repo — bundled recipes, community contributes via PRs
- **License**: Open source (GPL-3.0 aligns with Whisky/Heroic ecosystem)
- **Scope**: One game family first (old strategy games), expand from there

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name: Cellar | Fits Wine/bottle metaphor, memorable, available | — Pending |
| Homebrew for Wine | Avoids bundling complexity, leverages existing package management | — Pending |
| API-first AI | Simpler to build than local inference, good enough for MVP | — Pending |
| User-confirmed validation | Avoids vision model complexity in v1, honest about what we can detect | — Pending |
| Cossacks: European Wars as flagship | 2001 RTS, DirectX-heavy, known Wine compatibility challenges, dedicated audience | — Pending |
| Recipes in Git repo | Community PRs, version-controlled, works offline with bundled set | — Pending |
| GPL-3.0 license | Aligns with Whisky/Heroic ecosystem, encourages contribution | — Pending |

---
*Last updated: 2026-03-25 after initialization*
