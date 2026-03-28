# Phase 7: Agentic v2 — Research-Diagnose-Adapt Loop - Context

**Gathered:** 2026-03-27
**Status:** Ready for planning
**Source:** PRD Express Path (.planning/agentic-architecture-v2.md)

<domain>
## Phase Boundary

Replace the v1 agent's linear config-search loop with a three-phase Research-Diagnose-Adapt architecture. The v1 agent has 10 tools all focused on acting (set env, place DLL, launch). v2 adds tools that *investigate* and *understand* — web research, diagnostic trace launches, DLL verification, file access checks — so the agent can make non-linear pivots based on evidence rather than blindly cycling configs.

This phase delivers:
1. Research tools (web search, page fetch, success DB queries)
2. Enhanced diagnostic tools (trace_launch, verify_dll_override, check_file_access)
3. Enhanced action tools (place_dll with syswow64, write_game_file, launch_game with CWD fix)
4. Success database for storing and querying game launch knowledge
5. Updated system prompt with correct macOS/Wine domain knowledge
6. Infrastructure bug fixes (WineProcess CWD, wow64 DLL paths)

</domain>

<decisions>
## Implementation Decisions

### Research Tools
- `search_web` tool: search for game-specific Wine compatibility info (WineHQ, ProtonDB, PCGamingWiki, forums)
- `fetch_page` tool: read a specific URL and extract text content for the agent
- Cache research results per game in `~/.cellar/research/{gameId}.json` — skip if <7 days old
- Research is optional: skip if success DB has a known-working record

### Diagnostic Tools
- `trace_launch` tool: launch game briefly with targeted Wine debug channels (+loaddll, +ddraw, +relay), kill after N seconds, return **structured analysis** (not raw stderr) — parsed DLL load info, errors, etc.
- `verify_dll_override` tool: combine registry/env override config + trace_launch + comparison to explain discrepancies (e.g., "native DLL exists in game_dir but Wine loaded builtin from syswow64")
- `check_file_access` tool: verify game can find files it needs by comparing working directory vs game directory for relative paths
- `inspect_game` enhancement: add PE imports via `objdump -p`, bottle type detection (wow64), data file reading, known shim flagging

### Action Tool Enhancements
- `place_dll` enhancement: add syswow64 target, auto-detect based on bottle type (wow64 + 32-bit system DLL → syswow64), write companion config files (ddraw.ini), verify after placement
- `launch_game` enhancement: ALWAYS set working directory to game EXE's parent directory, return structured DLL load analysis, distinguish diagnostic vs real launch, include pre-flight checks
- `write_game_file` new tool: write config/data files the game needs (mode.dat, ddraw.ini, etc.) into the game directory

### Infrastructure Fixes (P0)
- WineProcess.run() must set `process.currentDirectoryURL` to the binary's parent directory
- DLLPlacementTarget must include `.syswow64` case for 32-bit system DLLs in wow64 bottles
- place_dll must write companion configs (ddraw.ini for cnc-ddraw) based on KnownDLLRegistry metadata

### System Prompt Updates
- Remove: virtual desktop suggestions (doesn't work on macOS winemac.drv)
- Add: wow64 DLL search order (syswow64 for 32-bit system DLLs)
- Add: cnc-ddraw requires ddraw.ini with renderer=opengl on macOS
- Add: CWD must be game EXE's parent directory
- Add: PE imports show actual DLL dependencies
- Add: diagnostic methodology (trace before configuring, verify after placing)
- Add: research methodology (search before first launch)

### KnownDLLRegistry Enhancement
- Add `companionFiles: [CompanionFile]` — files to write alongside the DLL (e.g., ddraw.ini)
- Add `preferredTarget: DLLPlacementTarget` — .syswow64 for system DLLs in wow64
- Add `variants: [String: String]` — game-specific variants

### Success Database
- Storage: `~/.cellar/successdb/{game-id}.json`
- Schema captures: executable info, working directory requirements, environment, DLL overrides with placement details, game config files, registry settings, game-specific DLLs, pitfalls (symptom + cause + fix + wrong_fix), resolution narrative, tags
- `query_successdb` tool: query by game_id (exact), tags (overlap), engine (substring), graphics_api (substring), symptom (fuzzy match against pitfalls)
- `save_success` tool: replaces/extends save_recipe — agent constructs full record from session context
- Agent queries success DB before web research; similar-game queries by engine/graphics_api/tags

### Agent Loop Changes
- Three-phase flow: Research → Diagnose → Adapt (non-linear, can jump between phases)
- Diagnostic launches are NOT full launches — short, traced, killed after N seconds
- Budget: 3 diagnostic launches before first real launch, 2 between each failed real launch
- Research phase pre-summarizes web results to extract only actionable info (env vars, registry keys, DLL overrides, known bugs)

### Cost/Performance
- Research results cached per game (7-day TTL)
- Parallel research: WineHQ + ProtonDB + PCGamingWiki concurrently
- Trace launches ~3-5 seconds each (cheaper than full launch attempts)
- Token budget: pre-summarize web results before injecting into agent context

### Claude's Discretion
- Internal implementation details of tool handlers
- Error handling and edge cases within each tool
- Exact structured output format for trace_launch parsing
- How to organize new tools within AgentTools.swift
- Test strategy and test file organization
- Order of implementation across plans

</decisions>

<specifics>
## Specific Ideas

### Success Criteria from Architecture Doc
The v2 architecture succeeds if the agent can:
1. Discover that cnc-ddraw needs to go in syswow64 (not game_dir) by running a diagnostic trace
2. Discover that mode.dat controls resolution (not registry) by researching on forums
3. Discover that the game needs CWD set correctly by checking file access before launching
4. Discover that mdraw.dll is a custom shim by inspecting PE imports
5. Avoid suggesting virtual desktop on macOS by having correct domain knowledge

### DLLPlacementTarget.autoDetect
```swift
static func autoDetect(bottleURL: URL, dllBitness: Int, isSystemDLL: Bool) -> DLLPlacementTarget {
    let isWow64 = FileManager.default.fileExists(
        atPath: bottleURL.appendingPathComponent("drive_c/windows/syswow64").path
    )
    if isSystemDLL && isWow64 && dllBitness == 32 { return .syswow64 }
    return .gameDir
}
```

### WineProcess CWD Fix
```swift
let binaryURL = URL(fileURLWithPath: binary)
process.currentDirectoryURL = binaryURL.deletingLastPathComponent()
```

### Cossacks Success Record
Full example success record is documented in the architecture doc — serves as the schema reference and first entry for the success database.

</specifics>

<deferred>
## Deferred Ideas

- `check_protondb` convenience wrapper (can be implemented as search_web + fetch_page)
- Community sharing of success database records (Phase 5 scope)
- Game-specific DLL variants in KnownDLLRegistry (e.g., cnc-ddraw_cossacks.zip)
- Local inference alternative to API-first AI

</deferred>

---

*Phase: 07-agentic-v2-research-diagnose-adapt-loop-with-web-search-diagnostic-traces-and-success-database*
*Context gathered: 2026-03-27 via PRD Express Path*
