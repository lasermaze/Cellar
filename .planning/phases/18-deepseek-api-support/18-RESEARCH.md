# Phase 18: Deepseek API Support - Research

**Researched:** 2026-03-30
**Domain:** AI provider abstraction, OpenAI-compatible tool-use API, Swift provider protocol
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Create an AIProviderProtocol with Anthropic + Deepseek implementations
- AgentLoop becomes provider-agnostic — takes a provider instance, not an API key
- Deepseek uses OpenAI-compatible tool-use format (function_call), which differs from Anthropic's tool_use blocks
- Provider protocol handles: request building, response parsing, stop_reason translation, tool-use format conversion
- Only refactor what's necessary to make the protocol work — don't restructure existing OpenAI simple-API path
- `AI_PROVIDER` env var or config.json field selects the active provider (values: `claude`, `deepseek`)
- `DEEPSEEK_API_KEY` env var or ~/.cellar/.env for the API key
- Web settings page gets a provider dropdown and Deepseek API key field
- Change takes effect next launch — no hot-switching mid-session
- Auto-detection fallback: if only one provider's key is present, use that provider
- Default Deepseek model: `deepseek-chat` (deepseek-reasoner does NOT support function calling — see critical finding)
- Per-provider pricing map replaces hardcoded Sonnet pricing in AgentLoop
- Map: model string -> (inputPricePerMillion, outputPricePerMillion)
- Default budget stays $15
- Same system prompt for both providers with minor tweaks (remove Anthropic/Claude self-references)
- Don't restructure existing OpenAI simple-API path
- Touch list: AIProvider enum, provider protocol + implementations, AIModels (OpenAI-format tool types), AIService (provider routing), Settings (dropdown + key field), pricing map

### Claude's Discretion
- Provider protocol exact interface design
- How to handle Deepseek-specific quirks (if any) in tool-use responses
- Whether to split provider implementations into separate files or keep in one
- Test strategy for provider switching

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

## Summary

Phase 18 adds Deepseek as a second AI provider for the full agent loop (tool-use), recipe generation, and log interpretation. The core work is extracting Anthropic-specific HTTP call code from `AgentLoop.swift` into a protocol, then implementing a parallel Deepseek implementation using the OpenAI-compatible chat completions API.

**Critical finding:** `deepseek-reasoner` does NOT support function calling. The agent loop requires tool use, so the correct default model is `deepseek-chat` (DeepSeek-V3.2 non-thinking mode). The CONTEXT.md listed `deepseek-reasoner` as the default but this is wrong — the planner must use `deepseek-chat` for the agent loop.

Deepseek's tool-use format uses OpenAI's `tool_calls` / `finish_reason: "tool_calls"` conventions instead of Anthropic's `tool_use` blocks / `stop_reason: "tool_use"`. The provider protocol must translate between these on both the request side (tool definitions) and response side (parsing tool calls and constructing tool results). The rest of the loop logic (iterations, budget tracking, retries, canStop) stays unchanged.

**Primary recommendation:** Implement `AgentLoopProvider` protocol in `AgentLoop.swift`, add `AnthropicAgentProvider` (extracts existing code) and `DeepseekAgentProvider` (new OpenAI-format implementation), extend `AIProvider` enum with `.deepseek`, add `AI_PROVIDER` config routing in `AIService`, extend `SettingsController` for provider dropdown + Deepseek key, and add per-provider pricing map.

## Standard Stack

### Core
| Component | Version/Location | Purpose | Why Standard |
|-----------|-----------------|---------|--------------|
| URLSession + DispatchSemaphore | Already in codebase | Synchronous HTTP bridge | Established pattern in both AIService and AgentLoop |
| Codable (JSONEncoder/Decoder) | Swift stdlib | Request/response serialization | Already used for all API types |
| `deepseek-chat` model | Current | Agent loop tool-use | Only Deepseek model supporting function calling |
| `https://api.deepseek.com/v1` | Deepseek docs | Base URL (OpenAI-compatible path) | Standard endpoint per official docs |

### Supporting
| Component | Version/Location | Purpose | When to Use |
|-----------|-----------------|---------|-------------|
| `deepseek-chat` for simple API | Current | Recipe generation, log diagnosis | Matches existing OpenAI simple-API path pattern |
| Per-provider pricing map | New dict in AgentLoop | Token cost calculation | Replaces hardcoded Sonnet constants |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Protocol + implementations | Strategy pattern via closure | Protocol gives type safety, testability; closures would be simpler but harder to extend |
| deepseek-chat for agent loop | deepseek-reasoner | deepseek-reasoner does NOT support function calling — not viable |

