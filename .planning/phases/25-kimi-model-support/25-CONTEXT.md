# Phase 25: Kimi model support - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Add Kimi (Moonshot AI) as a supported AI provider alongside Claude and Deepseek. Users can select Kimi as their provider for recipe generation, log interpretation, and the full agent loop. Follows the exact same integration pattern established in Phase 18 (Deepseek).

</domain>

<decisions>
## Implementation Decisions

### API integration
- Kimi uses an OpenAI-compatible API format — same as Deepseek
- Create a KimiAgentProvider implementing AgentLoopProvider protocol, modeled on DeepseekAgentProvider
- Kimi API endpoint: https://api.moonshot.cn/v1/chat/completions
- Default model: moonshot-v1-128k (128K context, strong reasoning)
- Add Kimi pricing to the modelPricing map in AgentLoopProvider.swift

### Provider enum and detection
- Add `.kimi(apiKey: String)` case to AIProvider enum in AIModels.swift
- Env var: `KIMI_API_KEY` (consistent with existing `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY` pattern)
- AI_PROVIDER config value: `"kimi"` or `"moonshot"`
- Auto-detection cascade: Anthropic → Deepseek → Kimi → OpenAI → unavailable
- AIService.detectProvider() extended with Kimi detection
- AIService.runAgentLoop() routes `.kimi` to KimiAgentProvider

### Web settings UI
- Extend settings dropdown with Kimi option
- Add Kimi API key field to settings form (same masked-input pattern as Deepseek)
- settings.leaf template extended

### System prompt
- Same system prompt as other providers — no Kimi-specific modifications
- Remove any provider self-references (already done in Phase 18)

### Scope boundary
- Kimi support only — no other new providers
- Follow Phase 18 pattern exactly: enum case, provider implementation, detection, settings UI, pricing
- Touch list: AIModels.swift (enum), AIService.swift (detection + routing), AgentLoopProvider.swift (pricing + KimiAgentProvider), SettingsController.swift (dropdown + key), settings.leaf (form fields), CellarConfig.swift (if needed)

### Claude's Discretion
- Whether KimiAgentProvider is a new struct or a parameterized reuse of DeepseekAgentProvider (both are OpenAI-compatible)
- Exact Kimi model pricing (verify from current API docs)
- Whether to add moonshot-v1-8k and moonshot-v1-32k as alternative model options
- Any Kimi-specific quirks in tool-use response format

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DeepseekAgentProvider` in AgentLoopProvider.swift — Kimi is also OpenAI-compatible, may be directly reusable or slightly adapted
- `agentCallAPI()` shared async HTTP helper — already used by both Anthropic and Deepseek providers
- `modelPricing` map — just add Kimi entries
- `AIProvider` enum — add one case
- `AIService.detectProvider()` — extend switch with "kimi"/"moonshot" case
- `SettingsController.swift` — existing pattern for provider dropdown + API key fields

### Established Patterns
- Provider protocol: `AgentLoopProvider` with `callWithRetry`, `appendUserMessage`, etc.
- HTTP: native async/await via `agentCallAPI()` (migrated in Phase 24)
- Config priority: env var > ~/.cellar/.env > default
- Settings: masked API key fields, provider dropdown, POST handler

### Integration Points
- `AIModels.swift:5-10` — AIProvider enum (add `.kimi` case)
- `AIService.swift:9-30` — detectProvider() switch statement
- `AIService.swift` — runAgentLoop() provider routing
- `AgentLoopProvider.swift:42-47` — modelPricing map (add Kimi entries)
- `AgentLoopProvider.swift` — new KimiAgentProvider struct (or parameterized DeepseekAgentProvider)
- `SettingsController.swift` — dropdown options + key field handler
- `settings.leaf` — form template

</code_context>

<specifics>
## Specific Ideas

- Kimi API is OpenAI-compatible, so the DeepseekAgentProvider may work with just a different base URL and model name — evaluate whether to create a separate provider or parameterize the existing one
- User directive: "same pattern as Deepseek" — follow Phase 18 integration approach exactly

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 25-kimi-model-support*
*Context gathered: 2026-04-02*
