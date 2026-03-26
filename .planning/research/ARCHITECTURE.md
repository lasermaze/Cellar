# Architecture Research: Cellar

**Domain:** macOS CLI+TUI Wine game launcher with AI-powered recipe system
**Date:** 2026-03-25

## Component Overview

```
┌─────────────────────────────────────────────────┐
│              TUI Shell (Terminal UI)              │
│  (Library, Game Detail, Setup, Logs, Repair)     │
└──────────────────────┬──────────────────────────┘
                       │
              ┌────────┴────────┐
              │    App State     │
              └────────┬────────┘
                       │
    ┌──────────┬───────┼───────┬──────────┐
    │          │       │       │          │
┌───┴───┐ ┌───┴───┐ ┌─┴──┐ ┌──┴───┐ ┌───┴────┐
│Import │ │Bottle │ │Wine│ │Recipe│ │   AI   │
│Engine │ │Manager│ │Proc│ │Engine│ │Subsys  │
└───────┘ └───────┘ └────┘ └──────┘ └────────┘
                       │
              ┌────────┴────────┐
              │   Persistence    │
              │  (JSON files)    │
              └─────────────────┘
```

## Interface: CLI + TUI

**CLI commands** for scriptable operations:
```
cellar add /path/to/game/files
cellar launch cossacks
cellar repair cossacks
cellar recipe show cossacks
cellar log cossacks --last
cellar status
```

**TUI mode** for interactive use (lazygit/btop style):
```
cellar           # opens TUI
cellar tui       # explicit TUI mode
```

TUI shows game library, launch status, logs, repair actions in an interactive terminal interface.

**Implementation:** Swift CLI executable. TUI via a terminal UI library (candidates: custom ANSI rendering, or a Swift ncurses wrapper).

## Runtime Engine

### Primary: Wine via Gcenx Homebrew Tap
```
brew tap gcenx/wine
brew install --cask wine-crossover
```

For old DX8/DX9/DirectDraw games (the wedge):
```
Game (DirectDraw/DX8/DX9) → wined3d → OpenGL → macOS OpenGL stack → Metal
```

**Why Gcenx tap:** The official Homebrew `wine-stable` cask is deprecated (disable date 2026-09-01). Gcenx tap is the de facto standard, maintained by the official WineHQ macOS package maintainer.

### Future: Optional GPTK Detection
For DX11/DX12 games, detect if GPTK is installed and use its D3DMetal path:
```
Game (DX11/DX12) → D3DMetal → Metal
```

D3DMetal cannot be redistributed (Apple EULA). Cellar would detect an existing GPTK installation and use it. Same pattern Whisky used.

### Supplemental: cnc-ddraw
For DirectDraw games like Cossacks, cnc-ddraw is a compatibility shim that replaces ddraw.dll and provides better rendering. Can be included in recipes as a DLL override.

## Component Boundaries

### 1. CLI/TUI Shell
**Responsibility:** All user-facing interaction — command parsing, TUI rendering, input handling.
**Talks to:** App State only.
**Owns:** Argument parsing, terminal rendering, user input.

### 2. App State
**Responsibility:** Coordinates between subsystems. Tracks game library, active processes, operation status.
**Talks to:** All subsystems.
**Pattern:** Central state object, not a database — JSON files on disk for persistence.

### 3. Import Engine
**Responsibility:** Scans game directories, extracts EXE metadata (PE headers), computes file hashes, identifies games.
**Talks to:** App State, AI Subsystem (for identification when needed).
**Owns:** File scanning, hash computation, metadata extraction.

### 4. Bottle Manager
**Responsibility:** Creates, configures, resets, deletes Wine bottles. One WINEPREFIX per game.
**Talks to:** Wine Process Layer (runs wineboot, regedit), Recipe Engine (applies config).
**Owns:** Bottle lifecycle, WINEPREFIX directory management.
**Bottle path:** `~/.cellar/bottles/{game-id}/`