## Architecture Patterns

### Recommended Structure

**New file: `Sources/cellar/Core/AgentLoopProvider.swift`** (or add to AgentLoop.swift)
```
AgentLoopProvider protocol
  AnthropicAgentProvider (extracted from AgentLoop)
  DeepseekAgentProvider (new)
```

**Modified files:**
```
AIModels.swift         — add OpenAI-format tool-use request/response types
AIService.swift        — extend detectProvider(), update runAgentLoop(), add .deepseek case
AgentLoop.swift        — take provider instance instead of apiKey; extract callAnthropic* → AnthropicAgentProvider
CellarConfig.swift     — add aiProvider: String? field
SettingsController.swift — provider dropdown + Deepseek key field
settings.leaf          — provider dropdown + Deepseek key input
```

### Pattern 1: AgentLoopProvider Protocol

**What:** Protocol encapsulating all provider-specific API communication for the agent loop
**When to use:** Any time AgentLoop needs to call the AI API

```swift
// Conceptual interface — exact design is Claude's discretion
protocol AgentLoopProvider {
    func callWithRetry(
        messages: [some Encodable],
        maxTokens: Int
    ) throws -> AgentLoopProviderResponse

    var pricingMap: [String: (input: Double, output: Double)] { get }
    var modelName: String { get }
}

struct AgentLoopProviderResponse {
    enum StopReason { case endTurn, toolUse, maxTokens, other(String) }
    let textBlocks: [String]
    let toolCalls: [(id: String, name: String, input: JSONValue)]
    let stopReason: StopReason
    let inputTokens: Int
    let outputTokens: Int
}
```

The provider normalizes Anthropic's `stop_reason: "end_turn"/"tool_use"/"max_tokens"` and Deepseek's `finish_reason: "stop"/"tool_calls"/"length"` into the same `StopReason` enum. AgentLoop only sees `AgentLoopProviderResponse` — no provider-specific types.

### Pattern 2: Deepseek Request/Response Types (OpenAI-compatible format)

Deepseek uses OpenAI's chat completions format. New types needed in AIModels.swift:

**Request:**
```swift
struct OpenAIToolRequest: Encodable {
    let model: String
    let maxTokens: Int           // "max_tokens"
    let messages: [Message]
    let tools: [OpenAIToolDef]?  // OpenAI tool definition format

    struct Message: Encodable {
        let role: String          // "system", "user", "assistant", "tool"
        let content: String?
        let toolCalls: [ToolCall]?   // "tool_calls" — present on assistant messages
        let toolCallId: String?      // "tool_call_id" — present on tool result messages
    }
}

struct OpenAIToolDef: Encodable {
    // {"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}
    let type: String              // always "function"
    let function: FunctionDef
    struct FunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: JSONValue  // same JSONValue as Anthropic input_schema
    }
}
```

**Response:**
```swift
struct OpenAIToolResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
        let finishReason: String  // "finish_reason": "stop" | "tool_calls" | "length"
    }
    struct Message: Decodable {
        let role: String
        let content: String?
        let toolCalls: [ToolCall]?  // present when finish_reason == "tool_calls"
    }
    struct ToolCall: Decodable {
        let id: String
        let type: String           // always "function"
        let function: FunctionCall
        struct FunctionCall: Decodable {
            let name: String
            let arguments: String  // JSON string — needs JSONDecoder to parse into JSONValue
        }
    }
    struct Usage: Decodable {
        let promptTokens: Int      // "prompt_tokens"
        let completionTokens: Int  // "completion_tokens"
    }
}
```

### Pattern 3: Message Conversion (Anthropic → OpenAI format)

The provider must convert between formats for the conversation history.

**Anthropic assistant message with tool_use blocks:**
```json
{"role": "assistant", "content": [
  {"type": "text", "text": "..."},
  {"type": "tool_use", "id": "tu_1", "name": "inspect_game", "input": {...}}
]}
```

**OpenAI equivalent:**
```json
{"role": "assistant", "content": "...",
 "tool_calls": [{"id": "tu_1", "type": "function", "function": {"name": "inspect_game", "arguments": "{...}"}}]}
```

