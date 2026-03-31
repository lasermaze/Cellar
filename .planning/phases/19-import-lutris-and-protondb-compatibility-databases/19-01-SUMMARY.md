---
phase: 19-import-lutris-and-protondb-compatibility-databases
plan: 01
subsystem: api
tags: [lutris, protondb, compatibility, wine, urlsession, caching, fuzzy-matching]

# Dependency graph
requires:
  - phase: 14-memory-entry-schema
    provides: ExtractedEnvVar, ExtractedDLL, ExtractedVerb, ExtractedRegistry types from PageParser.swift
  - phase: 16-write-path
    provides: CellarPaths.researchCacheDir pattern for cache directory layout
provides:
  - CompatibilityService.fetchReport(for:) — unified Lutris + ProtonDB compatibility lookup
  - CompatibilityReport.formatForAgent() — formatted context block for agent injection
  - CellarPaths.lutrisCompatCacheDir — ~/.cellar/research/lutris/
  - CellarPaths.protondbCompatCacheDir — ~/.cellar/research/protondb/
affects: [phase-19-02-agent-integration, phase-20-smarter-log-parsing, future-agent-loop]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - DispatchSemaphore + ResultBox<T> for parallel async fetches (same as CollectiveMemoryService)
    - CompatibilityCache<T: Codable> generic wrapper with ISO8601 fetchedAt and isStale(ttlDays:)
    - Jaccard token-overlap similarity for fuzzy game name matching
    - Proton-prefix filtering to strip Linux-only env vars before agent injection

key-files:
  created:
    - Sources/cellar/Core/CompatibilityService.swift
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift

key-decisions:
  - "ExtractedEnvVar/DLL/Verb/Registry context field used (not source) — matched actual PageParser.swift struct fields"
  - "Jaccard threshold 0.3 (not 0.5) — game names vary significantly between Cellar slugs and Lutris titles"
  - "Proton-only prefix list: PROTON_, STEAM_, SteamAppId, SteamGameId, LD_PRELOAD, WINEDLLPATH, WINELOADERNOEXEC, DXVK_FILTER_DEVICE_NAME"
  - "fetchReport returns nil for empty report (no Proton tier and no Lutris config) — caller never receives useless data"
  - "Cache normalized name uses letter/digit/hyphen only slug for filesystem-safe cache keys"

patterns-established:
  - "CompatibilityCache<T>: generic Codable wrapper with 30-day TTL via isStale(ttlDays:) — reusable for future API caches"
  - "filterPortableEnvVars: strip Proton-only prefixes before agent sees env vars — pattern for future Linux-specific data sources"

requirements-completed: [COMPAT-01, COMPAT-02]

# Metrics
duration: 2min
completed: 2026-03-31
---

# Phase 19 Plan 01: Import Lutris and ProtonDB Compatibility Databases Summary

**Lutris game search + installer extraction and ProtonDB tier fetch unified into CompatibilityService with 30-day disk cache and Proton-flag filtering**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-31T19:54:06Z
- **Completed:** 2026-03-31T19:56:03Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- CellarPaths extended with lutrisCompatCacheDir and protondbCompatCacheDir path helpers
- CompatibilityService created with full fetch/parse/cache/filter/format pipeline
- Lutris fuzzy name matching (Jaccard, threshold 0.3) with 30-day cache per game
- Installer script extraction: env vars, DLL overrides, winetricks verbs, registry edits
- ProtonDB tier summary fetched by Steam AppID (extracted from Lutris providerGames)
- Proton-specific env var filtering keeps only portable Wine/macOS-compatible config
- CompatibilityReport.formatForAgent() produces structured context block for agent injection

## Task Commits

Each task was committed atomically:

1. **Task 1: Add cache path helpers to CellarPaths** - `8b45502` (feat)
2. **Task 2: Create CompatibilityService with full data pipeline** - `d1ed9d2` (feat)

## Files Created/Modified
- `Sources/cellar/Core/CompatibilityService.swift` - Full Lutris + ProtonDB service: fetch, parse, cache, filter, format
- `Sources/cellar/Persistence/CellarPaths.swift` - Added lutrisCompatCacheDir and protondbCompatCacheDir

## Decisions Made
- Used actual PageParser.swift struct field names (`context` not `source`, `path` not `keyPath`) — the plan's interface block was slightly off from the real types
- Jaccard threshold 0.3 as specified (game names vary significantly between sources)
- Proton-only env var prefix list matches plan specification exactly
- `CompatibilityCache<T>` is a private generic inside the file — not exposed as public API

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Adapted struct fields to match actual PageParser.swift types**
- **Found during:** Task 2 (CompatibilityService creation)
- **Issue:** Plan's interface block showed `ExtractedEnvVar.source`, `ExtractedRegistry.keyPath/valueName/valueData`, `ExtractedDLL.source`, `ExtractedVerb.source/context?` — but actual PageParser.swift uses `context` (not `source`), `path` (not `keyPath`), `value` (not `valueData`)
- **Fix:** Used the actual field names from PageParser.swift throughout CompatibilityService
- **Files modified:** Sources/cellar/Core/CompatibilityService.swift
- **Verification:** swift build succeeds with no errors
- **Committed in:** d1ed9d2 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - struct field name mismatch)
**Impact on plan:** Necessary for compilation correctness. No scope creep.

## Issues Encountered
None - build succeeded first attempt after field name adaptation.

## User Setup Required
None - no external service configuration required. Cache directories created automatically on first use.

## Next Phase Readiness
- CompatibilityService.fetchReport(for:) ready for agent loop injection (Phase 19-02)
- formatForAgent() output is structured for direct prepending to agent initial message (same pattern as CollectiveMemoryService)
- Both cache directories resolve correctly from CellarPaths
- Service fails silently on network errors — safe to call in any context

---
*Phase: 19-import-lutris-and-protondb-compatibility-databases*
*Completed: 2026-03-31*