### 5. Wine Process Layer
**Responsibility:** Spawns and monitors Wine processes. Captures stdout/stderr. Manages process lifecycle.
**Talks to:** Bottle Manager (receives WINEPREFIX), App State (reports status).
**Owns:** Process spawning via Foundation.Process, log streaming via Pipe, exit code handling, wineserver management.
**Critical:** Track wineserver PID per bottle. On app quit, terminate all wineservers.

### 6. Recipe Engine
**Responsibility:** Loads, applies, saves game recipes. Matches games to recipes. Manages recipe variants for retry.
**Talks to:** Bottle Manager, AI Subsystem, Persistence.
**Owns:** Recipe schema (JSON), recipe matching, recipe application (registry edits, DLL overrides, env vars, launch args).

### 7. AI Subsystem
**Responsibility:** All AI API calls. Log interpretation, game identification, recipe generation.
**Talks to:** External APIs (Claude/OpenAI). Called by Import Engine, Recipe Engine, App State.
**Owns:** API key management (macOS Keychain), prompt construction, response parsing.
**Pattern:** Async, optional. App works fully without AI using bundled recipes.

### 8. Persistence
**Responsibility:** Stores game library, recipes, launch history, settings.
**Approach:** JSON files in `~/.cellar/` — no database. Simple, inspectable, version-controllable.

### 9. Dependency Checker
**Responsibility:** Detects Homebrew, Wine (Gcenx tap), optional GPTK. Guides installation.
**Talks to:** App State, TUI Shell (for guided install flow).

## Data Flows

### Flow 1: Game Import
```
cellar add /path/to/cossacks/
  → Import Engine scans directory
  → Extracts EXE metadata + file hashes
  → Checks bundled recipe index for match
  → (if no match + AI configured) asks AI to identify
  → Creates game entry in ~/.cellar/games.json
  → TUI/CLI confirms: "Added: Cossacks: European Wars"
```

### Flow 2: First Launch
```
cellar launch cossacks
  → Check Wine installed (Dependency Checker)
  → Create bottle if needed (Bottle Manager → wineboot)
  → Find recipe (Recipe Engine → bundled or AI-generated)
  → Apply recipe to bottle (registry edits, DLL overrides)
  → Spawn Wine process with WINEPREFIX (Wine Process Layer)
  → Stream logs to terminal + log file
  → On exit: "Did the game reach the menu? [y/n]"
```

### Flow 3: Repair Loop
```
cellar repair cossacks
  → Read last launch logs
  → Send to AI for interpretation
  → AI suggests config changes
  → Show suggestions: "Try: disable intro video, switch to windowed mode"
  → User approves → Recipe Engine applies variant
  → Re-launch with new config
```

### Flow 4: Subsequent Launch (fast path)
```
cellar launch cossacks
  → Verified recipe exists → apply and launch
  → No validation prompt unless --verify flag
```

## Build Order

| Order | Component | Depends On | Deliverable |
|-------|-----------|------------|-------------|
| 1 | Project scaffold + Dependency Checker | Nothing | Swift CLI that detects Wine |
| 2 | Bottle Manager + Wine Process Layer | Swift CLI | Can create bottle and spawn Wine |
| 3 | Import Engine (basic, no AI) | Persistence | Can add game files |
| 4 | Recipe Engine (bundled, Cossacks recipe) | Bottle Manager | Can apply config and launch |
| 5 | CLI commands + basic TUI | All above | Usable product for one game |
| 6 | AI Subsystem | Recipe Engine | Log interpretation, recipe generation |
| 7 | Repair loop + validation | AI, Recipe Engine | Self-healing launch cycle |
| 8 | Community features | Recipe Engine | Recipe export/sharing |

## Key Patterns

1. **Bottle = directory.** `~/.cellar/bottles/{id}/` is the WINEPREFIX. Nothing more.
2. **Recipe = JSON file.** Declarative: what to configure. Bottle Manager interprets.
3. **Wine = fire and monitor.** Spawn, pipe logs, watch for exit. Never block.
4. **AI = optional.** Every AI feature has a non-AI fallback.
5. **CLI-first.** TUI is sugar on top of CLI commands. Both work.
6. **JSON persistence.** No database. Files in `~/.cellar/`. Inspectable and portable.

---
*Researched: 2026-03-25*
