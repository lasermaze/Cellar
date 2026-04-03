# Phase 35: Wire It Together - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Wire all Phase 31-34 pieces together so the build compiles and the agent loop works end-to-end. Update AIService.runAgentLoop(), ActiveAgents, LaunchController stop/confirm routes. This phase makes swift build pass again.

</domain>

<decisions>
## Implementation Decisions

### AIService.runAgentLoop() rewrite (INT-01)
- Create AgentControl, set tools.control = control
- Create AgentEventLog(gameId:)
- Create MiddlewareContext(control:budgetCeiling:)
- Create middleware chain: [BudgetTracker, SpinDetector, EventLogger]
- Create AgentLoop with middleware + prepareStep: nil
- Call agentLoop.run() with new signature (toolExecutor returns ToolResult, control, middlewareContext)
- toolExecutor closure: `{ name, input in await tools.execute(toolName: name, input: input) }`
- POST-LOOP SAVE: if result.stopReason == .userConfirmed, call save_success with await (ONE save path)
- Register tools + control with ActiveAgents
- Log session end to event log
- Handle stop reasons: .completed, .userConfirmed, .userAborted, .budgetExhausted, .maxIterations, .apiError

### ActiveAgents update (INT-02)
- Store AgentControl alongside AgentTools
- Add register(gameId:tools:control:), getControl(gameId:), update remove()
- Stop/confirm routes use getControl() instead of setting bare vars on tools

### LaunchController routes (INT-03, BUG-02)
- Stop route: `ActiveAgents.shared.getControl(gameId:)?.abort()` instead of `tools.shouldAbort = true`
- Confirm route: `ActiveAgents.shared.getControl(gameId:)?.confirm()` instead of `tools.userForceConfirmed = true`
- Respond route (ask_user): unchanged — still uses getTools() for PendingUserResponse

### prepareStep hook (INT-04)
- Wired as nil initially — placeholder for future context trimming
- PrepareStepHook typealias already in AgentLoop.swift

### Constraints
- After this phase, `swift build` MUST pass
- `swift test` MUST pass (all 165 tests)
- No changes to tool implementation files or provider protocol

</decisions>

<code_context>
## Existing Code Insights

### Files to modify
1. Sources/cellar/Core/AIService.swift — rewrite runAgentLoop() (~lines 930-1087)
2. Sources/cellar/Web/Controllers/LaunchController.swift — ActiveAgents + stop/confirm routes

### The brief has exact new code
- "Changes to AIService.runAgentLoop()" section
- "Changes to LaunchController" section (ActiveAgents, stop route, confirm route)

### Dependencies from Phase 31-34
- ToolResult, AgentStopReason (.userAborted, .userConfirmed) — AgentLoop.swift
- AgentControl — AgentControl.swift
- AgentMiddleware, MiddlewareContext, BudgetTracker, SpinDetector, EventLogger — AgentMiddleware.swift
- AgentEventLog — AgentEventLog.swift
- AgentTools.execute() returns ToolResult, has var control: AgentControl!

</code_context>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 35-wire-it-together*
*Context gathered: 2026-04-03 via brief*
