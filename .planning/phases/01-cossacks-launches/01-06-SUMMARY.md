---
phase: 01-cossacks-launches
plan: 06
subsystem: cli
tags: [wine, winetricks, bottle-scanner, retry-loop, error-diagnosis, agentic]

# Dependency graph
requires:
  - phase: 01-05
    provides: WineResult, WineErrorParser, BottleScanner, winetricks dependency, Recipe.setupDeps/installDir/retryVariants

provides:
  - AddCommand multi-step pipeline: bottle + winetricks deps + GOG installer + BottleScanner + validation + save
  - LaunchCommand self-healing retry loop: base config + retry variants (up to 3 attempts)
  - GameEntry.executablePath populated from BottleScanner results
  - LaunchResult.attemptCount and .diagnosis for post-failure reporting
  - WineErrorParser exhaustion report with suggested fixes

affects:
  - future CLI phases (recipe authoring, game library management)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - winetricks subprocess pattern: Process with readabilityHandler streaming, WINEPREFIX env var
    - retry loop with variant cycling: base config + retryVariants from recipe, capped at 3
    - ValidationPrompt returns Bool? (reachedMenu); caller constructs full LaunchResult with attemptCount

key-files:
  created: []
  modified:
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Commands/LaunchCommand.swift
    - Sources/cellar/Models/GameEntry.swift
    - Sources/cellar/Models/LaunchResult.swift
    - Sources/cellar/Core/ValidationPrompt.swift

key-decisions:
  - "ValidationPrompt.run() returns Bool? instead of LaunchResult — LaunchCommand constructs full result with attemptCount and diagnosis; this decouples validation UI from result serialization"
  - "Retry loop capped at 3 attempts (min of envConfigs count and 3) per AGENT-09 spec"
  - "Exhaustion detection: finalResult.elapsed < 2.0 AND exitCode != 0 AND attemptCount >= maxAttempts"
  - "Legacy backward compat: games without executablePath fall back to hardcoded GOG path + recipe.executable"

patterns-established:
  - "Winetricks subprocess: spawn Process with readabilityHandler streaming (same pattern as WineProcess.run)"
  - "Post-install validation: BottleScanner.scanForExecutables + findExecutable(named:in:) for recipe match"
  - "Retry loop: envConfigs array built once, iterate with labeled attempts, break on success (elapsed > 2s or exit 0)"

requirements-completed: [AGENT-02, AGENT-05, AGENT-06, AGENT-09, AGENT-10, AGENT-11]

# Metrics
duration: 7min
completed: 2026-03-26
---

# Phase 01 Plan 06: Agentic Pipeline Wiring Summary

**Full agentic CLI pipeline wired: AddCommand installs winetricks deps + scans bottle, LaunchCommand retries up to 3 variants with WineErrorParser exhaustion report**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-03-26T05:04:03Z
- **Completed:** 2026-03-26T05:11:08Z
- **Tasks:** 2 of 3 complete (Task 3 is checkpoint:human-verify)
- **Files modified:** 5

## Accomplishments

- AddCommand is now a full multi-step pipeline: bottle creation -> winetricks setupDeps -> GOG installer -> BottleScanner post-install scan -> installDir validation -> GameEntry with executablePath saved
- LaunchCommand has a self-healing retry loop: base recipe env + up to 2 retry variants (capped at 3 total), each attempt labeled "Trying variant N/M: description"
- On exhaustion, prints actionable report: each attempt description + diagnosed errors + best diagnosis with suggested fix (winetricks verb, env var, or DLL override)
- GameEntry.executablePath persisted from BottleScanner — LaunchCommand uses stored path with legacy fallback for pre-01-06 entries
- LaunchResult now carries attemptCount and diagnosis for historical record

## Task Commits

1. **Task 1: Enhance AddCommand with winetricks deps, BottleScanner, and post-install validation** - `53cfda4` (feat)
2. **Task 2: Implement self-healing retry loop in LaunchCommand** - `5998a47` (feat)

## Files Created/Modified

- `Sources/cellar/Commands/AddCommand.swift` - Multi-step pipeline: winetricks deps (step 6), BottleScanner scan+validation (step 8), executablePath stored in GameEntry (step 9)
- `Sources/cellar/Commands/LaunchCommand.swift` - Self-healing retry loop with WineErrorParser diagnosis, exhaustion report, backward-compatible executable path resolution
- `Sources/cellar/Models/GameEntry.swift` - Added `executablePath: String?` mutable field (AGENT-06)
- `Sources/cellar/Models/LaunchResult.swift` - Added `attemptCount: Int` and `diagnosis: String?` fields (AGENT-11)
- `Sources/cellar/Core/ValidationPrompt.swift` - Returns `Bool?` (reachedMenu) instead of `LaunchResult` — decouples prompt from result construction

## Decisions Made

- ValidationPrompt.run() returns `Bool?` instead of `LaunchResult` — LaunchCommand constructs the full LaunchResult with attemptCount and diagnosis. This is cleaner separation: the prompt knows only about the user's answer, not about how many retries happened.
- Retry loop uses `min(envConfigs.count, 3)` — if recipe has no retryVariants, only 1 attempt is made (no pointless retrying with identical config)
- Exhaustion detection requires all three conditions: elapsed < 2s AND exitCode != 0 AND attemptCount >= maxAttempts — if game ran for > 2s and then crashed, it still goes to validation prompt (user can report it)
- Legacy backward compat: entries without `executablePath` fall back to hardcoded `drive_c/GOG Games/Cossacks - European Wars/{recipe.executable}` path

## Deviations from Plan

**1. [Rule 1 - Bug] ValidationPrompt return type mismatch**
- **Found during:** Task 2 build verification
- **Issue:** ValidationPrompt.run() still returned `LaunchResult` after LaunchResult gained new required fields (attemptCount, diagnosis) — build error: `cannot assign value of type 'Bool' to type 'LaunchResult'`
- **Fix:** The plan specified changing ValidationPrompt to return `Bool?` — this was executed as part of Task 1 (ValidationPrompt.swift updated alongside LaunchResult.swift). LaunchCommand then constructs the full LaunchResult.
- **Files modified:** Sources/cellar/Core/ValidationPrompt.swift (included in Task 1 commit)
- **Verification:** swift build succeeds cleanly
- **Committed in:** 53cfda4 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — type mismatch, caught during compilation)
**Impact on plan:** Required fix, no scope creep. The plan explicitly described this change.

## Issues Encountered

None beyond the ValidationPrompt build error described above.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Full agentic pipeline operational for code-path verification
- Task 3 (checkpoint:human-verify) requires human to test with real GOG Cossacks installer
- After human verification, Phase 1 is functionally complete for the Cossacks use case
- Known limitation: winetricks subprocess pattern is separate from WineProcess abstraction — could be unified in a future refactor if other commands need winetricks

---
*Phase: 01-cossacks-launches*
*Completed: 2026-03-26*
