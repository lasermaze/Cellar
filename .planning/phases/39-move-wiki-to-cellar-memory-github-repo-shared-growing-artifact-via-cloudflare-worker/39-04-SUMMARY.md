---
phase: 39-move-wiki-to-cellar-memory
plan: "04"
subsystem: infra
tags: [spm, swift-package-manager, wiki, cellar-memory, bundle-cleanup]

# Dependency graph
requires:
  - phase: 39-01
    provides: WikiService reads from ~/.cellar/wiki/ local cache populated from GitHub raw URLs
  - phase: 39-02
    provides: WikiService.ingest POSTs to Cloudflare Worker; no Bundle.module writes remain
  - phase: 39-03
    provides: Cloudflare Worker /api/wiki/append endpoint for authenticated wiki writes
provides:
  - SPM cellar target ships no wiki bundle — single source of truth is cellar-memory GitHub repo
  - Sources/cellar/wiki/ directory removed from repo history
  - Package.swift resources array contains only .copy("Resources")
affects: [future-wiki-phases, homebrew-tap, binary-size]

# Tech tracking
tech-stack:
  added: []
  patterns: [wiki content lives exclusively in cellar-memory GitHub repo; local ~/.cellar/wiki/ is a read cache]

key-files:
  created: []
  modified:
    - Package.swift

key-decisions:
  - "Empty resources array not used — .copy(Resources) kept as sole entry, matching existing Swift style"

patterns-established:
  - "No bundled content that must grow post-install — all wiki data fetched at runtime from GitHub"

requirements-completed: []

# Metrics
duration: 5min
completed: 2026-04-15
---

# Phase 39 Plan 04: SPM Wiki Bundle Removal Summary

**Removed .copy("wiki") from Package.swift and deleted Sources/cellar/wiki/ (11 files) — wiki seed now lives exclusively in lasermaze/cellar-memory/wiki/ on GitHub**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-15T01:03:00Z
- **Completed:** 2026-04-15T01:03:38Z
- **Tasks:** 1 (Task 1 was pre-completed by operator; Task 2 executed here)
- **Files modified:** 12 (Package.swift + 11 deleted wiki files)

## Accomplishments
- Removed `.copy("wiki")` resource directive from Package.swift cellar target
- Deleted entire Sources/cellar/wiki/ directory (SCHEMA.md, index.md, log.md, 4 subdirs with 7 engine/symptom/environment pages)
- Confirmed swift build succeeds with zero errors
- Confirmed swift test passes with all 173 tests

## Task Commits

Each task was committed atomically:

1. **Task 2: Remove .copy("wiki") from Package.swift and delete Sources/cellar/wiki/** - `01f2e68` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `Package.swift` - Removed `.copy("wiki")` from resources array; `.copy("Resources")` is the only remaining entry
- `Sources/cellar/wiki/` - Entire directory deleted (11 .md files across 4 subdirectories)

## Decisions Made
- Kept resources array with single `.copy("Resources")` entry rather than removing the `resources:` parameter entirely — the Resources bundle is still actively used by the web server for Leaf templates and static assets

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 39 is fully complete: wiki reads from GitHub via local cache, writes through Cloudflare Worker, SPM target ships no wiki bundle
- Phase 40 (wiki batch ingest from Lutris/ProtonDB/WineHQ/PCGamingWiki) can now proceed — the write path via Worker is the single channel for all wiki content

---
*Phase: 39-move-wiki-to-cellar-memory*
*Completed: 2026-04-15*
