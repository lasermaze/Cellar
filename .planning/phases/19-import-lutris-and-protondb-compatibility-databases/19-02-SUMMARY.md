---
phase: 19-import-lutris-and-protondb-compatibility-databases
plan: "02"
subsystem: agent
tags: [compatibility, lutris, protondb, wine, agent-tools, ai-service]

# Dependency graph
requires:
  - phase: 19-01
    provides: CompatibilityService.fetchReport() and CompatibilityReport.formatForAgent()
provides:
  - query_compatibility tool in AgentTools (tool #20, on-demand lookup during agent loop)
  - Auto-injected COMPATIBILITY DATA block in agent initial message via AIService.runAgentLoop()
  - System prompt guidance for interpreting ProtonDB tiers and applying Lutris config hints
affects: [agent-loop, ai-service, agent-tools, phase-20, phase-21]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Compatibility data injected after collective memory but before session handoff in contextParts — ordering reflects confidence hierarchy (Cellar-confirmed > community > community-database)"
    - "Silent-skip pattern extended: nil CompatibilityService result leaves initialMessage identical to pre-Phase-19 behavior"
    - "Tool handler delegates directly to CompatibilityService.fetchReport — no added logic, single source of truth"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "Compatibility data position: after collective memory (higher confidence), before session handoff and launch instruction"
  - "Available Tools count updated to 21 in system prompt to reflect query_compatibility addition"
  - "query_compatibility returns nil message string (not error JSON) for no-match — keeps agent response human-readable"

patterns-established:
  - "Context injection order in contextParts: collective memory > compatibility data > session handoff > launch instruction"

requirements-completed: [COMPAT-03]

# Metrics
duration: 8min
completed: 2026-03-31
---

# Phase 19 Plan 02: Agent Integration Summary

**Compatibility data wired into agent loop — auto-injected as COMPATIBILITY DATA block in initial message and available on-demand via query_compatibility tool (tool #20), with system prompt guidance on ProtonDB tiers and Lutris config hints**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-03-31T20:00:00Z
- **Completed:** 2026-03-31T20:08:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `query_compatibility` tool definition, dispatch case, and handler to `AgentTools` — agent can call it mid-session for any game name variation
- Added `CompatibilityService.fetchReport()` call in `AIService.runAgentLoop()` — compatibility data auto-injected into agent initial message before diagnosis begins
- Added `## Compatibility Data` section to system prompt guiding agent on ProtonDB tiers, Lutris hints, and when to call `query_compatibility`
- Updated Available Tools count in system prompt from 20 to 21

## Task Commits

Each task was committed atomically:

1. **Task 1: Add query_compatibility tool and system prompt guidance** - `3f58ad2` (feat)
2. **Task 2: Inject compatibility data into agent initial message** - `2922fd5` (feat)

## Files Created/Modified

- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentTools.swift` - Added tool definition (#20), dispatch case, and `queryCompatibility()` handler method
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AIService.swift` - Added `CompatibilityService.fetchReport()` call and `compatReport` injection in `contextParts`, plus `## Compatibility Data` system prompt section

## Decisions Made

- Compatibility data position in `contextParts`: after collective memory (higher confidence — Cellar-confirmed success), before session handoff and launch instruction. Community database data is useful prior knowledge but not as trusted as confirmed Cellar runs.
- `query_compatibility` returns a plain string "No compatibility data found..." on nil rather than a JSON error — keeps the agent's context clean and human-readable.
- Updated "Available Tools (21 total)" in system prompt and added `query_compatibility` to the Research tool list.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 19 is now complete. Both plans delivered:
- Plan 01: CompatibilityService data layer (Lutris + ProtonDB fetch, cache, filter, formatForAgent)
- Plan 02: Agent integration (auto-injection + on-demand tool + system prompt guidance)

Phase 20 (Smarter Wine Log Parsing) and Phase 21 (Pre-flight PE Dependency Check) can proceed independently.

---
*Phase: 19-import-lutris-and-protondb-compatibility-databases*
*Completed: 2026-03-31*
