# Phase 8: Loop Resilience - Research

**Researched:** 2026-03-28
**Domain:** Swift 6 agent loop — Anthropic API error handling, token usage tracking, budget management
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Budget behavior**
- Default ceiling: $5.00 per `cellar launch` session
- Graceful wind-down: at 80% inject warning to agent via system message; at 100% inject "wrap up now" prompt, let agent save progress and exit cleanly
- Budget is per launch command (each `cellar launch` gets its own budget)
- Configuration: `~/.cellar/config.json` with budget field, overridable by `CELLAR_BUDGET` env var
- Budget ceiling overrides max_tokens escalation: if doubling max_tokens would push past 80% budget, use continuation prompt instead of escalating

**Cost display**
- End-of-session summary: full transparency — "Session cost: $0.47 (12,340 input + 3,210 output tokens, 8 iterations)"
- Mid-session alerts only at 50% and 80% budget thresholds — not every iteration
- Model pricing: hardcoded constants for current model rates. The model is Opus (not Sonnet) — use Opus pricing ($5/$25 per 1M tokens — current rates). Update when rates change.

**Retry UX**
- API retries: brief status line — "API error, retrying (2/3)..." — not silent, not alarming
- max_tokens truncation retries: always visible — "max_tokens hit, retrying with 32768..."
- All retries failed: abort with clear message — "API unavailable after 3 attempts. Your game state is unchanged." — do not fall back to recipe-only

**Escalation limits**
- max_tokens doubling ceiling: 32k (decision from discussion, though actual Opus 4.6 max is 128k — 32k is the intended escalation cap per the context)
- If still truncated at 32k: fall back to continuation prompt ("Your response was truncated. Continue.")
- Escalation strategy: start at current 16384, double on truncation (16384 → 32768), cap at 32k

### Claude's Discretion

- Exact exponential backoff timing (1s → 2s → 4s or similar)
- How to distinguish 429 (rate limit) from other 4xx errors in retry logic
- Whether to reset max_tokens back to default after a successful non-truncated response
- Internal message format for budget warning injection

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| LOOP-01 | Agent recovers from max_tokens truncation — detects incomplete tool_use blocks and retries with higher max_tokens instead of sending broken continuation | Anthropic API: stop_reason="max_tokens" + content block detection in `AgentLoop.callAnthropic`; mutable `currentMaxTokens` in run loop |
| LOOP-02 | Agent retries on transient API errors — 3-attempt exponential backoff on 5xx and network errors; 4xx (except 429) are fatal | `AgentLoopError.httpError(statusCode:body:)` already in place; upgrade `callAPI` to classify errors; exponential sleep with `Thread.sleep` |
| LOOP-03 | Agent tracks token usage per session and prints total cost at end — configurable budget ceiling with 80% warning and halt at 100% | `AnthropicToolResponse` needs `usage` field added; `AgentLoopResult` needs token/cost fields; `CellarConfig` struct reads `~/.cellar/config.json` |
| LOOP-04 | Agent handles empty end_turn responses by sending continuation prompt instead of aborting | `AgentLoop.run()` case "end_turn": — check if `response.content` is empty before returning |
</phase_requirements>

---

## Summary

This phase is pure refactoring of `AgentLoop.swift` and `AIService.swift` — no new tools, no new capabilities. The four requirements are surgical additions to the existing run loop. The code structure is already well-organized: `AgentLoop.run()` has a clear `switch response.stopReason` block, `callAPI` has a clean error-classification point, and `AnthropicToolResponse` is a Decodable struct that just needs a `usage` field added.

The key challenge is state management: `AgentLoop` is a struct with `let` properties and a local-variable run loop. Token tracking requires accumulating `inputTokens` and `outputTokens` per iteration, which is straightforward with a `var` accumulator in `run()`. Budget tracking needs to be checked mid-loop, which means the budget config must be threaded into the loop. The cleanest path is a new `CellarConfig` struct that reads `~/.cellar/config.json` and a budget `var` in the loop.

The Anthropic API already returns `usage.input_tokens` and `usage.output_tokens` in every response — they just aren't decoded yet. Claude Opus 4.6 (the model used for the agent loop) is priced at $5.00/MTok input and $25.00/MTok output. The model ID used in `AgentLoop.init` is currently wrong (`claude-sonnet-4-20250514`) — this phase should correct it to `claude-opus-4-6`.

