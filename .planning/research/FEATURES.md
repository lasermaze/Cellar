# Features Research: Cellar

**Domain:** macOS CLI+TUI Wine game launcher for old Windows games
**Date:** 2026-03-25

## Ecosystem Landscape

| Tool | Status | Approach | Relevance |
|------|--------|----------|-----------|
| Whisky | No longer actively maintained | Native macOS Wine wrapper, bottle management | Direct predecessor — proves demand, shows maintenance risk |
| CrossOver | Active (commercial) | Polished Wine wrapper, per-app bottles, CodeWeavers support | Gold standard UX, but paid and closed-source |
| Heroic | Active | Open-source game launcher, multi-store | macOS path uses CrossOver, not standalone Wine |
| Bottles | Active (Linux) | Flatpak Wine manager, environments, installers | Good UX inspiration but Linux-only |
| PlayOnMac | Stale | Wine wrapper with install scripts | Legacy approach, largely abandoned |
| Lutris | Active (Linux) | Script-based game installer/manager | Recipe/script model worth studying |
| Apple GPTK | Active | Evaluation/porting toolkit | Not a consumer launcher — ecosystem gap Cellar fills |

## Table Stakes (must have or users leave)

### Game Library Management
- **Add/import game files** — `cellar add /path/to/game` to register game directories
- **Game list with metadata** — title, last played, status (CLI list + TUI browse)
- **Launch command** — `cellar launch <game>` from terminal
- **Remove game** — clean removal including bottle cleanup option
- Complexity: Low-Medium
- Dependencies: Bottle Manager, Persistence

### Bottle Management
- **Per-game isolated bottles** — one WINEPREFIX per game, no shared state
- **Automatic bottle creation** — create on first import, user doesn't think about it
- **Bottle cleanup/reset** — wipe and recreate when things go wrong
- **Wine configuration exposure** — at minimum, winecfg access for advanced users
- Complexity: Medium
- Dependencies: Wine runtime detection

### Wine Runtime
- **Detect installed Wine** — find Homebrew Wine on the system
- **Guide Wine installation** — walk user through installing Homebrew + Wine if missing
- **Launch games via Wine** — spawn Wine process with correct WINEPREFIX and flags
- **Log capture** — capture stdout/stderr from Wine process
- Complexity: Medium
- Dependencies: None (foundational)

### Recipe System
- **Bundled recipes** — ship with known-good configs for supported games
- **Apply recipe on launch** — set registry keys, env vars, launch flags automatically
- **Recipe includes**: Wine version requirements, DLL overrides, registry edits, launch arguments, known workarounds
- Complexity: Medium
- Dependencies: Bottle Manager

## Differentiators (competitive advantage)

### AI-Powered Compatibility
- **Game identification** — AI reads file structure, EXE metadata, hashes to identify title
- **Log interpretation** — AI translates Wine crash logs into human-readable diagnosis
- **Recipe generation** — AI proposes configuration when no bundled recipe exists
- **Repair suggestions** — when launch fails, AI suggests specific fixes to try
- Complexity: Medium-High
- Dependencies: AI API integration, Log capture

### Self-Healing Launch Loop
- **Launch → validate → repair cycle** — try config, ask user if it worked, adjust if not
- **Multiple candidate configs** — try 3-5 setups and let user pick what works
- **Confidence scoring** — track which recipes work and how reliably
- Complexity: High
- Dependencies: Recipe System, AI, Validation

### Community Recipe Sharing
- **Export working recipe** — save what worked as a shareable file
- **Submit recipe via PR** — contribute back to the bundled recipe repo
- **Debug bundle export** — one-click export of logs, config, system info for bug reports
- Complexity: Medium
- Dependencies: Recipe System

### Guided Onboarding
- **First-run setup wizard** — detect system state, guide through Homebrew/Wine install
- **No-jargon language** — "Setting up your game" not "Creating WINEPREFIX"
- **Progress indicators** — show what's happening during bottle creation and setup
- Complexity: Low-Medium
- Dependencies: Wine runtime detection

## Anti-Features (deliberately NOT building)

| Anti-Feature | Why Not |
|--------------|---------|
| Game store / purchasing | Not a store — users bring their own game files |
| Cloud streaming | Everything runs locally on the user's Mac |
| Steam/Epic/GOG integration | Adds massive scope — just manage local game files |
| Built-in Wine fork | Maintenance trap, contributed to Whisky burnout |
| Compatibility database website | Start with bundled recipes in Git, not a web service |
| Windows app compatibility (non-games) | Scope creep — games only |
| Automatic game downloads | Legal minefield — user provides their own files |
| Multi-platform (Linux/Windows) | macOS-only — that's the whole point |

## Feature Dependencies

```
Wine Runtime Detection
  └── Bottle Manager
        └── Recipe System
              ├── AI Recipe Generation
              │     └── Self-Healing Loop
              └── Community Sharing
  └── Game Library
        └── Game Identification (AI)

Guided Onboarding (independent, but needs Wine detection)
Log Capture (parallel to Bottle Manager)
```

## MVP Prioritization

**v0.1 (prove it works):**
1. Wine detection + guided Homebrew install
2. Game import (manual file selection)
3. Per-game bottle creation
4. Bundled recipe for Cossacks: European Wars
5. One-click launch with log capture
6. Basic CLI commands + TUI browse

**v0.2 (add intelligence):**
7. AI game identification
8. AI log interpretation
9. AI recipe generation for unknown games
10. User-confirmed validation loop

**v0.3 (community):**
11. Recipe export/sharing
12. Debug bundle export
13. Community recipe submissions

---
*Researched: 2026-03-25*
