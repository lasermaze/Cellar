# Phase 25: Kimi Model Support - Research

**Researched:** 2026-04-02
**Domain:** AI provider integration (OpenAI-compatible HTTP API)
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Kimi uses an OpenAI-compatible API format — same as Deepseek
- Create a KimiAgentProvider implementing AgentLoopProvider protocol, modeled on DeepseekAgentProvider
- Kimi API endpoint: https://api.moonshot.cn/v1/chat/completions
- Default model: moonshot-v1-128k (128K context, strong reasoning)
- Add Kimi pricing to the modelPricing map in AgentLoopProvider.swift
- Add `.kimi(apiKey: String)` case to AIProvider enum in AIModels.swift
- Env var: `KIMI_API_KEY` (consistent with existing `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY` pattern)
- AI_PROVIDER config value: `"kimi"` or `"moonshot"`
- Auto-detection cascade: Anthropic → Deepseek → Kimi → OpenAI → unavailable
- AIService.detectProvider() extended with Kimi detection
- AIService.runAgentLoop() routes `.kimi` to KimiAgentProvider
- Extend settings dropdown with Kimi option
- Add Kimi API key field to settings form (same masked-input pattern as Deepseek)
- settings.leaf template extended
- Same system prompt as other providers — no Kimi-specific modifications
- Scope: Kimi only — follow Phase 18 pattern exactly
- Touch list: AIModels.swift, AIService.swift, AgentLoopProvider.swift, SettingsController.swift, settings.leaf, CellarConfig.swift (if needed)

### Claude's Discretion
- Whether KimiAgentProvider is a new struct or a parameterized reuse of DeepseekAgentProvider (both are OpenAI-compatible)
- Exact Kimi model pricing (verify from current API docs)
- Whether to add moonshot-v1-8k and moonshot-v1-32k as alternative model options
- Any Kimi-specific quirks in tool-use response format

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| Kimi API integration | Use OpenAI-compatible API at api.moonshot.cn/v1 with Bearer auth | Confirmed: same OpenAI format as Deepseek — reuse OpenAIToolRequest/OpenAIToolResponse types |
| AIProvider enum extension | Add `.kimi(apiKey: String)` case to AIProvider in AIModels.swift | Pattern clear from existing `.deepseek(apiKey:)` case |
| AIService provider detection | Extend detectProvider() and makeAPICall() with kimi case | 4 switch sites in AIService.swift need updating |
| AgentLoopProvider Kimi implementation | KimiAgentProvider struct implementing AgentLoopProvider | Can be separate struct or parameterized DeepseekAgentProvider — see Architecture section |
| .env/config support | KIMI_API_KEY env var, `"kimi"`/`"moonshot"` config value | Follows existing loadEnvironment() + CellarConfig.aiProvider pattern |
</phase_requirements>

## Summary

Kimi (Moonshot AI) uses an OpenAI-compatible API at `https://api.moonshot.cn/v1/chat/completions` with Bearer token authentication. The API format is functionally identical to Deepseek for the purposes of this integration: same request structure (`OpenAIToolRequest`), same response structure (`OpenAIToolResponse`), same finish_reason values (`"tool_calls"`, `"stop"`, `"length"`), and same tool-result submission pattern (`role: "tool"` messages). The only differences are the base URL and the API key header value.

This means Phase 25 is almost entirely mechanical: add one enum case, extend four switch statements, add one new struct (or parameterize the existing DeepseekAgentProvider), update three settings files, and add pricing entries. The DeepseekAgentProvider is a near-perfect template — the KimiAgentProvider differs only in the URL string and the default model name.

The key discretion question is whether to create a separate `KimiAgentProvider` struct or refactor `DeepseekAgentProvider` into a generic `OpenAICompatibleAgentProvider` parameterized by URL and model. The latter is cleaner and avoids code duplication, but requires renaming/restructuring. Either approach is valid; the parameterized approach is recommended since Kimi and Deepseek share 100% of logic with a single URL difference.

**Primary recommendation:** Implement KimiAgentProvider as a thin wrapper or second instance of a refactored `OpenAICompatibleAgentProvider`, using `api.moonshot.cn` as the base URL and `moonshot-v1-128k` as the default model. This avoids copy-paste duplication while remaining fully aligned with Phase 18 patterns.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URLSession async/await | System | HTTP to Kimi API | Already used by agentCallAPI() — no new dependency |
| OpenAIToolRequest/Response | Internal | Wire format for Kimi calls | Kimi uses identical OpenAI-compatible format |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| JSONEncoder/JSONDecoder | System | Serialize requests/deserialize responses | Same pattern as all other providers |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate KimiAgentProvider struct | Parameterized OpenAICompatibleAgentProvider | Parameterized avoids code duplication; separate struct is simpler/faster to implement |
| moonshot-v1-128k default | kimi-k2.5 or kimi-latest | v1-128k is stable, widely documented, clearly priced; kimi-k2 models are newer but less tested for tool use |

