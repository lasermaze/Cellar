---
phase: 34-update-agenttools
plan: "01"
subsystem: agent
tags: [swift, agenttools, toolresult, agentcontrol, typed-results]

# Dependency graph
requires:
  - phase: 31-new-types
    provides: ToolResult enum and AgentControl class consumed here
  - phase: 33-rewrite-the-loop
    provides: AgentLoop.run() that will consume the new ToolResult return type
provides:
  - AgentTools.execute() returning typed ToolResult instead of String
  - var control: AgentControl! for thread-safe flag reads in execute()
  - private trackPendingAction() helper extracted from execute()
  - Elimination of fire-and-forget inline save race condition (BUG-01)
affects: [35-update-callers, AIService.runAgentLoop]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "execute() returns ToolResult enum — callers pattern-match .success/.stop/.error instead of parsing STOP strings"
    - "Control flags accessed via control.shouldAbort/userForceConfirmed — thread-safe via OSAllocatedUnfairLock in AgentControl"
    - "userForceConfirmed returns .stop immediately — no inline save; post-loop save wired in Phase 35"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "execute() returns .stop(reason: .userConfirmedWorking) on userForceConfirmed — actual save deferred to post-loop in AIService (Phase 35)"
  - "trackPendingAction() extracted as private method — cleaner separation of dispatch vs side-effect tracking"
  - "TaskState enum, taskState var, isTaskComplete computed property fully removed — control flow is now caller's responsibility via ToolResult"

patterns-established:
  - "ToolResult wrapping: all dispatch cases use resultString local var then return .success(content: resultString)"
  - "Unknown tool: return .error(content:) — typed error, not silent string fallback"

requirements-completed: [ARCH-01, BUG-01]

# Metrics
duration: 8min
completed: 2026-04-02
---

# Phase 34 Plan 01: Update AgentTools Summary

**AgentTools.execute() rewritten to return typed ToolResult enum with thread-safe AgentControl for shouldAbort/userForceConfirmed — eliminating the fire-and-forget save race condition (BUG-01)**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-02T00:00:00Z
- **Completed:** 2026-04-02T00:08:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Removed bare `shouldAbort`, `userForceConfirmed` mutable vars, `TaskState` enum, `taskState` var, and `isTaskComplete` computed property from AgentTools
- Added `var control: AgentControl!` to replace the bare vars with thread-safe access
- Rewrote `execute()` to return `ToolResult` — `.success(content:)`, `.stop(content:reason:)`, or `.error(content:)` instead of String
- Extracted pending action tracking into private `trackPendingAction()` method
- Eliminated the fire-and-forget save block (old lines 595-606) — `userForceConfirmed` now returns `.stop` only, post-loop save wired in Phase 35

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove bare vars, add AgentControl, remove TaskState** - `282f5cb` (refactor)
2. **Task 2: Rewrite execute() to return ToolResult, extract trackPendingAction()** - `cc27f26` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AgentTools.swift` - execute() returns ToolResult, bare vars replaced by control: AgentControl!, TrackPendingAction() extracted

## Decisions Made
- `execute()` returns `.stop(reason: .userConfirmedWorking)` on `userForceConfirmed` — actual save deferred to post-loop in AIService (Phase 35), not inline here
- `trackPendingAction()` extracted as private method — dispatch switch stays clean
- `TaskState` enum fully removed — loop control is now entirely via ToolResult return values and AgentControl

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Build is expected to fail after this phase (AIService still uses old String return type — fixed in Phase 35).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- AgentTools.execute() now returns ToolResult — Phase 35 (update-callers) can wire AIService.runAgentLoop() to consume typed results
- AgentControl wired into AgentTools — AIService just needs to instantiate AgentControl and assign to tools.control before loop
- Fire-and-forget save race condition eliminated — post-loop save in Phase 35 will be the single save path

---
*Phase: 34-update-agenttools*
*Completed: 2026-04-02*
