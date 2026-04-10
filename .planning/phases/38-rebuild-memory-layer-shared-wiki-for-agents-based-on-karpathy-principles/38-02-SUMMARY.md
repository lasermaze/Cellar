---
phase: 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles
plan: 02
subsystem: agent
tags: [wiki, agent-tools, context-injection, wine, research]

# Dependency graph
requires:
  - phase: 38-01
    provides: WikiService.swift with fetchContext and search methods; wiki bundled as SPM resource
provides:
  - query_wiki agent tool (defined, dispatched, implemented)
  - WikiService.fetchContext injection into agent session initial context
  - queryWiki(input:) implementation in ResearchTools extension
affects:
  - agent loop behavior (passive wiki context + active query_wiki tool available)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - query_wiki dispatch is non-async (WikiService.search is synchronous file I/O)
    - Wiki context position: collective memory -> wiki -> compatibility -> session handoff -> launch instruction

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "query_wiki dispatch is non-async — WikiService.search is synchronous file I/O, no await needed"
  - "Wiki context injected after collective memory and before compatibility data — synthesized pattern knowledge is higher-level than raw compat reports"

patterns-established:
  - "queryWiki follows exact pattern of queryCompatibility but calls synchronous WikiService.search instead of async CompatibilityService.fetchReport"

requirements-completed: []

# Metrics
duration: 8min
completed: 2026-04-10
---

# Phase 38 Plan 02: Wire WikiService into Agent Loop Summary

**query_wiki tool wired into agent with passive context injection at session start and active mid-session lookup via WikiService**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-10T01:37:00Z
- **Completed:** 2026-04-10T01:45:08Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Added `query_wiki` as tool #21 in AgentTools.toolDefinitions with description guiding agents to use it before web research
- Added dispatch case in AgentTools.execute() for `query_wiki` (non-async — WikiService.search is synchronous)
- Added `queryWiki(input:)` in ResearchTools extension calling WikiService.search
- Injected `WikiService.fetchContext(for: entry.name)` into AIService contextParts between collective memory and compatibility data

## Task Commits

Each task was committed atomically:

1. **Task 1: Add query_wiki tool definition, dispatch, and ResearchTools implementation** - `5c576c6` (feat)
2. **Task 2: Inject WikiService.fetchContext into AIService contextParts** - `630f40c` (feat, committed as part of 38-03 execution)

**Plan metadata:** _(to be committed)_

## Files Created/Modified
- `Sources/cellar/Core/AgentTools.swift` - Added query_wiki ToolDefinition (#21) and dispatch case
- `Sources/cellar/Core/Tools/ResearchTools.swift` - Added queryWiki(input:) method calling WikiService.search
- `Sources/cellar/Core/AIService.swift` - Injected WikiService.fetchContext into contextParts assembly

## Decisions Made
- `query_wiki` dispatch is non-async: WikiService.search reads bundled resource files synchronously — no await needed, unlike queryCompatibility which uses URLSession
- Wiki context position in contextParts: after collective memory (community configs) but before compatibility data (Lutris/ProtonDB). Wiki is synthesized pattern knowledge — higher-level than raw compat reports but less authoritative than per-game memory

## Deviations from Plan

None - plan executed exactly as written.

Note: Task 2's AIService.swift changes were found already committed by a prior agent session (38-03 agent committed them as part of that plan's work). The content is correct and matches the plan specification exactly.

## Issues Encountered
- AIService.swift changes for Task 2 were pre-committed by the 38-03 agent in the same git session. The changes are identical to the plan specification. No re-work needed.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 38 P02 complete — agents now have both passive wiki context injection and active query_wiki tool
- Phase 38 P03 (WikiService.ingest post-session) was already completed by a prior agent session
- Wiki layer is fully operational: seed pages bundled, context injection working, query tool available, post-session ingest wired

## Self-Check: PASSED

- FOUND: Sources/cellar/Core/AgentTools.swift (query_wiki defined x3, dispatch case x1)
- FOUND: Sources/cellar/Core/Tools/ResearchTools.swift (queryWiki implemented)
- FOUND: Sources/cellar/Core/AIService.swift (WikiService.fetchContext call present)
- FOUND: 38-02-SUMMARY.md
- FOUND: commit 5c576c6 (Task 1)
- FOUND: commit 630f40c (Task 2 — AIService changes)

---
*Phase: 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles*
*Completed: 2026-04-10*