**Installation:** No new packages required.

## Architecture Patterns

### Recommended Project Structure

No new files are required. All changes are additions to existing files:

```
Sources/cellar/
├── Models/AIModels.swift          — add .kimi(apiKey:) enum case
├── Core/AIService.swift           — extend detectProvider(), makeAPICall(), runAgentLoop()
├── Core/AgentLoopProvider.swift   — add modelPricing entries + KimiAgentProvider (or refactor)
├── Web/Controllers/SettingsController.swift  — add kimiKey field handling
└── Resources/Views/settings.leaf  — add Kimi provider option + key field
```

### Pattern 1: OpenAI-Compatible Provider Struct

**What:** KimiAgentProvider (or refactored OpenAICompatibleAgentProvider) is structurally identical to DeepseekAgentProvider with different URL and model defaults.

**When to use:** Any provider whose wire format is OpenAI-compatible.

**Recommended approach — refactor DeepseekAgentProvider into parameterized struct:**

```swift
// Source: derived from existing DeepseekAgentProvider in AgentLoopProvider.swift
struct OpenAICompatibleAgentProvider: AgentLoopProvider {
    let apiKey: String
    let modelName: String
    let baseURL: String  // e.g. "https://api.deepseek.com/v1" or "https://api.moonshot.cn/v1"
    let maxOutputTokensLimit: Int = 8192
    private let openAITools: [OpenAIToolDef]
    private var messages: [OpenAIToolRequest.Message] = []

    init(apiKey: String, model: String, baseURL: String, tools: [ToolDefinition], systemPrompt: String) {
        self.apiKey = apiKey
        self.modelName = model
        self.baseURL = baseURL
        // ... identical to DeepseekAgentProvider init ...
    }
    // All other methods identical to DeepseekAgentProvider
    // Only callDeepseek() changes — uses self.baseURL instead of hardcoded string
}
```

**Alternative — separate KimiAgentProvider (simpler, matches Phase 18 exactly):**

```swift
// Source: modeled on DeepseekAgentProvider in AgentLoopProvider.swift
struct KimiAgentProvider: AgentLoopProvider {
    let apiKey: String
    let modelName: String
    let maxOutputTokensLimit: Int = 8192
    private let openAITools: [OpenAIToolDef]
    private var messages: [OpenAIToolRequest.Message] = []

    init(apiKey: String, model: String = "moonshot-v1-128k", tools: [ToolDefinition], systemPrompt: String) {
        // identical to DeepseekAgentProvider.init except model default
    }

    private func callKimi(maxTokens: Int) async throws -> OpenAIToolResponse {
        var urlRequest = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/chat/completions")!)
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        // ... rest identical to callDeepseek() ...
    }
}
```

### Pattern 2: AIProvider enum extension

```swift
// Source: AIModels.swift:5-10
enum AIProvider {
    case anthropic(apiKey: String)
    case openai(apiKey: String)
    case deepseek(apiKey: String)
    case kimi(apiKey: String)      // NEW
    case unavailable
}
```

### Pattern 3: detectProvider() extension

```swift
// Source: AIService.swift:13-29
switch configProvider?.lowercased() {
case "deepseek":
    if let key = env["DEEPSEEK_API_KEY"], !key.isEmpty { return .deepseek(apiKey: key) }
    return .unavailable
case "kimi", "moonshot":                                    // NEW
    if let key = env["KIMI_API_KEY"], !key.isEmpty { return .kimi(apiKey: key) }
    return .unavailable
// ...
default:
    let hasAnthropic = env["ANTHROPIC_API_KEY"].map { !$0.isEmpty } ?? false
    let hasDeepseek  = env["DEEPSEEK_API_KEY"].map  { !$0.isEmpty } ?? false
    let hasKimi      = env["KIMI_API_KEY"].map       { !$0.isEmpty } ?? false   // NEW
    if hasAnthropic { return .anthropic(apiKey: env["ANTHROPIC_API_KEY"]!) }
    if hasDeepseek  { return .deepseek(apiKey: env["DEEPSEEK_API_KEY"]!) }
    if hasKimi      { return .kimi(apiKey: env["KIMI_API_KEY"]!) }             // NEW
    if let key = env["OPENAI_API_KEY"], !key.isEmpty { return .openai(apiKey: key) }
    return .unavailable
}
```

