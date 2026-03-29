---
phase: 12-web-interface
plan: 03
subsystem: web
tags: [vapor, leaf, htmx, pico-css, crud, game-management]

# Dependency graph
requires:
  - phase: 12-web-interface
    provides: Vapor + Leaf foundation, GameService actor, LaunchService, base.leaf layout
  - phase: 01-foundation
    provides: CellarStore CRUD, GameEntry model, CellarPaths
provides:
  - GameController with full CRUD routes (GET /, GET /games, GET /games/add, POST /games, DELETE /games/:gameId)
  - Leaf templates for game library card grid, game card partial, add-game form, game-list partial
  - HTMX-powered interactions for add/delete without page reloads
affects: [12-04]

# Tech tracking
tech-stack:
  added: []
  patterns: [HTMX partial swap pattern for CRUD operations, Leaf extend/export/import template inheritance, actor-mediated controller pattern]

key-files:
  created:
    - Sources/cellar/Web/Controllers/GameController.swift
    - Sources/cellar/Resources/Views/index.leaf
    - Sources/cellar/Resources/Views/game-card.leaf
    - Sources/cellar/Resources/Views/add-game.leaf
    - Sources/cellar/Resources/Views/game-list.leaf
  modified:
    - Sources/cellar/Web/WebApp.swift

key-decisions:
  - "GameViewData.status derived from lastResult.reachedMenu rather than raw status field"
  - "Form field named installPath (matching GameEntry) not installerPath from plan"
  - "Extracted loadGameViewData helper to avoid duplicating game-to-viewmodel mapping across routes"

patterns-established:
  - "GameController enum pattern: static register() for Vapor route registration"
  - "HTMX partial swap: delete returns game-list partial, swaps #game-list div in-place"

requirements-completed: [WEB-01, WEB-02]

# Metrics
duration: 2min
completed: 2026-03-29
---

# Phase 12 Plan 03: Game Library CRUD Summary

**GameController with card grid UI, HTMX-powered add/delete, and Leaf templates extending base layout with Pico CSS**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-29T23:34:43Z
- **Completed:** 2026-03-29T23:37:03Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- GameController registers 5 routes for full game library CRUD
- Card grid UI shows game name, status (derived from launch results), last played date, and context-aware launch buttons
- HTMX delete swaps game list in-place without page reload; add form redirects to library
- Game cards show "Launch" + "Launch with AI" for direct-launch-eligible games, "Launch with AI" only otherwise

## Task Commits

Each task was committed atomically:

1. **Task 1: GameController with CRUD routes** - `2977bdb` (feat)
2. **Task 2: Leaf templates for game library UI** - `2733d18` (feat)

## Files Created/Modified
- `Sources/cellar/Web/Controllers/GameController.swift` - CRUD routes, view models, date formatting
- `Sources/cellar/Web/WebApp.swift` - Replaced placeholder route with GameController.register()
- `Sources/cellar/Resources/Views/index.leaf` - Game library page extending base with card grid
- `Sources/cellar/Resources/Views/game-card.leaf` - Individual game card with launch/delete buttons
- `Sources/cellar/Resources/Views/add-game.leaf` - Add game form with installer path input
- `Sources/cellar/Resources/Views/game-list.leaf` - Partial for HTMX delete swap

## Decisions Made
- Used `installPath` (matching actual GameEntry field) instead of `installerPath` from plan
- Derived game status from `lastResult.reachedMenu` ("Working"/"Needs Attention") rather than a raw status string field that does not exist on GameEntry
- Extracted shared `loadGameViewData()` helper to DRY up game-to-viewmodel mapping across 3 routes

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed field name mismatch: installerPath vs installPath**
- **Found during:** Task 1 (GameController implementation)
- **Issue:** Plan referenced `installerPath` but GameEntry uses `installPath`
- **Fix:** Used correct field name `installPath` throughout controller and form template
- **Files modified:** GameController.swift, add-game.leaf
- **Verification:** swift build succeeds
- **Committed in:** 2977bdb, 2733d18

**2. [Rule 1 - Bug] Fixed status derivation from non-existent field**
- **Found during:** Task 1 (GameViewData mapping)
- **Issue:** Plan used `game.status ?? "Ready"` but GameEntry has no `status` field; it has `lastResult: LaunchResult?`
- **Fix:** Derived status from `lastResult.reachedMenu`: "Working" if reached menu, "Needs Attention" if not, "Ready" if never launched
- **Files modified:** GameController.swift
- **Verification:** swift build succeeds
- **Committed in:** 2977bdb

---

**Total deviations:** 2 auto-fixed (2 bugs)
**Impact on plan:** Both fixes necessary for compilation against actual GameEntry model. No scope creep.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Game library UI ready for Plan 12-04 (launch log page with live agent streaming)
- Launch links point to /games/:gameId/launch routes that Plan 12-04 will implement
- HTMX + SSE infrastructure from base.leaf available for live agent event streaming

---
*Phase: 12-web-interface*
*Completed: 2026-03-29*
