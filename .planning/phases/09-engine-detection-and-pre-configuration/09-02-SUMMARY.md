---
phase: 09-engine-detection-and-pre-configuration
plan: 02
subsystem: ai
tags: [system-prompt, engine-detection, pre-configuration, wine, agent-loop]

# Dependency graph
requires:
  - phase: 09-01
    provides: "EngineRegistry with 8 engine families, engine/graphics_api fields in inspect_game results"
provides:
  - "Engine-aware agent system prompt with pre-configuration guidance, search enrichment, and success DB cross-referencing"
affects: [10-trace-output-parsing, 11-search-enhancement]

# Tech tracking
tech-stack:
  added: []
  patterns: ["Engine-aware prompt methodology: pre-configure known engines before first launch attempt"]

key-files:
  created: []
  modified: ["Sources/cellar/Core/AIService.swift"]

key-decisions:
  - "Engine-Aware Methodology placed between Three-Phase Workflow and Domain Knowledge sections for optimal prompt ordering"
  - "Step 2b added to Phase 1 Research to create explicit engine detection checkpoint in workflow"

patterns-established:
  - "Engine pre-configuration before first launch: DirectDraw games get cnc-ddraw, OpenGL games get MESA overrides, Unreal gets renderer INI"
  - "Search query enrichment pattern: [engine] + [graphics API] + [symptom] + Wine macOS"
  - "Cross-game success DB queries by engine family and graphics_api for transferable solutions"

requirements-completed: [ENGN-03, ENGN-04]

# Metrics
duration: 1min
completed: 2026-03-28
---

# Phase 9 Plan 02: Engine-Aware System Prompt Summary

**Agent system prompt updated with engine-aware pre-configuration guidance for 5 engine categories, search query enrichment, and success database cross-referencing by engine family**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-28T23:56:00Z
- **Completed:** 2026-03-28T23:56:50Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added Engine-Aware Methodology section with pre-configuration guidance for DirectDraw, OpenGL, Unreal 1, Unity, and UE4/5 engines
- Added search query enrichment instructions combining engine name + graphics API + symptom
- Added success database cross-referencing guidance by engine family and graphics_api
- Added step 2b in Phase 1 Research workflow for engine detection checkpoint

## Task Commits

Each task was committed atomically:

1. **Task 1: Add engine-aware methodology section to system prompt** - `e81fed5` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AIService.swift` - Added Engine-Aware Methodology section to agent system prompt with pre-configuration, search enrichment, and success DB cross-referencing guidance

## Decisions Made
- Placed Engine-Aware Methodology between Three-Phase Workflow and Domain Knowledge sections so the agent reads engine guidance immediately after learning the workflow phases
- Added step 2b (not replacing step 3) to preserve existing workflow numbering while inserting engine detection checkpoint

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Engine detection (Plan 01) and engine-aware prompting (Plan 02) complete
- Agent will now pre-configure known engines before first launch, use engine-enriched search queries, and cross-reference success database by engine family
- Ready for Phase 10 (trace output parsing) which builds on engine-aware diagnosis

---
*Phase: 09-engine-detection-and-pre-configuration*
*Completed: 2026-03-28*
