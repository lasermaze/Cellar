---
phase: 03-repair-loop
plan: 02
subsystem: launch
tags: [wine, ai, repair-loop, recipe, retry]

# Dependency graph
requires:
  - phase: 03-01
    provides: AIService.generateVariants(), AIVariantResult, CellarPaths.repairReportFile(), WineResult.timedOut

provides:
  - LaunchCommand single-loop AI variant injection (no duplicated launch body)
  - Winning AI variant auto-saved as user recipe via RecipeEngine.saveUserRecipe()
  - Structured repair report written to ~/.cellar/logs/{game}/repair-report-{timestamp}.txt on exhaustion
  - Hung launches (timedOut) treated as failed attempts, advancing to next variant

affects: [future-phases, testing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single while loop with AI injection mid-loop — avoids duplicating ~60 lines of launch/SIGINT/error-parsing code"
    - "aiVariantsGenerated flag ensures AI called at most once per launch session"
    - "winningConfigIndex + originalEnvConfigsCount determine if winning config came from AI stage"

key-files:
  created: []
  modified:
    - Sources/cellar/Commands/LaunchCommand.swift

key-decisions:
  - "maxTotalAttempts raised from 5 to 10 to accommodate AI variant budget (3 AI variants + existing budget)"
  - "AI variant injection uses same loop body as bundled variants — no code duplication"
  - "Exhaustion condition broadened to include timedOut to catch hung launches that exhaust the attempt budget"
  - "Recipe save only triggers when winning config came from AI stage (winningConfigIndex >= originalEnvConfigsCount)"
  - "Minimal recipe created when no base recipe exists for game, using executablePath as executable"

patterns-established:
  - "Loop extension pattern: change while condition to (existing || !newStageGenerated) then inject new items at loop top"

requirements-completed: [RECIPE-04]

# Metrics
duration: 1min
completed: 2026-03-27
---

# Phase 3 Plan 02: Repair Loop Integration Summary

**LaunchCommand self-healing loop: AI variant injection mid-loop, winning config auto-saved as recipe, exhaustion writes structured repair report**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-27T18:56:17Z
- **Completed:** 2026-03-27T18:57:39Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Single while loop extended with AI variant injection — no duplicated launch/SIGINT/error-parsing code
- Hung launches (timedOut) treated as failed attempts, loop advances to next variant
- AI variants requested exactly once per launch (aiVariantsGenerated flag)
- AI reasoning printed inline before first AI variant is tried
- Winning AI variant auto-saved as user recipe with config diff displayed
- Repair report with full attempt history, per-attempt environments, errors, and best diagnosis written on exhaustion

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend retry loop with AI variant injection and hung-launch handling** - `88c4c37` (feat)
2. **Task 2: Recipe save on success and repair report on exhaustion** - `66eeccc` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `Sources/cellar/Commands/LaunchCommand.swift` - Extended retry loop with AI injection, timedOut handling, recipe save, repair report

## Decisions Made
- maxTotalAttempts raised from 5 to 10: gives headroom for AI variant budget (up to 3 AI variants) on top of existing bundled variants plus dep-install retries
- Exhaustion condition updated to `(finalResult.elapsed < 2.0 || finalResult.timedOut)`: ensures hung launches that hit attempt ceiling are reported via repair report path rather than falling through to validation prompt
- Minimal recipe construction when `recipe == nil`: uses `executablePath` (already resolved earlier in run()) as executable, `"ai-generated"` as source — allows any game without a bundled recipe to benefit from AI variant saves

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- RECIPE-04 complete: self-healing repair loop is fully integrated
- Phase 03 is complete (both plans done)
- Repair loop infrastructure from Plan 01 + integration from Plan 02 = complete self-healing launch pipeline

---
*Phase: 03-repair-loop*
*Completed: 2026-03-27*
