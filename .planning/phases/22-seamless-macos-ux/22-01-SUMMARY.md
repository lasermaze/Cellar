---
phase: 22-seamless-macos-ux
plan: "01"
subsystem: cli-ux
tags: [permissions, error-messages, screen-recording, actionable-errors]
dependency_graph:
  requires: []
  provides: [PermissionChecker, actionable-errors]
  affects: [LaunchCommand, AddCommand, ServeCommand, GameController]
tech_stack:
  added: []
  patterns: [advisory-permission-check, try-this-error-pattern]
key_files:
  created:
    - Sources/cellar/Core/PermissionChecker.swift
  modified:
    - Sources/cellar/Commands/LaunchCommand.swift
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Commands/ServeCommand.swift
    - Sources/cellar/Web/Controllers/GameController.swift
decisions:
  - "PermissionChecker uses CGPreflightScreenCaptureAccess() (no system prompt) — advisory only, never blocks launch"
  - "Only Screen Recording checked — Accessibility deferred (no current code uses Accessibility API per research)"
  - "ServeCommand suggestion uses portValue variable to reflect actual configured port"
metrics:
  duration: 82s
  completed_date: "2026-04-02"
  tasks_completed: 2
  files_changed: 5
requirements: [UX-01, UX-05]
---

# Phase 22 Plan 01: Pre-flight Permissions and Actionable Errors Summary

Pre-flight Screen Recording permission check with advisory warning and deep-link, plus "Try this:" actionable suggestions on every user-facing error across LaunchCommand, AddCommand, ServeCommand, and GameController.

## What Was Built

### PermissionChecker.swift (new)

Advisory Screen Recording permission check using `CGPreflightScreenCaptureAccess()`. When permission is missing, prints a multi-line advisory with a direct `open` command to System Settings > Privacy & Security > Screen Recording. Never blocks launch — informational only.

### LaunchCommand updates

- Calls `PermissionChecker.printWarningsIfNeeded()` immediately after Wine dependency check succeeds
- All 4 error sites updated with "Try this:" suggestions pointing to the right corrective action

### AddCommand updates

All 5 error sites updated:
1. Installer not found: `ls <path>` diagnostic suggestion
2. Wine not installed: `cellar` to reinstall dependencies
3. winetricks missing (force-proactive-deps flag): `brew install winetricks`
4. winetricks missing (reactive dep install): `brew install winetricks`
5. winetricks missing (fallback install): `brew install winetricks`

### ServeCommand update

Generic `Error: \(error)` now followed by port-specific diagnosis: `lsof -i :<port>` and `cellar serve --port <port+1>`. Uses the actual configured port value.

### GameController update

Wine-not-installed `Abort(.serviceUnavailable)` reason changed from bare "Wine is not installed" to "Wine is not installed. Visit /status for setup instructions." — consistent with the `/status` setup page.

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 | af3d932 | PermissionChecker + LaunchCommand actionable errors |
| Task 2 | 8e165e8 | Actionable errors in AddCommand, ServeCommand, GameController |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- PermissionChecker.swift: FOUND
- SUMMARY.md: FOUND
- Commit af3d932: FOUND
- Commit 8e165e8: FOUND
