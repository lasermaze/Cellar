---
phase: 32-middleware-system
plan: 01
subsystem: agent-loop
tags: [swift, middleware, budget-tracking, spin-detection, agent-loop]

requires:
  - phase: 31-new-types
    provides: ToolResult enum and AgentControl class used by middleware protocol and context

provides:
  - AgentMiddleware protocol with beforeTool/afterTool/afterStep hooks
  - MiddlewareContext shared state class
  - BudgetTracker middleware (50% event, 80% message injection)
  - SpinDetector middleware (2-tool cycle and same-tool-4x detection)

affects: [33-middleware-wiring, 35-agent-loop-rewrite]

tech-stack:
  added: []
  patterns:
    - "Middleware pattern: protocol hooks (before/after/step) with shared MiddlewareContext"
    - "One-shot flag pattern: hasSentNudge/hasSentWarningMessage prevent duplicate injections"
    - "Context injection flags: middleware sets shouldInject* flags, loop reads and appends messages"

key-files:
  created:
    - Sources/cellar/Core/AgentMiddleware.swift
  modified: []

key-decisions:
  - "BudgetTracker sets context.shouldInjectBudgetWarning flag AND returns message from afterStep — loop reads either signal"
  - "SpinDetector appends to context.recentActionTools in afterTool (not in the loop body) — consistent with middleware ownership"
  - "MiddlewareContext is a class (reference type) so all middleware see mutations made by others during the same step"

patterns-established:
  - "Middleware protocol: beforeTool returns ToolResult? to short-circuit; afterStep returns String? to inject user message"
  - "Context flags: middleware signals intent via shouldInject* booleans; loop reads after afterStep completes"

requirements-completed: [MW-01, MW-02, MW-03]

duration: 2min
completed: 2026-04-02
---

# Phase 32 Plan 01: Middleware System Summary

**AgentMiddleware protocol, MiddlewareContext, BudgetTracker (50%/80% thresholds), and SpinDetector (2-tool cycle + same-tool-4x) added as standalone new file with no existing files modified**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-02T22:17:49Z
- **Completed:** 2026-04-02T22:19:54Z
- **Tasks:** 2
- **Files modified:** 1 (created)

## Accomplishments

- Created AgentMiddleware protocol with three hooks: beforeTool (can short-circuit), afterTool (observe), afterStep (can inject user message)
- Created MiddlewareContext class with control ref, iteration/cost tracking, recentActionTools rolling window, and injection flags
- Implemented BudgetTracker: emits .budgetWarning at 50%, injects warning message string at 80%, one-shot per threshold
- Implemented SpinDetector: tracks action tools in afterTool, detects A-B-A-B-A-B cycle and same-tool-4x in afterStep, one-shot nudge

## Task Commits

1. **Task 1: AgentMiddleware protocol and MiddlewareContext** - `a78207a` (feat)
2. **Task 2: BudgetTracker and SpinDetector middleware** - `0e893d1` (feat)

## Files Created/Modified

- `Sources/cellar/Core/AgentMiddleware.swift` - AgentMiddleware protocol, MiddlewareContext, BudgetTracker, SpinDetector

## Decisions Made

- BudgetTracker sets `context.shouldInjectBudgetWarning` flag AND returns the message from `afterStep` — gives the wiring layer two signals to use
- SpinDetector appends to `context.recentActionTools` in `afterTool` rather than in `beforeTool` — tracks completed calls, not attempted ones
- MiddlewareContext is a `final class` (reference type) so all middleware share mutation across a single step

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- AgentMiddleware.swift is ready for Phase 33 (middleware wiring into the loop)
- Phase 33 will create an EventLogger middleware (MW-04) and AgentEventLog (LOG-01) per the context file
- No blockers

---
*Phase: 32-middleware-system*
*Completed: 2026-04-02*
