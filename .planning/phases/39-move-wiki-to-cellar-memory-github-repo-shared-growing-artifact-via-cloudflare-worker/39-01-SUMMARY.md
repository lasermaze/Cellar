---
phase: 39-move-wiki-to-cellar-memory
plan: 01
subsystem: wiki
tags: [wiki, cache, github-raw, async-await, cellar-paths]

# Dependency graph
requires:
  - phase: 38-rebuild-memory-layer
    provides: WikiService with Bundle.module-based read path, index.md keyword ranking
  - phase: 29-secure-collective-memory
    provides: CellarPaths.memoryRepo pattern, CollectiveMemoryService cache TTL pattern
provides:
  - WikiService.fetchContext async — reads from ~/.cellar/wiki/ cache, fetches from GitHub raw URLs
  - WikiService.search async — same cache+fetch pattern for agent query_wiki tool
  - CellarPaths.wikiCacheDir and wikiCacheFile(for:) helpers
  - Stale-cache-on-failure read path (graceful degradation when offline)
affects:
  - phase-39-P02 (write path / ingest via Worker)
  - phase-39-P04 (remove SPM bundle / Sources/cellar/wiki/)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wiki cache at ~/.cellar/wiki/ mirrors CollectiveMemoryService cache+GitHub-raw pattern"
    - "cacheTTL=1h, isCacheFresh via attributesOfItem modificationDate"
    - "stale-on-failure: if GitHub fails, any cached copy (even expired) is returned"
    - "createDirectory(withIntermediateDirectories: true) before writes to handle subdirs"

key-files:
  created: []
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/WikiService.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift
    - Sources/cellar/Core/AgentTools.swift

key-decisions:
  - "fetchContext parameter renamed from 'for gameName: String' to 'engine: String?' to match planned interface"
  - "Bundle.module left in ingest() body — P02 will replace entire ingest function"
  - "queryWiki made async (was sync) — execute() in AgentTools was already async context"
  - "maxResults param added to search() matching new interface contract"

patterns-established:
  - "Wiki read helpers (fetchPage, readCache, writeCache, isCacheFresh) mirror CollectiveMemoryService exactly"

requirements-completed: []

# Metrics
duration: 2min
completed: 2026-04-11
---

# Phase 39 Plan 01: Wiki Read Path Migration Summary

**WikiService read path migrated from read-only SPM bundle to async cache+GitHub-raw pattern at ~/.cellar/wiki/, enabling wiki reads on notarized Homebrew builds**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-04-11T01:56:51Z
- **Completed:** 2026-04-11T01:58:37Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments
- Added `wikiCacheDir` and `wikiCacheFile(for:)` to CellarPaths mirroring memoryCacheDir pattern
- Rewrote WikiService.fetchContext and .search to be async with 1h TTL cache at ~/.cellar/wiki/
- All callers (AIService, ResearchTools, AgentTools) updated to `await` the async calls
- Build passes with zero errors; stale-on-failure degradation preserves offline operation

## Task Commits

Each task was committed atomically:

1. **Task 1: Add wiki cache paths to CellarPaths** - `811836e` (feat)
2. **Task 2: Rewrite WikiService read path to use cache + async GitHub fetch** - `3733d73` (feat)
3. **Task 3: Update WikiService callers to await async reads** - `a6fab8e` (feat)

## Files Created/Modified
- `Sources/cellar/Persistence/CellarPaths.swift` - Added wikiCacheDir and wikiCacheFile(for:)
- `Sources/cellar/Core/WikiService.swift` - Removed Bundle.module from read path; new async fetchPage/readCache/writeCache helpers; fetchContext and search are now async
- `Sources/cellar/Core/AIService.swift` - await WikiService.fetchContext(engine: entry.name)
- `Sources/cellar/Core/Tools/ResearchTools.swift` - queryWiki made async; await WikiService.search
- `Sources/cellar/Core/AgentTools.swift` - await queryWiki(input:) in execute() dispatch

## Decisions Made
- `fetchContext` parameter renamed from `for gameName: String` to `engine: String?` to match the planned P01 interface contract. AIService call site updated accordingly.
- `Bundle.module` reference left in `ingest()` body untouched — plan explicitly defers ingest body rewrite to P02.
- `queryWiki` in ResearchTools made async (was sync) — `execute()` in AgentTools was already an async context so no control flow changes required.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- WikiService read path is fully async and cache-based; ready for P02 (ingest write path via Worker)
- P02 will replace the `ingest()` function body and remove the remaining `Bundle.module` reference in WikiService
- P04 will remove `Sources/cellar/wiki/` directory and `.copy("wiki")` from Package.swift

---
*Phase: 39-move-wiki-to-cellar-memory*
*Completed: 2026-04-11*

## Self-Check: PASSED

All files present and all task commits verified in git history.