**Anthropic tool result:**
```json
{"role": "user", "content": [
  {"type": "tool_result", "tool_use_id": "tu_1", "content": "result text"}
]}
```

**OpenAI equivalent:**
```json
{"role": "tool", "tool_call_id": "tu_1", "content": "result text"}
```

The `DeepseekAgentProvider` must maintain its own OpenAI-format message array and translate each AgentLoop append operation into the correct format. **Key insight:** AgentLoop currently builds `[AnthropicToolRequest.Message]` directly — the provider pattern needs to abstract message storage too, OR AgentLoop passes abstract message types and the provider converts.

**Simplest approach (recommended):** Provider owns the message array entirely. AgentLoop calls `provider.appendUserMessage(text)`, `provider.appendAssistantResponse(response)`, `provider.appendToolResults([(id, result)])` and never holds provider-specific message types. This keeps AgentLoop clean.

### Pattern 4: Tool Definition Conversion

`ToolDefinition` (Anthropic format) → `OpenAIToolDef` (OpenAI format):

```
Anthropic: {name, description, input_schema: JSONValue}
OpenAI:    {type: "function", function: {name, description, parameters: JSONValue}}
```

The `input_schema` JSONValue and `parameters` JSONValue have the same content — just different nesting. DeepseekAgentProvider wraps each `ToolDefinition` into `OpenAIToolDef` on init.

### Pattern 5: Provider Detection with AI_PROVIDER Config

Extend `AIService.detectProvider()`:

```swift
// Priority: AI_PROVIDER env/config → key-based auto-detection → default
// 1. Check AI_PROVIDER env var (or config.json aiProvider field)
// 2. If "deepseek" → use DEEPSEEK_API_KEY
// 3. If "claude" → use ANTHROPIC_API_KEY
// 4. Auto-detect: if only one key present, use that
// 5. If both keys present and no AI_PROVIDER set → use claude (existing behavior)
```

### Pattern 6: Per-Provider Pricing Map

Replace AgentLoop's hardcoded pricing constants with a lookup:

```swift
// In AgentLoop or a new PricingRegistry.swift
static let modelPricing: [String: (input: Double, output: Double)] = [
    "claude-sonnet-4-6":  (input: 3.0 / 1_000_000, output: 15.0 / 1_000_000),
    "claude-opus-4-6":    (input: 15.0 / 1_000_000, output: 75.0 / 1_000_000),
    "deepseek-chat":      (input: 0.28 / 1_000_000, output: 0.42 / 1_000_000),
    "deepseek-reasoner":  (input: 0.28 / 1_000_000, output: 0.42 / 1_000_000),
]
// Fallback: 0.0 / 0.0 if model not in map (no crash, no cost tracking)
```

### Anti-Patterns to Avoid

- **Using deepseek-reasoner for agent loop:** It does NOT support function calling. Will get API errors. Use `deepseek-chat` only.
- **Including `reasoning_content` in multi-turn messages:** Deepseek returns `reasoning_content` in responses; if this is forwarded back in the next request, the API returns HTTP 400. Strip it before appending assistant messages.
- **Assuming finish_reason maps 1:1 to stop_reason:** Deepseek uses `"stop"` where Anthropic uses `"end_turn"`, and `"tool_calls"` where Anthropic uses `"tool_use"`, and `"length"` where Anthropic uses `"max_tokens"`. The provider must translate all three.
- **Storing tool arguments as JSONValue directly:** Deepseek returns tool arguments as a JSON `string` in `arguments` field — must `JSONDecoder().decode(JSONValue.self, from: argumentsString.data)` to parse.
- **Rewriting the existing OpenAI simple-API path:** `callOpenAI()` in AIService is for recipe/diagnosis calls, not agent loop. Keep it untouched.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP to Deepseek | Custom URLSession wrapper | Extend existing `callAPI()` pattern from AgentLoop | Already handles DispatchSemaphore, ResultBox, error handling |
| JSON encoding of tool defs | Custom serializer | Codable + JSONEncoder | Already how Anthropic tools are serialized |
| Message history management | Custom diff/merge | Provider-owned array with typed appends | Prevents format leakage between providers |

**Key insight:** The entire HTTP + retry infrastructure is already in place — this phase is purely about format translation and routing.

## Common Pitfalls

