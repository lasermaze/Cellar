# Phase 36: Event Log Resume - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** agent-loop-rewrite-brief.md

<domain>
## Phase Boundary

Wire the JSONL event log into the session resume flow. When a game is relaunched after budget exhaustion or API error, the initial message should include a richer summary from the event log (what tools were called, what env was set, what launches happened and their outcomes) instead of just the SessionHandoff snapshot. SessionHandoff remains as fallback when no event log exists.

</domain>

<decisions>
## Implementation Decisions

### Event log resume in AIService (LOG-03)
- In AIService.runAgentLoop(), when constructing the initial message, check for a recent event log file
- If event log exists for this gameId: call eventLog.summarizeForResume() and inject into initial message
- If no event log: fall back to SessionHandoff.read(gameId:)?.formatForAgent() (existing behavior)
- Event log summary is richer: includes tool call history, env changes, launch outcomes with exit codes

### SessionHandoff fallback (LOG-04)
- SessionHandoff.read() and .write() stay unchanged
- SessionHandoff is still written on budget/iterations/error stop reasons (existing behavior from Phase 35)
- On resume: prefer event log summary, fall back to SessionHandoff if no log exists
- Delete event log file after successful session (same as SessionHandoff.delete)

### Finding the most recent event log
- Event logs are at ~/.cellar/logs/<gameId>-<timestamp>.jsonl
- Find the most recent .jsonl file matching the gameId prefix
- AgentEventLog needs a static method: `static func findMostRecent(gameId: String) -> AgentEventLog?`

### Constraints
- swift build must pass
- swift test must pass (165 tests)
- No changes to AgentLoop, AgentTools, middleware, or providers

</decisions>

<code_context>
## Existing Code Insights

### Files to modify
1. Sources/cellar/Core/AgentEventLog.swift — add findMostRecent() static method
2. Sources/cellar/Core/AIService.swift — wire event log resume into initial message construction

### Existing resume flow (AIService.swift)
- SessionHandoff.read(gameId:) checks for ~/.cellar/sessions/<gameId>.json
- If found, SessionHandoff.formatForAgent() returns a multi-line context string
- This string is appended to the initial message before the agent starts

### AgentEventLog already has
- summarizeForResume() — returns formatted string with tool history, env changes, launch outcomes
- readAll() — decodes all JSONL entries
- append() — writes new entries

</code_context>

<deferred>
## Deferred Ideas

None.

</deferred>

---

*Phase: 36-event-log-resume*
*Context gathered: 2026-04-03 via brief*