### Pattern 4: modelPricing entries

```swift
// Source: AgentLoopProvider.swift:42-47 + verified pricing from platform.moonshot.ai/docs/pricing/chat
let modelPricing: [String: (input: Double, output: Double)] = [
    "claude-sonnet-4-6":    (input: 3.0 / 1_000_000,  output: 15.0 / 1_000_000),
    "claude-opus-4-6":      (input: 15.0 / 1_000_000, output: 75.0 / 1_000_000),
    "deepseek-chat":        (input: 0.27 / 1_000_000, output: 1.10 / 1_000_000),
    "deepseek-reasoner":    (input: 0.55 / 1_000_000, output: 2.19 / 1_000_000),
    // Kimi moonshot-v1 series (per platform.moonshot.ai docs)
    "moonshot-v1-8k":       (input: 0.20 / 1_000_000, output: 2.00 / 1_000_000),  // NEW
    "moonshot-v1-32k":      (input: 1.00 / 1_000_000, output: 3.00 / 1_000_000),  // NEW
    "moonshot-v1-128k":     (input: 2.00 / 1_000_000, output: 5.00 / 1_000_000),  // NEW
]
```

### Pattern 5: settings.leaf extension (follows Deepseek pattern)

```html
<!-- Add to provider select dropdown -->
<option value="kimi" #if(aiProvider == "kimi"):selected#endif>Kimi (Moonshot AI)</option>

<!-- Add new key field after deepseekKey block -->
<div class="form-group">
  <label for="kimiKey">
    Kimi API Key
    #if(hasKimiKey):
      <span style="color: var(--success);"> (configured)</span>
    #endif
  </label>
  <input
    type="password"
    id="kimiKey"
    name="kimiKey"
    placeholder="#if(hasKimiKey): #(kimiKey) #else: sk-... #endif"
    autocomplete="off"
  >
</div>
```

### Pattern 6: SettingsController SettingsContext extension

```swift
// SettingsController.swift — SettingsContext
struct SettingsContext: Content {
    let title: String
    let anthropicKey: String
    let openaiKey: String
    let deepseekKey: String
    let kimiKey: String           // NEW
    let hasAnthropicKey: Bool
    let hasOpenaiKey: Bool
    let hasDeepseekKey: Bool
    let hasKimiKey: Bool          // NEW
    let aiProvider: String
    // ...
}

// KeysInput
struct KeysInput: Content {
    let anthropicKey: String?
    let openaiKey: String?
    let deepseekKey: String?
    let kimiKey: String?          // NEW
    let aiProvider: String?
}
```

### Pattern 7: runAgentLoop() provider routing

```swift
// AIService.swift:821-828
case .kimi(let apiKey):
    agentProvider = KimiAgentProvider(    // (or OpenAICompatibleAgentProvider)
        apiKey: apiKey,
        tools: AgentTools.toolDefinitions,
        systemPrompt: systemPrompt
    )
```

### Anti-Patterns to Avoid

- **Do not use kimi-k2-thinking or kimi-k2-thinking-turbo as default:** These are reasoning models — unclear whether they support function calling in the same way. Stick to moonshot-v1-128k (confirmed tool use support).
- **Do not use `tool_choice: "required"`:** Kimi does not support this parameter (confirmed in official migration docs). The existing codebase does not use `tool_choice: required`, so no change needed.
- **Do not use the deprecated `functions` parameter:** Kimi only supports `tools`, not the legacy `functions` API. Existing code already uses `tools` via `OpenAIToolDef`.
- **Do not set temperature > 1.0:** Kimi's temperature range is `[0, 1]` vs OpenAI's `[0, 2]`. Cellar does not set temperature explicitly in agent loop calls, so no impact — but don't add temperature params without capping at 1.0.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP client | Custom URLSession wrapper | Existing `agentCallAPI()` | Already handles errors, used by both Anthropic and Deepseek providers |
| Tool format conversion | Custom serializer | Existing `OpenAIToolDef` / `OpenAIToolRequest` | Already implements OpenAI tool format used by Kimi |
| Response parsing | Custom parser | Existing `OpenAIToolResponse` + `translateDeepseekResponse()` | Kimi uses identical response format — method can be copied verbatim |
| Retry logic | Custom backoff | Copy existing `callWithRetry()` from DeepseekAgentProvider | Same 3-attempt exponential backoff pattern |

**Key insight:** Kimi's 100% OpenAI format compatibility means zero new data model work. All existing types (`OpenAIToolRequest`, `OpenAIToolResponse`, `OpenAIToolDef`) work as-is.

