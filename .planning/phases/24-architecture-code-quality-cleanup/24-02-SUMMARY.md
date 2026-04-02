---
phase: 24-architecture-code-quality-cleanup
plan: 02
subsystem: agent
tags: [swift, agent-tools, async-await, refactor, decomposition]

# Dependency graph
requires:
  - phase: 24-01
    provides: async toolExecutor in AgentLoop.run() enabling execute() to be async
provides:
  - AgentTools.swift as pure coordinator (~700 lines, down from 2,513)
  - Core/Tools/DiagnosticTools.swift with inspect_game, read_log, read_registry, trace_launch, check_file_access, verify_dll_override
  - Core/Tools/ConfigTools.swift with set_environment, set_registry, install_winetricks, place_dll, write_game_file, read_game_file
  - Core/Tools/LaunchTools.swift with launch_game, ask_user, list_windows, computeChangesDiff, describeFix
  - Core/Tools/SaveTools.swift with save_recipe, query_successdb, save_success, successRecordToDict
  - Core/Tools/ResearchTools.swift with search_web (async/await), fetch_page (async/await), query_compatibility
affects: [agent, aiservice, launch-flow, diagnostics]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - AgentTools extension pattern: tool categories live in Core/Tools/*.swift as extensions on AgentTools
    - Internal access for cross-extension state: pendingActions, lastAppliedActions, previousDiagnostics, jsonResult() are internal (not private)
    - Async tool methods: searchWeb/fetchPage use URLSession async/await instead of DispatchSemaphore+ResultBox

key-files:
  created:
    - Sources/cellar/Core/Tools/DiagnosticTools.swift
    - Sources/cellar/Core/Tools/ConfigTools.swift
    - Sources/cellar/Core/Tools/LaunchTools.swift
    - Sources/cellar/Core/Tools/SaveTools.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
  modified:
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "AgentTools.swift keeps only: stored properties, init, captureHandoff, toolDefinitions, execute(), jsonResult() — no tool logic"
  - "pendingActions/lastAppliedActions/previousDiagnostics changed from private to internal so LaunchTools and DiagnosticTools can access them"
  - "ResearchCache and ResearchResult structs moved to ResearchTools.swift as private (single-file scope)"
  - "searchWeb and fetchPage migrated from DispatchSemaphore+ResultBox to URLSession async/await during move"
  - "execute() dispatch adds await before search_web, fetch_page, place_dll, query_compatibility"

patterns-established:
  - "Tool extension pattern: each category is a separate file in Core/Tools/ as extension AgentTools"
  - "Coordinator class holds state, definitions, dispatch only — no implementations"

requirements-completed: [AgentTools decomposition]

# Metrics
duration: 19min
completed: 2026-04-02
---

# Phase 24 Plan 02: AgentTools Decomposition Summary

**AgentTools.swift reduced from 2,513 to 698 lines by splitting into 5 focused extension files in Core/Tools/, with searchWeb/fetchPage migrated from DispatchSemaphore+ResultBox to async/await**

## Performance

- **Duration:** 19 min
- **Started:** 2026-04-02T15:05:30Z
- **Completed:** 2026-04-02T15:24:30Z
- **Tasks:** 2
- **Files modified:** 6 (1 modified + 5 created)

## Accomplishments
- Reduced AgentTools.swift from 2,513 lines to 698 lines (72% reduction)
- Created 5 focused extension files totaling 1,755 lines in Core/Tools/
- Migrated DispatchSemaphore+ResultBox HTTP patterns to URLSession async/await in ResearchTools.swift
- All 21 tools continue to work identically — zero behavioral changes

## Task Commits

1. **Task 1: Create Core/Tools/ directory and move tool implementations** - `2d8c6e4` (feat)
2. **Task 2: Verify tool dispatch and update AIService toolExecutor** - no code changes (AIService already had `await tools.execute()` from Plan 01; verified in same build)

**Plan metadata:** (forthcoming docs commit)

## Files Created/Modified
- `Sources/cellar/Core/AgentTools.swift` - Reduced to coordinator only: state, init, captureHandoff, toolDefinitions (~460 lines), execute(), jsonResult()
- `Sources/cellar/Core/Tools/DiagnosticTools.swift` - 664 lines: inspect_game, read_log, read_registry, trace_launch, check_file_access, verify_dll_override, parseMsgboxDialogs, TraceStderrCapture
- `Sources/cellar/Core/Tools/ConfigTools.swift` - 304 lines: set_environment, set_registry, install_winetricks, place_dll, write_game_file, read_game_file
- `Sources/cellar/Core/Tools/LaunchTools.swift` - 303 lines: launch_game, ask_user, list_windows, computeChangesDiff, describeFix
- `Sources/cellar/Core/Tools/SaveTools.swift` - 246 lines: save_recipe, query_successdb, save_success, successRecordToDict
- `Sources/cellar/Core/Tools/ResearchTools.swift` - 238 lines: searchWeb (async), fetchPage (async), queryCompatibility; includes private ResearchCache/ResearchResult structs

## Decisions Made
- `pendingActions`, `lastAppliedActions`, `previousDiagnostics` changed from `private` to `internal` — required for LaunchTools and DiagnosticTools extensions to access mutable state
- `jsonResult()` changed from `private` to `internal` — all tool extension files need it
- `ResearchCache` and `ResearchResult` structs kept `private` but moved to `ResearchTools.swift` since they're only used by `searchWeb`
- `import CoreGraphics` moved to `LaunchTools.swift`; `@preconcurrency import SwiftSoup` moved to `ResearchTools.swift`
- `parseMsgboxDialogs` and `TraceStderrCapture` placed in `DiagnosticTools.swift` (both used only by diagnostic tools)
- `computeChangesDiff` and `describeFix` placed in `LaunchTools.swift` (both used only by launch/trace flow)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- AgentTools decomposition complete — Core/Tools/ directory established as the pattern for tool category files
- Plan 24-03 (KnownDLLRegistry expansion or similar) can proceed independently
- Any future tool additions should follow the extension pattern established here

---
*Phase: 24-architecture-code-quality-cleanup*
*Completed: 2026-04-02*
