---
phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
plan: "03"
subsystem: launch-command
tags: [agent-loop, launch-command, ai-service, graceful-degradation, wine-expert]
dependency_graph:
  requires: ["06-01", "06-02"]
  provides: ["agentic-cellar-launch", "recipe-fallback-launch"]
  affects: ["LaunchCommand", "AIService"]
tech_stack:
  added: []
  patterns: ["agent-handoff", "graceful-degradation", "recipe-fallback"]
key_files:
  created: []
  modified:
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Commands/LaunchCommand.swift
decisions:
  - "Agent loop is Anthropic-only — OpenAI tool-use API differs; .openai returns .unavailable"
  - "do/catch not needed around AgentLoop.run() — it never throws (errors returned in AgentLoopResult)"
  - "recipeFallbackLaunch is mutating (calls CellarStore.updateGame with inout entry) — must be private mutating func"
  - "Executable path resolution preserved in run() before agent/fallback split — both paths need it"
metrics:
  duration: "5min"
  completed: "2026-03-27"
  tasks: 2
  files: 2
---

# Phase 06 Plan 03: Final Wiring — Agent Handoff and Graceful Degradation Summary

**One-liner:** Replaced ~500-line LaunchCommand retry pipeline with ~80-line agent handoff to AIService.runAgentLoop(), with recipeFallbackLaunch() as the no-key path.

## What Was Built

### Task 1: AIService.runAgentLoop()

New static method added to `AIService` that:
- Accepts all game context needed by AgentTools: gameId, entry, executablePath, wineURL, bottleURL, wineProcess
- Returns `.unavailable` for non-Anthropic providers (OpenAI or no key)
- Constructs `AgentTools` + `AgentLoop` with claude-sonnet-4-20250514, maxIterations=20, maxTokens=4096
- Passes a Wine expert system prompt encoding the inspect->configure->launch->diagnose->save_recipe workflow
- Includes domain knowledge: DirectDraw/cnc-ddraw, virtual desktop mode, DLL override syntax, WINE_CPU_TOPOLOGY
- Returns `.success(result.finalText)` when the agent loop completes

### Task 2: LaunchCommand Refactor

`LaunchCommand.run()` reduced from ~500 lines to ~80 lines:
- Steps 1-4 preserved: dependency check, find game, check bottle, resolve executable path
- Step 5: calls AIService.runAgentLoop() and switches on result
  - `.success`: prints agent summary, updates lastLaunched, returns
  - `.unavailable`: prints "No AI API key configured", calls recipeFallbackLaunch()
  - `.failed`: prints agent error, calls recipeFallbackLaunch()

`recipeFallbackLaunch()` private mutating method (~50 lines):
- Loads bundled recipe, applies it (env vars, winetricks)
- Prepares log file, sets up SIGINT handler (wineserver -k pattern)
- Launches via wineProcess.run()
- Cancels SIGINT handler
- Runs ValidationPrompt.run() for user feedback
- Records result in entry.lastResult, calls CellarStore.updateGame()

## Deviations from Plan

None — plan executed exactly as written.

The plan showed an explicit do/catch around agentLoop.run() but AgentLoop.run() does not throw (errors are captured in AgentLoopResult). The implementation omits the do/catch, which is correct behavior.

## Verification

1. `swift build` passes — Build complete with no errors (2 warnings in unrelated files)
2. LaunchCommand.run() is ~80 lines (plan spec was ~50-70; delta is acceptable, legacy path resolution preserved)
3. AIService.runAgentLoop() exists and constructs AgentLoop + AgentTools — confirmed via grep
4. System prompt contains Wine domain knowledge (DirectDraw, virtual desktop, DLL overrides, WINE_CPU_TOPOLOGY)
5. Graceful degradation: .unavailable triggers recipeFallbackLaunch — confirmed in switch case
6. Agent failure: .failed also triggers recipeFallbackLaunch — confirmed in switch case
7. All existing AIService methods (diagnose, generateRecipe, generateVariants) still present — confirmed
8. ValidationPrompt.swift still exists for fallback path — confirmed

## Commits

- `87030dd` feat(06-03): add AIService.runAgentLoop() with Wine expert system prompt
- `0b558a5` feat(06-03): refactor LaunchCommand to use agent loop with graceful degradation

## Self-Check: PASSED
