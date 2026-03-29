---
phase: 10-dialog-detection
plan: 02
subsystem: ai
tags: [system-prompt, dialog-detection, heuristics, wine, msgbox]

# Dependency graph
requires:
  - phase: 10-dialog-detection/10-01
    provides: "Msgbox parsing in launch_game/trace_launch, list_windows CoreGraphics tool"
  - phase: 09-engine-detection-and-pre-configuration/09-02
    provides: "Engine-Aware Methodology section in system prompt"
provides:
  - "Dialog detection methodology in agent system prompt"
  - "Multi-signal heuristic table for combining trace:msgbox + list_windows"
  - "Permission probe guidance for Screen Recording"
  - "Common dialog pattern guidance with actionable fixes"
affects: [phase-11, agent-behavior]

# Tech tracking
tech-stack:
  added: []
  patterns: ["multi-signal heuristic table in system prompt", "permission probe once-per-session pattern"]

key-files:
  created: []
  modified:
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "Dialog Detection section placed between Engine-Aware Methodology and macOS + Wine Domain Knowledge for optimal prompt ordering"
  - "Phase 3 Adapt workflow gets step 2b for dialog checking, mirroring Phase 1 Research step 2b pattern"

patterns-established:
  - "Heuristic table format: rows are signal combinations, columns are exit behavior + dialogs + windows + diagnosis"
  - "Permission probe pattern: test once early, ask user once if denied, never ask again"

requirements-completed: [DIAG-03]

# Metrics
duration: 1min
completed: 2026-03-29
---

# Phase 10 Plan 02: Dialog Detection System Prompt Summary

**Multi-signal dialog detection heuristics added to agent system prompt with permission probe, common pattern guidance, and engine pre-config connection**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-29T00:30:05Z
- **Completed:** 2026-03-29T00:31:04Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments
- Dialog Detection section with permission probe, multi-signal heuristic table, common dialog patterns, and engine pre-config connection
- Phase 3 Adapt workflow updated with step 2b to check dialogs array after launch (mirrors Phase 1 Research step 2b)
- Section correctly placed between Engine-Aware Methodology (line 539) and macOS + Wine Domain Knowledge (line 606)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add dialog detection methodology section to system prompt** - `e57bce2` (feat)

## Files Created/Modified
- `Sources/cellar/Core/AIService.swift` - Added Dialog Detection section to system prompt with 39 new lines of methodology guidance

## Decisions Made
- Dialog Detection section placed between Engine-Aware Methodology and macOS + Wine Domain Knowledge (per plan interfaces spec)
- Phase 3 Adapt step 2b mirrors the existing Phase 1 Research step 2b pattern for consistency

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 10 (Dialog Detection) is now complete with both plans delivered
- Agent has full dialog detection capability: msgbox parsing tools (10-01) + reasoning methodology (10-02)
- Ready to proceed to Phase 11

---
*Phase: 10-dialog-detection*
*Completed: 2026-03-29*
