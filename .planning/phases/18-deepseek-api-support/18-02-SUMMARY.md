---
phase: 18-deepseek-api-support
plan: 02
subsystem: api
tags: [deepseek, anthropic, ai-provider, agent-loop, settings-ui, swift]

# Dependency graph
requires:
  - phase: 18-01
    provides: AgentLoopProvider protocol, AnthropicAgentProvider, DeepseekAgentProvider structs

provides:
  - Provider-agnostic AgentLoop driven by AgentLoopProvider protocol
  - AIService.detectProvider() respects AI_PROVIDER env/config, auto-detects from available keys
  - AIService.runAgentLoop() creates correct provider (Anthropic or Deepseek) based on configuration
  - AIService.makeAPICall() routes simple calls (diagnose, recipe, variants) through Deepseek
  - CellarConfig.aiProvider field persists provider selection in config.json
  - Settings web UI with provider dropdown and Deepseek API key field
  - Provider-specific error messages when keys are missing

affects: [19-collective-memory-write-path, any phase using AIService]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - AgentLoopProvider protocol owns message array — AgentLoop only works with normalized AgentLoopProviderResponse
    - Provider created with fully-built systemPrompt after prompt construction (not placeholder at detection time)
    - Provider-specific error messages in .failed() when AI_PROVIDER is set but key is absent

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AgentLoop.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Persistence/CellarConfig.swift
    - Sources/cellar/Web/Controllers/SettingsController.swift
    - Sources/cellar/Resources/Views/settings.leaf

key-decisions:
  - "AgentLoop.run() is now mutating — uses var provider since protocol methods are mutating"
  - "Provider created after systemPrompt is built (not at provider-detection time) to avoid placeholder pattern"
  - "makeAPICall() routes Deepseek simple calls through callDeepseek() using OpenAIRequest/OpenAIResponse types"
  - "Budget warning injection uses appendUserMessage() after appendToolResults() instead of ToolContentBlock text"

patterns-established:
  - "AgentLoop is provider-agnostic: no Anthropic-specific types in run() body"
  - "detectProvider() reads AI_PROVIDER from CellarConfig.aiProvider first, then env var, then auto-detects"

requirements-completed: [DSPK-01, DSPK-02, DSPK-03]

# Metrics
duration: 12min
completed: 2026-03-30
---

# Phase 18 Plan 02: Deepseek API Support — Wire Integration Summary

**Provider-agnostic AgentLoop using AgentLoopProvider protocol with Deepseek routing in AIService and settings UI for provider selection**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-03-30
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- AgentLoop fully refactored: dropped apiKey/model/tools/systemPrompt properties, uses `var provider: AgentLoopProvider` — all private Anthropic HTTP methods deleted
- AIService.detectProvider() respects `AI_PROVIDER` from CellarConfig and env, with auto-detection fallback
- AIService.runAgentLoop() creates AnthropicAgentProvider or DeepseekAgentProvider based on detected provider
- AIService.makeAPICall() handles `.deepseek` via new `callDeepseek()` method (reuses OpenAIRequest/OpenAIResponse)
- Provider-specific error messages across diagnose(), generateRecipe(), generateVariants(), and runAgentLoop()
- CellarConfig gains `aiProvider: String?` / `"ai_provider"` JSON key
- Settings page: AI Provider dropdown (Auto-detect / Claude / Deepseek) + Deepseek key field

## Task Commits

1. **Task 1: Refactor AgentLoop + AIService routing + CellarConfig** - `891c5ea` (feat)
2. **Task 2: Settings UI — provider dropdown + Deepseek key field** - `62d1e26` (feat)

## Files Created/Modified

- `Sources/cellar/Core/AgentLoop.swift` - Removed apiKey/model, replaced with provider protocol; deleted private Anthropic HTTP methods
- `Sources/cellar/Core/AIService.swift` - detectProvider() with AI_PROVIDER support; runAgentLoop() provider routing; makeAPICall() Deepseek case; provider-specific error messages
- `Sources/cellar/Persistence/CellarConfig.swift` - Added aiProvider: String? field with ai_provider JSON key
- `Sources/cellar/Web/Controllers/SettingsController.swift` - SettingsContext + KeysInput extended with deepseekKey, hasDeepseekKey, aiProvider fields
- `Sources/cellar/Resources/Views/settings.leaf` - Provider dropdown and Deepseek key input field

## Decisions Made

- AgentLoop.run() is `mutating` because the provider protocol uses mutating methods for message state
- Provider is constructed after the systemPrompt string is fully built (late binding) — avoids the placeholder empty-string pattern
- Budget warning injection in tool_use path uses `appendUserMessage()` after `appendToolResults()` rather than inserting a `.text` ToolContentBlock — cleaner abstraction across providers
- `callDeepseek()` for simple API calls reuses existing `OpenAIRequest`/`OpenAIResponse` types with Deepseek URL and Bearer auth (same wire format)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- Full Deepseek integration is functional. Users can set `AI_PROVIDER=deepseek` and `DEEPSEEK_API_KEY=sk-xxx` in `~/.cellar/.env`, and all AI operations route through Deepseek.
- Phase 18 is complete. Phase 14 (Collective Agent Memory) is next.

---
*Phase: 18-deepseek-api-support*
*Completed: 2026-03-30*
