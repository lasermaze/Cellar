---
phase: 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles
plan: 01
subsystem: memory
tags: [wiki, knowledge-base, wine-compatibility, spm-resources, karpathy]

# Dependency graph
requires:
  - phase: 37-supporting-win32-apps-we-need-to-pick-when-it-is-best-to-decide-about-win32-bottle-against-win64
    provides: GameEntry.bottleArch, PEReader, arch detection foundation
provides:
  - Sources/cellar/wiki/ directory with SCHEMA.md, index.md, log.md, and 8 seed pages
  - WikiService.fetchContext(for:symptoms:) for agent startup context injection
  - WikiService.search(query:) for mid-session agent tool lookups
  - SPM resource bundle for wiki/ directory (ships with Homebrew binary)
affects:
  - AIService (WikiService.fetchContext injection at agent startup)
  - AgentTools ResearchTools (query_wiki tool integration)
  - Phase 38 plan 02+ (ingest/lint operations build on this wiki foundation)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "WikiService: static methods only, Sendable struct, nil-on-failure (matches CollectiveMemoryService pattern)"
    - "Bundle.module resource access for wiki/ directory (SPM .copy resource)"
    - "Keyword scoring: index.md catalog → NSRegularExpression link extraction → relevance-ranked page loading"
    - "maxContentLength=4000, maxPages=3 caps wiki context injection to prevent bloat"

key-files:
  created:
    - Sources/cellar/wiki/SCHEMA.md
    - Sources/cellar/wiki/index.md
    - Sources/cellar/wiki/log.md
    - Sources/cellar/wiki/engines/directdraw.md
    - Sources/cellar/wiki/engines/dxvk.md
    - Sources/cellar/wiki/engines/unity.md
    - Sources/cellar/wiki/symptoms/black-screen.md
    - Sources/cellar/wiki/symptoms/crash-on-launch.md
    - Sources/cellar/wiki/symptoms/d3d-errors.md
    - Sources/cellar/wiki/environments/apple-silicon.md
    - Sources/cellar/wiki/environments/wine-stable-9.md
    - Sources/cellar/Core/WikiService.swift
  modified:
    - Package.swift

key-decisions:
  - "Wiki lives in Sources/cellar/wiki/ as SPM bundled resource — ships with binary via brew upgrade, not in ~/.cellar/"
  - "WikiService.fetchContext returns nil gracefully when wiki/index.md is missing — pitfall #5 avoidance"
  - "maxContentLength=4000 and maxPages=3 cap context injection — pitfall #2 avoidance (don't dump all wiki)"
  - "WikiService.search returns String (never nil) for agent tool use; fetchContext returns Optional for startup injection"
  - "No YAML frontmatter in wiki pages — keeps pages human-writable and grep-friendly (plain markdown)"
  - "games/ directory reserved for future per-game pages from ingest — not seeded manually"

patterns-established:
  - "WikiService pattern: struct WikiService: Sendable with static methods only, matches CollectiveMemoryService"
  - "Wiki page format: plain markdown, optional # Title, Last updated: YYYY-MM-DD footer, no frontmatter"
  - "index.md format: category sections with - [path](path) — summary lines for keyword scoring"
  - "log.md format: ## [YYYY-MM-DD] operation | title entries for parseability"

requirements-completed: []

# Metrics
duration: 5min
completed: 2026-04-10
---

# Phase 38 Plan 01: Wiki Directory Structure and WikiService Summary

**Karpathy three-layer wiki with 8 Wine compatibility seed pages and WikiService for keyword-based context injection via Bundle.module SPM resources**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-04-10T01:34:09Z
- **Completed:** 2026-04-10T01:38:45Z
- **Tasks:** 2
- **Files modified:** 13 (11 wiki pages created, WikiService.swift created, Package.swift updated)

## Accomplishments
- Created wiki/ directory under Sources/cellar/ following Karpathy three-layer pattern (raw sources / wiki / schema)
- Seeded 8 wiki pages with real actionable Wine compatibility knowledge across engines/, symptoms/, environments/
- Implemented WikiService.swift with keyword-based page selection (fetchContext and search methods)
- Updated Package.swift with .copy("wiki") — wiki now ships as bundled resource in the Homebrew binary
- swift build passes cleanly with wiki resources copied during build

## Task Commits

Each task was committed atomically:

1. **Task 1: Create wiki directory structure with seed pages** - `4bb58d7` (feat)
2. **Task 2: Create WikiService.swift and update Package.swift** - `e323a29` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `Sources/cellar/wiki/SCHEMA.md` - Wiki conventions, page types, linking style, operations (ingest/query/lint)
- `Sources/cellar/wiki/index.md` - Content catalog of all wiki pages with one-line summaries by category
- `Sources/cellar/wiki/log.md` - Append-only chronological record (seed entry for initial creation)
- `Sources/cellar/wiki/engines/directdraw.md` - cnc-ddraw wrapper, Wine 9+ regression, affected games
- `Sources/cellar/wiki/engines/dxvk.md` - DXVK DX9/10/11→Vulkan, version notes, Apple Silicon/MoltenVK
- `Sources/cellar/wiki/engines/unity.md` - Unity on Wine: Mono crashes, Steam overlay, winhttp, input
- `Sources/cellar/wiki/symptoms/black-screen.md` - Causes (ddraw, renderer, resolution), diagnostic steps
- `Sources/cellar/wiki/symptoms/crash-on-launch.md` - PE imports, vcrun, dotnet, anti-cheat detection
- `Sources/cellar/wiki/symptoms/d3d-errors.md` - Device creation failures, shader errors, DXVK vs WineD3D
- `Sources/cellar/wiki/environments/apple-silicon.md` - Rosetta 2, WoW64, GPTK, MoltenVK quirks
- `Sources/cellar/wiki/environments/wine-stable-9.md` - WoW64 change, ddraw regression, version compat table
- `Sources/cellar/Core/WikiService.swift` - fetchContext(for:symptoms:) and search(query:) with keyword scoring
- `Package.swift` - Added .copy("wiki") to resources array

## Decisions Made
- Wiki stored as SPM bundled resource (.copy("wiki") in Package.swift) so it ships with the binary and users get updates on brew upgrade — not in ~/.cellar/ which would require a separate sync command
- WikiService.fetchContext returns nil (not empty string) on wiki absence — caller treats nil as "no wiki context available" and skips injection gracefully
- WikiService.search returns plain String (never nil) for agent tool use — agents need a human-readable response even on no-match
- games/ subdirectory created but empty — reserved for future per-game pages from ingest operations (not seeded manually, per research recommendation)
- No YAML frontmatter in wiki pages — plain markdown with Last updated footer keeps pages human-writable without a parser

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None. Build passed on first attempt.

## User Setup Required

None - no external service configuration required. Wiki ships with the binary automatically.

## Next Phase Readiness
- WikiService is ready for integration into AIService.runAgentLoop() as a startup context injection source
- WikiService.search is ready to be wired up as a query_wiki agent tool in ResearchTools
- Wiki pages are seeded with foundational Wine compatibility knowledge; ingest/lint operations can extend the wiki in future phases
- No blockers

---
*Phase: 38-rebuild-memory-layer-shared-wiki-for-agents-based-on-karpathy-principles*
*Completed: 2026-04-10*
