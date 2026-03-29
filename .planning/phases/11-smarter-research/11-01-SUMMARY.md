---
phase: 11-smarter-research
plan: 01
subsystem: core
tags: [swiftsoup, html-parsing, regex, wine-fixes, page-parser]

requires:
  - phase: 07-agentic-v2
    provides: "fetchPage tool and agent web research pipeline"
provides:
  - "SwiftSoup SPM dependency for HTML DOM parsing"
  - "PageParser protocol with URL-based dispatch"
  - "WineHQParser, PCGamingWikiParser, GenericParser implementations"
  - "ExtractedFixes model with 5 Wine artifact categories"
  - "extractWineFixes regex function for Wine-specific artifact extraction"
affects: [11-02, 11-03]

tech-stack:
  added: [SwiftSoup 2.13.x]
  patterns: [PageParser protocol dispatch, regex-based Wine artifact extraction, @preconcurrency import for Swift 6]

key-files:
  created:
    - Sources/cellar/Core/PageParser.swift
    - Tests/cellarTests/PageParserTests.swift
  modified:
    - Package.swift

key-decisions:
  - "SwiftSoup 2.13.x via from: 2.13.0 (not 2.8.7 from earlier roadmap reference)"
  - "Winetricks verb extraction uses stop-word filtering to avoid matching common English words"
  - "@preconcurrency import SwiftSoup for Swift 6 strict concurrency compatibility"

patterns-established:
  - "PageParser protocol: canHandle(url:) + parse(document:url:) with parseHTML convenience"
  - "extractWineFixes shared function for regex-based Wine artifact extraction across all parsers"
  - "Fallback pattern: specialized parsers fall through to GenericParser when expected DOM elements missing"

requirements-completed: [RSRCH-03]

duration: 4min
completed: 2026-03-29
---

# Phase 11 Plan 01: PageParser Module Summary

**SwiftSoup HTML parsing with WineHQ/PCGamingWiki/Generic parsers and regex-based Wine fix extraction (env vars, DLLs, registry, winetricks, INI)**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T16:00:28Z
- **Completed:** 2026-03-29T16:04:09Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- SwiftSoup added as SPM dependency, compiles with Swift 6 strict concurrency
- PageParser protocol with three implementations dispatching by URL domain
- ExtractedFixes model covering all 5 Wine artifact categories with deduplication
- extractWineFixes regex function handles env vars, DLL overrides, WINEDLLOVERRIDES compound, winetricks verbs, registry paths, and INI changes
- 20 unit tests covering models, parsers, regex extraction, and parser dispatch

## Task Commits

Each task was committed atomically:

1. **Task 1: Add SwiftSoup SPM dependency** - `5520c95` (chore)
2. **Task 2 RED: Failing tests for PageParser** - `4391f0a` (test)
3. **Task 2 GREEN: PageParser implementation** - `8914006` (feat)

## Files Created/Modified
- `Package.swift` - Added SwiftSoup 2.13.x dependency
- `Sources/cellar/Core/PageParser.swift` - PageParser protocol, 3 parsers, models, regex extraction (409 lines)
- `Tests/cellarTests/PageParserTests.swift` - 20 unit tests for all PageParser functionality

## Decisions Made
- Used SwiftSoup `from: "2.13.0"` instead of 2.8.7 referenced in earlier roadmap planning (2.13.x has important bugfixes, same API surface)
- Added stop-word filtering for winetricks verb extraction to avoid matching common English words like "to", "install"
- Used `@preconcurrency import SwiftSoup` for Swift 6 strict concurrency compatibility

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Winetricks regex matched common English words as verbs**
- **Found during:** Task 2 (GREEN phase, test run)
- **Issue:** Regex `winetricks\s+((?:[a-z0-9_]+\s*)+)` greedily matched words after verb arguments (e.g., "to", "install", "runtimes")
- **Fix:** Added stop-word set filtering to exclude common English words from verb results
- **Files modified:** Sources/cellar/Core/PageParser.swift
- **Verification:** Test "extractWineFixes finds winetricks verbs" passes with exactly 2 verbs
- **Committed in:** 8914006 (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Minor regex refinement for correctness. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- PageParser module ready for Plan 02 to wire into fetchPage() tool
- extractWineFixes function available for any text source
- selectParser dispatch ready for URL-based parser selection

---
*Phase: 11-smarter-research*
*Completed: 2026-03-29*
