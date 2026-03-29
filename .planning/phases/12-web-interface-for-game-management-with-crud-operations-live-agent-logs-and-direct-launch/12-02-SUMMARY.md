---
phase: 12-web-interface
plan: 02
subsystem: core
tags: [agent-loop, streaming, callback, events, sendable]

requires:
  - phase: 06-implement-agentic-launch-architecture
    provides: AgentLoop struct with print-based output
provides:
  - AgentEvent enum with structured event cases for web streaming
  - onOutput callback on AgentLoop for external consumers
affects: [12-04-sse-streaming, web-interface]

tech-stack:
  added: []
  patterns: [emit-pattern for dual CLI+callback output]

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentLoop.swift

key-decisions:
  - "emit() always prints AND calls callback -- CLI behavior preserved unconditionally"
  - "AgentEvent.completed wraps AgentLoopResult, emitted via makeResult helper for all exit paths"
  - "toolResult case includes truncated output (200 chars) for web UI preview"

patterns-established:
  - "Emit pattern: replace direct print() with emit() that does both print and callback"

requirements-completed: [WEB-04]

duration: 5min
completed: 2026-03-29
---

# Phase 12 Plan 02: Agent Event Streaming Callback Summary

**AgentEvent enum with 9 structured cases and optional onOutput callback on AgentLoop for real-time web UI streaming**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-29T23:19:46Z
- **Completed:** 2026-03-29T23:25:20Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added AgentEvent enum with iteration, text, toolCall, toolResult, cost, budgetWarning, status, error, completed cases
- Added optional onOutput callback to AgentLoop with nil default for full backward compatibility
- Replaced all 15 print() calls in run() and callAnthropicWithRetry() with emit() calls
- Added explicit Sendable conformance to AgentStopReason and AgentLoopResult

## Task Commits

Each task was committed atomically:

1. **Task 1: Add AgentEvent enum and onOutput callback to AgentLoop** - `d4c3d9d` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AgentLoop.swift` - Added AgentEvent enum, onOutput property, emit() helper, replaced all print() with emit()

## Decisions Made
- emit() always prints AND calls callback -- ensures CLI output is identical to before regardless of callback presence
- AgentEvent.completed case wraps full AgentLoopResult, emitted from makeResult() so all exit paths (success, error, budget, max iterations) produce the event
- toolResult case truncates output to 200 chars for web UI preview without sending full tool output over SSE

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- AgentLoop now emits structured events via callback, ready for Plan 12-04 to wire SSE streaming
- AIService.runAgentLoop() will need a new overload accepting onOutput (planned in 12-04)
- All existing callers compile unchanged (onOutput defaults to nil)

---
*Phase: 12-web-interface*
*Completed: 2026-03-29*

## Self-Check: PASSED