## Common Pitfalls

### Pitfall 1: Domain Ambiguity (api.moonshot.cn vs api.moonshot.ai)
**What goes wrong:** The official English migration guide says `api.moonshot.ai/v1`. The official Chinese API reference says `api.moonshot.cn/v1`. Both appear to be valid but may differ by region.
**Why it happens:** Moonshot AI operates separate regional endpoints — `.cn` is China-region, `.ai` is global.
**How to avoid:** The CONTEXT.md decision specifies `https://api.moonshot.cn/v1/chat/completions`. Use the `.cn` endpoint as directed. If a user's key was issued from the `.ai` platform, they may need the `.ai` endpoint — but this is an edge case outside current scope.
**Warning signs:** HTTP 401 with a valid key could indicate endpoint mismatch.

### Pitfall 2: Error messaging gaps
**What goes wrong:** The `diagnose()`, `generateRecipe()`, `generateVariants()`, and `runAgentLoop()` methods in AIService.swift each have a specific `.unavailable` handler that produces a named error message for Deepseek but falls back to generic for others. Each of these 4 sites needs a Kimi case added.
**Why it happens:** The pattern is manually repeated at each call site — not centralized.
**How to avoid:** When updating `detectProvider()`, also update all 4 `.unavailable` error message blocks. Search for `"Deepseek API key not configured"` — each occurrence needs a parallel `"kimi"` case.
**Warning signs:** User sets `AI_PROVIDER=kimi` but sees "Anthropic API key not configured" error.

### Pitfall 3: makeAPICall() non-agent path
**What goes wrong:** `AIService.makeAPICall()` (used for diagnose/recipe/variants) needs a `case .kimi` branch that calls a `callKimi()` function, just as Deepseek has `callDeepseek()`. Without it, `.kimi` falls through to `case .unavailable` and all non-agent-loop AI features fail.
**Why it happens:** There are two separate code paths — `runAgentLoop()` (uses `KimiAgentProvider`) and simple `makeAPICall()` (uses direct HTTP calls without provider structs).
**How to avoid:** Add both `KimiAgentProvider` (for agent loop) AND a `callKimi()` function + `case .kimi` in `makeAPICall()` (for simple API calls).

### Pitfall 4: SettingsContext template mismatch
**What goes wrong:** Leaf templates crash if a context property referenced in the template is missing from the `SettingsContext` struct, or vice versa.
**Why it happens:** Leaf does runtime template rendering — compile-time safety doesn't apply.
**How to avoid:** Add `kimiKey` and `hasKimiKey` to `SettingsContext` and `KeysInput` simultaneously with the template changes. Update all call sites that construct `SettingsContext` (GET handler, POST /settings/sync handler).

### Pitfall 5: Auto-detect cascade order
**What goes wrong:** If a user has both a Deepseek key and a Kimi key, auto-detect must pick one predictably. The CONTEXT.md defines the order: Anthropic → Deepseek → Kimi → OpenAI.
**Why it happens:** Order of `if hasX { return .x }` in the `default:` branch of `detectProvider()` determines priority.
**How to avoid:** Insert Kimi check AFTER Deepseek but BEFORE OpenAI in the auto-detect cascade.

## Code Examples

Verified patterns from official sources and existing codebase:

### Kimi API Request (wire format — identical to Deepseek)
```swift
// Source: https://platform.moonshot.cn/docs/api/chat
// Source: existing AgentLoopProvider.swift DeepseekAgentProvider.callDeepseek()
var urlRequest = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/chat/completions")!)
urlRequest.httpMethod = "POST"
urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
urlRequest.httpBody = try JSONEncoder().encode(requestBody)  // OpenAIToolRequest
```

### Kimi finish_reason → StopReason mapping
```swift
// Source: https://platform.moonshot.cn/docs/guide/use-kimi-api-to-complete-tool-calls
// Verified: Kimi uses same finish_reason values as Deepseek/OpenAI
switch choice.finishReason {
case "stop":        stopReason = .endTurn
case "tool_calls":  stopReason = .toolUse
case "length":      stopReason = .maxTokens
default:            stopReason = .other(choice.finishReason)
}
// Note: translateDeepseekResponse() can be copied verbatim as translateKimiResponse()
```

