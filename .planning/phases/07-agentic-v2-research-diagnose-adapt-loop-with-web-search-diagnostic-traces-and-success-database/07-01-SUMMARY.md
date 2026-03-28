---
phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
plan: 01
subsystem: core
tags: [wine-process, dll-placement, known-dll, cellar-paths, syswow64]

requires:
  - phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
    provides: AgentTools, AIService, WineActionExecutor with DLL placement
provides:
  - WineProcess CWD fix for relative-path games
  - DLLPlacementTarget.syswow64 with autoDetect() for wow64 bottles
  - KnownDLL companion files, preferredTarget, isSystemDLL, variants fields
  - CellarPaths successdbDir and researchCacheDir
affects: [07-02, 07-03, 07-04, 07-05]

tech-stack:
  added: []
  patterns:
    - "CompanionFile struct for DLL config file co-placement"
    - "DLLPlacementTarget.autoDetect() for runtime target resolution"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/WineProcess.swift
    - Sources/cellar/Core/WineErrorParser.swift
    - Sources/cellar/Models/KnownDLLRegistry.swift
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/WineActionExecutor.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "CompanionFile as standalone struct (not nested) for reusability across registry entries"
  - "autoDetect checks filesystem for syswow64 presence rather than bottle metadata"

patterns-established:
  - "DLLPlacementTarget.autoDetect() pattern: runtime filesystem check for placement decisions"

requirements-completed: []

duration: 2min
completed: 2026-03-28
---

# Phase 7 Plan 01: P0 Infrastructure Summary

**WineProcess CWD fix, DLLPlacementTarget.syswow64 with autoDetect, KnownDLL companion files and variants, CellarPaths success DB and research cache directories**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-28T01:49:19Z
- **Completed:** 2026-03-28T01:51:16Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- WineProcess.run() now sets CWD to the game binary's parent directory, fixing games that use relative paths
- DLLPlacementTarget extended with .syswow64 case and autoDetect() static method for wow64 bottle support
- KnownDLL struct extended with companionFiles, preferredTarget, isSystemDLL, and variants fields
- CellarPaths gains successdbDir/successdbFile and researchCacheDir/researchCacheFile

## Task Commits

Each task was committed atomically:

1. **Task 1: WineProcess CWD fix + DLLPlacementTarget.syswow64 + KnownDLL extensions** - `c10850d` (feat)
2. **Task 2: CellarPaths extensions for success DB and research cache** - `4dee09b` (feat)

## Files Created/Modified
- `Sources/cellar/Core/WineProcess.swift` - Added currentDirectoryURL assignment in run()
- `Sources/cellar/Core/WineErrorParser.swift` - Added .syswow64 case and autoDetect() static method
- `Sources/cellar/Models/KnownDLLRegistry.swift` - Added CompanionFile struct, extended KnownDLL with 4 new fields, updated cnc-ddraw entry
- `Sources/cellar/Persistence/CellarPaths.swift` - Added successdbDir, researchCacheDir with file helpers
- `Sources/cellar/Core/WineActionExecutor.swift` - Added .syswow64 switch case for DLL placement
- `Sources/cellar/Core/AIService.swift` - Updated DLLPlacementTarget parsing to handle syswow64
- `Sources/cellar/Core/AgentTools.swift` - Added syswow64 to place_dll tool enum and placement logic

## Decisions Made
- CompanionFile as a standalone struct (not nested in KnownDLL) for reusability
- autoDetect() checks filesystem for syswow64 directory existence rather than relying on bottle metadata

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added .syswow64 case to WineActionExecutor switch**
- **Found during:** Task 1 (compilation verification)
- **Issue:** Adding .syswow64 to DLLPlacementTarget made existing switch in WineActionExecutor non-exhaustive
- **Fix:** Added .syswow64 case mapping to drive_c/windows/syswow64 path
- **Files modified:** Sources/cellar/Core/WineActionExecutor.swift
- **Verification:** swift build succeeds
- **Committed in:** c10850d (Task 1 commit)

**2. [Rule 3 - Blocking] Updated AIService DLLPlacementTarget parsing for syswow64**
- **Found during:** Task 1 (code consistency check)
- **Issue:** AIService.parseWineFix used ternary that only handled system32/gameDir
- **Fix:** Changed to switch statement handling all three cases
- **Files modified:** Sources/cellar/Core/AIService.swift
- **Committed in:** c10850d (Task 1 commit)

**3. [Rule 3 - Blocking] Updated AgentTools place_dll tool for syswow64**
- **Found during:** Task 1 (code consistency check)
- **Issue:** AgentTools place_dll enum and placement logic only handled game_dir/system32
- **Fix:** Added syswow64 to tool schema enum and placement if-else chain
- **Files modified:** Sources/cellar/Core/AgentTools.swift
- **Committed in:** c10850d (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (3 blocking)
**Impact on plan:** All auto-fixes necessary for compilation and consistency. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All P0 infrastructure in place for plans 02-05
- DLLPlacementTarget.syswow64 ready for wow64 bottle support
- CellarPaths ready for success database and research cache persistence

---
*Phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database*
*Completed: 2026-03-28*
