---
phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database
verified: 2026-03-27T00:00:00Z
status: passed
score: 23/23 must-haves verified
re_verification: false
gaps: []
human_verification:
  - test: "Run agent loop against a real DirectDraw game (e.g. Cossacks EW)"
    expected: "Agent follows Research-Diagnose-Adapt flow: queries successdb, inspects game, traces before configuring, places cnc-ddraw in syswow64 for wow64 bottle, saves success record"
    why_human: "End-to-end agentic workflow requires a live Anthropic API key and real Wine bottle — cannot verify programmatically"
  - test: "search_web against DuckDuckGo HTML endpoint"
    expected: "Returns structured results with title/snippet/url; subsequent call within 7 days returns from_cache=true"
    why_human: "Live network call to DuckDuckGo; HTML structure may differ from regex patterns; cache TTL requires real time passing"
  - test: "trace_launch on a real game binary"
    expected: "Kills process after timeout, returns parsed loaded_dlls array (not raw stderr), wineserver cleaned up"
    why_human: "Requires a real Wine binary and prefix; timing behavior cannot be verified statically"
---

# Phase 07: Agentic v2 Research-Diagnose-Adapt Loop Verification Report

**Phase Goal:** Replace the v1 agent's linear config-search loop with a three-phase Research-Diagnose-Adapt architecture. Add research tools (web search, page fetch, success DB queries), enhanced diagnostic tools (trace_launch, verify_dll_override, check_file_access), enhanced action tools (place_dll with syswow64, write_game_file, enhanced launch_game), success database, updated system prompt with correct macOS/Wine domain knowledge, and infrastructure bug fixes (WineProcess CWD, wow64 DLL paths).
**Verified:** 2026-03-27
**Status:** PASSED (with human verification items noted)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | WineProcess.run() sets process CWD to the game binary's parent directory | VERIFIED | `WineProcess.swift:41` — `process.currentDirectoryURL = binaryURL.deletingLastPathComponent()` |
| 2 | DLLPlacementTarget has .syswow64 case with autoDetect logic | VERIFIED | `WineErrorParser.swift:18` — `case syswow64` present; `autoDetect()` at line 21 checks `drive_c/windows/syswow64` existence |
| 3 | KnownDLL struct has companionFiles, preferredTarget, isSystemDLL, and variants fields | VERIFIED | `KnownDLLRegistry.swift:8-20` — all four fields present in struct definition |
| 4 | CellarPaths provides successdbDir, researchCacheDir, and helper methods | VERIFIED | `CellarPaths.swift:48-59` — all four methods present |
| 5 | Agent can write config files into the game directory via write_game_file tool | VERIFIED | `AgentTools.swift:1522-1562` — full implementation with path traversal protection, atomic write |
| 6 | place_dll supports syswow64 target and writes companion config files automatically | VERIFIED | `AgentTools.swift:992-1058` — auto-detect at 1001-1003, companion file loop at 1029-1034 |
| 7 | place_dll auto-detects correct target using bottle type and DLL metadata | VERIFIED | `AgentTools.swift:999-1003` — uses `DLLPlacementTarget.autoDetect(bottleURL:dllBitness:isSystemDLL:)` when target omitted |
| 8 | Agent can run a short timed Wine launch with debug channels and get structured DLL load analysis | VERIFIED | `AgentTools.swift:1268-1384` — kill timer at 1329, +loaddll regex parsing at 1355, returns structured `loaded_dlls` array |
| 9 | Agent can verify whether a DLL override actually took effect by comparing config vs trace output | VERIFIED | `AgentTools.swift:1413-1518` — calls traceLaunch internally, compares configured override vs actual load type |
| 10 | Agent can check if game files exist relative to working directory | VERIFIED | `AgentTools.swift:1388-1409` — checks each relative path from game exe parent dir |
| 11 | inspect_game returns PE imports from objdump, bottle type (wow64 detection), and data file listing | VERIFIED | `AgentTools.swift:593-683` — objdump at 594-628, bottle_type at 635, data_files at 638-649, notable_imports at 651-666 |
| 12 | Agent can query success database by game_id, tags, engine, graphics_api, or symptom | VERIFIED | `AgentTools.swift:1568-1612` — priority-ordered query dispatch covering all 5 query types |
| 13 | Agent can save a full success record capturing environment, DLLs, pitfalls, and resolution narrative | VERIFIED | `AgentTools.swift:1616-1731` — builds complete SuccessRecord from session context + agent input |
| 14 | Success records persist as JSON files in ~/.cellar/successdb/ | VERIFIED | `SuccessDatabase.swift:97-106` — atomic write to `CellarPaths.successdbFile(for: record.gameId)` |
| 15 | Symptom matching uses keyword overlap for fuzzy matching | VERIFIED | `SuccessDatabase.swift:151-168` — keyword intersection / max-word-count ratio, 0.3 threshold |
| 16 | Agent can search the web for game-specific Wine compatibility info | VERIFIED | `AgentTools.swift:1747-1873` — DuckDuckGo HTML fetch with result parsing |
| 17 | Agent can fetch and extract text from a specific URL | VERIFIED | `AgentTools.swift:1877-1948` — HTML stripping, entity decoding, 8000-char truncation |
| 18 | Research results are cached per game with 7-day TTL | VERIFIED | `AgentTools.swift:1752-1766` — loads `ResearchCache` from `CellarPaths.researchCacheFile(for: gameId)`, calls `isStale()` (7-day check at line 13) |
| 19 | System prompt guides agent through Research-Diagnose-Adapt workflow with correct macOS/Wine domain knowledge | VERIFIED | `AIService.swift:510-566` — three-phase workflow, "NEVER suggest virtual desktop mode", syswow64 knowledge, all 18 tools listed |
| 20 | launch_game returns structured DLL load analysis and sets CWD correctly | VERIFIED | `AgentTools.swift:1163-1179` — +loaddll regex parsing, `loaded_dlls` in result dict; CWD set via WineProcess.run() |
| 21 | launch_game has diagnostic mode that does not count toward launch limit | VERIFIED | `AgentTools.swift:1065-1076` — `isDiagnostic` check at 1068 skips `launchCount` increment |
| 22 | launch_game performs pre-flight checks before launching | VERIFIED | `AgentTools.swift:1079-1109` — checks exe existence, checks DLL files exist for native overrides |
| 23 | Initial message directs agent to follow Research-Diagnose-Adapt workflow | VERIFIED | `AIService.swift:586` — message text references Research-Diagnose-Adapt by name |

