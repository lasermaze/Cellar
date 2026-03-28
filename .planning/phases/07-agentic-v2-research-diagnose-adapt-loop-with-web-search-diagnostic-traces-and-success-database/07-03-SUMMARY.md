---
phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
plan: 03
subsystem: core
tags: [agent-tools, diagnostic-trace, dll-analysis, wine-debug, pe-imports]

requires:
  - phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
    provides: P0 infrastructure (WineProcess CWD fix, DLLPlacementTarget.syswow64, KnownDLL extensions)
provides:
  - trace_launch diagnostic tool for DLL load analysis via timed Wine launches
  - verify_dll_override tool comparing configured vs actual DLL loading
  - check_file_access tool for relative path debugging
  - Enhanced inspect_game with PE imports, bottle type, data files, notable imports
affects: [07-05]

tech-stack:
  added: []
  patterns:
    - "TraceStderrCapture @unchecked Sendable + NSLock pattern for Process stderr capture"
    - "DispatchWorkItem kill timer for timed diagnostic launches"
    - "PE import extraction via objdump -p with DLL Name: line parsing"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "traceLaunch is func (not private) so verifyDllOverride can call it internally"
  - "DLL trace deduplication keeps last occurrence per DLL name (Wine may load/unload/reload)"
  - "objdump fallback scans for .dll references if DLL Name: format not found"
  - "Known shim DLL annotations hardcoded as dictionary (ddraw, d3d8, d3d9, d3d11, dinput, dinput8, dsound)"

patterns-established:
  - "Diagnostic tool pattern: timed Process launch with kill timer + stderr capture + structured parse"

requirements-completed: []

duration: 7min
completed: 2026-03-28
---

# Phase 7 Plan 03: Diagnostic Tools Summary

**Four diagnostic agent tools: trace_launch for DLL load analysis, verify_dll_override for config vs actual comparison, check_file_access for path debugging, and enhanced inspect_game with PE imports/bottle type/data files**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-28T01:53:38Z
- **Completed:** 2026-03-28T02:00:13Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- trace_launch runs timed diagnostic Wine launch with +loaddll debug channels, parses structured DLL load list (name, path, native/builtin), kills process+wineserver after configurable timeout
- verify_dll_override cross-references WINEDLLOVERRIDES config against actual Wine DLL loading via internal trace_launch call, explains discrepancies
- check_file_access verifies file existence relative to game executable directory for working directory debugging
- inspect_game enhanced with PE imports via objdump -p, bottle type detection (wow64 vs standard), data files listing (.dat/.ini/.cfg/.txt/.xml/.json), and notable import annotations for known shim DLLs

## Task Commits

Each task was committed atomically:

1. **Task 1: trace_launch + check_file_access tools** - `949b157` (feat)
2. **Task 2: verify_dll_override + enhanced inspect_game + dispatch registration** - `bcc9486` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AgentTools.swift` - Added 3 diagnostic tools (trace_launch, check_file_access, verify_dll_override), enhanced inspect_game with 4 new data sources, registered all in dispatch switch and toolDefinitions

## Decisions Made
- traceLaunch is non-private (func not private func) so verifyDllOverride can call it internally for DLL load verification
- DLL trace parsing deduplicates by name keeping last occurrence, since Wine may load/unload/reload DLLs during startup
- objdump PE import parsing has a fallback: if "DLL Name:" lines not found, scans for .dll string references
- Known shim DLLs (ddraw, d3d8, d3d9, d3d11, dinput, dinput8, dsound) annotated with actionable notes for the agent

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed JSONValue asDouble -> asNumber for timeout_seconds**
- **Found during:** Task 1 (compilation verification)
- **Issue:** Plan specified `asDouble` but JSONValue enum uses `asNumber` (returns Double?)
- **Fix:** Changed `input["timeout_seconds"]?.asDouble` to `input["timeout_seconds"]?.asNumber`
- **Files modified:** Sources/cellar/Core/AgentTools.swift
- **Verification:** swift build succeeds
- **Committed in:** 949b157

**2. [Rule 3 - Blocking] Added stub implementations for query_successdb/save_success**
- **Found during:** Task 2 (compilation verification)
- **Issue:** Plan 07-04 executor added dispatch entries for query_successdb/save_success without implementations, causing build failure
- **Fix:** Added stub methods returning error JSON, to be replaced by 07-04 full implementation
- **Files modified:** Sources/cellar/Core/AgentTools.swift
- **Verification:** swift build succeeds
- **Committed in:** bcc9486

**3. [Rule 3 - Blocking] Re-registered dispatch cases after concurrent plan overwrites**
- **Found during:** Task 1 (post-commit verification)
- **Issue:** Concurrent 07-02/07-04 executors overwrote the execute() dispatch switch, dropping trace_launch/check_file_access/verify_dll_override cases
- **Fix:** Re-added all three dispatch cases to execute() switch
- **Files modified:** Sources/cellar/Core/AgentTools.swift
- **Committed in:** bcc9486

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All auto-fixes necessary for compilation. No scope creep.

## Issues Encountered
- Concurrent plan executors (07-02, 07-04) modified AgentTools.swift simultaneously, requiring dispatch re-registration after merge conflicts

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All diagnostic tools ready for agent loop integration in plan 07-05
- trace_launch provides DLL load evidence for the research-diagnose-adapt pattern
- verify_dll_override enables closed-loop verification of DLL override configurations

---
*Phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database*
*Completed: 2026-03-28*
