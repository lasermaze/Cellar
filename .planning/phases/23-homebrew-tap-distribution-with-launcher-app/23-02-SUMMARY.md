---
phase: 23-homebrew-tap-distribution-with-launcher-app
plan: "02"
subsystem: cli
tags: [homebrew, app-bundle, swift-argumentparser, filesystem]

requires:
  - phase: 23-homebrew-tap-distribution-with-launcher-app
    provides: Homebrew formula that builds and installs Cellar.app to libexec

provides:
  - cellar install-app CLI subcommand that copies Cellar.app from Homebrew libexec to ~/Applications
  - Automatic ~/Applications directory creation if missing
  - Overwrite support (removes existing .app before copy for clean updates)
  - Actionable error when .app not found (guides user to brew install path)

affects:
  - homebrew-formula
  - distribution-docs

tech-stack:
  added: []
  patterns:
    - "Binary symlink resolution: resolveSymlinksInPath on CommandLine.arguments[0] to discover Homebrew install root"
    - "App location derived from binary: bin/cellar -> (up one) version root -> libexec/Cellar.app"

key-files:
  created:
    - Sources/cellar/Commands/InstallAppCommand.swift
  modified:
    - Sources/cellar/Cellar.swift

key-decisions:
  - "Binary resolved via (path as NSString).resolvingSymlinksInPath to follow Homebrew symlinks from /opt/homebrew/bin/cellar to actual version directory"
  - "App path derived as ../libexec/Cellar.app relative to the bin/ directory (after symlink resolution) — no brew --prefix subprocess needed"
  - "InstallAppCommand placed last in subcommands array (after RemoveCommand) as an infrequently used utility"

requirements-completed: [DIST-03]

duration: 1min
completed: 2026-04-02
---

# Phase 23 Plan 02: Install-App Subcommand Summary

**`cellar install-app` subcommand that discovers Cellar.app in Homebrew libexec via symlink resolution and copies it to ~/Applications with overwrite support**

## Performance

- **Duration:** ~1 min
- **Started:** 2026-04-02T06:29:55Z
- **Completed:** 2026-04-02T06:30:55Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Created `InstallAppCommand.swift` implementing the full copy workflow: locate via symlink resolution, create ~/Applications if missing, overwrite-safe copy
- Registered `InstallAppCommand.self` in `CellarCLI.subcommands` so `cellar install-app` appears in help output
- Actionable error message distinguishes Homebrew install vs source build scenarios

## Task Commits

Each task was committed atomically:

1. **Task 1: InstallAppCommand subcommand** - `f75ec2c` (feat)
2. **Task 2: Register install-app subcommand in CellarCLI** - `f826b09` (feat)

## Files Created/Modified

- `Sources/cellar/Commands/InstallAppCommand.swift` - CLI subcommand: locates Homebrew libexec .app, creates ~/Applications, copies with overwrite
- `Sources/cellar/Cellar.swift` - Added InstallAppCommand.self to subcommands array

## Decisions Made

- Binary symlink resolved with `(path as NSString).resolvingSymlinksInPath` — follows Homebrew's bin → Cellar/version/bin symlink chain to find the actual version directory without spawning a `brew --prefix` subprocess
- App path computed as `<version-root>/libexec/Cellar.app` by going up one level from the resolved bin directory — simple and deterministic for Homebrew installs
- InstallAppCommand placed last in subcommands (after RemoveCommand) as a one-time setup utility

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `cellar install-app` is ready for inclusion in Homebrew formula post-install instructions
- The formula's post_install step should call this or document it for users after `brew install cellar`
- Remaining phase 23 plans can build on this to complete the full Homebrew tap distribution workflow

---
*Phase: 23-homebrew-tap-distribution-with-launcher-app*
*Completed: 2026-04-02*