### Pitfall 1: deepseek-reasoner Has No Function Calling
**What goes wrong:** Agent loop makes tool calls → Deepseek returns HTTP 400 or ignores tools
**Why it happens:** deepseek-reasoner explicitly does NOT support function calling per official docs
**How to avoid:** Always use `deepseek-chat` for the agent loop. Update CONTEXT.md assumption.
**Warning signs:** 400 errors from Deepseek API when tools array is present with reasoner model

### Pitfall 2: reasoning_content in Multi-Turn Requests
**What goes wrong:** API returns HTTP 400 on second+ request
**Why it happens:** deepseek-chat in some configurations returns a `reasoning_content` field; if included in subsequent messages, the API rejects it
**How to avoid:** When building assistant messages from Deepseek responses, only forward `content` and `tool_calls` — never `reasoning_content`
**Warning signs:** HTTP 400 on iteration 2+ but not iteration 1

### Pitfall 3: Tool Arguments Are a String, Not an Object
**What goes wrong:** Trying to cast `arguments` field directly to `JSONValue` → decode fails
**Why it happens:** Deepseek (like OpenAI) returns `"arguments": "{\"key\": \"value\"}"` — a JSON-encoded string, not an inline object
**How to avoid:** Parse `arguments` as `String`, then decode `JSONValue` from `Data(arguments.utf8)`
**Warning signs:** JSONDecoder error on tool call arguments field

### Pitfall 4: Anthropic Message Type Used in Deepseek Provider
**What goes wrong:** Compiler error or subtle data corruption from mixing `AnthropicToolRequest.Message` with Deepseek calls
**Why it happens:** AgentLoop currently builds typed Anthropic message arrays
**How to avoid:** Provider owns its message array entirely — AgentLoop never holds `AnthropicToolRequest.Message` after refactor; it calls provider methods
**Warning signs:** Compiler errors mixing types; or runtime encoding wrong format

### Pitfall 5: AIService.detectProvider() Still Returns .anthropic for Agent Loop
**What goes wrong:** Even with `AI_PROVIDER=deepseek`, agent loop still uses Claude
**Why it happens:** `runAgentLoop()` currently has `guard case .anthropic(let apiKey) = provider` and returns `.unavailable` for anything else
**How to avoid:** Update `runAgentLoop()` to accept `.deepseek` case and route to DeepseekAgentProvider
**Warning signs:** Agent loop returns `.unavailable` even with Deepseek key set

### Pitfall 6: Settings Page Doesn't Persist AI_PROVIDER
**What goes wrong:** Provider dropdown selection is lost on refresh
**Why it happens:** `writeEnvFile` must be extended to also write `AI_PROVIDER` key
**How to avoid:** Add `AI_PROVIDER` to the env file write path alongside API keys
**Warning signs:** Dropdown resets to default on page reload

## Code Examples

Verified patterns from codebase and official sources:

### Deepseek Authentication Header
```swift
// Source: https://api-docs.deepseek.com/
urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
// Base URL: https://api.deepseek.com/v1/chat/completions
```

### finish_reason → StopReason Translation
```swift
// Source: https://api-docs.deepseek.com/api/create-chat-completion
// Deepseek finish_reason values: "stop", "length", "content_filter", "tool_calls", "insufficient_system_resource"
func translateStopReason(_ finishReason: String) -> AgentLoopProviderResponse.StopReason {
    switch finishReason {
    case "stop":       return .endTurn
    case "tool_calls": return .toolUse
    case "length":     return .maxTokens
    default:           return .other(finishReason)
    }
}
```

### Tool Arguments Parsing
```swift
// Deepseek returns arguments as a JSON string, not an inline object
// Source: https://api-docs.deepseek.com/api/create-chat-completion
let argumentsString = toolCall.function.arguments
guard let data = argumentsString.data(using: .utf8),
      let input = try? JSONDecoder().decode(JSONValue.self, from: data) else {
    // Handle malformed arguments
    continue
}
```

### Existing ToolDefinition → OpenAI Tool Definition Conversion
```swift
// ToolDefinition has: name, description, inputSchema (JSONValue)
// OpenAI wants: {type: "function", function: {name, description, parameters: JSONValue}}
struct OpenAIToolDef: Encodable {
    let type = "function"
    let function: FunctionDef
    struct FunctionDef: Encodable {
        let name: String
        let description: String
        let parameters: JSONValue  // same content as inputSchema
    }
}
// Conversion: toolDef.inputSchema maps directly to parameters
```

