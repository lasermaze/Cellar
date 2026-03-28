---
phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
plan: 05
subsystem: core
tags: [agent-tools, search-web, fetch-page, research-cache, system-prompt, launch-game, diagnostic-mode]

requires:
  - phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
    provides: AgentTools with 16 tools (07-01 through 07-04), CellarPaths.researchCacheFile, SuccessDatabase
provides:
  - search_web tool for DuckDuckGo web research with 7-day per-game cache
  - fetch_page tool for URL text extraction with HTML stripping
  - Enhanced launch_game with pre-flight checks, diagnostic mode, and loaded DLL analysis
  - V2 system prompt with Research-Diagnose-Adapt three-phase workflow and macOS/Wine domain knowledge
  - Complete 18-tool agentic v2 architecture
affects: []

tech-stack:
  added: []
  patterns:
    - "DuckDuckGo HTML search parsing via NSRegularExpression for result extraction"
    - "Research cache with Codable struct and ISO8601 7-day TTL staleness check"
    - "Pre-flight DLL override file existence checks before Wine launch"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "DuckDuckGo HTML search (no API key needed) for web research tool"
  - "Research cache per-game with 7-day TTL stored at CellarPaths.researchCacheFile"
  - "Diagnostic launches do not count toward 8-launch limit"
  - "Virtual desktop mode removed from system prompt (winemac.drv incompatible on macOS)"
  - "System prompt references all 18 tools organized by category (Research/Diagnostic/Action/User/Persistence)"

patterns-established:
  - "Three-phase agent workflow: Research (query_successdb + search_web) -> Diagnose (trace_launch + verify) -> Adapt (configure + launch)"

requirements-completed: []

duration: 4min
completed: 2026-03-28
---

# Phase 7 Plan 05: Research Tools + V2 System Prompt Summary

**search_web/fetch_page research tools with 7-day cache, enhanced launch_game with pre-flight checks and diagnostic mode, and Research-Diagnose-Adapt system prompt completing the 18-tool agentic v2 architecture**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-28T02:04:33Z
- **Completed:** 2026-03-28T02:08:24Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- search_web queries DuckDuckGo HTML for Wine compatibility info, parses result links/titles/snippets via regex, caches per-game with 7-day TTL using ResearchCache Codable struct
- fetch_page fetches any URL, strips scripts/styles/HTML tags, decodes HTML entities, collapses whitespace, truncates to 8000 chars
- launch_game enhanced: pre-flight checks verify executable exists and DLL files present for native overrides; parsed loaded_dlls from stderr; diagnostic param exempts from 8-launch limit
- System prompt rewritten: three-phase Research-Diagnose-Adapt workflow, correct macOS/Wine domain knowledge (no virtual desktop, syswow64 for 32-bit system DLLs, cnc-ddraw requires ddraw.ini), references all 18 tools by category

## Task Commits

Each task was committed atomically:

1. **Task 1: search_web + fetch_page tools with research cache** - `8b80967` (feat)
2. **Task 2: Enhanced launch_game + v2 system prompt** - `e2ea639` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AgentTools.swift` - Added ResearchCache/ResearchResult structs, search_web + fetch_page tools (definitions + dispatch + implementations), enhanced launch_game with pre-flight checks + diagnostic mode + loaded_dlls
- `Sources/cellar/Core/AIService.swift` - Replaced system prompt with v2 Research-Diagnose-Adapt workflow, updated initial message

## Decisions Made
- DuckDuckGo HTML search requires no API key -- simplest path for web research
- Research cache uses per-game JSON files with ISO8601 timestamp and 7-day TTL
- Diagnostic launches exempt from launch limit to encourage tracing before configuring
- Virtual desktop suggestion removed from system prompt (winemac.drv does not support it on macOS)
- System prompt organizes 18 tools into 5 categories: Research, Diagnostic, Action, User, Persistence

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required. DuckDuckGo HTML search needs no API key.

## Next Phase Readiness
- V2 agentic architecture complete: 18 tools (10 original + 8 new from phase 07)
- Agent can now research before configuring, diagnose before acting, and save comprehensive success records
- Ready for UAT testing with real games

---
*Phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database*
*Completed: 2026-03-28*
