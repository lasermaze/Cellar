# Phase 31: New Types - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Create foundational types that the rest of v1.3 builds on: ToolResult enum, AgentControl class, LoopState struct, expanded AgentStopReason. No behavior changes yet — just new types that compile alongside existing code.

</domain>

<decisions>
## Implementation Decisions

### ToolResult enum (ARCH-01)
- Three cases: .success(content: String), .stop(content: String, reason: StopReason), .error(content: String)
- StopReason sub-enum: .userAborted, .userConfirmedWorking
- Computed properties: .content (underlying string), .isStop, .isError
- Defined in AgentLoop.swift above the AgentLoop struct
- Does NOT change execute() return type yet — that's Phase 34

### AgentControl class (ARCH-02, BUG-04)
- New file: Sources/cellar/Core/AgentControl.swift
- final class, Sendable
- Uses OSAllocatedUnfairLock (Swift 6 concurrency-safe, no new deps)
- Private State struct with shouldAbort and userForceConfirmed bools
- Public read: var shouldAbort: Bool, var userForceConfirmed: Bool
- Public write: func abort(), func confirm()
- Does NOT wire into AgentTools/LaunchController yet — that's Phase 34/35

### LoopState struct (ARCH-03)
- Private struct inside AgentLoop.swift
- Consolidates: iterationCount, allText, currentMaxTokens, maxTokensCeiling, totalInputTokens, totalOutputTokens, pricing, budgetCeiling
- Computed: estimatedCost, budgetFraction
- Method: addTokens(input:output:), makeResult(completed:stopReason:)
- Does NOT replace current local vars yet — that's Phase 33

### AgentStopReason expansion
- Add .userAborted and .userConfirmed cases to existing AgentStopReason enum
- Keep existing cases: .completed, .budgetExhausted, .maxIterations, .apiError(String)

### Constraints
- All new types must compile alongside existing code — no breaking changes
- AgentLoop.swift already exists and has AgentStopReason — extend it, don't duplicate
- No behavior changes in this phase

### Claude's Discretion
- Whether to put ToolResult in AgentLoop.swift or a new AgentLoopTypes.swift
- Exact documentation comments

</decisions>

<code_context>
## Existing Code Insights

### Files to modify/create
1. Sources/cellar/Core/AgentLoop.swift — add ToolResult enum, LoopState struct, expand AgentStopReason
2. Sources/cellar/Core/AgentControl.swift — NEW file

### Established Patterns
- AgentLoop.swift already has AgentStopReason, AgentLoopResult, AgentEvent, AgentLoopError
- @unchecked Sendable used elsewhere (AgentTools, WineProcess) — AgentControl should be properly Sendable via OSAllocatedUnfairLock

</code_context>

<specifics>
## Specific Ideas

- The brief has exact Swift code for all types — use it as-is
- OSAllocatedUnfairLock requires import os (or Foundation includes it)

</specifics>

<deferred>
## Deferred Ideas

None — types are foundational, no scope creep possible.

</deferred>

---

*Phase: 31-new-types*
*Context gathered: 2026-04-03 via brief*