**Score: 23/23 truths verified**

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Sources/cellar/Core/WineProcess.swift` | CWD fix in run() method | VERIFIED | `currentDirectoryURL = binaryURL.deletingLastPathComponent()` at line 41 |
| `Sources/cellar/Core/WineErrorParser.swift` | DLLPlacementTarget.syswow64 + autoDetect | VERIFIED | `case syswow64` at line 18; `autoDetect()` method at lines 21-31 |
| `Sources/cellar/Models/KnownDLLRegistry.swift` | CompanionFile struct, extended KnownDLL | VERIFIED | `struct CompanionFile` at line 3; all 4 new fields in KnownDLL; cnc-ddraw entry has ddraw.ini companion, syswow64 target, isSystemDLL=true |
| `Sources/cellar/Persistence/CellarPaths.swift` | successdbDir, researchCacheDir paths | VERIFIED | Both static lets and both helper functions present at lines 47-59 |
| `Sources/cellar/Core/AgentTools.swift` | write_game_file tool | VERIFIED | Tool definition at line 266, execute() dispatch at line 497, implementation at line 1522 |
| `Sources/cellar/Core/AgentTools.swift` | Enhanced place_dll with syswow64 + companion files | VERIFIED | syswow64 enum at line 218, auto-detect at 999-1003, companion loop at 1029-1034 |
| `Sources/cellar/Core/AgentTools.swift` | trace_launch, verify_dll_override, check_file_access tools | VERIFIED | All three in execute() switch at lines 500-502; full implementations present |
| `Sources/cellar/Core/AgentTools.swift` | Enhanced inspect_game | VERIFIED | PE imports via objdump, bottle_type detection, data_files listing, notable_imports — all present |
| `Sources/cellar/Core/SuccessDatabase.swift` | SuccessRecord Codable schema + SuccessDatabase CRUD + fuzzy symptom matching | VERIFIED | 170-line file; all schema structs, load/save/loadAll, all 5 query methods present |
| `Sources/cellar/Core/AgentTools.swift` | query_successdb and save_success tool handlers | VERIFIED | Both in execute() at lines 498-499; full implementations present |
| `Sources/cellar/Core/AgentTools.swift` | search_web, fetch_page tools + enhanced launch_game | VERIFIED | All in execute() at 503-504, 495; full implementations present |
| `Sources/cellar/Core/AIService.swift` | Updated system prompt with v2 workflow | VERIFIED | "Three-Phase Workflow: Research -> Diagnose -> Adapt" at line 513; domain knowledge block; 18-tool list |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `WineErrorParser.swift` | `KnownDLLRegistry.swift` | `preferredTarget: DLLPlacementTarget` | VERIFIED | `KnownDLL.preferredTarget` field typed as `DLLPlacementTarget` (KnownDLLRegistry.swift:17) |
| `AgentTools.swift` | `KnownDLLRegistry.swift` | `place_dll reads companionFiles and preferredTarget` | VERIFIED | `knownDLL.companionFiles` at line 1029; auto-detect uses `knownDLL.isSystemDLL` at 1001 |
| `AgentTools.swift` | `WineErrorParser.swift` | `place_dll uses DLLPlacementTarget.autoDetect` | VERIFIED | `DLLPlacementTarget.autoDetect(bottleURL: bottleURL, dllBitness: 32, isSystemDLL: true)` at line 1002 |
| `AgentTools.swift (trace_launch)` | `WineProcess.swift` | Uses `wineProcess.wineBinary`, `killWineserver()` for timed diagnostic launch | VERIFIED | `wineProcess.wineBinary` at line 1295; `wineProcess.killWineserver()` at lines 1327, 1342 |
| `AgentTools.swift (verify_dll_override)` | `AgentTools.swift (trace_launch)` | Calls traceLaunch internally | VERIFIED | `traceLaunch(input: traceInput)` at line 1455; result JSON parsed to extract `loaded_dlls` |
| `AgentTools.swift` | `SuccessDatabase.swift` | Tool handlers create/query SuccessRecord via SuccessDatabase | VERIFIED | `SuccessDatabase.queryByGameId()` at line 1572; `SuccessDatabase.save(record)` at line 1697 |
| `SuccessDatabase.swift` | `CellarPaths.swift` | Uses CellarPaths.successdbDir for file storage | VERIFIED | `CellarPaths.successdbFile(for:)` at SuccessDatabase.swift line 91, 105 |
| `AgentTools.swift (search_web)` | `CellarPaths.swift` | Research cache stored at CellarPaths.researchCacheFile | VERIFIED | `CellarPaths.researchCacheFile(for: gameId)` at AgentTools.swift line 1753 |
| `AIService.swift` | `AgentTools.swift` | System prompt references all tools; toolDefinitions passed to AgentLoop | VERIFIED | `AgentTools.toolDefinitions` at AIService.swift line 579; all 18 tools named in system prompt |

---

## Requirements Coverage

No requirement IDs declared in any plan frontmatter (`requirements: []` in all five plans). Phase 07 is an INSERTED phase that extends the Phase 6 agentic architecture. No REQUIREMENTS.md entries map to this phase. Coverage not applicable.

---

## Anti-Patterns Found

No TODO, FIXME, placeholder comments, or empty implementations found in any phase 07 modified files. Scan covered all seven files:
- `Sources/cellar/Core/WineProcess.swift`
- `Sources/cellar/Core/WineErrorParser.swift`
- `Sources/cellar/Models/KnownDLLRegistry.swift`
- `Sources/cellar/Persistence/CellarPaths.swift`
- `Sources/cellar/Core/AgentTools.swift`
- `Sources/cellar/Core/SuccessDatabase.swift`
- `Sources/cellar/Core/AIService.swift`

**Build status:** `swift build` completes with zero errors or warnings.

---

## Notable Implementation Details

### Minor Behavioral Note: timeout_applied always true in trace_launch

`traceLaunch()` returns `"timeout_applied": true` unconditionally (line 1381), regardless of whether the kill timer actually fired. The process may have exited naturally before the timeout. This does not block goal achievement — the field is informational for the agent — but is slightly misleading.

### verifyDllOverride calls traceLaunch with internal JSONValue

The internal call at line 1451-1455 constructs a `JSONValue.object` directly rather than going through the execute() dispatcher. This is correct (avoids double-dispatch overhead) and the pattern works.

### ResearchCache write uses try? (best-effort)

`AgentTools.swift:1861` — `try? cacheData.write(to: cacheFile)` is silent on cache write failure. Cache misses on next call are handled gracefully (re-fetch). Not a concern.

---

## Human Verification Required

### 1. End-to-End Agent Loop with Real Game

**Test:** Run `cellar launch <game-id>` on a DirectDraw game (e.g., Cossacks: European Wars) with an Anthropic API key configured and a wow64 bottle.
**Expected:** Agent calls `query_successdb` first, then `inspect_game`, then `trace_launch` before configuring, then `place_dll` targeting `syswow64` (auto-detected for wow64 bottle), then `launch_game`, then `save_success`. Resulting JSON file appears in `~/.cellar/successdb/<game-id>.json`.
**Why human:** Requires live Anthropic API, real Wine installation, real game binary, and wow64 bottle. Cannot verify agentic decision-making statically.

### 2. Web Search Cache Behavior

**Test:** Call `search_web` twice for the same game within 7 days. Then delete the cache file and call again.
**Expected:** Second call returns `from_cache: true`. Third call (after deletion) hits network and returns `from_cache: false`.
**Why human:** Requires network access to DuckDuckGo; DuckDuckGo HTML structure may have changed since the regex patterns were written; results depend on live internet.

### 3. Trace Launch Kill Timer

**Test:** Call `trace_launch` on a game that does not exit quickly (e.g., a game with a splash screen).
**Expected:** Process is terminated after `timeout_seconds`, wineserver is killed, and the call returns within `timeout + 1` second.
**Why human:** Requires real Wine process; timing behavior cannot be verified from source alone.

---

## Gaps Summary

No gaps. All 23 must-have truths are verified in the codebase. All artifacts exist and are substantive (not stubs). All key links are wired. The build is clean. The three items flagged for human verification are behavioral/runtime concerns, not code deficiencies.

---

_Verified: 2026-03-27_
_Verifier: Claude (gsd-verifier)_
