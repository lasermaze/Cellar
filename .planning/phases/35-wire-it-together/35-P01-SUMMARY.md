---
phase: 35-wire-it-together
plan: P01
subsystem: agent-loop
tags: [agent-loop, rewrite, architecture, wiring, compilation-fix]
dependency_graph:
  requires: [31-new-types, 32-middleware-system, 33-rewrite-the-loop, 34-update-agenttools]
  provides: [compilable-codebase, end-to-end-agent-loop]
  affects: [AIService, LaunchController, LaunchTools, SaveTools]
tech_stack:
  added: []
  patterns: [AgentControl thread-safe abort/confirm, middleware chain, post-loop save, AgentEventLog JSONL]
key_files:
  created: []
  modified:
    - Sources/cellar/Web/Controllers/LaunchController.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/Tools/LaunchTools.swift
    - Sources/cellar/Core/Tools/SaveTools.swift
decisions:
  - "if case pattern matching used for AgentStopReason equality checks — enum has associated values, no Equatable conformance"
  - "isCompleted local bool derived via if case .completed = result.stopReason to avoid repeated pattern match"
metrics:
  duration: ~2 min
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_modified: 4
---

# Phase 35 Plan P01: Wire It Together Summary

**One-liner:** Wired all Phase 31-34 pieces (AgentControl, MiddlewareContext, AgentEventLog, new AgentLoop.run() signature) into AIService and LaunchController so `swift build` passes with zero errors.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Update LaunchController and fix stale tool file references | 71056b1 | LaunchController.swift, LaunchTools.swift, SaveTools.swift |
| 2 | Rewrite AIService.runAgentLoop() to use new architecture | 20030be | AIService.swift |

## What Was Built

**Task 1 — LaunchController + tool files:**
- `ActiveAgents` now stores `[String: AgentControl]` alongside `[String: AgentTools]`; renamed `get()` to `getTools()`, added `getControl()`; `register()` takes both tools and control; `remove()` cleans both dicts
- Stop route: `ActiveAgents.shared.getControl(gameId: gameId)?.abort()` — replaces `tools.shouldAbort = true`
- Confirm route: `ActiveAgents.shared.getControl(gameId: gameId)?.confirm()` — replaces `tools.userForceConfirmed = true`
- `onToolsCreated` callback updated to `(AgentTools, AgentControl) -> Void`
- `LaunchTools`: removed `taskState = .exhausted`, `taskState = .userConfirmedOk`, `taskState = .working` assignments
- `SaveTools`: removed `if taskState == .userConfirmedOk { taskState = .savedAfterConfirm }` block

**Task 2 — AIService.runAgentLoop():**
- `onToolsCreated` parameter updated to `((AgentTools, AgentControl) -> Void)? = nil`
- Creates `AgentControl()`, sets `tools.control = control`, calls `onToolsCreated?(tools, control)`
- Creates `AgentEventLog(gameId:)` and appends `sessionStarted` entry
- Creates `MiddlewareContext(control:budgetCeiling:)`
- Creates middleware chain: `[BudgetTracker, SpinDetector, EventLogger]`
- `AgentLoop` initialized with `middleware:` and `prepareStep: nil`
- `agentLoop.run()` called with new 4-arg signature: `initialMessage:toolExecutor:control:middlewareContext:`
- Post-loop save: `if case .userConfirmed = result.stopReason` → `await tools.execute("save_success", ...)` — no fire-and-forget `Task.detached`
- `handleContributionIfNeeded` guard on `taskState` removed — function only called when `didSave == true`
- Session end logged: `eventLog.append(.sessionEnded(reason:iterations:cost:))`
- `userAborted` handled as early return (no handoff written)

## Verification Results

1. `swift build` — **PASS** (Build complete, 0 errors)
2. No `tools.shouldAbort`, `tools.userForceConfirmed`, `tools.taskState`, or `canStop.*isTaskComplete` in Sources — **PASS**
3. No `Task.detached.*save_success` in AIService.swift — **PASS**
4. Stop/confirm routes use `getControl()?.abort()` / `getControl()?.confirm()` — **PASS**
5. AIService contains `AgentEventLog`, `MiddlewareContext`, `BudgetTracker`, `SpinDetector`, `EventLogger` — **PASS**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] AgentStopReason enum has no Equatable conformance**
- **Found during:** Task 2, first swift build attempt
- **Issue:** Plan used `result.stopReason == .userConfirmed` but `AgentStopReason` has `apiError(String)` with associated value — Swift cannot synthesize `==` for such enums
- **Fix:** Used `if case .userConfirmed = result.stopReason` pattern matching throughout; extracted `isCompleted` bool via `if case .completed = result.stopReason`
- **Files modified:** Sources/cellar/Core/AIService.swift
- **Commit:** 20030be (within Task 2 commit)

## Self-Check: PASSED

Files confirmed present:
- Sources/cellar/Web/Controllers/LaunchController.swift ✓
- Sources/cellar/Core/AIService.swift ✓
- Sources/cellar/Core/Tools/LaunchTools.swift ✓
- Sources/cellar/Core/Tools/SaveTools.swift ✓

Commits confirmed:
- 71056b1 ✓
- 20030be ✓
