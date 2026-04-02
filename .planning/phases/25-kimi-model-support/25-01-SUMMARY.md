---
phase: 25-kimi-model-support
plan: 01
subsystem: ai
tags: [kimi, moonshot, ai-provider, openai-compatible]

# Dependency graph
requires:
  - phase: 18-deepseek-api-support
    provides: DeepseekAgentProvider pattern, OpenAI-compatible API integration, AIProvider enum extension pattern
provides:
  - .kimi(apiKey: String) enum case in AIProvider
  - KimiAgentProvider struct calling api.moonshot.cn with moonshot-v1-128k default
  - detectProvider() Kimi detection and auto-detect cascade (Anthropic -> Deepseek -> Kimi -> OpenAI)
  - callKimi() for non-agent AI operations (diagnose, generateRecipe, generateVariants)
  - Kimi-specific error messages at all 4 unavailable error sites
affects: [AIService, AgentLoopProvider, AIModels, any future AI provider additions]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "KimiAgentProvider mirrors DeepseekAgentProvider exactly — separate structs per provider (Phase 18 pattern)"
    - "Kimi uses OpenAI-compatible API format (same as Deepseek) with Bearer auth"
    - "Provider auto-detect cascade: Anthropic -> Deepseek -> Kimi -> OpenAI (env key presence order)"

key-files:
  created: []
  modified:
    - Sources/cellar/Models/AIModels.swift
    - Sources/cellar/Core/AgentLoopProvider.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "KimiAgentProvider is a separate struct (not refactoring DeepseekAgentProvider) — follows Phase 18 pattern of one struct per provider"
  - "moonshot-v1-128k as default Kimi model — largest context window for game compatibility research"
  - "Kimi inserted between Deepseek and OpenAI in auto-detect cascade — Deepseek has priority as established alternative provider"
  - "KIMI_API_KEY env var (not MOONSHOT_API_KEY) — shorter and consistent with pattern"

patterns-established:
  - "New AI provider = 3-file change: AIModels.swift (enum case), AgentLoopProvider.swift (provider struct + pricing), AIService.swift (detection + routing + API call)"

requirements-completed:
  - Kimi API integration
  - AIProvider enum extension
  - AIService provider detection
  - AgentLoopProvider Kimi implementation

# Metrics
duration: 8min
completed: 2026-04-02
---

# Phase 25 Plan 01: Kimi Model Support Summary

**Kimi (Moonshot AI) added as full AI provider: .kimi enum case, KimiAgentProvider using api.moonshot.cn, KIMI_API_KEY auto-detect in cascade, and Kimi routing in all 4 AIService operations**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-02T00:00:00Z
- **Completed:** 2026-04-02T00:08:00Z
- **Tasks:** 2 (committed together — Task 1 alone caused build error, Task 2 resolved it)
- **Files modified:** 3

## Accomplishments
- Added `.kimi(apiKey: String)` enum case to `AIProvider` in AIModels.swift
- Created `KimiAgentProvider` struct (copy of DeepseekAgentProvider with moonshot endpoint and defaults)
- Added 3 Kimi pricing entries: moonshot-v1-8k/32k/128k with Moonshot AI pricing
- Wired `detectProvider()` to handle AI_PROVIDER=kimi/moonshot and KIMI_API_KEY auto-detection
- Added Kimi error messages at all 4 `.unavailable` error sites (diagnose, generateRecipe, generateVariants, runAgentLoop)
- Added `.kimi` routing in `runAgentLoop()` to `KimiAgentProvider`
- Added `.kimi` routing in `makeAPICall()` to new `callKimi()` function calling api.moonshot.cn

## Task Commits

Both tasks committed atomically as a single commit (Task 1 alone would not compile without Task 2's switch exhaustiveness fix):

1. **Tasks 1+2: Add Kimi provider (enum, agent provider, AIService wiring)** - `4c95b45` (feat)

**Plan metadata:** (pending)

## Files Created/Modified
- `Sources/cellar/Models/AIModels.swift` - Added `.kimi(apiKey: String)` case to `AIProvider` enum
- `Sources/cellar/Core/AgentLoopProvider.swift` - Added `KimiAgentProvider` struct and moonshot pricing entries
- `Sources/cellar/Core/AIService.swift` - Kimi detection, error messages, runAgentLoop routing, makeAPICall routing, callKimi()

## Decisions Made
- KimiAgentProvider is a separate struct mirroring DeepseekAgentProvider exactly — consistent with Phase 18 "one struct per provider" pattern
- moonshot-v1-128k as default model for both agent loop and simple API calls — large context window suits game compatibility research
- Auto-detect cascade inserts Kimi after Deepseek (before OpenAI legacy) — Deepseek has established priority
- Tasks 1 and 2 committed together — Task 1 alone produced an exhaustive switch error, making a single combined commit cleaner

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 were committed together due to compilation dependency (new enum case requires new switch branches) but all specified changes were made as planned.

## Issues Encountered
None - build passed cleanly after all changes were applied.

## User Setup Required
To use Kimi: add `KIMI_API_KEY=your-key-here` to `~/.cellar/.env`, or set `AI_PROVIDER=kimi` with the key set.

## Next Phase Readiness
- Kimi provider fully functional — all AI operations (agent loop, diagnose, generateRecipe, generateVariants) route to Kimi when configured
- Phase 25 is a single-plan phase — complete after this plan

## Self-Check: PASSED

All 3 modified files exist on disk. Commit 4c95b45 verified in git log.

---
*Phase: 25-kimi-model-support*
*Completed: 2026-04-02*
