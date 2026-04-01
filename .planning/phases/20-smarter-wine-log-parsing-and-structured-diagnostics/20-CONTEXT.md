# Phase 20: Smarter Wine Log Parsing and Structured Diagnostics - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Upgrade Wine log parsing from basic regex pattern matching (~5 patterns) to a structured, subsystem-grouped diagnostic system. The parser gains broader error coverage (audio, input, font, memory), positive success signals, causal chain detection, noise filtering, and cross-launch trend tracking. Output feeds into the existing agent tool results (launch_game, trace_launch, read_log) as a unified diagnostic format that replaces the current `detected_errors` array.

</domain>

<decisions>
## Implementation Decisions

### Error Pattern Coverage
- Add 4 new subsystems: audio (dsound/alsa/pulse), input (dinput/xinput), font/text (freetype/gdi), memory/addressing
- Top 2-3 patterns per new subsystem — cover the most common failures old games hit, not comprehensive
- Every recognized pattern maps to an auto-fix suggestion (WineFix) when a known fix exists
- Version-agnostic patterns — no Wine version-specific databases; agent reasons about Wine version via existing tools
- For ambiguous patterns (multiple possible causes), suggest the most common fix; agent escalates to research if it doesn't help
- Detect causal chains: group related sequential errors into root cause + downstream effects (e.g., "missing d3d9.dll caused DirectX init failure" as one diagnostic, not two)
- No confidence levels on pattern matches — if it matches, report it
- Extract positive success signals alongside errors (e.g., "DirectDraw initialized", "audio device opened") — agent sees what's working AND what failed
- Hardcoded patterns only — no recipe-extensible or plugin patterns

### Signal vs Noise Filtering
- Selective fixme: filtering — strip fixme: lines EXCEPT from subsystems that have a matching detected error (keep fixme:d3d if there's an err:d3d)
- Keep all repeated lines — no deduplication of identical error lines
- Include a diagnostic summary header with counts: errors, warnings, successes, filtered noise lines
- Build a small allowlist of known-harmless warn: lines on macOS Wine (e.g., X11 warnings when using winemac.drv) and filter those too
- Filtering applied everywhere — launch_game results, trace_launch results, and read_log all return filtered/structured output; agent never sees raw noise

### Structured Diagnostic Output
- Diagnostics grouped by subsystem: `graphics{errors, successes}`, `audio{errors, successes}`, `input{...}`, `memory{...}`, etc.
- Causal chains as a separate top-level section linking root causes to downstream effects
- Summary header at top: "2 errors (graphics, audio), 1 success (input), 847 fixme lines filtered"
- Replaces the existing `detected_errors` field in launch_game results — not additive, full replacement
- Unified format for both launch_game and trace_launch (DLL loads and dialogs become entries within the subsystem structure)
- Diagnostics only appear in launch/trace/read_log results — not injected into agent initial message before first launch

### Cross-Launch Trend Detection
- launch_game and trace_launch results include a `changes_since_last` section: new errors, resolved errors, persistent errors, new successes
- Diff annotated with `last_actions` showing what the agent applied before this launch (set_environment, install_winetricks, etc.) — cause-and-effect visibility
- Diagnostics persisted to disk at `~/.cellar/diagnostics/{gameId}/` — enables cross-session comparison
- trace_launch and launch_game share the same tracking baseline — agent can trace → fix → trace and see what changed
- On new agent session: if previous diagnostic data exists on disk, inject a summary of last session's diagnostic state into the agent initial message (e.g., "PREVIOUS SESSION: 3 errors (graphics x2, audio x1), last action was install_winetricks d3dx9")

### Claude's Discretion
- Exact regex patterns for each new subsystem's error/success detection
- Which specific warn: patterns go on the macOS known-harmless allowlist
- Internal data structures for the diagnostic model (Swift structs/enums)
- How to track "last_actions" within AgentTools (session state management)
- Diagnostic file format on disk (~/.cellar/diagnostics/)
- How to integrate positive signals with existing DLL load and dialog parsing in trace_launch

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `WineErrorParser` (WineErrorParser.swift): Current 5-pattern parser with `parse(_ stderr:) -> [WineError]` — will be expanded significantly
- `WineError` / `WineErrorCategory` / `WineFix` enums: Existing structured types to extend with new subsystems and causal chains
- `AgentTools.parseMsgboxDialogs()`: Dialog extraction from +msgbox traces — will fold into unified diagnostic format
- `AgentTools.traceLaunch()`: Already parses DLL loads and errors — restructure output to unified format
- `StderrCapture` class: Thread-safe buffer in WineProcess — feeds the parser

### Established Patterns
- WineProcess already enriches WINEDEBUG with +msgbox automatically — same pattern for any new channels needed
- launch_game returns JSON dict with structured fields — add `diagnostics` and `changes_since_last` keys, remove `detected_errors`
- read_log returns last 8000 chars of raw stderr — will now return filtered/structured output instead
- Agent system prompt in AIService.runAgentLoop() documents tool output formats — must update for new diagnostic structure

### Integration Points
- `AgentTools.launchGame()` (line ~1346): Where launch results are assembled — replace `detected_errors` with new `diagnostics`
- `AgentTools.traceLaunch()` (line ~1484): Where trace results are assembled — unify with same diagnostic format
- `AgentTools.readLog()`: Currently returns raw tail — switch to filtered/structured
- `AIService.runAgentLoop()`: System prompt and initial message — update format docs, add previous session injection
- `CellarPaths`: Add diagnostics directory path (`~/.cellar/diagnostics/{gameId}/`)

</code_context>

<specifics>
## Specific Ideas

- Subsystem-grouped JSON output: `{ "summary": "...", "graphics": { "errors": [...], "successes": [...] }, "audio": {...}, "causal_chains": [...] }`
- Changes diff: `{ "changes_since_last": { "last_actions": [...], "new_errors": [...], "resolved_errors": [...], "persistent_errors": [...], "new_successes": [...] } }`
- Previous session injection: "PREVIOUS SESSION: 3 errors (graphics x2, audio x1), last action was install_winetricks d3dx9"

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 20-smarter-wine-log-parsing-and-structured-diagnostics*
*Context gathered: 2026-03-31*
