---
phase: 10-dialog-detection
plan: 01
subsystem: diagnostics
tags: [wine-msgbox, corегraphics, dialog-detection, window-enumeration, stderr-parsing]

# Dependency graph
requires:
  - phase: 07-agentic-v2
    provides: "trace_launch tool, loaddll parsing pattern, TraceStderrCapture class"
  - phase: 09-engine-detection
    provides: "Engine-aware system prompt (dialog detection connects to pre-configuration)"
provides:
  - "parseMsgboxDialogs static helper for Wine trace:msgbox line parsing"
  - "dialogs array in launch_game and trace_launch JSON results"
  - "list_windows tool (CoreGraphics window enumeration for Wine processes)"
  - "+msgbox in trace_launch default debug channels"
affects: [10-02-PLAN, system-prompt, agent-reasoning]

# Tech tracking
tech-stack:
  added: [CoreGraphics]
  patterns: [msgbox-stderr-parsing, cg-window-enumeration, screen-recording-permission-detection]

key-files:
  created: [Tests/cellarTests/DialogParsingTests.swift]
  modified: [Sources/cellar/Core/AgentTools.swift, Sources/cellar/Core/AIService.swift]

key-decisions:
  - "parseMsgboxDialogs is a static method on AgentTools for testability"
  - "Wine escape unescaping order: \\n then \\t then \\\\ (backslash last to avoid double-unescape)"
  - "list_windows uses broad Wine process matching (exact names + contains 'wine') for Gcenx variant coverage"
  - "Screen Recording permission detected via kCGWindowName presence on non-self windows"
  - "kCGWindowBounds parsed with flexible CGFloat/Double casting for robustness"

patterns-established:
  - "Msgbox parsing: guard line.contains('trace:msgbox:MSGBOX_OnInit'), extract between L\" and last \", unescape"
  - "CoreGraphics window enumeration: CGWindowListCopyWindowInfo with optionOnScreenOnly + excludeDesktopElements"

requirements-completed: [DIAG-01, DIAG-02]

# Metrics
duration: 4min
completed: 2026-03-29
---

# Phase 10 Plan 01: Dialog Detection Summary

**Msgbox trace parsing in launch_game/trace_launch and CoreGraphics list_windows tool for Wine dialog detection**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-29T00:23:23Z
- **Completed:** 2026-03-29T00:27:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- parseMsgboxDialogs helper parses Wine trace:msgbox lines with escape unescaping, integrated into both launch_game and trace_launch results
- trace_launch default channels now include +msgbox alongside +loaddll
- list_windows tool queries CoreGraphics for Wine process windows with size, owner, likely_dialog flag, and optional title
- Screen Recording permission detection via kCGWindowName availability heuristic
- 6 unit tests covering single/multiple/empty msgbox parsing, escape sequences, and both TID formats

## Task Commits

Each task was committed atomically:

1. **Task 1: Add msgbox parsing (RED)** - `3fc7ee0` (test)
2. **Task 1: Add msgbox parsing (GREEN)** - `03317f4` (feat)
3. **Task 2: Implement list_windows tool** - `d778c19` (feat)

## Files Created/Modified
- `Tests/cellarTests/DialogParsingTests.swift` - 6 tests for msgbox line parsing and escape handling
- `Sources/cellar/Core/AgentTools.swift` - parseMsgboxDialogs helper, dialogs in launch_game/trace_launch, list_windows tool, CoreGraphics import
- `Sources/cellar/Core/AIService.swift` - Tool count updated to 19, list_windows added to Diagnostic tools list

## Decisions Made
- Made parseMsgboxDialogs a static method on AgentTools (not private) for direct unit testing without needing to call launch_game
- Wine only traces message body (no caption/type) per source verification -- dialogs array has "message" and "source" fields only
- list_windows bounds parsing handles both CGFloat and Double casts for robustness across macOS versions
- Broad Wine process name matching (set of known names + contains("wine") case-insensitive) covers Gcenx/CrossOver variants

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Plan 10-02 can now add dialog detection heuristics to the system prompt
- The agent has structured dialog data from both launch_game and trace_launch
- list_windows provides secondary signal for dialog vs. normal game window classification
- Screen Recording permission state is reported so the agent can guide the user once if needed

---
*Phase: 10-dialog-detection*
*Completed: 2026-03-29*
