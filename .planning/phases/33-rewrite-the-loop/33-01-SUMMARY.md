---
phase: 33-rewrite-the-loop
plan: "01"
subsystem: AgentLoop
tags: [agent-loop, middleware, architecture, bug-fix]
dependency_graph:
  requires: [31-new-types, 32-middleware-system]
  provides: [rewritten-agent-loop]
  affects: [AIService.runAgentLoop]
tech_stack:
  added: []
  patterns: [middleware-chain, prepare-step-hook, typed-tool-results, clean-endTurn]
key_files:
  created: []
  modified:
    - Sources/cellar/Core/AgentLoop.swift
decisions:
  - "LoopState changed from private to file-internal (no access modifier) so PrepareStepHook typealias can reference it"
  - "checkBudgetHalt made async (mutating func) to allow await on final API call — brief showed it as mutating func"
  - "handleAPIError uses state: inout LoopState despite being non-mutating — inout used for text append"
metrics:
  duration: "2 min 14 sec"
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_changed: 1
---

# Phase 33 Plan 01: Rewrite AgentLoop Summary

**One-liner:** Clean 81-line while-loop with middleware hooks, typed ToolResult, and immediate endTurn semantics replacing 280-line monolith with inline budget/spin/tug-of-war logic.

## What Was Built

Rewrote `Sources/cellar/Core/AgentLoop.swift` — the main agent orchestration loop — to use Phase 31 types and Phase 32 middleware. The 280-line monolithic `run()` is replaced by a clean loop calling 4 extracted helpers.

### Changes to AgentLoop.swift

**New types added (before AgentLoop struct):**
- `StepModification` struct with `trimMessages`, `injectMessage`, `maxTokensOverride` fields
- `PrepareStepHook` typealias: `(Int, LoopState) -> StepModification?`

**AgentLoop struct changes:**
- Added `middleware: [AgentMiddleware]` and `prepareStep: PrepareStepHook?` properties
- Updated `init()` with `middleware: []` and `prepareStep: nil` default parameters

**New `run()` signature:**
```swift
mutating func run(
    initialMessage: String,
    toolExecutor: (String, JSONValue) async -> ToolResult,
    control: AgentControl,
    middlewareContext: MiddlewareContext
) async -> AgentLoopResult
```

**Main loop body: 81 lines** (while line 219 to closing brace line 299) — well under the 150-line target.

**4 extracted helpers:**
1. `executeTools()` — appends assistant response, runs middleware beforeTool/afterTool/afterStep hooks, accumulates results
2. `checkBudgetHalt()` — budget 100% halt: inject message, one final API call, return budgetExhausted
3. `handleAPIError()` — format and emit error, return apiError result
4. `handleTruncation()` — three cases: escalate tokens, continuation at ceiling, text-only continuation

### What Was Removed

- `canStop` parameter — gone entirely
- `shouldAbort` closure parameter — replaced by `control.shouldAbort` property
- `consecutiveContinuations` — gone (no more tug-of-war)
- All inline budget tracking vars (`hasAlertedAt50`, `hasWarnedAt80`, `hasSentBudgetWarningMessage`, `hasSentBudgetHalt`) — moved to `BudgetTracker` middleware
- All inline spin detection vars (`recentActionTools`, `hasSentPivotNudge`, `actionTools` Set) — moved to `SpinDetector` middleware
- `estimatedCost()` local function — replaced by `state.estimatedCost` computed property on `LoopState`
- `makeResult()` local function — replaced by `state.makeResult()` on `LoopState`
- The tug-of-war in `.endTurn` case (canStop/consecutiveContinuations forcing continuation) — replaced by immediate return

### Key Behavioral Changes

- **endTurn = done, period.** `case .endTurn:` now returns `state.makeResult(completed: true, stopReason: .completed)` with no conditions.
- **Typed ToolResult.** `result.isStop` replaces `result.contains("\"STOP\": true")` string matching.
- **Middleware hooks.** `beforeTool`, `afterTool`, `afterStep` called in `executeTools()` for composable cross-cutting concerns.
- **prepareStep hook.** Called before each LLM API call for dynamic per-iteration modifications.

## Verification Results

| Check | Result |
|-------|--------|
| `canStop` count | 0 |
| `consecutiveContinuations` count | 0 |
| `hasAlertedAt50` count | 0 |
| `hasSentPivotNudge` count | 0 |
| `run()` has `control: AgentControl` | Yes |
| `run()` has `middlewareContext: MiddlewareContext` | Yes |
| `.endTurn` case count | 1 (immediate return) |
| All 4 helpers exist | Yes |
| Loop body line count | 81 (≤150 target) |
| `LoopState` not private | Yes |

Note: `swift build` is NOT expected to pass — callers in `AIService.runAgentLoop()` still use the old signature. Phase 35 updates callers.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

- [x] `Sources/cellar/Core/AgentLoop.swift` exists and was modified
- [x] Commit `8a0c576` exists: `feat(33-01): rewrite AgentLoop with new run() signature, middleware, and helpers`
- [x] Task 2 required no code changes — verification passed on Task 1's output

## Self-Check: PASSED
