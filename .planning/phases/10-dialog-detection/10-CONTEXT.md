# Phase 10: Dialog Detection - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect when a Wine game is stuck on a dialog box using two complementary signals: Wine trace:msgbox parsing (primary, no permissions needed) and macOS window list inspection via CGWindowListCopyWindowInfo (optional complement, requires Screen Recording permission). The agent combines these signals to distinguish dialog-stuck from running-normally from crashed. No automated dialog clicking — detection only.

</domain>

<decisions>
## Implementation Decisions

### Wine trace:msgbox parsing
- Add +msgbox as a default WINEDEBUG channel in both trace_launch AND launch_game — dialog detection is always-on, not opt-in
- Parse MessageBox output into structured fields: title (window caption), message (body text), and button type (OK, OK/Cancel, Yes/No, etc.)
- Research phase MUST capture actual Gcenx wine-crossover trace:msgbox output before building the parser — do not rely on Wine source docs alone
- Parsed msgbox data appears in both trace_launch and launch_game results as a `dialogs` array of structured entries

### macOS window list tool
- New standalone `list_windows` agent tool — agent calls it whenever needed, not integrated into launch_game result
- Uses CoreGraphics (CGWindowListCopyWindowInfo) directly from Swift — no AppleScript, no subprocess
- Filters to Wine processes only (wine/wine64/wineserver process names) — no leaking info about other apps
- Returns window titles, sizes (width x height), and owner process for each Wine window
- Small window heuristic: windows smaller than ~640x480 flagged as likely dialogs. Agent makes final judgment from size data.

### Permission handling
- When Screen Recording permission is denied: return error result explaining permission is needed with instructions to grant it in System Settings
- Agent falls back to trace:msgbox as sole dialog signal when list_windows is unavailable
- Proactive permission probe: system prompt tells agent to call list_windows once early in session (after inspect_game) to test permission state
- If denied, agent tells user once via ask_user: "For best dialog detection, grant Screen Recording permission to Terminal in System Settings." Then continues with trace:msgbox only.
- Never ask user about permission more than once per session

### Hybrid signal reasoning
- Agent combines signals itself — no hardcoded hybrid logic in tool code
- System prompt includes multi-signal heuristic guidance:
  - Quick exit + msgbox data = dialog stuck
  - Quick exit + no msgbox = crash
  - Still running + small window = dialog waiting for input
  - Still running + large window = game running normally
- System prompt includes common dialog pattern guidance:
  - MessageBox about renderer/video mode = pre-configuration needed (connect to Phase 9 engine pre-config)
  - MessageBox about missing file = DLL or data issue
  - MessageBox about registration/serial = can usually dismiss
- Prompt suggests calling list_windows after launch_game when game exits quickly or msgbox data is present — not mandated after every launch

### Claude's Discretion
- Exact msgbox trace line regex patterns (must match real Gcenx output from research)
- How to detect permission denial from CGWindowListCopyWindowInfo return values
- list_windows tool schema details (input params, output format)
- Internal implementation of CoreGraphics window enumeration
- How to identify Wine process names reliably across different Wine builds

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `trace_launch` (AgentTools.swift:1329): Already captures stderr with WINEDEBUG channels, parses +loaddll lines into structured data. Adding +msgbox parsing follows the exact same pattern — parse regex from stderr lines, return structured array.
- `launch_game` (AgentTools.swift:1125): Already merges WINEDEBUG channels, returns structured results with exit code, elapsed time, stderr tail, errors. Adding msgbox parsing and +msgbox channel extends this existing flow.
- `TraceStderrCapture` class: Used by trace_launch for async stderr capture. Reusable for launch_game msgbox capture.
- `jsonResult()` helper: Standard pattern for all tool results.

### Established Patterns
- Tool definitions in `toolDefinitions` array with JSON schema
- Tool dispatch in `execute(toolName:input:)` switch statement
- WINEDEBUG channel merging pattern in both trace_launch and launch_game
- Stderr line parsing with regex (loaddll pattern at line 1420) — msgbox parsing follows same approach

### Integration Points
- `trace_launch` default channels: currently `["+loaddll"]` at line 1335 — add `"+msgbox"`
- `launch_game` WINEDEBUG merging: line 1176-1178 — add +msgbox to base channels
- Tool definitions array: add list_windows definition
- Tool dispatch switch: add list_windows case
- System prompt (AIService.swift): add dialog detection methodology section
- CoreGraphics import needed for CGWindowListCopyWindowInfo — may need to add `import CoreGraphics` to the tool file or a new file

</code_context>

<specifics>
## Specific Ideas

- The trace:msgbox parser is the workhorse — it works without any permissions and captures the exact dialog text. The window list is a nice-to-have complement that adds size/visibility info.
- This connects directly to Phase 9's engine pre-configuration: if the agent detects a renderer selection dialog via msgbox, it knows pre-configuration should have prevented it and can adjust settings for next launch.
- The proactive permission probe keeps UX clean — user hears about Screen Recording once, not every time the agent wants to check windows.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-dialog-detection*
*Context gathered: 2026-03-29*
