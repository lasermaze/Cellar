# Agentic Cellar Architecture

## Overview

Replace the 500-line hardcoded pipeline in `LaunchCommand.swift` with an AI agent loop that has tools to inspect, configure, launch, and diagnose Wine games. The agent drives the entire process — no fixed escalation levels, no hardcoded retry logic.

## Architecture

```
User runs: cellar launch <game>
         |
         v
  ┌─────────────────────┐
  │  Gather Context      │  (game info, bottle state, recipe, exe metadata)
  │  Build system prompt │
  └──────────┬──────────┘
             v
  ┌─────────────────────────────────────────┐
  │           AGENT LOOP                     │
  │                                          │
  │  Claude sees: game context + tools       │
  │  Claude decides: what to try             │
  │  Claude calls: tools                     │
  │  Claude observes: results                │
  │  Claude adapts: based on what happened   │
  │                                          │
  │  Loop until: end_turn OR max iterations  │
  └─────────────────────────────────────────┘
             |
             v
  Agent returns: summary + saved recipe (if success)
```

## Tool Set (10 tools)

### Diagnostic Tools (read-only, safe)

#### 1. `inspect_game`
Get game metadata without launching.

```
Input:  { game_id: string }
Output: { exe_type: "PE32"|"PE32+", imports: ["ddraw.dll","kernel32.dll",...],
          game_files: ["dmln.exe","dmcr.exe","Cossacks.ini",...],
          bottle_exists: bool, bottle_contents: [...],
          installed_dlls: ["ddraw.dll",...], recipe: {...} | null }
```

Uses `file` command on exe, scans game dir, checks bottle state. Gives agent full situational awareness upfront.

#### 2. `read_log`
Read a Wine launch log.

```
Input:  { game_id: string, log_index?: int }  // 0 = latest
Output: { stderr: string (last 8000 chars), full_path: string }
```

#### 3. `read_registry`
Read Wine registry values.

```
Input:  { game_id: string, key_path: string }
Output: { values: { name: data, ... } }
```

Reads from `user.reg` / `system.reg` files directly (no Wine process needed).

#### 4. `ask_user`
Ask the user a question.

```
Input:  { question: string, options?: [string] }
Output: { answer: string }
```

For validation ("Did the game reach the menu?") and gathering info ("What did you see?"). Agent decides when and what to ask.

### Action Tools (modify state)

#### 5. `set_environment`
Set Wine environment variables for next launch.

```
Input:  { vars: { key: value, ... } }
Output: { applied: [key, ...] }
```

Accumulates into the next launch config. Agent can call multiple times.

#### 6. `set_registry`
Write Wine registry values.

```
Input:  { game_id: string, key_path: string, values: { name: data, ... } }
Output: { success: bool, error?: string }
```

#### 7. `install_winetricks`
Install a winetricks verb.

```
Input:  { game_id: string, verb: string }
Output: { success: bool, output: string, elapsed_seconds: number }
```

Validates against allowlist. Has 5-minute timeout.

#### 8. `place_dll`
Download and place a known DLL.

```
Input:  { dll_name: string, target: "game_dir"|"system32", game_id: string }
Output: { success: bool, placed_path?: string, error?: string }
```

Only allows DLLs from KnownDLLRegistry. Refuses unknown DLLs with message.

### Execution Tools

#### 9. `launch_game`
Launch the game with current config.

```
Input:  { game_id: string, extra_winedebug?: string }
Output: { exit_code: int, elapsed_seconds: number, timed_out: bool,
          stderr_tail: string (last 4000 chars),
          detected_errors: [{ category, detail, suggested_fix? }] }
```

Runs Wine process with accumulated environment. Streams output to terminal + log. Returns structured result. The agent can add debug channels (e.g., `+loaddll`) to get more diagnostic info.

#### 10. `save_recipe`
Persist the working configuration.

```
Input:  { game_id: string, description: string, environment: {...}, actions: [...] }
Output: { saved_path: string }
```

Agent calls this when the game works. Creates/updates the recipe file.

## System Prompt

