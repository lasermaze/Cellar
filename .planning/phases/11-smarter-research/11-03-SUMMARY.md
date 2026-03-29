---
phase: 11-smarter-research
plan: 03
subsystem: ai
tags: [system-prompt, research-quality, extracted-fixes, similar-games, agent-methodology]

requires:
  - phase: 11-smarter-research/01
    provides: "PageParser with SwiftSoup HTML parsing and structured fix extraction"
  - phase: 11-smarter-research/02
    provides: "fetch_page integration with extracted_fixes and query_successdb similar_games"
provides:
  - "Research Quality methodology section in agent system prompt"
  - "Agent guidance for preferring extracted_fixes over raw text_content"
  - "Agent guidance for cross-game similar_games queries"
  - "Phase 1 Research step 2c for similar_games fallback"
affects: [agent-behavior, research-workflow]

tech-stack:
  added: []
  patterns: ["System prompt methodology sections between Dialog Detection and Domain Knowledge"]

key-files:
  created: []
  modified: ["Sources/cellar/Core/AIService.swift"]

key-decisions:
  - "Research Quality section placed between Dialog Detection and macOS + Wine Domain Knowledge, continuing the established prompt ordering pattern"
  - "Tool descriptions inlined in Available Tools line rather than separate subsection, keeping the existing compact format"

patterns-established:
  - "Research Quality methodology: extracted_fixes-first, then text_content fallback"
  - "Cross-game matching: score 4+ apply with confidence, lower scores as research hints"

requirements-completed: [RSRCH-01, RSRCH-02]

duration: 1min
completed: 2026-03-29
---

# Phase 11 Plan 03: Research Quality Methodology Summary

**Agent system prompt updated with Research Quality section teaching extracted_fixes-first workflow and cross-game similar_games matching**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-29T16:06:39Z
- **Completed:** 2026-03-29T16:08:00Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Added Research Quality methodology section with three subsections: Using extracted_fixes, Cross-Game Solution Matching, Research Workflow Integration
- Added step 2c to Phase 1 Research for similar_games fallback when no exact match exists
- Updated Available Tools descriptions for fetch_page (extracted_fixes) and query_successdb (similar_games)
- Section correctly placed between Dialog Detection and macOS + Wine Domain Knowledge

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Research Quality methodology to system prompt** - `a4b0023` (feat)

**Plan metadata:** TBD (docs: complete plan)

## Files Created/Modified
- `Sources/cellar/Core/AIService.swift` - Added 51 lines: Research Quality section, step 2c, updated tool descriptions

## Decisions Made
- Research Quality section placed between Dialog Detection and macOS + Wine Domain Knowledge, continuing the established prompt ordering pattern from Phase 9 (Engine-Aware) and Phase 10 (Dialog Detection)
- Tool descriptions kept inline in the existing compact Available Tools format rather than adding separate subsections

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 11 complete: all 3 plans delivered (PageParser, tool integration, agent prompt methodology)
- Agent now has full pipeline: SwiftSoup parsing -> structured extraction -> prompt guidance for using extracted data
- Ready for milestone v1.1 completion assessment

---
*Phase: 11-smarter-research*
*Completed: 2026-03-29*
