# Phase 9: Engine Detection and Pre-configuration - Context

**Gathered:** 2026-03-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect a game's engine family and graphics API from file patterns, PE imports, registry keys, and binary string heuristics. Return detection results as part of inspect_game. Update the system prompt so the agent pre-configures known engine settings before first launch and constructs engine-aware web search queries. No new agent tools — detection extends inspect_game, pre-configuration uses existing action tools (set_registry, write_game_file, set_environment), and search enrichment is prompt-level guidance.

</domain>

<decisions>
## Implementation Decisions

### Engine detection architecture
- Extend inspect_game tool to add an `engine` field to its result — no separate tool
- Detection uses all three signal types: file patterns, PE imports, and binary string heuristics for engine version strings
- Also scan Wine registry for engine-specific keys via read_registry patterns
- Weighted confidence scoring: file pattern match = high weight, PE import = medium, string scan = supporting. Multiple agreeing signals = "high" confidence, single weak signal = "low"
- Returns engine info only — no config hints baked into detection results. Agent reasons about configuration itself.
- Separate `graphics_api` field alongside engine (ddraw.dll = DirectDraw, d3d9.dll = DX9, opengl32.dll = OpenGL, etc.) — matches success database schema
- Re-detect every time, no caching — detection is fast enough

### Engine family coverage
- All 8 engine families per requirements: GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard
- Data-driven registry structure — array/dictionary of engine definitions with name, file patterns, PE import patterns, string signatures, graphics API associations
- Easy to add new engines by adding data entries, not new code

### Pre-configuration scope
- Full known-engine presets: renderer, resolution, sound, input settings — not just renderer selection dialogs
- Agent decides whether to pre-configure — system prompt suggests pre-configuring for known engines, agent chooses
- Uses existing tools: set_registry, write_game_file, set_environment — no new pre_configure tool
- Agent diagnoses and adjusts if pre-config is wrong — no snapshot/rollback mechanism. The Research-Diagnose-Adapt loop handles failures.

### Search query enrichment
- Prompt-level guidance only — system prompt tells agent to include engine name, graphics API, and current symptoms in search queries
- General guidance, not per-engine query templates — keeps prompt shorter, agent is smart enough
- Engine + symptom together in queries (e.g., "GSC engine DirectDraw renderer selection dialog Wine macOS")
- System prompt tells agent to cross-reference success database by engine type and graphics API after detection — query_successdb already supports these params

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `inspect_game` (AgentTools.swift:526): Already runs `objdump -p` for PE imports, lists game directory files, detects bottle type, flags notable DLL imports (ddraw, d3d9, d3d8, d3d11, dinput, dsound). Engine detection extends this existing analysis.
- `knownShimDLLs` dictionary (AgentTools.swift:652): Maps PE import DLLs to descriptions. Can be expanded or replaced by engine-aware graphics API detection.
- `query_successdb` (AgentTools.swift:1577): Already accepts engine and graphics_api query params. No changes needed — just better prompt guidance to use them.
- `search_web` (AgentTools.swift:1756): Free-text query, no changes needed. Enrichment is prompt-level.
- `write_game_file`, `set_registry`, `set_environment`: All exist and can write pre-configuration without new tools.

### Established Patterns
- Tool results are JSON dictionaries returned via `jsonResult()` helper
- PE imports already parsed from `objdump -p` output with DLL Name: line extraction and fallback regex
- System prompt in AIService.swift defines the agent's methodology — engine-aware guidance goes here

### Integration Points
- `inspectGame()` return dictionary: add `engine`, `engine_confidence`, `graphics_api`, `detected_signals` fields
- System prompt (AIService.swift ~510): add engine detection methodology and pre-configuration guidance
- Success database queries: prompt update to tell agent to query by detected engine/graphics_api

</code_context>

<specifics>
## Specific Ideas

- The 8 engine families are all from the old PC game era that Cellar targets — these are the engines that show up in strategy, management, and turn-based games from 1995-2010
- Pre-configuration should feel proactive — the agent detects the engine, knows what settings old games on that engine typically need, and sets them up before the user even sees a dialog
- The data-driven engine registry pattern mirrors KnownDLLRegistry — a central place to define engine fingerprints and add new ones

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 09-engine-detection-and-pre-configuration*
*Context gathered: 2026-03-28*