**Primary recommendation:** Add `usage` decoding to `AnthropicToolResponse`, upgrade `callAPI` error classification, and augment the `run()` loop with a `var currentMaxTokens`, token accumulators, and budget check — all within `AgentLoop.swift`. Add `CellarConfig` + `CellarPaths.configFile` as a thin new file.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation | macOS 14+ | `URLSession`, `Thread.sleep`, `JSONDecoder`, `ProcessInfo` | Already used everywhere in the project |
| Swift 6 | 6.0 | Language version — `@unchecked Sendable` for `ResultBox` | Project is already Swift 6 |

### No New Dependencies
This phase requires zero new Swift Package Manager dependencies. All functionality is built with Foundation primitives already in use.

---

## Architecture Patterns

### Recommended Change Map

```
Sources/cellar/
├── Core/AgentLoop.swift          # Main changes (LOOP-01, LOOP-02, LOOP-04)
│   ├── AgentLoopResult           # Add totalInputTokens, totalOutputTokens, estimatedCost
│   ├── AgentLoop.run()           # Add currentMaxTokens var, token accumulators,
│   │                             # budget checks, empty end_turn detection
│   └── AgentLoop.callAPI()       # Add error classification (5xx vs 4xx vs network)
├── Core/AIService.swift          # Minor changes
│   └── runAgentLoop()            # Thread CellarConfig budget, fix model ID,
│                                 # print cost summary after result
├── Models/AIModels.swift         # Add usage field to AnthropicToolResponse (LOOP-03)
│   └── AnthropicToolUsage        # New struct: inputTokens, outputTokens
└── Persistence/
    ├── CellarPaths.swift         # Add configFile path
    └── CellarConfig.swift        # NEW: read ~/.cellar/config.json, budget field
```

### Pattern 1: Usage Field Decoding (LOOP-03)

Add `AnthropicToolUsage` to `AIModels.swift` and add it to `AnthropicToolResponse`:

```swift
// Source: Anthropic API docs — usage field structure
struct AnthropicToolUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

struct AnthropicToolResponse: Decodable {
    let content: [ToolContentBlock]
    let stopReason: String
    let usage: AnthropicToolUsage?   // nil-safe for forward compatibility

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
    }
}
```

### Pattern 2: AgentLoopResult Extended (LOOP-03)

```swift
struct AgentLoopResult {
    let finalText: String
    let iterationsUsed: Int
    let completed: Bool
    // New token/cost fields:
    let totalInputTokens: Int
    let totalOutputTokens: Int
    let estimatedCostUSD: Double
}
```

### Pattern 3: Error Classification in callAPI (LOOP-02)

The current `callAPI` in `AgentLoop` throws `AgentLoopError.httpError(statusCode:body:)` for all HTTP 4xx/5xx. The retry logic needs to inspect the status code to determine retry eligibility.

```swift
// Classification logic (no new error cases needed — use existing httpError)
// In the retry wrapper inside run():
func isRetriable(_ error: Error) -> Bool {
    guard let loopError = error as? AgentLoopError,
          case .httpError(let statusCode, _) = loopError else {
        return true  // network errors (URLError) are retriable
    }
    if statusCode == 429 { return true }   // rate limit — retry with backoff
    if statusCode >= 500 { return true }   // server error — retry
    return false                           // 4xx client error — fatal, don't retry
}
```

Exponential backoff: 1s → 2s → 4s (doubles each attempt). Use `Thread.sleep(forTimeInterval:)` — already used in `AIService.withRetry`. Cap at 3 attempts total.

```swift
// Backoff sequence: attempt 1 fails → sleep 1s, attempt 2 fails → sleep 2s, attempt 3 fails → throw
let backoffSeconds: [Double] = [1.0, 2.0, 4.0]
```

### Pattern 4: max_tokens Truncation Handling (LOOP-01)

The current `case "max_tokens":` in `AgentLoop.run()` appends the truncated response and sends a continuation prompt. The bug: if the truncated response contains an incomplete `tool_use` block, appending it corrupts message history — the API will reject a `tool_use` block with no matching `tool_result`.

**Detection:** When `stopReason == "max_tokens"`, check if any content block is a `.toolUse`:

