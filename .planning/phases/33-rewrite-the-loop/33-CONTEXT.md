# Phase 33: Rewrite the Loop - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Rewrite AgentLoop.run() to use the new types from Phase 31 (ToolResult, AgentControl, LoopState) and middleware from Phase 32. The loop body shrinks to ≤150 lines. endTurn means stop (no tug-of-war). prepareStep hook available. Budget/spin/logging logic removed from loop body (now in middleware).

This is the BIG phase — it replaces the existing loop implementation.

</domain>

<decisions>
## Implementation Decisions

### New run() signature
- Takes: initialMessage, toolExecutor (returns ToolResult not String), control: AgentControl, middlewareContext: MiddlewareContext
- Removes: canStop closure, shouldAbort closure
- toolExecutor is now `(String, JSONValue) async -> ToolResult` (was `(String, JSONValue) -> String`)

### LoopState adoption
- Replace 12 scattered local vars with LoopState struct from Phase 31
- All state reads/writes go through `state.` prefix

### Clean endTurn
- `.endTurn` → return immediately with .completed. No tug-of-war, no consecutiveContinuations, no forced continuation
- Remove canStop parameter entirely

### Middleware integration
- After each tool: call beforeTool/afterTool on each middleware
- After all tools in a batch: call afterStep, collect injected messages
- Budget/spin detection logic REMOVED from loop body — middleware handles it

### prepareStep hook
- Called before each LLM API call
- Returns optional StepModification: trimMessages, injectMessage, maxTokensOverride
- Initial use: context trimming (deferred to Phase 35 wiring)

### Extracted helper methods
- executeTools() — handles tool batch, middleware hooks, stop detection
- checkBudgetHalt() — 100% budget halt (stays in loop, not middleware)
- handleTruncation() — maxTokens retry/continuation logic
- handleAPIError() — error formatting and result creation

### What's removed from loop body
- Budget threshold tracking (50%, 80%, warning injection) → BudgetTracker middleware
- Spin detection (recentActionTools, pattern matching, pivot nudge) → SpinDetector middleware
- consecutiveContinuations counter and tug-of-war logic
- canStop/shouldAbort closure parameters
- String matching for "STOP": true → ToolResult.isStop

### Constraints
- Existing tests must still pass (swift test)
- AgentLoop.run() callers (AIService.runAgentLoop) will temporarily break — Phase 35 fixes callers
- The toolExecutor closure type changes from `(String, JSONValue) -> String` to `(String, JSONValue) async -> ToolResult`

### Claude's Discretion
- Whether to keep backward-compat wrapper for old String-returning toolExecutor (recommend: no, Phase 34/35 will update callers)
- Exact line count (target ≤150, accept up to 200 if clearer)

</decisions>

<code_context>
## Existing Code Insights

### File to rewrite
- Sources/cellar/Core/AgentLoop.swift — currently 422 lines, will shrink to ~200

### Dependencies from Phase 31-32
- ToolResult enum (AgentLoop.swift)
- AgentControl (AgentControl.swift)
- LoopState (AgentLoop.swift)
- AgentMiddleware protocol + MiddlewareContext (AgentMiddleware.swift)

### Callers that will break
- AIService.runAgentLoop() — calls agentLoop.run() with old signature. Fixed in Phase 35.

</code_context>

<specifics>
## Specific Ideas

- The brief has the complete new AgentLoop.swift implementation (~280 lines including helpers)
- The key behavioral change: endTurn = stop, period

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 33-rewrite-the-loop*
*Context gathered: 2026-04-03 via brief*
