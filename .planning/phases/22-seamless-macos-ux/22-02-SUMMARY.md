---
phase: 22-seamless-macos-ux
plan: "02"
subsystem: cli
tags: [wine, game-removal, cleanup, artifact-management]

# Dependency graph
requires:
  - phase: 22-seamless-macos-ux-01
    provides: actionable errors established in CLI commands
provides:
  - GameRemover shared service deleting all 9 artifact types per game
  - cellar remove CLI command with --yes flag and confirmation prompt
  - Web UI delete button upgraded to full artifact cleanup via GameRemover
affects: [future phases that manage game lifecycle, web UI game management]

# Tech tracking
tech-stack:
  added: []
  patterns: [shared removal service pattern — GameRemover centralizes all artifact deletion logic for both CLI and web UI consumers]

key-files:
  created:
    - Sources/cellar/Core/GameRemover.swift
    - Sources/cellar/Commands/RemoveCommand.swift
  modified:
    - Sources/cellar/Cellar.swift
    - Sources/cellar/Web/Services/GameService.swift

key-decisions:
  - "GameRemover always deletes all artifacts regardless of cleanBottle parameter — web delete now always does full cleanup"
  - "games.json removal is the critical step (throws on failure); artifact deletion uses try? so missing files are silently skipped"
  - "cleanBottle parameter retained in GameService.deleteGame() for API compatibility but ignored internally"

patterns-established:
  - "Shared removal service: single GameRemover.remove() call used by both CLI (RemoveCommand) and web UI (GameService)"
  - "Actionable errors: unknown game ID prints 'Try this:' suggestion with concrete next steps"

requirements-completed: [UX-03]

# Metrics
duration: 2min
completed: 2026-04-01
---

# Phase 22 Plan 02: Game Removal Summary

**GameRemover shared service deletes all 9 artifact types (bottle, logs, recipe, successdb, session, diagnostics, research/lutris/protondb cache) via new `cellar remove` CLI command and upgraded web delete**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-01T01:59:12Z
- **Completed:** 2026-04-01T02:01:30Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- GameRemover.swift created as shared service removing all 9 artifact paths per game
- `cellar remove <game-id>` CLI command with interactive confirmation prompt and `--yes` skip flag
- Actionable error message when game ID not found, with "Try this:" suggestion
- Web UI deleteGame() upgraded from partial cleanup (bottle only) to full artifact cleanup via GameRemover

## Task Commits

Each task was committed atomically:

1. **Task 1: Create GameRemover service and RemoveCommand** - `9a11755` (feat)
2. **Task 2: Upgrade web delete to use GameRemover** - `68cfc7a` (feat)

**Plan metadata:** committed with docs commit below

## Files Created/Modified
- `Sources/cellar/Core/GameRemover.swift` - Shared service deleting all 9 game artifact paths
- `Sources/cellar/Commands/RemoveCommand.swift` - CLI command with confirmation prompt and --yes flag
- `Sources/cellar/Cellar.swift` - RemoveCommand registered in subcommands array
- `Sources/cellar/Web/Services/GameService.swift` - deleteGame() delegates to GameRemover.remove()

## Decisions Made
- GameRemover always performs full cleanup regardless of the `cleanBottle` parameter — the parameter is kept for API compatibility but the correct behavior (per UX-03) is always full cleanup
- games.json update is the critical step that throws; all artifact removals use `try?` so missing files don't block removal
- cleanBottle parameter retained in GameService.deleteGame() signature to avoid breaking callers

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
- Transient "input file modified during build" error on first two build attempts due to pre-existing `AddCommand.swift` modifications on disk; resolved on third build attempt with no code changes needed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Game removal is fully operational via both CLI and web UI
- Ready for Phase 22 Plan 03 (first-run setup or remaining UX improvements)
- No blockers

## Self-Check: PASSED

All files confirmed present. All commits verified in git log.

---
*Phase: 22-seamless-macos-ux*
*Completed: 2026-04-01*
