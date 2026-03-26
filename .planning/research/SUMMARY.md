# Research Summary: Cellar

**Date:** 2026-03-25

## One-Line Summary

Cellar is a CLI+TUI tool that manages per-game Wine bottles on macOS, using AI to generate and refine configuration recipes for old Windows games — starting with Cossacks: European Wars on Apple Silicon.

## Key Findings

### Stack
- **Swift 6 CLI** with Swift Argument Parser + TUI (library TBD)
- **Zero or minimal dependencies** — Foundation covers process mgmt, HTTP, JSON
- **JSON persistence** in `~/.cellar/` — no database needed
- **Distribution:** Homebrew formula + GitHub release binary
- Swift TUI ecosystem is weak — may need raw ANSI or consider language alternatives if TUI quality matters

### Engine
- **Primary:** Wine via Gcenx Homebrew tap (`wine-crossover` from `gcenx/wine`)
- **DX translation for old games:** wined3d → OpenGL (deprecated but functional on macOS)
- **D3DMetal (GPTK) doesn't help** for DX8/DX9 games — only covers DX11/DX12
- **Future:** Detect GPTK if installed for DX11+ games (cannot redistribute D3DMetal — Apple EULA)
- **cnc-ddraw** as supplemental DirectDraw compatibility shim for games like Cossacks
- **Risk:** macOS OpenGL is deprecated. Only viable DX8/DX9 path. Monitor for breakage.

### Table Stakes
1. Game import (`cellar add`)
2. Per-game isolated bottles (one WINEPREFIX per game)
3. Bundled recipes with auto-apply on launch
4. Wine detection + guided Homebrew/Wine installation
5. Launch with log capture (`cellar launch`)
6. Bottle reset/cleanup (`cellar reset`)

### Differentiators
1. **AI-powered compatibility** — log interpretation, recipe generation, game identification
2. **Self-healing launch loop** — try config, validate, repair, retry
3. **Community recipe sharing** — export recipes, contribute via PRs
4. **Guided onboarding** — Wine-naive users can get started without knowing Wine

### Anti-Features (do NOT build)
- Game store / purchasing
- Steam/Epic/GOG integration
- Bundled Wine (maintenance trap)
- D3DMetal redistribution (illegal)
- Compatibility database website (premature)
- Multi-platform support
- Windows app compatibility (games only)

### Watch Out For
1. **Wine process lifecycle** — must track wineserver PIDs per bottle, clean up on exit
2. **Bottle cross-contamination** — always set WINEPREFIX explicitly, never use default
3. **Over-scoping** — Cossacks must work before adding more games or AI
4. **Deprecated OpenGL** — the only DX8/DX9 path on macOS, could break in future macOS
5. **Gcenx tap dependency** — single maintainer for macOS Wine Homebrew ecosystem
6. **Silent Wine failures** — Wine exits code 0 but game never rendered. Must capture + analyze logs.
7. **Apple Silicon path confusion** — Homebrew paths differ between ARM and Intel

### Architecture
- 9 components: CLI/TUI Shell, App State, Import Engine, Bottle Manager, Wine Process Layer, Recipe Engine, AI Subsystem, Persistence, Dependency Checker
- Build order driven by dependencies: Persistence → Bottle Manager → Wine Process → Import → Recipes → CLI/TUI → AI → Validation Loop
- All AI features optional — app works with bundled recipes only
- Bottle = directory, Recipe = JSON, Wine = fire-and-monitor process

### Ecosystem Context
- **Whisky** (archived May 2025): proves demand, shows maintenance risk. Used GPTK/CrossOver Wine underneath. Solo maintainer burned out.
- **CrossOver** ($75, commercial): gold standard, has D3DMetal license from Apple. Source published under LGPL.
- **Heroic**: macOS path uses CrossOver, not standalone Wine.
- **Gcenx**: single maintainer who runs the WineHQ macOS packages AND the Homebrew tap. Key dependency.
- **Homebrew `wine-stable`**: deprecated, disable date 2026-09-01. Gcenx tap is the replacement.

## Implications for Roadmap

1. **Phase 1 must deliver:** Swift CLI scaffold + dependency detection + bottle creation + Wine launch for Cossacks with a hardcoded recipe
2. **AI comes after** the manual launch flow works end-to-end
3. **TUI comes after** CLI commands work — it's sugar, not foundation
4. **Community features are last** — prove personal value first
5. **GPTK support is future scope** — not needed for the old-game wedge

---
*Synthesized: 2026-03-25*
