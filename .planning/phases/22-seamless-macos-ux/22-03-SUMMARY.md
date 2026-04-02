---
phase: 22-seamless-macos-ux
plan: "03"
subsystem: cli
tags: [wine, dependency-install, bottle-scanner, guided-installer, executable-resolution]

# Dependency graph
requires:
  - phase: 22-seamless-macos-ux
    provides: GuidedInstaller (installHomebrew, installWine), BottleScanner.scanForExecutables + findExecutable, PermissionChecker

provides:
  - AddCommand offers inline Wine/Homebrew installation when dependencies missing
  - LaunchCommand resolves game executables dynamically via BottleScanner (works for any game)
  - Hardcoded "GOG Games/Cossacks - European Wars" path removed from LaunchCommand

affects: [cellar-add-flow, cellar-launch-flow, first-run-ux]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Inline dependency resolution: check -> install -> re-check before proceeding"
    - "BottleScanner as canonical executable resolver: findExecutable by name, fallback to first, error with actionable message"

key-files:
  created: []
  modified:
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Commands/LaunchCommand.swift

key-decisions:
  - "AddCommand re-checks status after each install step (Homebrew must succeed before Wine can install)"
  - "winetricks not installed inline in AddCommand — only needed for specific games, not initial add flow"
  - "LaunchCommand falls back to first discovered executable if recipe exe not found by name — avoids hard failure when recipe name slightly differs"

patterns-established:
  - "Inline install pattern: var status = check(); if !ok { install(); status = check() again }"
  - "BottleScanner resolution: findExecutable(named:) -> discovered.first -> error with actionable message"

requirements-completed: [UX-02, UX-04]

# Metrics
duration: 4min
completed: 2026-04-02
---

# Phase 22 Plan 03: Seamless macOS UX — Inline Deps and Dynamic Exe Resolution Summary

**AddCommand installs missing Wine/Homebrew inline via GuidedInstaller; LaunchCommand resolves executables via BottleScanner instead of a hardcoded GOG path**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-04-02T05:41:00Z
- **Completed:** 2026-04-02T05:44:22Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- AddCommand no longer exits with an error when Wine is missing — it installs dependencies inline using the existing GuidedInstaller (which already handles retries and streaming output)
- LaunchCommand's hardcoded `GOG Games/Cossacks - European Wars` path replaced with BottleScanner dynamic discovery — now works for any game with a bundled recipe
- Both commands maintain actionable "Try this:" error messages on failure

## Task Commits

Each task was committed atomically:

1. **Task 1: Inline dependency installation in AddCommand** - `cf59cb0` (feat)
2. **Task 2: Replace hardcoded GOG path with BottleScanner** - `1ca666b` (feat)

**Plan metadata:** (docs commit after SUMMARY)

## Files Created/Modified
- `Sources/cellar/Commands/AddCommand.swift` - Replaced early-exit guard with inline GuidedInstaller flow; `var status` pattern enables re-check after each install step
- `Sources/cellar/Commands/LaunchCommand.swift` - Replaced 2-line hardcoded GOG path block with 8-line BottleScanner resolution with named exe lookup, first-exe fallback, and error

## Decisions Made
- Re-check DependencyStatus after each install step so Homebrew prerequisite is validated before Wine install is attempted
- Do not install winetricks inline — it's only needed for specific game deps, not for the core add flow
- LaunchCommand falls back to `discovered.first` when recipe exe name not matched — prevents hard failure when recipe name differs slightly from installed filename

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 22 Plan 03 is the final plan in the phase. Phase 22 (Seamless macOS UX) is complete.
- All three plans delivered: PermissionChecker + actionable errors (22-01), GameRemover + cellar remove (22-02), inline deps + dynamic exe resolution (22-03).

---
*Phase: 22-seamless-macos-ux*
*Completed: 2026-04-02*
