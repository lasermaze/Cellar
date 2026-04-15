---
phase: 40-wiki-batch-ingest
plan: 01
subsystem: wiki
tags: [wiki, ingest, CompatibilityService, WikiService, PageParser, URLSession, markdown]

# Dependency graph
requires:
  - phase: 39-move-wiki-to-cellar-memory
    provides: WikiService.postWikiAppend and cellar-memory Worker write path
  - phase: 19-import-lutris-and-protondb-compatibility-databases
    provides: CompatibilityService.fetchReport and all Lutris/ProtonDB fetch/parse logic
  - phase: 20-smarter-wine-log-parsing-and-structured-diagnostics
    provides: PageParser protocol, WineHQParser, PCGamingWikiParser, ExtractedFixes types
provides:
  - WikiIngestService.ingest(gameName:) — full fetch-format-POST pipeline for a single game
  - WikiService.postWikiAppend and slugify promoted to internal (callable cross-module)
  - CompatibilityService.fetchPopularGames(limit:) — top N games from Lutris catalog
affects:
  - 40-02 (CLI WikiCommand/IngestCommand will call WikiIngestService.ingest and fetchPopularGames)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - TTL-guarded ingest (7-day freshness check via GitHub raw URL before re-fetching)
    - Nil-safe source aggregation (each of 4 sources is optional; page skipped only if all nil/empty)
    - Combined dedup (env vars by name, DLLs by lowercased name, winetricks by lowercased verb)

key-files:
  created:
    - Sources/cellar/Core/WikiIngestService.swift
  modified:
    - Sources/cellar/Core/WikiService.swift
    - Sources/cellar/Core/CompatibilityService.swift

key-decisions:
  - "WikiIngestService.ingest calls WikiService.slugify (internal static) — no slug duplication needed"
  - "fetchPopularGames placed in CompatibilityService (not WikiIngestService) so private LutrisSearchResponse is accessible without promotion"
  - "TTL check fetches GitHub raw URL; 404 or network error → treat as stale, proceed with ingest"
  - "All sources optional — page skipped only when all 4 return nil/empty (not partial skip)"
  - "postWikiAppend called once per game (games/{slug}.md only) — index.md and log.md updates deferred to P02 batch layer to avoid rate limit on first pass"

patterns-established:
  - "WikiIngestService: static struct with ingest(gameName:) as entry point, private formatGamePage and fetchHTML helpers"
  - "Source aggregation: treat each source as optional ExtractedFixes?; combine and dedup before formatting"

requirements-completed: []

# Metrics
duration: 4min
completed: 2026-04-15
---

# Phase 40 Plan 01: Wiki Batch Ingest Pipeline Summary

**WikiIngestService with TTL-guarded fetch-format-POST pipeline using Lutris/ProtonDB/WineHQ/PCGamingWiki as sources; postWikiAppend and slugify promoted to internal**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-15T01:06:37Z
- **Completed:** 2026-04-15T01:10:26Z
- **Tasks:** 2
- **Files modified:** 3 (1 created, 2 modified)

## Accomplishments

- Promoted `WikiService.postWikiAppend` and `slugify` from `private` to `internal` — callable from WikiIngestService and the upcoming CLI command
- Added `CompatibilityService.fetchPopularGames(limit:)` using the existing private `LutrisSearchResponse` struct
- Created `WikiIngestService.swift` with a complete `ingest(gameName:) async -> Bool` pipeline: TTL check, 4-source fetch, nil-safe aggregation, markdown formatting, and Worker POST
- `formatGamePage` produces structured markdown with Compatibility, Known Working Configuration (Lutris), and Fixes (WineHQ/PCGamingWiki) sections with deduplication across sources

## Task Commits

1. **Task 1: Promote private helpers and add fetchPopularGames** — `69b6328` (feat)
2. **Task 2: Create WikiIngestService with fetch-format-POST pipeline** — `b7aeed7` (feat)

## Files Created/Modified

- `/Users/peter/Documents/Cellar/Sources/cellar/Core/WikiIngestService.swift` — Full ingest pipeline: TTL check, WineHQ/PCGW fetch, formatGamePage, fetchHTML helper
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/WikiService.swift` — Removed `private` from `postWikiAppend` and `slugify`
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/CompatibilityService.swift` — Added `fetchPopularGames(limit:)` static method

## Decisions Made

- `fetchPopularGames` placed in `CompatibilityService` (not `WikiIngestService`) so the private `LutrisSearchResponse` struct stays accessible without a visibility change
- TTL check fetches `raw.githubusercontent.com` directly; network error or 404 both treated as stale — proceed with ingest rather than blocking
- All 4 sources are optional: page is only skipped when all return nil/empty; partial data (e.g., Lutris data but no WineHQ) produces a valid page
- `postWikiAppend` called once per ingest (game page only) — index.md/log.md updates deferred to the P02 batch layer to stay within the Worker's 10 writes/hr/IP rate limit

## Deviations from Plan

None — plan executed exactly as written. The `CompatibilityReport` type used `[ExtractedVerb]` (not `[String]`) for winetricks and `[ExtractedRegistry]` (not `[ExtractedRegistryEdit]`) for registry — these matched the actual codebase, not the plan's interface sketch, and were handled correctly.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `WikiIngestService.ingest(gameName:)` is ready to be wired into a CLI command (`cellar wiki ingest`)
- `CompatibilityService.fetchPopularGames(limit:)` is ready for the `--popular` batch flag
- P02 will add `WikiCommand` + `IngestCommand` and handle `--all-local` via `SuccessDatabase.loadAll()`

---
*Phase: 40-wiki-batch-ingest*
*Completed: 2026-04-15*
