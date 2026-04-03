---
phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key
plan: 02
subsystem: api
tags: [github-api, cache, anonymous-reads, collective-memory]

# Dependency graph
requires:
  - phase: 28-fix-collective-memory-prompt-injection-vulnerability
    provides: sanitizeEntry() and CollectiveMemoryEntry struct that read path consumes
  - phase: 13-github-app-authentication
    provides: GitHubAuthService and CellarPaths.defaultMemoryRepo that this plan replaces with anonymous access
provides:
  - CellarPaths.memoryRepo (CELLAR_MEMORY_REPO env var override with default fallback)
  - CellarPaths.memoryCacheDir (~/.cellar/cache/memory/)
  - CellarPaths.memoryCacheFile(for:) cache path helper
  - CollectiveMemoryService with anonymous reads and 1-hour TTL local file cache
  - MemoryStatsService with anonymous reads (zero GitHubAuthService references)
affects: [29-03, 29-04, collective-memory-write-path]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Cache-first read with stale fallback on 403/429 or network failure
    - Env var override pattern for repo slug (CellarPaths.memoryRepo)
    - decodeAndFormat() helper shared between cache path and network path

key-files:
  created: []
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift
    - Sources/cellar/Core/CollectiveMemoryService.swift
    - Sources/cellar/Web/Services/MemoryStatsService.swift

key-decisions:
  - "CellarPaths.memoryRepo reads CELLAR_MEMORY_REPO env var with defaultMemoryRepo fallback — consistent with CellarPaths pattern for env overrides"
  - "Stale cache served on 403/429 and network failure — rate-limit resilience more important than freshness"
  - "decodeAndFormat() helper shared between cache-hit and network-200 paths — no duplication of decode/rank/format logic"

patterns-established:
  - "Cache-first read pattern: isCacheFresh check → serve from cache → else network → write cache → decode"
  - "Stale cache fallback: serve stale on rate limit (403/429) or network error before returning nil"

requirements-completed: []

# Metrics
duration: 8min
completed: 2026-04-03
---

# Phase 29 Plan 02: Anonymous Reads + Local Cache Summary

**CollectiveMemoryService and MemoryStatsService converted to anonymous public GitHub API reads with a 1-hour TTL local file cache at ~/.cellar/cache/memory/**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-03T18:43:00Z
- **Completed:** 2026-04-03T18:51:46Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Removed all `GitHubAuthService` auth checks and Bearer token headers from both read-path services
- Added `CellarPaths.memoryRepo`, `memoryCacheDir`, and `memoryCacheFile(for:)` for centralized path management
- Implemented cache-first read logic with 1-hour TTL in `CollectiveMemoryService.fetchBestEntry`
- Stale cache served as fallback when GitHub returns 403/429 or network fails
- `MemoryStatsService` now has zero references to `GitHubAuthService`

## Task Commits

Each task was committed atomically:

1. **Task 1: CellarPaths extensions + anonymous reads in CollectiveMemoryService with cache** - `6c6bfe0` (feat)
2. **Task 2: Remove auth from MemoryStatsService** - `cc8442e` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `Sources/cellar/Persistence/CellarPaths.swift` - Added memoryRepo, memoryCacheDir, memoryCacheFile(for:)
- `Sources/cellar/Core/CollectiveMemoryService.swift` - Anonymous reads, cache-first + stale fallback, decodeAndFormat() helper
- `Sources/cellar/Web/Services/MemoryStatsService.swift` - Removed all auth checks and Authorization headers

## Decisions Made

- `CellarPaths.memoryRepo` reads `CELLAR_MEMORY_REPO` env var with `defaultMemoryRepo` fallback — consistent with existing CellarPaths pattern
- Stale cache served on 403/429 and network failure — rate-limit resilience more important than freshness for read path
- `decodeAndFormat()` helper shared between cache-hit and network-200 paths — avoids duplicating the decode/rank/format pipeline

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Read paths for CollectiveMemoryService and MemoryStatsService are now fully anonymous
- Plan 29-03 can delete GitHubAuthService and bundled credentials — read paths have zero dependencies on it
- Plan 29-04 can update CollectiveMemoryWriteService to POST to Cloudflare Worker proxy

---
*Phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key*
*Completed: 2026-04-03*

## Self-Check: PASSED

- FOUND: Sources/cellar/Persistence/CellarPaths.swift
- FOUND: Sources/cellar/Core/CollectiveMemoryService.swift
- FOUND: Sources/cellar/Web/Services/MemoryStatsService.swift
- FOUND: .planning/phases/29-.../29-02-SUMMARY.md
- COMMIT 6c6bfe0: feat(29-02): anonymous reads + local cache in CollectiveMemoryService
- COMMIT cc8442e: feat(29-02): remove auth from MemoryStatsService — anonymous public reads
