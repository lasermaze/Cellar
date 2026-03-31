---
phase: 17-web-memory-ui
plan: 01
subsystem: ui
tags: [leaf, vapor, github-api, collective-memory, web]

# Dependency graph
requires:
  - phase: 13-github-app-authentication
    provides: GitHubAuthService.shared.getToken() and memoryRepo property
  - phase: 14-memory-entry-schema
    provides: CollectiveMemoryEntry, EnvironmentFingerprint, slugify()
  - phase: 16-write-path
    provides: collective memory repo populated with entries

provides:
  - MemoryStatsService with fetchStats() and fetchGameDetail(slug:)
  - MemoryController registering GET /memory and GET /memory/:gameSlug
  - memory.leaf aggregate stats template with isAvailable graceful degradation
  - memory-game.leaf per-game detail template with environment/confidence display
  - Memory nav link in base.leaf

affects: [future web phases, any UI referencing collective memory]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Stateless struct service with static methods (same as CollectiveMemoryService)"
    - "MemoryStatsService.isAvailable flag for graceful degradation — never throws, swallows all errors"
    - "Flat MemoryEntryViewData view model — Leaf cannot render deeply nested optionals"

key-files:
  created:
    - Sources/cellar/Web/Services/MemoryStatsService.swift
    - Sources/cellar/Web/Controllers/MemoryController.swift
    - Sources/cellar/Resources/Views/memory.leaf
    - Sources/cellar/Resources/Views/memory-game.leaf
  modified:
    - Sources/cellar/Web/WebApp.swift
    - Sources/cellar/Resources/Views/base.leaf

key-decisions:
  - "MemoryStats.isAvailable: false returned when auth unavailable — template shows guidance to Settings instead of error"
  - "fetchGameDetail(slug:) returns nil on any failure — template shows empty state, no Vapor 404 abort"
  - "GitHubDirectoryEntry is a private struct inside MemoryStatsService — not exported"

patterns-established:
  - "isAvailable flag pattern: service returns populated struct with isAvailable: false rather than throwing/crashing"
  - "Flat Content view model: deeply nested structs flattened into MemoryEntryViewData for Leaf compatibility"

requirements-completed: [WEBM-01, WEBM-02]

# Metrics
duration: 6min
completed: 2026-03-30
---

# Phase 17 Plan 01: Web Memory UI Summary

**Community memory web UI with aggregate stats at /memory and per-game entries at /memory/:slug, both gracefully degrading when the GitHub repo is unreachable**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-03-31T03:32:19Z
- **Completed:** 2026-03-31T03:38:00Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- MemoryStatsService fetches GitHub directory listing and per-game entry files, aggregates stats, returns top-10 recent contributions
- MemoryController routes /memory and /memory/:gameSlug to Leaf templates with Content-conforming context structs
- memory.leaf shows games covered, total confirmations, and a recent contributions table with links to per-game views
- memory-game.leaf shows per-game environment details (arch, Wine, macOS, flavor), confirmations, and agent reasoning in a collapsible details block
- base.leaf updated with Memory nav link between Games and Settings

## Task Commits

Each task was committed atomically:

1. **Task 1: Create MemoryStatsService and MemoryController with WebApp registration** - `c4dac76` (feat)
2. **Task 2: Create Leaf templates and add Memory nav link** - `75c54ed` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified
- `Sources/cellar/Web/Services/MemoryStatsService.swift` - GitHub API fetching for aggregate stats and per-game detail; graceful degradation via isAvailable flag
- `Sources/cellar/Web/Controllers/MemoryController.swift` - Routes for /memory and /memory/:gameSlug with Content-conforming context structs
- `Sources/cellar/Resources/Views/memory.leaf` - Aggregate stats template with conditional rendering on isAvailable and recentContributions
- `Sources/cellar/Resources/Views/memory-game.leaf` - Per-game entry detail template with environment details and agent reasoning
- `Sources/cellar/Web/WebApp.swift` - Added MemoryController.register(app) after SettingsController
- `Sources/cellar/Resources/Views/base.leaf` - Added Memory nav link between Games and Settings

## Decisions Made
- `MemoryStats.isAvailable: false` when auth is unavailable — the template guides users to Settings rather than showing a 500 error or crashing
- `fetchGameDetail(slug:)` returns `nil` on any failure (404, parse error, network) — MemoryController passes nil to the template which shows a graceful empty state; no Vapor `Abort(.notFound)` is thrown
- `GitHubDirectoryEntry` kept private inside MemoryStatsService since it is only used for directory listing
- Flat `MemoryEntryViewData` view model ensures Leaf can render all fields without encountering deeply nested optionals

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required. GitHub App credentials configured via existing Settings page.

## Next Phase Readiness

- /memory and /memory/:slug routes are live; end-to-end visible once GitHub App credentials are configured
- Phase 17 plan 01 complete; any additional plans in phase 17 can proceed

---
*Phase: 17-web-memory-ui*
*Completed: 2026-03-30*