```swift
case "max_tokens":
    let hasIncompleteToolUse = response.content.contains {
        if case .toolUse = $0 { return true }
        return false
    }
    if hasIncompleteToolUse {
        // Do NOT append truncated response to messages — retry with higher max_tokens
        print("[Agent: max_tokens hit with incomplete tool_use, retrying with \(nextMaxTokens)...]")
        currentMaxTokens = nextMaxTokens  // double, up to 32768 cap
        // Do not append anything to messages — just retry the same call
        continue  // restart the while loop with higher maxTokens
    } else {
        // Text-only truncation — safe to append and continue
        messages.append(...)
        messages.append(user continuation prompt)
    }
```

**Important:** When retrying due to max_tokens, the iteration counter should NOT increment — this is a retry of the same logical step, not a new agent step. Use a separate retry counter.

**max_tokens reset:** After a successful non-truncated response, reset `currentMaxTokens` to the initial value (`maxTokens`). This prevents runaway escalation across iterations.

### Pattern 5: Empty end_turn Handling (LOOP-04)

```swift
case "end_turn":
    let hasContent = response.content.contains {
        if case .text(let t) = $0, !t.isEmpty { return true }
        if case .toolUse = $0 { return true }
        return false
    }
    if hasContent {
        return AgentLoopResult(...)  // normal termination
    } else {
        // Empty end_turn — send continuation prompt
        print("[Agent: empty response, sending continuation...]")
        messages.append(AnthropicToolRequest.Message(
            role: "assistant",
            content: .blocks(response.content)
        ))
        messages.append(AnthropicToolRequest.Message(
            role: "user",
            content: .text("Please continue. What would you like to do next?")
        ))
        // Fall through to next iteration
    }
```

### Pattern 6: Budget Tracking (LOOP-03)

```swift
// In run(), before the while loop:
var totalInputTokens = 0
var totalOutputTokens = 0

// After each successful API response, accumulate:
if let usage = response.usage {
    totalInputTokens += usage.inputTokens
    totalOutputTokens += usage.outputTokens
}

// Pricing constants (Opus 4.6 — update when rates change):
let inputPricePerToken  = 5.0 / 1_000_000.0   // $5.00 / MTok
let outputPricePerToken = 25.0 / 1_000_000.0  // $25.00 / MTok

func estimatedCost(input: Int, output: Int) -> Double {
    return Double(input) * inputPricePerToken + Double(output) * outputPricePerToken
}

// Budget check after accumulating each iteration's usage:
let currentCost = estimatedCost(input: totalInputTokens, output: totalOutputTokens)
let budgetFraction = currentCost / budgetCeiling

if budgetFraction >= 1.0 {
    // Inject stop message to agent, then one final API call, then return
    // ...
} else if budgetFraction >= 0.8 && !hasWarnedAt80 {
    // Inject budget warning to agent as a user message
    hasWarnedAt80 = true
}

// 50% alert (print only, no agent message injection):
if budgetFraction >= 0.5 && !hasAlertedAt50 {
    print("[Budget: 50% used ($\(String(format: "%.2f", currentCost)) / $\(budgetCeiling))]")
    hasAlertedAt50 = true
}
```

### Pattern 7: CellarConfig (LOOP-03)

New file `Sources/cellar/Persistence/CellarConfig.swift`:

```swift
struct CellarConfig: Codable {
    var budgetCeiling: Double

    enum CodingKeys: String, CodingKey {
        case budgetCeiling = "budget"
    }

    static let defaultBudgetCeiling: Double = 5.00

    static func load() -> CellarConfig {
        // 1. Check CELLAR_BUDGET env var (overrides all)
        if let envVal = ProcessInfo.processInfo.environment["CELLAR_BUDGET"],
           let val = Double(envVal) {
            return CellarConfig(budgetCeiling: val)
        }
        // 2. Read ~/.cellar/config.json
        let configURL = CellarPaths.configFile
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(CellarConfig.self, from: data) {
            return config
        }
        // 3. Default
        return CellarConfig(budgetCeiling: defaultBudgetCeiling)
    }
}
```

Add to `CellarPaths.swift`:

```swift
static let configFile: URL = base.appendingPathComponent("config.json")
```

