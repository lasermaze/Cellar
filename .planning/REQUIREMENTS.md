# Requirements: Cellar

**Defined:** 2026-03-25
**Core Value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Setup & Dependencies

- [x] **SETUP-01**: Cellar detects whether Homebrew is installed (ARM and Intel paths)
- [x] **SETUP-02**: Cellar detects whether Wine is installed via Gcenx Homebrew tap
- [x] **SETUP-03**: Cellar guides user through installing Homebrew if missing
- [x] **SETUP-04**: Cellar guides user through installing Wine (Gcenx tap) if missing
- [x] **SETUP-05**: Cellar detects whether GPTK is installed on the system

### Game Library

- [ ] **GAME-01**: User can add a game by providing a directory path (`cellar add /path`)
- [ ] **GAME-02**: User can remove a game and optionally clean up its bottle (`cellar remove`)

### Bottle Management

- [ ] **BOTTLE-01**: Cellar creates an isolated WINEPREFIX per game automatically on first launch
- [ ] **BOTTLE-02**: User can reset a game's bottle to a clean state (`cellar reset`)
- [ ] **BOTTLE-03**: User can open winecfg for a game's bottle (`cellar config`)

### Recipe System

- [ ] **RECIPE-01**: Cellar ships with a bundled recipe for Cossacks: European Wars
- [ ] **RECIPE-02**: Recipes auto-apply on launch (registry edits, DLL overrides, env vars, launch args)
- [ ] **RECIPE-03**: AI generates a candidate recipe for games without a bundled recipe
- [ ] **RECIPE-04**: Cellar can try multiple recipe variants when a launch fails

### Launch & Logs

- [ ] **LAUNCH-01**: User can launch a game via Wine with correct WINEPREFIX and recipe flags
- [ ] **LAUNCH-02**: Cellar captures Wine stdout/stderr to per-launch log files
- [ ] **LAUNCH-03**: After launch, Cellar asks user if the game reached the menu (validation prompt)
- [ ] **LAUNCH-04**: AI interprets Wine crash logs and provides human-readable diagnosis

### Community

- [ ] **COMM-01**: User can export a working recipe as a shareable JSON file

### Interface

- [ ] **CLI-01**: CLI commands: `add`, `launch`, `remove`, `reset`, `config`, `log`, `status`

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Interface

- **TUI-01**: Interactive TUI mode for browsing game library (lazygit/btop style)

### Game Library

- **GAME-03**: AI-powered game identification from EXE metadata and file hashes
- **GAME-04**: List games with metadata (`cellar list` with status, last played)

### Recipe System

- **RECIPE-05**: Confidence scoring on recipes (track reliability across launches)
- **RECIPE-06**: cnc-ddraw integration for DirectDraw games

### Community

- **COMM-02**: Debug bundle export (logs + config + system info in one command)
- **COMM-03**: Submit recipe via PR workflow guidance

### Setup

- **SETUP-06**: Detect Wine architecture (ARM vs x86_64/Rosetta) and warn on mismatch
- **SETUP-07**: Wine version reporting and compatibility warnings

## Out of Scope

| Feature | Reason |
|---------|--------|
| Game store / purchasing | Not a store — users bring their own game files |
| Steam/Epic/GOG integration | Massive scope increase, not core to the recipe layer |
| Cloud streaming | Everything runs locally on user's Mac |
| Bundled Wine | Maintenance trap — contributed to Whisky burnout |
| D3DMetal redistribution | Apple EULA prohibits it — detect-only |
| Custom graphics layer | Rely on Wine's wined3d and existing translation |
| Wine fork | Use upstream Wine via Gcenx Homebrew tap |
| Multi-platform | macOS-only |
| DX11/DX12 game support (v1) | Wedge is old DX8/DX9 games; GPTK detect for future |
| Native GUI (SwiftUI) | CLI-first for simplicity; TUI in v2 |
| Automatic game downloads | Legal issues — user provides their own files |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SETUP-01 | Phase 1 | Complete |
| SETUP-02 | Phase 1 | Complete |
| SETUP-03 | Phase 1 | Complete |
| SETUP-04 | Phase 1 | Complete |
| SETUP-05 | Phase 1 | Complete |
| BOTTLE-01 | Phase 1 | Pending |
| RECIPE-01 | Phase 1 | Pending |
| RECIPE-02 | Phase 1 | Pending |
| LAUNCH-01 | Phase 1 | Pending |
| LAUNCH-02 | Phase 1 | Pending |
| LAUNCH-03 | Phase 1 | Pending |
| RECIPE-03 | Phase 2 | Pending |
| LAUNCH-04 | Phase 2 | Pending |
| RECIPE-04 | Phase 3 | Pending |
| GAME-01 | Phase 4 | Pending |
| GAME-02 | Phase 4 | Pending |
| BOTTLE-02 | Phase 4 | Pending |
| BOTTLE-03 | Phase 4 | Pending |
| CLI-01 | Phase 4 | Pending |
| COMM-01 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 20
- Unmapped: 0

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-25 after roadmap revision to vertical slices*
