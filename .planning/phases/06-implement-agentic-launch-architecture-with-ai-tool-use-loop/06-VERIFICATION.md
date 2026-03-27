---
phase: 06-implement-agentic-launch-architecture-with-ai-tool-use-loop
verified: 2026-03-27T23:30:00Z
status: passed
score: 12/12 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run `cellar launch cossacks-european-wars` with ANTHROPIC_API_KEY set"
    expected: "Agent loop starts, calls inspect_game, prints 'Agent: ...' text blocks and '-> inspect_game' tool call prefix, asks user questions, attempts launches, saves recipe on success"
    why_human: "Requires runtime Anthropic API key and a working Wine bottle — cannot verify agent conversation flow programmatically"
  - test: "Run `cellar launch cossacks-european-wars` without any API key set"
    expected: "Prints 'No AI API key configured. Launching with recipe defaults only.' and runs recipe fallback path with ValidationPrompt"
    why_human: "Requires runtime environment and Wine installation"
---

# Phase 6: Implement Agentic Launch Architecture with AI Tool-Use Loop — Verification Report

**Phase Goal:** Replace the ~500-line hardcoded LaunchCommand pipeline with an AI agent loop that has tools to inspect, configure, launch, and diagnose Wine games — no fixed escalation levels, no hardcoded retry logic. Graceful degradation to recipe-only launch when no API key is set.
**Verified:** 2026-03-27T23:30:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | JSONValue can round-trip arbitrary JSON (strings, numbers, bools, nulls, arrays, nested objects) through Codable encode/decode | VERIFIED | `indirect enum JSONValue: Codable, Equatable` at AIModels.swift:142; Bool decoded before Double (critical ordering) per comment at line 153-156 |
| 2 | ContentBlock (ToolContentBlock) encodes/decodes text, tool_use, and tool_result blocks correctly with Anthropic API field names | VERIFIED | `enum ToolContentBlock: Codable` at AIModels.swift:225; CodingKeys map `tool_use_id`, `is_error`; is_error only encoded when true |
| 3 | AnthropicToolRequest encodes tools array with input_schema as JSON Schema objects (not double-encoded strings) | VERIFIED | `struct AnthropicToolRequest: Encodable` at AIModels.swift:334; `struct ToolDefinition: Encodable` with `inputSchema = "input_schema"` CodingKey at line 327 |
| 4 | AgentLoop sends messages, receives tool_use responses, executes tool functions, returns tool_result blocks, and terminates on end_turn or max iterations | VERIFIED | AgentLoop.swift:64 `func run()`; end_turn case at line 98; tool_use case at line 105-121; max iterations guard at line 76; completed:true only on end_turn |
| 5 | inspect_game returns exe type (PE32/PE32+), game directory listing, bottle state, installed DLLs, and recipe info | VERIFIED | AgentTools.swift:278 `inspectGame()`; uses `/usr/bin/file`, FileManager contentsOfDirectory, RecipeEngine.findBundledRecipe |
| 6 | read_log returns the last 8000 chars of Wine stderr from the most recent log file | VERIFIED | AgentTools.swift:360 `readLog()`; `content.suffix(8000)` at line 393; scans CellarPaths.logDir for most recent if lastLogFile is nil |
| 7 | read_registry reads Wine registry values directly from user.reg/system.reg files | VERIFIED | AgentTools.swift:399 `readRegistry()`; hive detection for HKCU/HKLM, normalizeRegistryKey() expands abbreviations, UTF-8/CP1252 fallback |
| 8 | ask_user prompts the user with a question (optionally multiple-choice) and returns their answer | VERIFIED | AgentTools.swift:516 `askUser()`; print to stdout, numbered options, readLine() |
| 9 | set_environment accumulates Wine env vars across multiple calls; set_registry writes via wine regedit; install_winetricks validates allowlist; place_dll uses KnownDLLRegistry only | VERIFIED | Lines 542-700: accumulatedEnv[key]=value; .reg temp file + applyRegistryFile; AIService.agentValidWinetricksVerbs check; KnownDLLRegistry.find() guard |
| 10 | launch_game runs Wine with accumulated env, respects max 8 launches, returns structured result with exit code, elapsed, stderr tail, detected errors | VERIFIED | AgentTools.swift:707 `launchGame()`; launchCount >= maxLaunches guard; WineErrorParser.parse; stderr.suffix(4000) |
| 11 | cellar launch with ANTHROPIC_API_KEY invokes agent loop; without API key falls back to recipe-only single launch | VERIFIED | LaunchCommand.swift:51 switch on AIService.runAgentLoop(); .unavailable branch at line 66 calls recipeFallbackLaunch(); .failed branch at line 77 also falls back |
| 12 | Agent has a Wine expert system prompt guiding methodical inspect-configure-launch-diagnose workflow | VERIFIED | AIService.swift:510-540: system prompt contains Workflow (7 steps), Key Domain Knowledge, Constraints, Communication sections |

