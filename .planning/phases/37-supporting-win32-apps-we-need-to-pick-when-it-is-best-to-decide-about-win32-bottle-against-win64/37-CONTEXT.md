# Phase 37: Win32 Bottle Support - Context

**Gathered:** 2026-04-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Add win32 vs win64 bottle architecture selection to the game installation flow. Cellar currently creates all bottles as win64 (Wine default). This phase adds PE-type detection at `cellar add` time to create win32 bottles for 32-bit games, improving compatibility for old/retro titles that struggle with wow64 bottle complexity.

</domain>

<decisions>
## Implementation Decisions

### Decision timing
- Bottle arch is decided at `cellar add` time, before bottle creation
- PE type of the installer exe is inspected to determine arch: PE32 → win32, PE32+ → win64
- For disc images / multi-file installers, inspect the installer exe itself (installers almost always match game bitness for old titles)
- Fallback when PE detection fails (non-PE, corrupted headers, raw directory): default to win64 (current behavior)
- Store `bottleArch: String?` ("win32" or "win64") in GameEntry in games.json

### Detection heuristic
- Pure PE type detection: PE32 → win32 bottle, PE32+ → win64 bottle
- No era/size heuristics — keep it deterministic
- Extract PE header reading into a shared utility used by both `cellar add` (arch decision) and `inspect_game` (agent reporting) — DRY, single source of truth
- Update agent system prompt with bottle arch awareness so it doesn't waste cycles on syswow64 tricks in win32 bottles

### User override
- CLI: `--arch win32` / `--arch win64` flag on `cellar add` to override PE detection
- Web UI: show detected arch after file analysis, with dropdown to override. Non-intrusive but available
- No bottle re-creation in this phase — changing arch on an existing game is deferred

### Claude's Discretion
- Exact PE header parsing approach for the shared utility (reuse existing 64KB scan or use a more targeted read of the PE machine type field)
- How to pass WINEARCH to WineProcess.initPrefix() (env var injection)
- Exact wording of agent system prompt additions for bottle arch awareness

</decisions>

<specifics>
## Specific Ideas

- The existing `DiagnosticTools.inspect_game` already reads PE headers and reports "PE32 (32-bit)" vs "PE32+ (64-bit)" — extract and reuse that logic
- `BottleManager.createBottle()` needs to accept and pass WINEARCH env var to `WineProcess.initPrefix()`
- `DLLPlacementTarget.autoDetect()` already handles wow64 vs standard — win32 bottles simplify this (no syswow64 at all)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DiagnosticTools` PE header scanning (lines 15-36): reads first 64KB, checks PE magic bytes and machine type field — extract into shared utility
- `DLLPlacementTarget.autoDetect()` in WineErrorParser.swift: already checks for syswow64 presence to determine bottle type
- `SuccessRecord.bottleType` field: already supports "wow64" vs "standard" — aligns with this phase

### Established Patterns
- `GameEntry` in Models/GameEntry.swift: add `bottleArch` field following existing Codable pattern
- `BottleManager.createBottle()`: modify to accept arch parameter, set `WINEARCH` env var
- `WineProcess.initPrefix()`: already builds env dict — add WINEARCH there
- `AddCommand` CLI flags: uses swift-argument-parser `@Option` — add `--arch` following existing flag patterns

### Integration Points
- `AddCommand.swift` line 97-99: bottle creation — add PE detection before, pass arch to createBottle
- `GameController.swift` line 262-266: web UI bottle creation — same arch detection + user override from form
- `AIService.swift` system prompt (line ~876): already mentions wow64/syswow64 — add arch-aware guidance
- `inspect_game` tool output: add bottle_arch field alongside existing bottle_exists

</code_context>

<deferred>
## Deferred Ideas

- Bottle re-creation command (`cellar recreate <game> --arch win32`) — destructive, needs careful design, own phase
- Agent tool to recreate bottle mid-session — too destructive for automated use without more safeguards

</deferred>

---

*Phase: 37-supporting-win32-apps-we-need-to-pick-when-it-is-best-to-decide-about-win32-bottle-against-win64*
*Context gathered: 2026-04-06*