### CellarConfig Extension for AI_PROVIDER
```swift
// Extend existing CellarConfig struct
struct CellarConfig: Codable {
    var budgetCeiling: Double
    var aiProvider: String?  // "claude" | "deepseek" | nil (auto-detect)

    enum CodingKeys: String, CodingKey {
        case budgetCeiling = "budget"
        case aiProvider = "ai_provider"
    }
}
```

### Provider Error Message (Success Criterion 3)
```swift
// Named provider in error messages — not generic "API key missing"
case .deepseek:
    return .unavailable  // show: "Deepseek API key not configured. Set DEEPSEEK_API_KEY."
case .anthropic:
    return .unavailable  // show: "Anthropic API key not configured. Set ANTHROPIC_API_KEY."
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|-----------------|--------------|--------|
| deepseek-reasoner for agent loop (CONTEXT.md assumption) | deepseek-chat only | Verified 2026-03-30 | deepseek-reasoner has no function calling — must use deepseek-chat |
| Hardcoded Sonnet pricing in AgentLoop lines 148-154 | Per-provider pricing map | Phase 18 | Accurate cost tracking for Deepseek (~14x cheaper than Claude) |
| AgentLoop tied to Anthropic API directly | Provider protocol | Phase 18 | Enables future providers without touching loop logic |

**Deprecated/outdated:**
- CONTEXT.md model choice `deepseek-reasoner`: Cannot be used for tool-use agent loop. Replace with `deepseek-chat`.

## Open Questions

1. **deepseek-reasoner for simple API (non-agent) calls**
   - What we know: `deepseek-reasoner` doesn't support function calling, but simple API calls (recipe generation, diagnosis) don't use tools
   - What's unclear: Is `deepseek-reasoner` a better default for non-agent calls than `deepseek-chat`?
   - Recommendation: Use `deepseek-chat` for everything — simpler, consistent, avoids multi-model management. The planner can split if desired.

2. **Deepseek's `reasoning_content` field**
   - What we know: `deepseek-chat` may return `reasoning_content` in some modes; including it in subsequent requests causes HTTP 400
   - What's unclear: Does `deepseek-chat` (non-thinking mode) actually return `reasoning_content`?
   - Recommendation: Defensively strip `reasoning_content` when building assistant messages from Deepseek responses regardless.

3. **Provider protocol scope: agent loop only, or also simple API?**
   - What we know: Simple API (recipe gen, diagnosis) already has `makeAPICall(provider:)` with a switch statement
   - What's unclear: Should simple API also go through the provider protocol, or keep the existing switch?
   - Recommendation: Keep simple API separate (existing `makeAPICall` switch pattern). Only the agent loop gets the new protocol.

## Validation Architecture

> `workflow.nyquist_validation` is not set in .planning/config.json — skip this section.

## Sources

### Primary (HIGH confidence)
- https://api-docs.deepseek.com/api/create-chat-completion — finish_reason values, tool_calls format, message roles, authentication
- https://api-docs.deepseek.com/guides/reasoning_model — deepseek-reasoner does NOT support function calling (explicit)
- https://api-docs.deepseek.com/quick_start/pricing — model pricing: $0.28/$0.42 per MTok for both models
- https://api-docs.deepseek.com/ — base URL (`https://api.deepseek.com/v1`), Bearer auth header
- Codebase: `AgentLoop.swift` — existing Anthropic tool-use loop, pricing constants at lines 148-154
- Codebase: `AIModels.swift` — existing ToolDefinition, AnthropicToolRequest/Response types
- Codebase: `AIService.swift` — existing detectProvider(), runAgentLoop(), callAnthropic/callOpenAI patterns
- Codebase: `SettingsController.swift` — existing API key form pattern to extend
- Codebase: `CellarConfig.swift` — existing config struct to extend

### Secondary (MEDIUM confidence)
- https://api-docs.deepseek.com/guides/function_calling — function calling format (Python examples, JSON structure inferred)

### Tertiary (LOW confidence)
- CONTEXT.md assumption about `deepseek-reasoner` being the default — **contradicted** by official docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — official Deepseek docs confirm OpenAI-compatible format, deepseek-chat for tool use
- Architecture: HIGH — patterns directly derived from existing codebase structure
- Pitfalls: HIGH — deepseek-reasoner limitation and reasoning_content issue are from official docs

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (Deepseek pricing/model features change frequently — verify before planning if delayed)