### Pattern 8: Cost Summary Display (LOOP-03)

In `AIService.runAgentLoop()`, after `agentLoop.run(...)` returns:

```swift
let result = agentLoop.run(...)

// Always print cost summary, regardless of success/failure:
let costStr = String(format: "%.2f", result.estimatedCostUSD)
print("Session cost: $\(costStr) (\(result.totalInputTokens) input + \(result.totalOutputTokens) output tokens, \(result.iterationsUsed) iterations)")
```

### Pattern 9: Model ID Correction

`AgentLoop.init` currently defaults to `"claude-sonnet-4-20250514"`. `AIService.runAgentLoop()` passes `model: "claude-sonnet-4-20250514"`. Both must be updated to `"claude-opus-4-6"`. (Note: `AIService.callAnthropic` for non-agent paths already uses `"claude-opus-4-6"` correctly.)

### Anti-Patterns to Avoid

- **Appending truncated tool_use to messages:** When max_tokens hits mid-tool_use, the API returns an incomplete tool_use block. Appending it creates an orphaned tool_use with no tool_result, causing a 400 error on the next call.
- **Incrementing iterationCount on max_tokens retry:** Retries are not new agent iterations. Count them separately.
- **Inserting budget warning as a system message:** The Anthropic API only allows one system message, passed at request construction time. Budget warnings must be injected as user messages in the `messages` array.
- **Budget check before token accumulation:** Always accumulate tokens from the response before checking budget fractions.
- **Using `AgentLoop.maxTokens` (let) for escalation:** Since `maxTokens` is a `let` property, escalation requires a `var currentMaxTokens` local to `run()`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP client | Custom URLSession wrapper | Existing `callAPI` + `ResultBox` pattern | Already written, Swift 6 Sendable-compliant, semaphore pattern proven |
| JSON config parsing | Custom parser | `JSONDecoder().decode(CellarConfig.self, ...)` | Codable is standard Swift |
| Exponential backoff | Timer/async scheduler | `Thread.sleep(forTimeInterval:)` | Loop is already synchronous; sleep is correct here |
| Token counting | Local tokenizer | Decode `usage` from API response | API provides exact counts; local tokenizer would be wrong |

**Key insight:** The existing synchronous `DispatchSemaphore + URLSession` pattern is intentional for Swift 6 compliance in a CLI context. Do not introduce async/await.

---

## Common Pitfalls

### Pitfall 1: Incomplete tool_use Corrupts Message History
**What goes wrong:** `stop_reason="max_tokens"` can occur mid-tool_use block. The response has a `.toolUse` block but the `input` JSONValue may be incomplete or empty. Appending this to `messages` then sending a continuation causes a 400 "tool_use block has no matching tool_result" error.
**Why it happens:** The API truncates output mid-stream. The content array contains whatever was generated before hitting the token limit.
**How to avoid:** Detect `.toolUse` blocks in a max_tokens response and do NOT append to messages. Retry the call with higher `currentMaxTokens` from the same message state.
**Warning signs:** 400 HTTP errors after max_tokens recovery; error body mentions "tool_use_id" or "tool_result".

### Pitfall 2: Budget Warning via System Message Fails
**What goes wrong:** Trying to inject a mid-session budget warning by modifying the system prompt fails — the system prompt is set at `AgentLoop.init` time and passed to every request as-is.
**Why it happens:** Anthropic API `system` field is per-request, but the current code passes it once from `AgentLoop.systemPrompt`. Modifying it mid-loop requires threading it as a mutable value or passing it as a user message instead.
**How to avoid:** Inject budget warnings as user-role messages in the `messages` array, not as system prompt modifications. This is simpler and works within the existing `messages: [Message]` pattern.
**Warning signs:** Budget alerts that never appear; system prompt growing unexpectedly.

### Pitfall 3: 429 Rate Limit Treated as Fatal 4xx
**What goes wrong:** The retry classification treats all 4xx as fatal. 429 (Too Many Requests) is a transient condition that should be retried with backoff, not aborted.
**Why it happens:** Simple status code range check (`>= 400 && < 500`) groups 429 with client errors.
**How to avoid:** Explicitly test `statusCode == 429` before the general 4xx check. Retry 429 with the same backoff as 5xx.
**Warning signs:** Agent aborting with "HTTP 429" during heavy usage instead of waiting.

