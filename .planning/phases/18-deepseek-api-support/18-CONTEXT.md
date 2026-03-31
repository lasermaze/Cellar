# Phase 18: Deepseek API Support - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Deepseek as a selectable AI provider alongside Claude. Users can choose which backend drives recipe generation, log interpretation, and the full agent loop. This phase adds Deepseek support only — it does not restructure the existing OpenAI simple-API path or add other providers.

</domain>

<decisions>
## Implementation Decisions

### Agent loop strategy
- Create an AIProviderProtocol with Anthropic + Deepseek implementations
- AgentLoop becomes provider-agnostic — takes a provider instance, not an API key
- Deepseek uses OpenAI-compatible tool-use format (function_call), which differs from Anthropic's tool_use blocks
- Provider protocol handles: request building, response parsing, stop_reason translation, tool-use format conversion
- Only refactor what's necessary to make the protocol work — don't restructure existing OpenAI simple-API path

### Provider selection UX
- `AI_PROVIDER` env var or config.json field selects the active provider
- Values: `claude` (default), `deepseek`
- `DEEPSEEK_API_KEY` env var or ~/.cellar/.env for the API key
- Web settings page gets a provider dropdown and Deepseek API key field
- Change takes effect next launch — no hot-switching mid-session
- Auto-detection fallback: if only one provider's key is present, use that provider

### Model and pricing
- Default Deepseek model: `deepseek-reasoner` (reasoning-focused, $0.55/$2.19 per MTok)
- Per-provider pricing map replaces hardcoded Sonnet pricing in AgentLoop
- Map: model string -> (inputPricePerMillion, outputPricePerMillion)
- Default budget stays $15 (goes ~5-7x further with Deepseek)
- Pricing map lives in a central location, easy to update when models change

### System prompt
- Same system prompt for both providers with minor tweaks
- Remove any Anthropic/Claude self-references from the prompt
- Keep all tool descriptions, Wine debugging instructions, and agent behavior rules as-is
- The prompt describes WHAT to do, not provider-specific features

### Scope boundary
- Add Deepseek support only — minimal refactor
- Don't restructure existing OpenAI simple-API path unless it's in the way
- Don't add other providers (Gemini, local models, etc.)
- AIProvider enum: add `.deepseek` case
- Touch list: AIProvider enum, provider protocol + implementations, AIModels (OpenAI-format tool types), AIService (provider routing), Settings (dropdown + key field), pricing map

### Claude's Discretion
- Provider protocol exact interface design
- How to handle Deepseek-specific quirks (if any) in tool-use responses
- Whether to split provider implementations into separate files or keep in one
- Test strategy for provider switching

</decisions>

<specifics>
## Specific Ideas

- Deepseek API is OpenAI-compatible: same endpoint format, function_call tool-use, similar response structure
- The existing AIProvider enum already has `.anthropic` and `.openai` — adding `.deepseek` is natural
- AgentLoop currently takes `apiKey: String` and `model: String` — needs to take a provider instance instead
- SettingsController already handles two API keys (Anthropic + OpenAI) — extend pattern for Deepseek
- Pricing: deepseek-reasoner at $0.55/$2.19 vs Claude Sonnet at $3/$15 — roughly 5-7x cheaper

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AIProvider` enum in AIService.swift: already supports `.anthropic` and `.openai` switching for simple API calls
- `AIService.makeAPICall()`: existing provider dispatch pattern (switch on provider case)
- `OpenAIRequest`/`OpenAIResponse` in AIModels.swift: existing OpenAI-format types (simple API only, no tool-use)
- `SettingsController.swift`: existing API key form with masking — extend for Deepseek key + provider dropdown
- `settings.leaf`: existing settings template

### Established Patterns
- HTTP calls: URLSession.shared + DispatchSemaphore bridge (used by both AIService and AgentLoop)
- Retry: exponential backoff [1s, 2s, 4s], retry on 5xx/429
- Config: env var > ~/.cellar/.env > default (priority cascade)
- Pricing: hardcoded in AgentLoop lines 148-154 — needs to become a map

### Integration Points
- AgentLoop.swift (489 lines): main refactor target — extract Anthropic-specific code behind protocol
- AIModels.swift (379 lines): add OpenAI-format tool-use types (function_call request/response)
- AIService.swift (923 lines): update runAgentLoop() to use provider protocol instead of hardcoded Anthropic
- LaunchCommand.swift + LaunchController.swift: callers of runAgentLoop() — may need provider parameter
- CellarConfig.swift: add aiProvider field

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 18-deepseek-api-support*
*Context gathered: 2026-03-30*
