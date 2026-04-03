# Phase 32: Middleware System - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Create the middleware protocol, three concrete middleware implementations (BudgetTracker, SpinDetector, EventLogger), and the JSONL event log. These are standalone types that compile without modifying the existing loop — wiring happens in Phase 33/35.

</domain>

<decisions>
## Implementation Decisions

### AgentMiddleware protocol (MW-01)
- New file: Sources/cellar/Core/AgentMiddleware.swift
- Three hooks: beforeTool(name:input:context:) -> ToolResult?, afterTool(name:input:result:context:), afterStep(context:) -> String?
- MiddlewareContext class: holds control ref, iterationCount, estimatedCost, budgetCeiling, recentActionTools array, injection flags
- Protocol and context defined in same file

### BudgetTracker middleware (MW-02)
- In AgentMiddleware.swift
- Fires at 50% (alert), 80% (warning message), budget halt at 100% handled by loop not middleware
- Extracted from current AgentLoop.swift lines 214-242, 340-346
- Uses emit callback for AgentEvent emission

### SpinDetector middleware (MW-03)
- In AgentMiddleware.swift
- Tracks action tools in recentActionTools (via context)
- Detects: 2-tool repeating cycle (A→B→A→B→A→B) or same tool 4+ times in last 6
- Injects pivot nudge message via afterStep return
- One-shot: hasSentNudge prevents repeated nudges
- Extracted from current AgentLoop.swift lines 300-338

### EventLogger middleware (MW-04)
- In AgentMiddleware.swift
- Writes to AgentEventLog (LOG-01)
- beforeTool: log toolInvoked
- afterTool: log toolCompleted with truncated summary
- afterStep: log stepCompleted with iteration + cost

### JSONL Event Log (LOG-01, LOG-02)
- New file: Sources/cellar/Core/AgentEventLog.swift
- AgentLogEntry enum (Codable): sessionStarted, llmCalled, toolInvoked, toolCompleted, stepCompleted, envChanged, gameLaunched, spinDetected, budgetWarning, sessionEnded
- AgentEventLog class: append-only JSONL writer at ~/.cellar/logs/<gameId>-<timestamp>.jsonl
- readAll() for resume, summarizeForResume() for session injection
- Resume summary and SessionHandoff integration is Phase 36

### Constraints
- All new types compile standalone — no modifications to AgentLoop.swift or AgentTools.swift
- ToolResult type from Phase 31 is referenced by the protocol (beforeTool returns ToolResult?)
- MiddlewareContext references AgentControl from Phase 31
- No behavior changes to existing loop

### Claude's Discretion
- Whether to split middleware implementations into separate files or keep in AgentMiddleware.swift
- Exact JSONL field names in AgentLogEntry
- CellarPaths integration for log directory

</decisions>

<code_context>
## Existing Code Insights

### Dependencies from Phase 31
- ToolResult enum in AgentLoop.swift — used by beforeTool return type
- AgentControl in AgentControl.swift — referenced by MiddlewareContext

### Files to create
1. Sources/cellar/Core/AgentMiddleware.swift — protocol + MiddlewareContext + 3 implementations
2. Sources/cellar/Core/AgentEventLog.swift — JSONL writer + AgentLogEntry enum

</code_context>

<specifics>
## Specific Ideas

- The brief has exact Swift code for all types — use as implementation spec
- All middleware are class types (need mutable state like hasSentNudge, hasAlertedAt50)

</specifics>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 32-middleware-system*
*Context gathered: 2026-04-03 via brief*
