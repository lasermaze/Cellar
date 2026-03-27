---
phase: 03-repair-loop
plan: 01
subsystem: core
tags: [wine, ai, process-management, stale-timeout, swift6]

# Dependency graph
requires:
  - phase: 02-ai-intelligence
    provides: AIService, AIResult<T>, withRetry, makeAPICall, extractJSON patterns
  - phase: 01.1-reactive-dependencies
    provides: WineProcess, OutputMonitor/NSLock pattern, WinetricksRunner
provides:
  - WineProcess.run() stale-output hang detection with 5-min timeout
  - AIVariantResult struct (variants: [RetryVariant], reasoning: String)
  - CellarPaths.repairReportFile(for:timestamp:) path helper
  - AIService.generateVariants() method returning AIResult<AIVariantResult>
affects: [03-02-PLAN.md, LaunchCommand repair loop integration]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - OutputMonitor with NSLock + @unchecked Sendable (same as WinetricksRunner) in WineProcess
    - generateVariants follows same detectProvider + _private + withRetry + makeAPICall + extractJSON pattern as diagnose/generateRecipe
    - Error summary capped at 500 chars per attempt entry in AI prompt (prevent token explosion)

key-files:
  created: []
  modified:
    - Sources/cellar/Core/WineProcess.swift
    - Sources/cellar/Models/AIModels.swift
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "generateVariants prompt explicitly prohibits registry edits and winetricks — env vars and WINEDLLOVERRIDES only"
  - "Attempt history error summaries capped at 500 chars to prevent prompt token explosion"
  - "parseVariantsResponse caps at 3 variants via .prefix(3) matching plan spec"
  - "waitUntilExit() retained only in initPrefix() and killWineserver() — appropriate for short-lived commands not needing hang detection"

patterns-established:
  - "AI method pattern: public entry guard detectProvider → private _impl(provider:) → withRetry + makeAPICall → parseXxxResponse"
  - "AI prompt constraint: always explicitly list what AI must NOT do (no registry edits, no winetricks) alongside what it can do"

requirements-completed: [RECIPE-04]

# Metrics
duration: 8min
completed: 2026-03-27
---

# Phase 3 Plan 01: Repair Loop Infrastructure Summary

**WineProcess stale-output hang detection (5-min polling loop), AIVariantResult model, CellarPaths repair report path, and AIService.generateVariants() with cumulative attempt history and env-only constraint**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-27T18:00:00Z
- **Completed:** 2026-03-27T18:08:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- WineProcess.run() now polls for stale output every 2s, kills process + wineserver after 5 min of silence, returns timedOut=true
- AIVariantResult struct added to AIModels.swift as the return type for AI-generated launch variants
- CellarPaths.repairReportFile() provides consistent path under ~/.cellar/logs/{gameId}/repair-report-{timestamp}.txt
- AIService.generateVariants() accepts cumulative attempt history, builds structured prompt, parses up to 3 RetryVariant objects

## Task Commits

Each task was committed atomically:

1. **Task 1: WineProcess stale-output hang detection + AIVariantResult model + CellarPaths helper** - `b00822d` (feat)
2. **Task 2: AIService.generateVariants() method** - `5f95b9e` (feat)

## Files Created/Modified
- `Sources/cellar/Core/WineProcess.swift` - Added OutputMonitor class, replaced waitUntilExit() with 5-min stale polling loop, returns timedOut: didTimeout
- `Sources/cellar/Models/AIModels.swift` - Added AIVariantResult struct with variants: [RetryVariant] and reasoning: String
- `Sources/cellar/Persistence/CellarPaths.swift` - Added repairReportFile(for:timestamp:) returning URL under logDir
- `Sources/cellar/Core/AIService.swift` - Added generateVariants() public entry + _generateVariants() private impl + parseVariantsResponse()

## Decisions Made
- generateVariants system prompt explicitly prohibits registry edits and winetricks installs — plan constraint enforced at prompt level
- Attempt history error summaries capped at 500 chars per entry to prevent AI context window overflow (per RESEARCH.md anti-pattern)
- waitUntilExit() retained in initPrefix() and killWineserver() — hang detection is only needed in the game run() method, not for brief administrative commands
- parseVariantsResponse uses compactMap to skip malformed variant objects rather than failing the whole response

## Deviations from Plan

None - plan executed exactly as written. Task 1 infrastructure was already present in the working tree (applied as part of prior planning work) but uncommitted; committed here as the plan's Task 1 commit.

## Issues Encountered
None - both tasks compiled cleanly on first attempt.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All infrastructure building blocks are ready for Plan 02 (LaunchCommand integration)
- generateVariants() callable with correct signature: gameId, gameName, currentEnvironment, attemptHistory
- WineProcess.run() timedOut flag available for repair loop to detect hung sessions
- CellarPaths.repairReportFile() available for writing repair reports after multi-attempt sessions

---
*Phase: 03-repair-loop*
*Completed: 2026-03-27*
