---
phase: 12-web-interface
plan: 01
subsystem: web
tags: [vapor, leaf, htmx, pico-css, swift-concurrency, actor]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: CellarStore CRUD, CellarPaths, GameEntry model
  - phase: 03-launch
    provides: RecipeEngine, DependencyChecker, launch workflow
provides:
  - Vapor + Leaf SPM dependencies configured for Swift 6
  - ServeCommand subcommand with async-to-sync bridge
  - WebApp configuration (Leaf, FileMiddleware, localhost server)
  - base.leaf HTML layout with HTMX + Pico CSS CDN
  - GameService actor for thread-safe CellarStore access
  - LaunchService for direct launch detection and Wine resolution
affects: [12-02, 12-03, 12-04]

# Tech tracking
tech-stack:
  added: [vapor 4.115+, leaf 4.4+, htmx 2.0.8, htmx-ext-sse 2.2.4, pico-css 2]
  patterns: [actor-based service layer, async-to-sync bridge via DispatchQueue+Task+Semaphore, @preconcurrency import for Vapor/Leaf]

key-files:
  created:
    - Sources/cellar/Commands/ServeCommand.swift
    - Sources/cellar/Web/WebApp.swift
    - Sources/cellar/Web/Services/GameService.swift
    - Sources/cellar/Web/Services/LaunchService.swift
    - Sources/cellar/Resources/Views/base.leaf
  modified:
    - Package.swift
    - Sources/cellar/Cellar.swift

key-decisions:
  - "@preconcurrency import Vapor/Leaf for Swift 6 strict concurrency compatibility"
  - "DispatchQueue+Task+Semaphore bridge for async Vapor in sync ParsableCommand context"
  - "SPM .copy(Resources) with Bundle.module.resourcePath for Leaf views resolution"
  - "ArgumentParser.Option disambiguation to avoid ConsoleKit Option conflict"

patterns-established:
  - "Web services as actors for thread-safe CellarStore access from concurrent Vapor requests"
  - "WebApp.configure pattern for Vapor app setup, extensible by future controllers"

requirements-completed: [WEB-05]

# Metrics
duration: 12min
completed: 2026-03-29
---

# Phase 12 Plan 01: Vapor Foundation Summary

**Vapor web server with Leaf templating, HTMX+Pico base layout, GameService actor, and LaunchService for direct-launch detection**

## Performance

- **Duration:** 12 min
- **Started:** 2026-03-29T23:20:00Z
- **Completed:** 2026-03-29T23:32:00Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Vapor 4.115+ and Leaf 4.4+ integrated with Swift 6 strict concurrency
- `cellar serve` subcommand boots Vapor on localhost:8080 with Leaf templating
- base.leaf provides dark-themed HTML shell with HTMX and Pico CSS CDN links
- GameService actor serializes CellarStore access for thread-safe web requests
- LaunchService provides canDirectLaunch check (recipes + success database) and Wine resolution

## Task Commits

Each task was committed atomically:

1. **Task 1: SPM dependencies, ServeCommand, and WebApp boilerplate** - `c5f3c6d` (feat)
2. **Task 2: GameService actor and LaunchService** - `4baff7f` (feat)
3. **Fix: Async-to-sync bridge for Vapor startup** - `04f277e` (fix)

## Files Created/Modified
- `Package.swift` - Added Vapor + Leaf dependencies and resource bundling
- `Sources/cellar/Cellar.swift` - Added ServeCommand to subcommands array
- `Sources/cellar/Commands/ServeCommand.swift` - `cellar serve` with --port option and async bridge
- `Sources/cellar/Web/WebApp.swift` - Vapor app configuration (Leaf, FileMiddleware, routes)
- `Sources/cellar/Web/Services/GameService.swift` - Actor wrapping CellarStore for thread safety
- `Sources/cellar/Web/Services/LaunchService.swift` - Direct launch detection and Wine resolution
- `Sources/cellar/Resources/Views/base.leaf` - Dark-themed HTML layout with HTMX + Pico CSS

## Decisions Made
- Used `@preconcurrency import Vapor` and `@preconcurrency import Leaf` for Swift 6 compatibility, following the existing `@preconcurrency import SwiftSoup` pattern
- Disambiguated `ArgumentParser.Option` vs ConsoleKit's `Option` with explicit module prefix
- Used `Application.make(env)` (async) instead of deprecated `Application(env)` init
- Bridged async Vapor startup into sync ParsableCommand via DispatchQueue + Task + Semaphore pattern
- SPM resources placed at `Sources/cellar/Resources/` with `.copy("Resources")` for Bundle.module access

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Application.make is async, not sync**
- **Found during:** Task 1 (ServeCommand implementation)
- **Issue:** `Application(env)` init is deprecated; replacement `Application.make(env)` is async, incompatible with sync `ParsableCommand.run()`
- **Fix:** Created DispatchQueue + Task + Semaphore bridge to run async Vapor server from sync context
- **Files modified:** Sources/cellar/Commands/ServeCommand.swift
- **Verification:** swift build succeeds
- **Committed in:** 04f277e

**2. [Rule 3 - Blocking] Option property wrapper ambiguity**
- **Found during:** Task 1 (ServeCommand compilation)
- **Issue:** `@Option` is ambiguous between ArgumentParser.Option and ConsoleKit.Option (brought by Vapor)
- **Fix:** Used fully qualified `@ArgumentParser.Option` prefix
- **Files modified:** Sources/cellar/Commands/ServeCommand.swift
- **Verification:** swift build succeeds
- **Committed in:** c5f3c6d

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes necessary for compilation. No scope creep.

## Issues Encountered
- Cannot verify `cellar serve` at runtime in this environment because the process runs as root and `CellarPaths.refuseRoot()` exits immediately. Build compilation verified; runtime testing deferred to user environment.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Vapor foundation ready for Plan 02 (agent event streaming callback)
- WebApp.configure extensible for route controllers in Plans 03-04
- GameService and LaunchService available for game management routes

## Self-Check: PASSED

- All 7 created/modified files verified on disk
- All 3 commits (c5f3c6d, 4baff7f, 04f277e) verified in git log
- `swift build` succeeds

---
*Phase: 12-web-interface*
*Completed: 2026-03-29*
