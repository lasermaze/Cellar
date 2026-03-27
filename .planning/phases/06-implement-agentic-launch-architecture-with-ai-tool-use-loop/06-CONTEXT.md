# Phase 6: Implement agentic launch architecture with AI tool-use loop - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning
**Source:** PRD Express Path (.planning/agentic-architecture.md)

<domain>
## Phase Boundary

Replace the ~500-line hardcoded pipeline in `LaunchCommand.swift` with an AI agent loop that has tools to inspect, configure, launch, and diagnose Wine games. The agent drives the entire process — no fixed escalation levels, no hardcoded retry logic. Delivers: agent loop core, 10 tools, system prompt, guardrails, and graceful degradation.

</domain>

<decisions>
## Implementation Decisions

### Architecture
- Replace hardcoded `LaunchCommand.run()` pipeline with ~50-line agent loop calling `AIService.runAgentLoop()`
- AI drives the entire process via tool-use API — no fixed escalation levels
- Agent loop: send messages → execute tools → send results → repeat until `end_turn` or max iterations
- Graceful degradation: if no API key, fall back to recipe-only launch (no agent)

### API Types
- Add `JSONValue` recursive Codable enum for arbitrary JSON (tool schemas)
- Add `MessageContent` — either plain string or array of content blocks
- Add `ContentBlock` — tagged union: `.text(String)`, `.toolUse(id, name, input)`, `.toolResult(toolUseId, content, isError)`
- Add `ToolDefinition` — `name`, `description`, `inputSchema: JSONValue`
- Extend request/response types with `tools` array, `stopReason`, and `ContentBlock` array

### Diagnostic Tools (read-only, safe)
- `inspect_game` — game metadata: exe type (PE32/PE32+), imports, game files, bottle state, installed DLLs, recipe
- `read_log` — Wine launch log (last 8000 chars stderr)
- `read_registry` — read Wine registry values from user.reg/system.reg files directly
- `ask_user` — ask user questions with optional multiple-choice options

### Action Tools (modify state)
- `set_environment` — accumulate Wine env vars for next launch
- `set_registry` — write Wine registry values
- `install_winetricks` — install winetricks verb (validated against allowlist, 5-min timeout)
- `place_dll` — download and place known DLL from KnownDLLRegistry only

### Execution Tools
- `launch_game` — run Wine process with accumulated environment, return structured result with exit code, elapsed time, stderr tail, detected errors; supports extra `winedebug` channels
- `save_recipe` — persist working configuration as recipe file

### System Prompt
- Wine compatibility expert persona on macOS
- Methodical workflow: inspect → configure → launch → ask user → diagnose → save recipe
- Key domain knowledge baked in (cnc-ddraw, DirectDraw, virtual desktop, etc.)
- Max 8 launch attempts constraint in prompt

### Guardrails
- Max iterations: 20 tool calls (prevents runaway loops)
- Max launches: 8 game launches per session
- Winetricks allowlist: only known-safe verbs
- DLL allowlist: only KnownDLLRegistry entries
- Sandbox: all file operations restricted to game bottle + ~/.cellar/
- Cost control: consider model selection per game complexity

### Code Reuse
- `WineProcess` → powers `launch_game`
- `WineActionExecutor` → powers `set_environment`, `set_registry`, `place_dll`, `install_winetricks`
- `DLLDownloader` → powers `place_dll`
- `WinetricksRunner` → powers `install_winetricks`
- `RecipeEngine` → powers `save_recipe` and initial recipe loading in `inspect_game`
- `WineErrorParser` → optionally enriches `launch_game` output
- `CellarStore` → game entry lookup in `inspect_game`
- `BottleManager` → bottle existence check in `inspect_game`
- `ValidationPrompt` → replaced by `ask_user` tool

### Claude's Discretion
- Internal code organization (separate file per tool vs grouped)
- Error handling strategy within tool implementations
- Exact streaming/terminal output approach during agent loop
- How to structure the agent loop state machine
- Whether to keep WineErrorParser as enrichment or let agent reason from raw stderr
- Token/cost optimization strategies

</decisions>

<specifics>
## Specific Ideas

- Tool input/output schemas are fully specified in the architecture doc
- `inspect_game` uses `file` command on exe to determine PE32/PE32+ type
- `read_registry` reads from reg files directly — no Wine process needed
- `set_environment` accumulates vars across multiple calls
- `launch_game` can accept `extra_winedebug` for diagnostic channels like `+loaddll`
- `place_dll` auto-refuses unknown DLLs with message
- Agent constructs recipe from what actually worked (vs rigid structure)
- `save_recipe` called by agent when game confirmed working

</specifics>

<deferred>
## Deferred Ideas

- Model selection per game complexity (sonnet for simple games, opus for complex)
- TUI improvements (deferred to v2 per existing project decision)

</deferred>

---

*Phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop*
*Context gathered: 2026-03-27 via PRD Express Path*