```
You are a Wine compatibility expert running on macOS. Your job is to get
a Windows game launching successfully via Wine.

You have tools to inspect the game, configure Wine, and launch the game.
Work methodically:

1. INSPECT first — understand what game this is, what DLLs it imports,
   what's in the bottle, whether a recipe exists.
2. CONFIGURE — set environment variables, registry keys, place DLLs,
   install dependencies based on what you learned.
3. LAUNCH — run the game and observe the results.
4. ASK the user if the game reached the menu.
5. If it didn't work, read the log, diagnose, adjust, and try again.
6. When it works, SAVE the recipe for reuse.

Key knowledge:
- Pre-2000 games often need cnc-ddraw + ddraw=n,b + WINE_CPU_TOPOLOGY=1:0
- DirectDraw Init Failed = needs cnc-ddraw or virtual desktop
- Missing DLLs = winetricks verb or DLL override
- NtUserChangeDisplaySettings returning -2 = try virtual desktop (WINE_VD)
- GL_INVALID_FRAMEBUFFER_OPERATION = wined3d issue, try registry Direct3D settings
- Always check exe imports before guessing — ddraw.dll in imports = DirectDraw game

Constraints:
- Max 8 launch attempts
- Only install winetricks verbs from the known list
- Only place DLLs from the known registry (cnc-ddraw)
- Never modify files outside the game's bottle and ~/.cellar/
```

## What Changes vs Current Code

| Current | Agentic |
|---------|---------|
| 500-line `LaunchCommand.run()` with hardcoded loop | ~50-line agent loop calling `AIService.runAgentLoop()` |
| AI called at 2 fixed points | AI drives the entire process |
| 3 hardcoded escalation levels | Agent reasons about what to try |
| `WineErrorParser` hardcoded patterns | Agent reads stderr directly and reasons |
| Fixed validation prompt timing | Agent decides when to ask the user |
| Can't add `+loaddll` debug mid-run | Agent can add debug channels and re-launch |
| Recipe structure rigid | Agent constructs recipe from what worked |
| Can't inspect exe imports | `inspect_game` tool gives full context upfront |
| Can't read registry before acting | `read_registry` tool lets agent check current state |

## Implementation Plan

1. **Add `JSONValue` enum** — recursive Codable type for arbitrary JSON (needed for tool schemas)
2. **Add tool-use API types** — `AnthropicToolRequest`, `AnthropicToolResponse`, `ContentBlock` with tool_use/tool_result variants
3. **Add `AgentLoop`** — the core loop: send messages → execute tools → send results → repeat
4. **Implement 10 tools** — each as a function `(input) -> String`, most reusing existing code (WineProcess, WineActionExecutor, DLLDownloader, etc.)
5. **Replace `LaunchCommand.run()`** — gather context, build system prompt, call agent loop
6. **Add guardrails** — max iterations, tool allowlists, sandboxing to bottle

## Code Reuse

The existing infrastructure stays — it becomes tool implementations instead of pipeline stages:

- `WineProcess` → powers `launch_game` tool
- `WineActionExecutor` → powers `set_environment`, `set_registry`, `place_dll`, `install_winetricks` tools
- `DLLDownloader` → powers `place_dll` tool
- `WinetricksRunner` → powers `install_winetricks` tool
- `RecipeEngine` → powers `save_recipe` tool and initial recipe loading in `inspect_game`
- `WineErrorParser` → optionally used inside `launch_game` to enrich output (but agent can also reason from raw stderr)
- `CellarStore` → game entry lookup in `inspect_game`
- `BottleManager` → bottle existence check in `inspect_game`
- `ValidationPrompt` → replaced by `ask_user` tool (more flexible)

## API Details

### Anthropic Tool Use API Contract

**Request:** Add `tools` array to Messages API request. Each tool has `name`, `description`, `input_schema` (JSON Schema).

**Response:** When Claude wants to call tools, `stop_reason` is `"tool_use"` and `content` array contains `tool_use` blocks with `id`, `name`, `input`.

**Result:** Send back `tool_result` blocks in a `user` message, referencing `tool_use_id`.

**Loop:** Continue while `stop_reason == "tool_use"`. Exit on `"end_turn"`.

### Swift Types Needed

- `JSONValue` — recursive Codable enum for arbitrary JSON
- `MessageContent` — either a plain string or array of content blocks
- `ContentBlock` — tagged union: `.text(String)`, `.toolUse(id, name, input)`, `.toolResult(toolUseId, content, isError)`
- `ToolDefinition` — `name`, `description`, `inputSchema: JSONValue`
- `AnthropicToolRequest` — extends current request with `tools` array and heterogeneous `content`
- `AnthropicToolResponse` — extends current response with `stopReason` and `ContentBlock` array

## Guardrails

- **Max iterations:** 20 tool calls (prevents runaway loops)
- **Max launches:** 8 game launches per session
- **Winetricks allowlist:** Only known-safe verbs
- **DLL allowlist:** Only KnownDLLRegistry entries
- **Sandbox:** All file operations restricted to game bottle + ~/.cellar/
- **Cost control:** Agent loop uses claude-opus-4-6 (powerful but expensive); consider sonnet for simpler games
- **Graceful degradation:** If no API key, fall back to recipe-only launch (no agent)
