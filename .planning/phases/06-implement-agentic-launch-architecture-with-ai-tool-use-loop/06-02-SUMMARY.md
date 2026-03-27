---
phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
plan: 02
subsystem: ai
tags: [swift, agent, tool-use, wine, json-schema]

# Dependency graph
requires:
  - phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
    provides: AgentLoop state machine, JSONValue, ToolDefinition, ToolContentBlock types

provides:
  - AgentTools class with all 10 tool implementations
  - Static toolDefinitions array with JSON Schema inputSchema for each tool
  - execute() dispatch method routing tool names to implementations
  - Diagnostic tools: inspect_game, read_log, read_registry, ask_user
  - Action tools: set_environment, set_registry, install_winetricks, place_dll
  - Execution tools: launch_game, save_recipe
  - AIService.agentValidWinetricksVerbs public extension for shared allowlist

affects:
  - 06-03 (LaunchCommand integration wiring AgentTools into AgentLoop)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "class (reference type) for mutable state accumulation across tool calls (vs struct)"
    - "All tool methods return String (JSON), never throw — agent loop always gets a result"
    - "jsonResult([String:Any]) helper using JSONSerialization for uniform output encoding"
    - "AIService extension exposes agentValidWinetricksVerbs as public static for shared allowlist"
    - "WINEDLLOVERRIDES accumulation: append with semicolon separator, not replace"

key-files:
  created:
    - Sources/cellar/Core/AgentTools.swift
  modified: []

key-decisions:
  - "AgentTools is a class not struct — mutable state (accumulatedEnv, launchCount, installedDeps, lastLogFile) must persist across tool calls within one agent session"
  - "All tool implementations catch errors internally and return JSON error strings — the agent loop contract is String return, never throw"
  - "AIService.agentValidWinetricksVerbs added as public extension rather than duplicating the private validWinetricksVerbs — single source of truth"
  - "readRegistry normalizes HKCU/HKLM abbreviations to HKEY_CURRENT_USER/HKEY_LOCAL_MACHINE before searching .reg file section headers"
  - "place_dll applies requiredOverrides by appending to accumulatedEnv WINEDLLOVERRIDES with semicolon, not replacing"
  - "inspectGame uses /usr/bin/file via Process to detect PE32/PE32+ type — no dependency on external libraries"
  - "save_recipe includes installedDeps as setupDeps in the persisted Recipe — captures the full working configuration"

patterns-established:
  - "Tool dispatch: execute(toolName:input:) -> String with switch, never throws"
  - "State accumulation: accumulatedEnv[key] = value on set_environment, appended with semicolon on place_dll overrides"
  - "Registry reading: detect hive from prefix, open appropriate .reg file, scan for section header, parse value= lines"

requirements-completed: []

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 06 Plan 02: Agent Tools Implementation Summary

**10 Wine agent tools wrapping existing infrastructure — inspect, diagnose, configure, and launch games via AgentTools.execute() dispatch into AgentLoop**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-27T22:37:11Z
- **Completed:** 2026-03-27T22:39:51Z
- **Tasks:** 2 (implemented together in one file)
- **Files modified:** 1

## Accomplishments

- Implemented all 10 agent tool definitions with correct JSON Schema inputSchema objects
- Implemented all 10 tool methods: 4 diagnostic (inspect_game, read_log, read_registry, ask_user), 4 action (set_environment, set_registry, install_winetricks, place_dll), 2 execution (launch_game, save_recipe)
- Mutable session state (accumulatedEnv, launchCount, installedDeps, lastLogFile) accumulates correctly across tool calls
- All tools return JSON strings, never throw — safe for agent loop consumption
- Reused all existing infrastructure (WineProcess, WinetricksRunner, DLLDownloader, RecipeEngine, WineErrorParser) without modification

## Task Commits

1. **Tasks 1+2: AgentTools class with all 10 tool definitions and implementations** - `5ac18b4` (feat)

**Plan metadata:** (added in final commit)

## Files Created/Modified

- `Sources/cellar/Core/AgentTools.swift` - AgentTools class with 10 tool definitions, execute() dispatch, and all implementations; AIService.agentValidWinetricksVerbs extension

## Decisions Made

- AgentTools is a class (reference type) so mutable state persists across tool calls in the agent loop closure
- All tool methods catch errors internally and return `jsonResult(["error": ...])` — the agent loop always receives a String
- AIService.agentValidWinetricksVerbs exposed as a public extension rather than duplicating the existing private set
- readRegistry normalizes HKCU/HKLM abbreviations to full HKEY_ form before matching .reg file section headers
- place_dll appends requiredOverrides to WINEDLLOVERRIDES with semicolon rather than replacing the existing value

## Deviations from Plan

None - plan executed exactly as written. One compile error was fixed inline (optional binding on non-Optional Recipe return from findBundledRecipe, and an unused variable in installWinetricks).

## Issues Encountered

- `RecipeEngine.findBundledRecipe` returns `Recipe?` but the call pattern `if let recipe = try? ..., let r = recipe` is invalid since `try?` already unwraps to Optional. Fixed inline to `if let recipe = try? ...` directly.
- Unused `stderrTail` variable in installWinetricks removed.

## Next Phase Readiness

- AgentTools is ready for wiring into LaunchCommand as the tool executor for AgentLoop
- Plan 06-03 will integrate AgentTools with AgentLoop in LaunchCommand, providing the full agentic launch flow
- No blockers

---
*Phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop*
*Completed: 2026-03-27*
