---
phase: 32-middleware-system
plan: "02"
subsystem: agent-loop
tags: [swift, jsonl, middleware, event-log, agent-loop]

requires:
  - phase: 32-01
    provides: AgentMiddleware protocol, MiddlewareContext, BudgetTracker, SpinDetector

provides:
  - AgentLogEntry Codable enum with 10 event types for JSONL session logging
  - AgentEventLog class with append-only JSONL write at ~/.cellar/logs/<gameId>-<timestamp>.jsonl
  - readAll() decoder and summarizeForResume() for session history reconstruction
  - EventLogger middleware that logs toolInvoked, toolCompleted, stepCompleted events

affects: [33-agent-loop-rewrite, agent-loop, session-handoff]

tech-stack:
  added: []
  patterns:
    - "JSONL append-only log: seek-to-end + write for existing files, atomic write for new files"
    - "EventLogger uses let eventLog: AgentEventLog — injected dependency, not a singleton"

key-files:
  created:
    - Sources/cellar/Core/AgentEventLog.swift
  modified:
    - Sources/cellar/Core/AgentMiddleware.swift

key-decisions:
  - "ISO8601 colons replaced with dashes in log filename to avoid filesystem issues on macOS"
  - "summarizeForResume() only collects toolInvoked, envChanged, gameLaunched — other entries are metrics, not resume-relevant"
  - "EventLogger.afterTool prefixes 200-char result summary with STOP:/ERROR: to distinguish result types at a glance"

patterns-established:
  - "JSONL per-session log: one file per session, append-only, easy to tail/stream"
  - "Middleware dependency injection: EventLogger receives AgentEventLog at init (not constructed internally)"

requirements-completed:
  - MW-04
  - LOG-01
  - LOG-02

duration: 1min
completed: 2026-04-03
---

# Phase 32 Plan 02: JSONL Event Log and EventLogger Middleware Summary

**AgentLogEntry (10-case Codable enum) + AgentEventLog (JSONL append writer) + EventLogger middleware completing the 3-middleware system**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-03T22:20:19Z
- **Completed:** 2026-04-03T22:21:15Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `AgentEventLog.swift` with `AgentLogEntry` enum (10 cases: sessionStarted through sessionEnded) and `AgentEventLog` JSONL writer class
- `AgentEventLog` writes to `~/.cellar/logs/<gameId>-<ISO8601-timestamp>.jsonl` using `CellarPaths.logsDir`, creates directory if needed
- `readAll()` decodes all JSONL lines, `summarizeForResume()` formats tool/env/launch history as a plain-text resume block
- Added `EventLogger` class to `AgentMiddleware.swift` — completes the three-middleware system (BudgetTracker, SpinDetector, EventLogger)

## Task Commits

1. **Task 1: Create AgentLogEntry and AgentEventLog** - `5dd613f` (feat)
2. **Task 2: Add EventLogger middleware to AgentMiddleware.swift** - `9ed6d75` (feat)

**Plan metadata:** (docs commit — pending)

## Files Created/Modified

- `Sources/cellar/Core/AgentEventLog.swift` — AgentLogEntry enum (10 cases) + AgentEventLog JSONL writer with append/readAll/summarizeForResume
- `Sources/cellar/Core/AgentMiddleware.swift` — EventLogger class appended after SpinDetector

## Decisions Made

- ISO8601 timestamp colons replaced with dashes in filename to avoid filesystem issues on macOS (`replacingOccurrences(of: ":", with: "-")`)
- `summarizeForResume()` only surfaces `toolInvoked`, `envChanged`, and `gameLaunched` entries — llmCalled/stepCompleted/budgetWarning are metrics, not resume-useful narrative
- `EventLogger.afterTool` prefixes 200-char result with "STOP:" or "ERROR:" to distinguish result types at a glance in the log

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- All three middleware classes (BudgetTracker, SpinDetector, EventLogger) now exist in `AgentMiddleware.swift`
- Phase 33 can wire these middleware into the rewritten `AgentLoop`
- `AgentEventLog` is ready to be instantiated per-session and passed to EventLogger

---
*Phase: 32-middleware-system*
*Completed: 2026-04-03*
