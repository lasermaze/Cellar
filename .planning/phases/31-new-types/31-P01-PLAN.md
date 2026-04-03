---
phase: 31-new-types
plan: 01
type: execute
wave: 1
depends_on: []
files_modified: [Sources/cellar/Core/AgentLoop.swift]
autonomous: true
requirements: [ARCH-01, ARCH-03]

must_haves:
  truths:
    - ToolResult enum exists with .success, .stop, .error cases and computed properties (.content, .isStop, .isError)
    - LoopState private struct exists with consolidated loop vars, computed properties, and methods
    - AgentStopReason has .userAborted and .userConfirmed cases alongside existing cases
    - Existing code compiles without modification — no breaking changes
  artifacts:
    - Sources/cellar/Core/AgentLoop.swift (modified)
  key_links:
    - ToolResult.StopReason maps to AgentStopReason (.userAborted, .userConfirmed)
    - LoopState.makeResult() produces AgentLoopResult
---

<objective>
Add ToolResult enum, LoopState struct, and expanded AgentStopReason to AgentLoop.swift.

Purpose: Create the typed result and consolidated state types that the rest of v1.3 builds on.
Output: Modified AgentLoop.swift with three new type definitions that compile alongside existing code.
</objective>

<execution_context>
@/Users/peter/.claude/get-shit-done/workflows/execute-plan.md
@/Users/peter/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/agent-loop-rewrite-brief.md
@Sources/cellar/Core/AgentLoop.swift
</context>

<tasks>

<task type="auto">
  <name>Task 1: Expand AgentStopReason and add ToolResult enum</name>
  <files>Sources/cellar/Core/AgentLoop.swift</files>
  <action>
In AgentLoop.swift, make two changes:

1. **Expand AgentStopReason** — add two new cases to the existing enum:
```swift
enum AgentStopReason: Sendable {
    case completed          // Agent called end_turn naturally
    case userAborted        // User clicked stop
    case userConfirmed      // User clicked confirm — caller must save after loop
    case budgetExhausted
    case maxIterations
    case apiError(String)
}
```
Keep existing cases in their current order, add .userAborted and .userConfirmed after .completed.

2. **Add ToolResult enum** — place it ABOVE the AgentLoop struct (after AgentEvent, before the `// MARK: - AgentLoop` comment):
```swift
// MARK: - ToolResult

/// Typed result from tool execution. Eliminates string matching for control flow.
enum ToolResult: Sendable {
    /// Tool executed successfully. `content` is the JSON string for the LLM.
    case success(content: String)
    /// Tool executed but the agent should stop after this iteration.
    case stop(content: String, reason: StopReason)
    /// Tool execution failed (still sent to LLM as tool_result).
    case error(content: String)

    enum StopReason: Sendable {
        case userAborted
        case userConfirmedWorking
    }

    /// The JSON string to include in the tool_result message to the LLM.
    var content: String {
        switch self {
        case .success(let c), .stop(let c, _), .error(let c): return c
        }
    }

    var isStop: Bool {
        if case .stop = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}
```

No other changes. Existing code that switches on AgentStopReason will still compile because Swift enums with no exhaustive switch use `default:` cases — verify this compiles.
  </action>
  <verify>
    <automated>cd /Users/peter/Documents/Cellar && swift build 2>&1 | tail -5</automated>
  </verify>
  <done>AgentStopReason has .userAborted and .userConfirmed cases; ToolResult enum exists with all three cases and computed properties; project compiles</done>
</task>

<task type="auto">
  <name>Task 2: Add LoopState struct</name>
  <files>Sources/cellar/Core/AgentLoop.swift</files>
  <action>
Add a private LoopState struct inside AgentLoop.swift. Place it after the ToolResult enum and before the AgentLoop struct definition (or just inside the AgentLoop struct as a private type — either works, but the brief says "private struct inside AgentLoop.swift" so place it at file scope with `private` access):

```swift
// MARK: - LoopState

/// All mutable state for one agent loop run.
private struct LoopState {
    var iterationCount = 0
    var allText: [String] = []
    var currentMaxTokens: Int
    let maxTokensCeiling: Int
    var totalInputTokens = 0
    var totalOutputTokens = 0
    let pricing: (input: Double, output: Double)
    let budgetCeiling: Double

    init(maxTokens: Int, maxTokensCeiling: Int, pricing: (input: Double, output: Double), budgetCeiling: Double) {
        self.currentMaxTokens = maxTokens
        self.maxTokensCeiling = maxTokensCeiling
        self.pricing = pricing
        self.budgetCeiling = budgetCeiling
    }

    var estimatedCost: Double {
        Double(totalInputTokens) * pricing.input + Double(totalOutputTokens) * pricing.output
    }

    var budgetFraction: Double {
        budgetCeiling > 0 ? estimatedCost / budgetCeiling : 0
    }

    mutating func addTokens(input: Int, output: Int) {
        totalInputTokens += input
        totalOutputTokens += output
    }

    func makeResult(completed: Bool, stopReason: AgentStopReason) -> AgentLoopResult {
        AgentLoopResult(
            finalText: allText.joined(separator: "\n"),
            iterationsUsed: iterationCount,
            completed: completed,
            stopReason: stopReason,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            estimatedCostUSD: estimatedCost
        )
    }
}
```

This struct is not used yet (Phase 33 will adopt it) — it just needs to compile.
  </action>
  <verify>
    <automated>cd /Users/peter/Documents/Cellar && swift build 2>&1 | tail -5</automated>
  </verify>
  <done>LoopState struct exists with all fields, computed properties, addTokens(), and makeResult(); project compiles with no warnings from this type</done>
</task>

</tasks>

<verification>
1. `swift build` succeeds with zero errors
2. AgentStopReason has 6 cases: .completed, .userAborted, .userConfirmed, .budgetExhausted, .maxIterations, .apiError
3. ToolResult enum has 3 cases with StopReason sub-enum and computed properties
4. LoopState struct has all 8 stored properties, 2 computed properties, 2 methods
5. No existing behavior changed — grep for switch statements on AgentStopReason and verify they still compile (default cases cover new variants)
</verification>

<success_criteria>
- `swift build` passes
- All three type definitions present in AgentLoop.swift
- No changes to any other file
</success_criteria>

<output>
After completion, create `.planning/phases/31-new-types/31-P01-SUMMARY.md`
</output>
