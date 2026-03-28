# Phase 8: Loop Resilience - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the agent loop correct and observable: fix max_tokens truncation corruption, add transient error retry with backoff, track token usage and cost per session with a configurable budget ceiling, and handle empty end_turn responses. No new agent tools or capabilities — this is correctness and observability for the existing loop.

</domain>

<decisions>
## Implementation Decisions

### Budget behavior
- Default ceiling: $5.00 per `cellar launch` session
- Graceful wind-down: at 80% inject warning to agent via system message; at 100% inject "wrap up now" prompt, let agent save progress and exit cleanly
- Budget is per launch command (each `cellar launch` gets its own budget)
- Configuration: `~/.cellar/config.json` with budget field, overridable by `CELLAR_BUDGET` env var
- Budget ceiling overrides max_tokens escalation: if doubling max_tokens would push past 80% budget, use continuation prompt instead of escalating

### Cost display
- End-of-session summary: full transparency — "Session cost: $0.47 (12,340 input + 3,210 output tokens, 8 iterations)"
- Mid-session alerts only at 50% and 80% budget thresholds — not every iteration
- Model pricing: hardcoded constants for current model rates. The model is Opus (not Sonnet) — use Opus pricing ($15/$75 per 1M tokens or current rates). Update when rates change.

### Retry UX
- API retries: brief status line — "API error, retrying (2/3)..." — not silent, not alarming
- max_tokens truncation retries: always visible — "max_tokens hit, retrying with 32768..."
- All retries failed: abort with clear message — "API unavailable after 3 attempts. Your game state is unchanged." — do not fall back to recipe-only

### Escalation limits
- max_tokens doubling ceiling: 32k (Opus API maximum output tokens)
- If still truncated at 32k: fall back to continuation prompt ("Your response was truncated. Continue.")
- Escalation strategy: start at current 16384, double on truncation (16384 → 32768), cap at 32k

### Claude's Discretion
- Exact exponential backoff timing (1s → 2s → 4s or similar)
- How to distinguish 429 (rate limit) from other 4xx errors in retry logic
- Whether to reset max_tokens back to default after a successful non-truncated response
- Internal message format for budget warning injection

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `AIService.withRetry(maxAttempts: 3)` — existing retry helper, but uses linear 1s delay. Needs upgrade to exponential backoff with error-type awareness
- `AgentLoopError` enum — already has `.httpError(statusCode:body:)` and `.noResponse` cases
- `ResultBox: @unchecked Sendable` — pattern for synchronous HTTP in Swift 6

### Established Patterns
- `AgentLoop` is a struct with `run()` returning `AgentLoopResult` — all state is local to the run loop
- `AnthropicToolResponse` already has `stopReason: String` — parsed as "end_turn", "tool_use", "max_tokens"
- `ToolContentBlock` enum has `.toolUse(id:name:input:)` case — can detect incomplete tool_use in truncated responses
- Messages array grows linearly through iterations — `[Message]` with `.text` and `.blocks` content

### Integration Points
- `AIService.runAgentLoop()` (line ~582) creates the AgentLoop with maxIterations=20, maxTokens=16384 — this is where budget config would be injected
- `AnthropicToolResponse` needs `usage` field added for token tracking (currently not decoded)
- `AgentLoopResult` needs new fields: `totalInputTokens`, `totalOutputTokens`, `estimatedCost`
- `LaunchCommand` prints the agent result — this is where end-of-session cost summary would display

</code_context>

<specifics>
## Specific Ideas

- "Please stop thinking about Sonnet, we use Opus" — the model is Opus, not Sonnet. All pricing, token limits, and model references should use Opus values.
- Budget ceiling should feel protective, not punitive — the graceful wind-down gives the agent a chance to save its work before stopping.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-loop-resilience*
*Context gathered: 2026-03-28*
