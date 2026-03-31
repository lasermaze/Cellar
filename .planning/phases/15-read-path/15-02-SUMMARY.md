---
phase: 15-read-path
plan: 02
subsystem: ai
tags: [collective-memory, agent-loop, wine, context-injection]

# Dependency graph
requires:
  - phase: 15-read-path (plan 01)
    provides: CollectiveMemoryService.fetchBestEntry() — fetch/filter/rank/format pipeline
provides:
  - Agent initial messages include community-verified config context when available
  - System prompt instructs agent to try stored configs before web research
  - Silent fallback: behavior is unchanged when no memory entry exists
affects: [16-write-path, agent-loop, ai-service]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Memory injection: fetch collective memory before initialMessage construction, prepend block when non-nil"
    - "System prompt section: ## Collective Memory instructs agent to prefer stored config over fresh research"

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "Memory context injected as prefix to launchInstruction in initialMessage — agent sees community config before any tool calls"
  - "fetchBestEntry placed after AgentTools creation (wineURL available) but before initialMessage construction — no changes to AgentTools or AgentLoop"

patterns-established:
  - "Silent skip pattern: nil return from fetchBestEntry means initialMessage is identical to pre-Phase-15 behavior"

requirements-completed: [READ-01, READ-02, READ-03]

# Metrics
duration: 5min
completed: 2026-03-31
---

# Phase 15 Plan 02: Agent Loop Memory Integration Summary

**CollectiveMemoryService wired into AIService.runAgentLoop() — agents receive community-verified Wine config in the initial message before any tool calls**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-03-31T01:55:00Z
- **Completed:** 2026-03-31T01:59:52Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- System prompt extended with `## Collective Memory` section instructing agent to apply stored config before web research
- `CollectiveMemoryService.fetchBestEntry` called in `runAgentLoop` before `initialMessage` construction
- Memory context block prepended to launch instruction when available; identical behavior when nil
- Build compiles cleanly

## Task Commits

Each task was committed atomically:

1. **Task 1: Add system prompt section and inject memory context into initial message** - `634232c` (feat)

**Plan metadata:** (docs commit — pending)

## Files Created/Modified
- `Sources/cellar/Core/AIService.swift` - Added `## Collective Memory` system prompt section; replaced single `initialMessage` line with memory-aware construction using `CollectiveMemoryService.fetchBestEntry`

## Decisions Made
- Memory context fetch placed between `AgentTools` instantiation and `initialMessage` construction (after `wineURL` is available, no changes to `AgentTools` or `AgentLoop`)
- `launchInstruction` extracted as named variable to keep the conditional initialMessage construction readable

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Read path is complete: CollectiveMemoryService (plan 01) + AIService integration (plan 02)
- Agent launches now automatically receive community configs when available
- Phase 16 (write path / confidence deduplication) can begin
- Blocker noted: confidence deduplication mechanism (per-environment-hash) needs design before Phase 16

---
*Phase: 15-read-path*
*Completed: 2026-03-31*
