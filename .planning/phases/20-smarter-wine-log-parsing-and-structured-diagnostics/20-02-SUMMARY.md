---
phase: 20-smarter-wine-log-parsing-and-structured-diagnostics
plan: 02
subsystem: agent
tags: [wine, diagnostics, agent-tools, ai-service, error-parsing]

# Dependency graph
requires:
  - phase: 20-01
    provides: WineDiagnostics, DiagnosticRecord, WineErrorParser.parse() returning WineDiagnostics
provides:
  - Structured diagnostics in launchGame (diagnostics + changes_since_last replacing detected_errors)
  - Structured diagnostics in traceLaunch (diagnostics + changes_since_last replacing errors array)
  - Structured output in readLog (diagnostics + filtered_log replacing raw log tail)
  - Cross-launch diff with new/resolved/persistent errors and last_actions tracking
  - DiagnosticRecord persisted to disk after every launch for cross-session comparison
  - Previous-session diagnostic injection into agent initial message when no SessionHandoff
  - System prompt Structured Diagnostics section documenting new output format
affects: [agent-loop, agent-tools, ai-service, diagnostic-output]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - pendingActions/lastAppliedActions swap pattern for action tracking between launches
    - computeChangesDiff() comparing Set-based error identity (category:detail) across launches
    - Conditional DiagnosticRecord injection in contextParts (only when no SessionHandoff)

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "Action tracking appended in execute() dispatch after tool call returns — single instrumentation point covers all tools without modifying each handler"
  - "computeChangesDiff uses Set arithmetic on 'category:detail' strings for O(n) identity comparison without custom Equatable conformance"
  - "DiagnosticRecord injected into initial message only when previousSession is nil — avoids doubling context when SessionHandoff already provides last-session summary"
  - "pendingActions cleared after each launch (swap to lastAppliedActions) so changes_since_last only shows actions applied after the previous launch"

patterns-established:
  - "Action tool tracking: tool dispatch switch records key parameters to pendingActions for cause-effect visibility"
  - "Cross-launch diff: computeChangesDiff(current:previousDiagnostics:lastActions:) returns structured [String:Any] for JSON serialization"

requirements-completed: [DIAG-03, DIAG-04]

# Metrics
duration: 10min
completed: 2026-03-31
---

# Phase 20 Plan 02: Wire Diagnostics into Agent Tools Summary

**Structured WineDiagnostics wired into all three agent tools with cross-launch diff tracking, disk persistence, and previous-session injection**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-03-31T01:23:00Z
- **Completed:** 2026-03-31T01:33:35Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- launch_game and trace_launch now return `diagnostics` (subsystem-grouped WineDiagnostics) and `changes_since_last` (new/resolved/persistent errors with last_actions) instead of flat error arrays
- readLog now returns `diagnostics` and `filtered_log` (noise-filtered stderr) instead of a raw 8000-char tail
- Action tools (set_environment, set_registry, install_winetricks, place_dll, write_game_file) are tracked in pendingActions and surfaced in changes_since_last.last_actions
- DiagnosticRecord written to disk after every launchGame and traceLaunch call for cross-session comparison
- AIService injects previous-session diagnostics into initial agent message when no SessionHandoff exists
- System prompt updated with Structured Diagnostics section documenting diagnostics object, causal_chains, changes_since_last, and read_log output format

## Task Commits

1. **Task 1: Wire diagnostics into launchGame, traceLaunch, readLog + action tracking** - `7318637` (feat)
2. **Task 2: Update AIService system prompt and add previous-session diagnostic injection** - `ea1fe37` (feat)

## Files Created/Modified

- `Sources/cellar/Core/AgentTools.swift` - Added pendingActions/lastAppliedActions/previousDiagnostics state, action tracking in execute() dispatch, diagnostics/changes_since_last in launchGame and traceLaunch, diagnostics/filtered_log in readLog, computeChangesDiff() helper
- `Sources/cellar/Core/AIService.swift` - Added DiagnosticRecord injection in initial message (when no SessionHandoff), added Structured Diagnostics system prompt section, replaced detected_errors reference

## Decisions Made

- Action tracking appended in execute() dispatch after the tool call returns — single instrumentation point, no need to modify each individual tool handler
- computeChangesDiff uses Set arithmetic on "category:detail" strings for O(n) identity comparison without custom Equatable conformance on WineError
- DiagnosticRecord injected only when previousSession is nil to avoid doubling context when SessionHandoff already contains last session data
- pendingActions cleared (swapped to lastAppliedActions) at each launch so each diff only includes actions applied after the immediately preceding launch

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. The pre-existing build error in AgentLoop.swift:129 (maxOutputTokensLimit) is unrelated to these changes and was present before this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 20 complete: structured diagnostics data model (Plan 01) and agent tool wiring (Plan 02) both done
- Phase 21 (Pre-flight dependency check from PE imports) can now proceed
- Agent now has full visibility into subsystem-grouped errors, cross-launch trends, and persisted diagnostic history

---
*Phase: 20-smarter-wine-log-parsing-and-structured-diagnostics*
*Completed: 2026-03-31*
