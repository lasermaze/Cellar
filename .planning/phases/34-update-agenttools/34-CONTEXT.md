# Phase 34: Update AgentTools - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Update AgentTools.execute() to return ToolResult instead of String. Remove bare var shouldAbort/userForceConfirmed/taskState. Add var control: AgentControl. The save-and-stop block in execute() is replaced by simple .stop return — actual saving happens post-loop in Phase 35.

</domain>

<decisions>
## Implementation Decisions

### execute() returns ToolResult (ARCH-01 wire)
- Change return type from String to ToolResult
- All tool dispatch cases: wrap String result in ToolResult.success(content:)
- Check control.shouldAbort → return .stop(content:, reason: .userAborted)
- Check control.userForceConfirmed → return .stop(content:, reason: .userConfirmedWorking)
- Unknown tool → return .error(content:)

### Remove bare vars (BUG-04 wire, BUG-01 fix)
- Remove: var shouldAbort, var userForceConfirmed
- Remove: enum TaskState and var taskState
- Remove: var isTaskComplete computed property
- Remove: the save-and-stop block (current fire-and-forget save in shouldAbort check)
- Add: var control: AgentControl! (set by AIService before loop starts)

### Extract trackPendingAction()
- Move pending action tracking from execute() into its own private method
- Same logic, cleaner separation

### What stays
- All tool implementations (still return String) — execute() wraps in ToolResult
- accumulatedEnv, launchCount, maxLaunches, installedDeps, lastLogFile
- pendingActions, lastAppliedActions, previousDiagnostics
- askUserHandler callback
- captureHandoff() method

### Constraints
- Tool implementation files (SaveTools, DiagnosticTools, etc.) are NOT modified
- After this phase + Phase 35, the full build should compile again

</decisions>

<code_context>
## Existing Code Insights

### File to modify
- Sources/cellar/Core/AgentTools.swift — coordinator class (~700 lines)

### The brief has exact new execute() code
- See .planning/agent-loop-rewrite-brief.md "Changes to AgentTools" section

</code_context>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 34-update-agenttools*
*Context gathered: 2026-04-03 via brief*