### Simple (non-agent) Kimi call — callKimi()
```swift
// Source: modeled on AIService.callDeepseek()
private static func callKimi(apiKey: String, systemPrompt: String, userMessage: String) async throws -> String {
    let requestBody = OpenAIRequest(
        model: "moonshot-v1-128k",
        messages: [
            OpenAIRequest.Message(role: "system", content: systemPrompt),
            OpenAIRequest.Message(role: "user", content: userMessage)
        ],
        responseFormat: OpenAIRequest.ResponseFormat(type: "json_object")
    )
    var request = URLRequest(url: URL(string: "https://api.moonshot.cn/v1/chat/completions")!)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = try JSONEncoder().encode(requestBody)
    let responseData = try await callAPI(request: request)
    let response = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)
    guard let content = response.firstContent else {
        throw AIServiceError.decodingError("Kimi response had no content")
    }
    return content
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DispatchSemaphore + ResultBox HTTP | URLSession async/await | Phase 24 | agentCallAPI() already async — Kimi provider uses it natively |
| Deepseek-only alternative provider | Multi-provider (Deepseek + Kimi) | Phase 25 | Pattern already established in Phase 18 |

**Current model landscape (2026-04):**
- `moonshot-v1-128k` — stable, recommended, confirmed tool use, 128K context
- `moonshot-v1-8k` / `moonshot-v1-32k` — same family, smaller context windows, lower price
- `moonshot-v1-auto` — auto-selects tier by prompt length, same pricing tiers
- `kimi-k2.5` / `kimi-k2-thinking` — newer models, tool use support less confirmed for agent loop use
- Stick to `moonshot-v1-128k` as default per CONTEXT.md decision

## Open Questions

1. **Parameterized provider vs separate struct**
   - What we know: Kimi and Deepseek have 100% identical logic; only URL differs
   - What's unclear: Whether to refactor DeepseekAgentProvider into OpenAICompatibleAgentProvider now (cleaner) or defer (simpler change)
   - Recommendation: Implement as separate `KimiAgentProvider` struct that copies DeepseekAgentProvider. This is lower risk, directly follows Phase 18 pattern, and avoids touching working Deepseek code. Refactor can be deferred to a future cleanup phase.

2. **moonshot-v1-8k and moonshot-v1-32k as UI options**
   - What we know: They are valid models, priced lower, confirmed OpenAI-compatible
   - What's unclear: User preference — whether to expose them in settings or keep moonshot-v1-128k as the only option
   - Recommendation: Add pricing entries for all three in `modelPricing` map (zero cost, documents the values), but only expose `moonshot-v1-128k` as the default. Adding a model selector dropdown is out of scope for this phase.

3. **api.moonshot.cn vs api.moonshot.ai endpoint**
   - What we know: `.cn` is documented in the Chinese API reference; `.ai` is documented in the English migration guide
   - What's unclear: Which works better for non-Chinese users
   - Recommendation: Use `.cn` as specified in CONTEXT.md. Note in code comments that `.ai` is the global alternative.

## Validation Architecture

> `workflow.nyquist_validation` is not set in .planning/config.json — skipping this section.

(The config.json uses `"workflow": { "research": true, "plan_check": true, "verifier": true }` — no `nyquist_validation` key. Section omitted per instructions.)

## Sources

### Primary (HIGH confidence)
- `https://platform.moonshot.cn/docs/api/chat` — base URL `api.moonshot.cn/v1`, model list, OpenAI compatibility confirmed
- `https://platform.moonshot.ai/docs/guide/migrating-from-openai-to-kimi` — OpenAI compatibility details, known differences (temperature range, tool_choice limitations), tool use format
- `https://platform.moonshot.ai/docs/guide/use-kimi-api-to-complete-tool-calls` — finish_reason: tool_calls confirmed, tool result submission as role: "tool"
- Existing `AgentLoopProvider.swift` — DeepseekAgentProvider is the direct template for KimiAgentProvider

### Secondary (MEDIUM confidence)
- `https://platform.moonshot.ai/docs/pricing/chat` (via WebSearch) — pricing figures: moonshot-v1-8k $0.20/$2.00, moonshot-v1-32k $1.00/$3.00, moonshot-v1-128k $2.00/$5.00 per million tokens
- Multiple pricing aggregators (costgoat.com, pricepertoken.com) cross-verified the same pricing figures

### Tertiary (LOW confidence)
- None — all key claims verified with official sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all existing types confirmed compatible
- Architecture: HIGH — Phase 18 (Deepseek) is a perfect proven template; API format identity confirmed
- Pitfalls: HIGH — all identified from direct code inspection + official API compatibility notes
- Pricing: MEDIUM — figures from official pricing page via WebSearch; could change; document source in code comments

**Research date:** 2026-04-02
**Valid until:** 2026-07-02 (stable API; pricing may change sooner)
