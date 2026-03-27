---
phase: 01-cossacks-launches
plan: 02
subsystem: infra
tags: [swift, foundation-process, pipe, readabilityhandler, homebrew, wine, gcenx, interactive-cli]

# Dependency graph
requires:
  - phase: 01-01
    provides: DependencyChecker.checkAll() + DependencyStatus, Swift package scaffold
provides:
  - GuidedInstaller struct with installHomebrew() and installWine() using real-time pipe streaming
  - StatusCommand: full implementation detecting deps and walking user through guided install
  - runStreamingProcess helper pattern with post-exit drain (readabilityHandler EOF workaround)
affects: [01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pipe + readabilityHandler for real-time process output streaming (stdout and stderr separately)"
    - "Post-exit pipe drain via readDataToEndOfFile() after waitUntilExit() (corelibs-foundation #3275 workaround)"
    - "Sequential dep install flow: Homebrew first, Wine only after Homebrew confirmed present"
    - "fflush(stdout) before readLine() to ensure prompt appears before blocking on input"

key-files:
  created:
    - Sources/cellar/Core/GuidedInstaller.swift
  modified:
    - Sources/cellar/Commands/StatusCommand.swift

key-decisions:
  - "installHomebrew() uses /bin/bash -c with the official Homebrew install URL (brew doesn't exist yet at this point)"
  - "installWine() resolves brew binary via DependencyChecker().detectHomebrew() rather than hardcoding path"
  - "StatusCommand re-checks DependencyChecker after each install attempt for accurate updated status"
  - "Retry on failure re-calls the install method recursively (simple, handles repeated failures without extra state)"

patterns-established:
  - "runStreamingProcess: private helper encapsulating Pipe+readabilityHandler+drain for reuse in GuidedInstaller"
  - "Post-exit drain pattern: readabilityHandler = nil after drain to prevent spurious callbacks"
  - "StatusCommand install flow: homebrew gate first, wine only offered when homebrew confirmed present"

requirements-completed: [SETUP-03, SETUP-04]

# Metrics
duration: 2min
completed: 2026-03-27
---

# Phase 1 Plan 02: Guided Installer and Status Command Summary

**GuidedInstaller with real-time Pipe streaming for Homebrew and Wine (--no-quarantine) install, wired into StatusCommand for dep-detect-then-guide UX on first run**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-27T01:04:35Z
- **Completed:** 2026-03-27T01:05:59Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- GuidedInstaller struct providing installHomebrew() and installWine() with full real-time streaming via Foundation.Process + Pipe
- Private runStreamingProcess helper centralises Pipe setup, readabilityHandler attachment, waitUntilExit(), and post-exit drain (EOF bug workaround)
- Wine install command uses --no-quarantine flag (prevents macOS Gatekeeper "damaged" error on wine-crossover)
- StatusCommand fully implemented: detects Homebrew/Wine/GPTK, prints status table, prompts interactively for each missing dep, re-checks after install, shows next-step guidance when all deps present

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement GuidedInstaller with real-time streaming** - `5d5b035` (feat)
2. **Task 2: Wire StatusCommand with dependency detection and guided install flow** - `d5328d0` (feat)

## Files Created/Modified

- `Sources/cellar/Core/GuidedInstaller.swift` - GuidedInstaller struct with installHomebrew(), installWine(), and private runStreamingProcess helper
- `Sources/cellar/Commands/StatusCommand.swift` - Full implementation replacing stub; DependencyChecker + GuidedInstaller integration

## Decisions Made

- installHomebrew() invokes `/bin/bash -c` with the official Homebrew curl/install URL since `brew` doesn't exist yet during that step.
- installWine() calls DependencyChecker().detectHomebrew() to resolve the brew binary path rather than hardcoding /opt/homebrew or /usr/local — correctly handles both ARM and Intel Macs.
- StatusCommand re-runs DependencyChecker().checkAll() after each install attempt so the updated status reflects reality, not the pre-install snapshot.
- Retry on install failure re-calls the install method recursively. This keeps each install method self-contained without needing explicit retry loops or external state.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- GuidedInstaller is complete; future plans (01-03 bottle creation) can focus on Wine bottle management without revisiting install flow
- StatusCommand provides the first interactive surface for a fresh-Mac user; the dep-check pattern (DependencyChecker().checkAll()) is available to any subsequent command
- runStreamingProcess pattern established in GuidedInstaller should be considered the template for all subprocess output streaming in subsequent plans (WineProcess.swift uses the same pattern)

---
*Phase: 01-cossacks-launches*
*Completed: 2026-03-27*