**Score:** 12/12 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Models/AIModels.swift` | JSONValue, MessageContent, ToolContentBlock, ToolDefinition, AnthropicToolRequest, AnthropicToolResponse types | VERIFIED | All 6 new types present alongside unchanged existing types (AnthropicRequest, AnthropicResponse, AIProvider, AIResult, etc.) |
| `Sources/cellar/Core/AgentLoop.swift` | AgentLoop struct with send-execute-return cycle | VERIFIED | 223 lines; struct AgentLoop at line 27; AgentLoopResult struct at line 6; private callAnthropic + callAPI methods |
| `Sources/cellar/Core/AgentTools.swift` | 10 tool implementations, static toolDefinitions array, execute() dispatch | VERIFIED | 857 lines; final class AgentTools at line 9; static toolDefinitions with 10 ToolDefinition entries; execute() dispatch at line 245 with all 10 cases |
| `Sources/cellar/Commands/LaunchCommand.swift` | Refactored ~50-line run() with agent handoff and graceful degradation | VERIFIED | 153 lines total (run() body ~87 lines including recipeFallbackLaunch at line 94); AIService.runAgentLoop() call at line 51 |
| `Sources/cellar/Core/AIService.swift` | runAgentLoop static method, agent system prompt | VERIFIED | runAgentLoop() at line 496; constructs AgentTools + AgentLoop; system prompt at lines 510-540 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `AgentLoop.swift` | `AIModels.swift` | Uses AnthropicToolRequest, AnthropicToolResponse, ToolContentBlock, ToolDefinition, JSONValue | WIRED | Line 73: AnthropicToolRequest.Message; line 80: AnthropicToolResponse; line 110-115: ToolContentBlock.toolUse/.toolResult |
| `AgentLoop.swift` | `AIService.swift` | Uses AIService HTTP pattern (independent private callAPI, not shared) | WIRED | AgentLoop has its own private callAPI (lines 178-202) mirroring AIService pattern per plan decision |
| `AgentTools.swift` | `WineProcess.swift` | launch_game calls wineProcess.run() | WIRED | AgentTools.swift:740 `wineProcess.run(binary: executablePath, ...)` |
| `AgentTools.swift` | `WineActionExecutor` pattern | set_registry uses wineProcess.applyRegistryFile | WIRED | AgentTools.swift:581 `wineProcess.applyRegistryFile(at: tempFile)` |
| `AgentTools.swift` | `WinetricksRunner.swift` | install_winetricks creates WinetricksRunner and calls install(verb:) | WIRED | AgentTools.swift:618-625 `WinetricksRunner(...)` + `runner.install(verb:)` |
| `AgentTools.swift` | `DLLDownloader.swift` | place_dll calls DLLDownloader.downloadAndCache + place | WIRED | AgentTools.swift:677-678 `DLLDownloader.downloadAndCache(knownDLL)` + `.place(cachedDLL:into:)` |
| `AgentTools.swift` | `RecipeEngine.swift` | save_recipe calls RecipeEngine.saveUserRecipe(); inspect_game calls findBundledRecipe | WIRED | AgentTools.swift:336 `RecipeEngine.findBundledRecipe(for:)` and line 822 `RecipeEngine.saveUserRecipe(recipe)` |
| `LaunchCommand.swift` | `AIService.swift` | Calls AIService.runAgentLoop() | WIRED | LaunchCommand.swift:51 `AIService.runAgentLoop(...)` |
| `AIService.swift` | `AgentLoop.swift` | Creates AgentLoop instance and calls run() | WIRED | AIService.swift:551-565 `AgentLoop(...)` + `agentLoop.run(...)` |
| `AIService.swift` | `AgentTools.swift` | Creates AgentTools and passes execute as toolExecutor | WIRED | AIService.swift:542-564 `AgentTools(...)` + `tools.execute(toolName: name, input: input)` |

### Requirements Coverage

No formal requirement IDs are claimed by this phase. All three plans declare `requirements: []`. This is documented in ROADMAP.md as "Requirements: None (INSERTED phase — extends existing launch architecture)". No orphaned requirements found in REQUIREMENTS.md for phase 06.

### Anti-Patterns Found

No anti-patterns detected in phase files. Scan results:

- No TODO/FIXME/XXX/HACK/PLACEHOLDER comments in any phase file
- No empty implementations (return null, return {}, return [])
- No stub handlers or console.log-only implementations
- No "Not implemented" placeholders

### Human Verification Required

#### 1. Agent Loop Live Session

**Test:** Run `cellar launch <game>` with `ANTHROPIC_API_KEY` set pointing to a valid Anthropic key, with a game bottle already present.
**Expected:** Agent prints `Agent: ` prefixed thinking text, `-> inspect_game` tool call prefix, prompts user questions via ask_user, makes multiple launch attempts as needed, saves recipe on success. Max 20 iterations and 8 launches enforced.
**Why human:** Requires live API key, running Wine installation, and an actual game bottle. The conversation flow and correctness of AI reasoning cannot be verified statically.

#### 2. Graceful Degradation

**Test:** Run `cellar launch <game>` with no `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` set.
**Expected:** Prints "No AI API key configured. Launching with recipe defaults only." then runs recipe fallback path, calls ValidationPrompt at end.
**Why human:** Requires runtime Wine environment to exercise the actual fallback launch path.

---

## Verification Summary

All 12 must-have truths are verified against the actual codebase, not SUMMARY claims. The phase goal is fully achieved:

**Replaced hardcoded pipeline:** LaunchCommand.swift is now 153 lines (run() body ~87 lines) versus the ~500-line original. The old retry loop, escalation levels, and hardcoded repair logic are gone — replaced by the AIService.runAgentLoop() handoff at line 51.

**AI agent loop implemented:** AgentLoop.swift drives a clean send-execute-return cycle against the Anthropic tool-use API. AnthropicToolRequest/AnthropicToolResponse/ToolContentBlock types in AIModels.swift handle the full protocol.

**10 tools operational:** AgentTools.swift wraps all existing infrastructure (WineProcess, WinetricksRunner, DLLDownloader, RecipeEngine, WineErrorParser) — no new Wine code added. All tools return JSON strings, never throw.

**Guardrails enforced in code:** maxIterations=20 (AgentLoop), maxLaunches=8 (AgentTools.launchCount), winetricks allowlist (AIService.agentValidWinetricksVerbs), DLL allowlist (KnownDLLRegistry.find() guard).

**Graceful degradation verified:** .unavailable and .failed cases both call recipeFallbackLaunch() which uses ValidationPrompt — the pre-existing user experience is preserved for no-key users.

**Build:** `swift build` passes with no errors.

---

_Verified: 2026-03-27T23:30:00Z_
_Verifier: Claude (gsd-verifier)_
