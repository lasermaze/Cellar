# Cellar

## What This Is

An open-source macOS CLI+TUI tool that turns old Windows game files into working, repeatable launchers. Cellar sits above Wine as a recipe and repair layer — it manages per-game Wine bottles, applies known or AI-generated configuration recipes, and helps users get old PC games running on Apple silicon Macs without needing to understand Wine internals.

## Core Value

Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## Requirements

### Validated

<!-- Shipped in v1.0 — 7 phases, 22 plans -->

- ✓ Import game files and identify the game — v1.0
- ✓ Create isolated per-game Wine bottles — v1.0
- ✓ Apply configuration recipes (known or AI-generated) — v1.0
- ✓ Launch games from terminal (`cellar launch <game>`) — v1.0
- ✓ Detect and guide installation of dependencies (Homebrew, Wine via Gcenx tap) — v1.0
- ✓ AI-powered log interpretation and recipe generation (API-first) — v1.0
- ✓ User-confirmed launch validation ("Did the game reach the menu?") — v1.0
- ✓ Save working recipes for reuse and community sharing — v1.0
- ✓ Agentic launch with 18-tool Research-Diagnose-Adapt loop — v1.0
- ✓ Web search and page fetching for compatibility research — v1.0
- ✓ Diagnostic traces, DLL verification, success database — v1.0

### Active

<!-- v1.1: Agentic Independence -->

- [ ] Agent stays in diagnosis loop after game failure (doesn't exit prematurely)
- [ ] Agent detects Wine dialog boxes (renderer selection, error dialogs) via msgbox traces
- [ ] Agent pre-configures game settings to skip dialogs (INI files, registry)
- [ ] Agent performs deep research (PCGamingWiki API, structured extraction, cross-game patterns)
- [ ] Agent detects game engine type and applies engine-specific knowledge
- [ ] Agent uses macOS window detection to observe dialog/game state

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

- **Tech stack**: Swift 6 CLI+TUI — no GUI, terminal-based interface
- **Wine distribution**: Gcenx Homebrew tap (`gcenx/wine`) — official Homebrew wine-stable is deprecated
- **Wine engine**: wined3d → OpenGL for DX8/DX9 games. GPTK/D3DMetal optional for DX11+ (detect if installed, cannot redistribute)
- **AI inference**: API-first (Claude/OpenAI) — simpler to build, requires internet for AI features
- **Launch validation**: User-confirmed — ask the user if the game reached the menu, no automated screenshot analysis in v1
- **Recipe storage**: Local + Git repo — bundled recipes, community contributes via PRs
- **License**: Open source (GPL-3.0 aligns with Whisky/Heroic ecosystem)
- **Scope**: One game family first (old strategy games), expand from there

## Current Milestone: v1.1 Agentic Independence

**Goal:** Make the agent truly autonomous — it should detect dialog errors, deeply research game fixes, and persist through failures instead of giving up after one attempt.

**Target features:**
- Loop resilience: agent continues diagnosing after failures, handles max_tokens gracefully
- Dialog awareness: parse trace:msgbox output, detect Wine windows via CGWindowListCopyWindowInfo
- Game-aware pre-configuration: detect engine type (UE1, etc.), pre-set renderer in INI/registry to skip dialogs
- Deep research: PCGamingWiki Cargo API integration, structured data extraction, cross-game engine pattern database

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name: Cellar | Fits Wine/bottle metaphor, memorable, available | — Pending |
| Homebrew for Wine | Avoids bundling complexity, leverages existing package management | — Pending |
| API-first AI | Simpler to build than local inference, good enough for MVP | — Pending |
| User-confirmed validation | Avoids vision model complexity in v1, honest about what we can detect | — Pending |
| Cossacks: European Wars as flagship | 2001 RTS, DirectDraw/DX8, dedicated audience | — Pending |
| Recipes in Git repo | Community PRs, version-controlled, works offline with bundled set | — Pending |
| GPL-3.0 license | Aligns with Whisky/Heroic ecosystem, encourages contribution | — Pending |
| CLI+TUI instead of SwiftUI | Dramatically simpler, faster to build, no Xcode project needed | — Pending |
| Wine via Gcenx tap (not bundled) | Official wine-stable deprecated. Gcenx is the WineHQ macOS maintainer | — Pending |
| wined3d/OpenGL for DX8/DX9 | D3DMetal doesn't cover old DirectX. Only viable path for target wedge | — Pending |
| GPTK detect-only (not bundled) | Apple EULA prohibits redistribution of D3DMetal. Detect if installed. | — Pending |

---
*Last updated: 2026-03-28 after v1.1 milestone start*
