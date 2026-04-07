---
phase: 37-supporting-win32-apps
plan: 02
subsystem: agent, ui
tags: [wine, pe-reader, win32, win64, bottle-arch, web-ui, diagnostics]

# Dependency graph
requires:
  - phase: 37-01
    provides: PEReader.detectArch(fileURL:) and GameEntry.bottleArch field

provides:
  - inspect_game tool output includes bottle_arch field (win32/win64/unknown)
  - AIService system prompt with arch-aware DLL placement guidance for win32 games
  - DiagnosticTools uses PEReader instead of inline PE header parsing
  - add-game.leaf form with architecture override dropdown
  - Full arch threading: form -> POST redirect -> GET install -> SSE stream -> GameEntry

affects:
  - Agent DLL placement decisions (now guided by bottle_arch)
  - Web install flow (arch override available before install)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "PEReader used as single source of truth for PE arch detection across CLI and web"
    - "Arch param threads through redirect chain as query param (omitted when auto)"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/Tools/DiagnosticTools.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Web/Controllers/GameController.swift
    - Sources/cellar/Resources/Views/add-game.leaf

key-decisions:
  - "inspect_game keeps exe_type for backward compat and adds bottle_arch as canonical arch field"
  - "arch query param omitted from redirect URL when auto/nil — clean URLs for default case"
  - "bottleArch in GameEntry uses arch override first, falls back to PE auto-detection"

patterns-established:
  - "PEReader.detectArch: single reusable PE detection replacing ad-hoc inline parsing"
  - "Query param threading pattern for optional install metadata through redirect chain"

requirements-completed: [PE-04, PE-05, PE-06]

# Metrics
duration: 8min
completed: 2026-04-06
---

# Phase 37 Plan 02: Win32 Arch Awareness — Agent + Web UI Summary

**Agent sees bottle_arch in inspect_game output for DLL placement; web add-game form gains arch override dropdown with full threading through the install redirect chain**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-06T01:02:49Z
- **Completed:** 2026-04-06T01:10:49Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- DiagnosticTools.inspectGame() now calls PEReader.detectArch() instead of inline PE parsing (fixes e_lfanew 2-byte read bug from Plan 01)
- inspect_game JSON output includes `bottle_arch` field alongside existing `exe_type` for backward compatibility
- AIService system prompt gains 5 arch-aware guidance bullets covering win32 DLL placement in syswow64, WoW64 bottle nature, and prohibition on recreating bottles with different arch
- add-game.leaf form has architecture select dropdown (Auto-detect / 32-bit / 64-bit) with hint text
- arch parameter threads through full chain: POST /games -> /games/install redirect -> /games/install/stream -> runInstall() -> GameEntry.bottleArch

## Task Commits

Each task was committed atomically:

1. **Task 1: Update DiagnosticTools and AIService for arch awareness** - `975731e` (feat)
2. **Task 2: Add arch override to web UI add-game form and install flow** - `91c2b31` (feat)

**Plan metadata:** (docs commit — see below)

## Files Created/Modified
- `Sources/cellar/Core/Tools/DiagnosticTools.swift` - Replaced inline PE parsing with PEReader.detectArch; added bottle_arch to JSON output
- `Sources/cellar/Core/AIService.swift` - Added 5 arch-aware guidance bullets to system prompt after wow64 line
- `Sources/cellar/Web/Controllers/GameController.swift` - AddGameInput.arch field; arch param threading; PEReader call in runInstall; bottleArch in GameEntry constructor
- `Sources/cellar/Resources/Views/add-game.leaf` - Architecture select dropdown with auto/win32/win64 options

## Decisions Made
- `inspect_game` keeps `exe_type` string field (backward compat) and adds `bottle_arch` as the canonical machine-readable field
- `arch` query param is omitted from redirect URLs when "auto" or nil — keeps URLs clean for the default case
- `bottleArch` stored in GameEntry uses arch override if provided, falls back to PE auto-detection from installer

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 37 complete: PEReader, GameEntry.bottleArch, AddCommand --arch, DiagnosticTools bottle_arch, AIService guidance, web UI arch override all wired
- 173 tests pass, swift build succeeds
- No known blockers

---
*Phase: 37-supporting-win32-apps*
*Completed: 2026-04-06*