### Pitfall 4: max_tokens Escalation Bleeds Across Iterations
**What goes wrong:** After a truncation event escalates `currentMaxTokens` from 16384 to 32768, all subsequent iterations use 32768 even when the larger limit is no longer needed. This wastes output token budget.
**Why it happens:** If `currentMaxTokens` is not reset after a successful non-truncated response, it stays elevated.
**How to avoid:** After `stopReason != "max_tokens"` (i.e., a complete response), reset `currentMaxTokens = maxTokens` (the loop's initial default).
**Warning signs:** All iterations after the first truncation showing unusually high output token counts.

### Pitfall 5: model ID Still Points to Sonnet
**What goes wrong:** `AgentLoop.init` defaults to `"claude-sonnet-4-20250514"` and `AIService.runAgentLoop()` passes this. Cost tracking will use wrong pricing constants and the wrong model runs.
**Why it happens:** The model was changed for `callAnthropic` (non-agent path) but not updated in `AgentLoop`.
**How to avoid:** In this phase, update both `AgentLoop.init` default and `AIService.runAgentLoop()` call to `"claude-opus-4-6"`.

### Pitfall 6: Zero-Usage Response Crashes Cost Calculation
**What goes wrong:** If `response.usage` is nil (unexpected API response or decoding gap), accumulating `0` is correct but division by zero or nil unwrap could crash if not guarded.
**Why it happens:** `AnthropicToolUsage` is decoded as optional (`usage: AnthropicToolUsage?`). If the API ever omits it, forced unwrap crashes.
**How to avoid:** Use optional chaining: `if let usage = response.usage { ... }`. Treat nil usage as 0 tokens (no accumulation).

---

## Code Examples

### Corrected max_tokens Case in run()

```swift
// Source: derived from AgentLoop.swift current implementation
case "max_tokens":
    let hasIncompleteToolUse = response.content.contains {
        if case .toolUse = $0 { return true }
        return false
    }
    if hasIncompleteToolUse && currentMaxTokens < maxTokensCeiling {
        // Do NOT corrupt message history — retry same call with more tokens
        let newMax = min(currentMaxTokens * 2, maxTokensCeiling)
        print("[Agent: max_tokens hit with incomplete tool_use, retrying with \(newMax)...]")
        currentMaxTokens = newMax
        // No messages.append — fall through to next iteration with same messages
    } else {
        // Text-only truncation (or already at ceiling) — append and continue
        print("[Agent: response truncated, continuing...]")
        messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
        messages.append(AnthropicToolRequest.Message(
            role: "user",
            content: .text("Your response was truncated. Continue.")
        ))
        if currentMaxTokens > maxTokens {
            currentMaxTokens = maxTokens  // reset after text-only truncation
        }
    }
```

### Retry Wrapper with Error Classification

```swift
// Replaces the single callAnthropic call in run()
// Source: upgrade of existing AIService.withRetry pattern

private func callAnthropicWithRetry(
    messages: [AnthropicToolRequest.Message],
    maxTokens: Int
) throws -> AnthropicToolResponse {
    var lastError: Error = AgentLoopError.noResponse
    let backoffSeconds: [Double] = [1.0, 2.0, 4.0]

    for attempt in 1...3 {
        do {
            return try callAnthropic(messages: messages, overrideMaxTokens: maxTokens)
        } catch let error as AgentLoopError {
            if case .httpError(let code, _) = error {
                if code >= 400 && code < 500 && code != 429 {
                    throw error  // Fatal 4xx — do not retry
                }
            }
            lastError = error
            if attempt < 3 {
                let delay = backoffSeconds[attempt - 1]
                print("API error, retrying (\(attempt)/3)...")
                Thread.sleep(forTimeInterval: delay)
            }
        } catch {
            lastError = error
            if attempt < 3 {
                let delay = backoffSeconds[attempt - 1]
                print("API error, retrying (\(attempt)/3)...")
                Thread.sleep(forTimeInterval: delay)
            }
        }
    }
    throw lastError
}
```

### Budget Injection Message Format

```swift
// At 80% — inject to agent as user message (NOT system message)
let warnMsg = "[BUDGET WARNING: \(Int(budgetFraction * 100))% of session budget used ($\(String(format: "%.2f", currentCost)) / $\(budgetCeiling)). Begin wrapping up — save progress and finalize results soon.]"

messages.append(AnthropicToolRequest.Message(
    role: "user",
    content: .text(warnMsg)
))

// At 100% — inject stop directive, make one final API call to let agent save, then halt
let stopMsg = "[BUDGET LIMIT REACHED: $\(String(format: "%.2f", budgetCeiling)) session budget exhausted. You must stop now. Call save_success or save_recipe if you have a working configuration, then stop. Do not make further tool calls.]"
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `claude-sonnet-4-20250514` | `claude-opus-4-6` | This phase | Correct model for agent loop; different pricing |
| Opus pricing $15/$75 per MTok | Opus 4.6 pricing $5/$25 per MTok | Model upgrade to Opus 4.6 | Lower cost — $5.00 default budget goes further |
| max_tokens = 4096 (AgentLoop default) | max_tokens = 16384 (AIService.runAgentLoop sets it) | Phase 7 | Already escalated from original default; escalation ceiling is 32768 |
| Linear 1s retry in AIService.withRetry | Exponential 1s/2s/4s with error classification | This phase | Smarter — fast fail on client errors, patient on server errors |

**Model IDs in use (verified 2026-03-28):**
- Agent loop (tool-use): currently `"claude-sonnet-4-20250514"` — MUST change to `"claude-opus-4-6"`
- Non-agent diagnose/recipe paths: already `"claude-opus-4-6"` in `AIService.callAnthropic`

**Opus 4.6 max output tokens:** 128k. The context decision caps escalation at 32k — this is a deliberate conservative limit, not the API limit.

---

## Open Questions

1. **AgentLoop.init model default**
   - What we know: `AgentLoop` struct has `model: String = "claude-sonnet-4-20250514"` as default. `AIService.runAgentLoop()` passes `model: "claude-sonnet-4-20250514"` explicitly, overriding the default.
   - What's unclear: Should the default in `AgentLoop.init` be changed, or only the call site in `AIService.runAgentLoop()`?
   - Recommendation: Change both. The default should be `"claude-opus-4-6"` since AgentLoop is only used with Opus in this project.

2. **Budget warning as user message vs assistant message injection**
   - What we know: The Anthropic API requires alternating user/assistant roles. A budget warning injected as a user message will disrupt the tool-result → assistant → user turn sequence if injected mid-loop.
   - What's unclear: Exact injection point in the message sequence.
   - Recommendation: Inject budget warnings only at the START of a new iteration, before calling the API, not mid-sequence. Append as a user message right after appending tool results.

3. **Config file format for `~/.cellar/config.json`**
   - What we know: `CellarPaths` doesn't currently define a `configFile` path. The CONTEXT.md specifies `~/.cellar/config.json`.
   - What's unclear: Should config read/write be atomic to avoid corruption?
   - Recommendation: Read-only in this phase (write is out of scope). `JSONDecoder` decode from file is safe for read-only.

---

## Sources

### Primary (HIGH confidence)
- Anthropic API docs (platform.claude.com/docs/en/api/messages) — usage field structure: `input_tokens`, `output_tokens` in `usage` object
- Anthropic pricing page (platform.claude.com/docs/en/about-claude/pricing) — Opus 4.6: $5.00/MTok input, $25.00/MTok output
- Claude 4.6 release notes (platform.claude.com/docs/en/about-claude/models/whats-new-claude-4-6) — model ID `claude-opus-4-6`, 128k max output tokens
- Project source code (`AgentLoop.swift`, `AIService.swift`, `AIModels.swift`) — current implementation, error types, patterns

### Secondary (MEDIUM confidence)
- Inferred from Anthropic API behavior: truncated tool_use corruption pattern is documented behavior in agent loop best practices

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; existing Foundation patterns
- Architecture: HIGH — changes are surgical additions to existing well-understood code
- Pitfalls: HIGH — truncated tool_use corruption is a known Anthropic API pattern; retry classification is standard HTTP practice
- Pricing constants: HIGH — verified directly from official Anthropic pricing page 2026-03-28

**Research date:** 2026-03-28
**Valid until:** Pricing constants should be verified when model changes. Architecture valid until AgentLoop is refactored.
