---
status: testing
phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
source: 07-01-SUMMARY.md, 07-02-SUMMARY.md, 07-03-SUMMARY.md, 07-04-SUMMARY.md, 07-05-SUMMARY.md
started: 2026-03-28T02:15:00Z
updated: 2026-03-28T02:15:00Z
---

## Current Test

number: 1
name: Project builds cleanly
expected: |
  `swift build` completes with zero errors and zero warnings related to Phase 7 changes
awaiting: user response

## Tests

### 1. Project builds cleanly
expected: `swift build` completes with zero errors. All 18 agent tools compile, SuccessDatabase.swift compiles, all new diagnostic/research/action tool methods resolve.
result: [pending]

### 2. Agent tool count is 18
expected: Running `cellar launch` with ANTHROPIC_API_KEY set sends 18 tool definitions to the API (10 original + 8 new: write_game_file, trace_launch, check_file_access, verify_dll_override, search_web, fetch_page, query_successdb, save_success). You can verify by checking AgentTools.toolDefinitions array count or by observing API traffic.
result: [pending]

### 3. System prompt uses Research-Diagnose-Adapt workflow
expected: The agent system prompt (visible in AIService.swift) describes a three-phase workflow: Research (query success DB, then web search), Diagnose (trace_launch, verify overrides), Adapt (configure and launch). It does NOT mention virtual desktop mode. It mentions syswow64 for 32-bit system DLLs.
result: [pending]

### 4. WineProcess sets working directory
expected: When the agent calls launch_game, Wine is invoked with the working directory set to the game executable's parent directory. Games that use relative paths (e.g., "Missions\Missions.txt") find their files correctly instead of getting "file not found" errors.
result: [pending]

### 5. place_dll auto-detects syswow64 for system DLLs
expected: When the agent calls place_dll for cnc-ddraw (a system DLL) in a wow64 bottle, the tool auto-detects that the DLL should go in `drive_c/windows/syswow64/` instead of the game directory. The result JSON shows the syswow64 placement path.
result: [pending]

### 6. place_dll writes companion ddraw.ini
expected: When cnc-ddraw is placed, the tool also writes `ddraw.ini` with `renderer=opengl` (and other settings) alongside the DLL. This happens automatically — the agent doesn't need to separately call write_game_file for the config.
result: [pending]

### 7. trace_launch returns structured DLL analysis
expected: When the agent calls trace_launch, it runs Wine briefly with +loaddll debug channel, kills after timeout, and returns a JSON object with a `loaded_dlls` array. Each entry has `name`, `path`, and `type` (native or builtin) — not raw Wine stderr text.
result: [pending]

### 8. inspect_game shows PE imports and bottle type
expected: When the agent calls inspect_game, the result includes `pe_imports` (list of DLL names the executable links against), `bottle_type` (wow64 or standard), `data_files` (config files like mode.dat), and `notable_imports` (annotations for known shim DLLs like mdraw.dll).
result: [pending]

### 9. Success database saves and queries records
expected: After the agent successfully launches a game and the user confirms it works, `save_success` creates a JSON file in `~/.cellar/successdb/`. On next launch of the same game, `query_successdb` finds the record and the agent can skip web research.
result: [pending]

### 10. search_web returns Wine compatibility results
expected: When the agent calls search_web with a game query, it fetches DuckDuckGo results and returns titles, URLs, and snippets related to Wine compatibility. Results are cached per game in `~/.cellar/research/` with 7-day TTL.
result: [pending]

### 11. End-to-end: agent uses v2 workflow for a game launch
expected: Running `cellar launch cossacks` with ANTHROPIC_API_KEY triggers the agent loop. The agent follows Research-Diagnose-Adapt: first queries success DB, then researches if needed, runs diagnostic traces, configures based on evidence, and launches. The agent does NOT blindly cycle through env var configs like v1.
result: [pending]

## Summary

total: 11
passed: 0
issues: 0
pending: 11
skipped: 0

## Gaps

[none yet]
