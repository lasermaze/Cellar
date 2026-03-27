---
phase: 01-cossacks-launches
plan: 04
subsystem: cli
tags: [swift, argumentparser, wine, wineprocess, cellarstore, json, foundation-process, sigint, dispatchsource]

# Dependency graph
requires:
  - phase: 01-03
    provides: WineProcess, BottleManager, RecipeEngine, Cossacks recipe JSON
  - phase: 01-02
    provides: DependencyChecker, CellarPaths, GameEntry, LaunchResult models
  - phase: 01-01
    provides: Recipe model, project scaffold, ArgumentParser setup
affects: [02-ai-recipes, 02-library]

provides:
  - CellarStore: read/write games.json with ISO8601 dates, findGame/addGame/updateGame API
  - AddCommand: verify installer, create Wine bottle, run GOG installer with silent flags, persist game entry
  - LogCommand: list all logs or show most recent for a game
  - LaunchCommand: full pipeline — find game, check bottle, load recipe, apply recipe, log capture, SIGINT handling, quick-exit detection, validation prompt, result persistence
  - ValidationPrompt: post-launch flow with quick-exit detection (<2s), wineserver shutdown prompt, did-game-reach-menu prompt

# Tech tracking
tech-stack:
  added: []
  patterns:
    - CellarStore uses JSONEncoder/JSONDecoder with .prettyPrinted + .iso8601 strategy
    - signal(SIGINT, SIG_IGN) + DispatchSource.makeSignalSource for Ctrl+C handling without process exit
    - slugify() derives game ID from installer parent directory name (lowercase, spaces to hyphens, strip non-alphanumeric)
    - GOG install path convention: {bottleURL}/drive_c/GOG Games/Cossacks - European Wars/{executable}

key-files:
  created:
    - Sources/cellar/Persistence/CellarStore.swift
    - Sources/cellar/Commands/LogCommand.swift
    - Sources/cellar/Core/ValidationPrompt.swift
  modified:
    - Sources/cellar/Commands/AddCommand.swift
    - Sources/cellar/Commands/LaunchCommand.swift
    - Sources/cellar/Cellar.swift

key-decisions:
  - "GOG install path hardcoded as drive_c/GOG Games/Cossacks - European Wars/ — GOG installer behavior is predictable; easy fix if it differs in practice"
  - "SIGINT handler kills wineserver (-k) rather than Process.terminate() — WineProcess.run() is synchronous and doesn't expose the underlying Process object externally; wineserver -k is the correct Wine-aware termination"
  - "AddCommand slugify: lowercase + spaces to hyphens + strip non-alphanumeric — produces stable IDs like cossacks-european-wars from directory names"
  - "CellarStore.loadGames() returns [] (not error) when games.json is absent — clean first-run behavior"

patterns-established:
  - "Game ID = slugified installer parent directory name — user controls naming by naming their game folder"
  - "ValidationPrompt.run() returns nil on quick-exit (<2s) — nil result means no record written, crash inferred from logs"

requirements-completed: [LAUNCH-01, LAUNCH-02, LAUNCH-03]

# Metrics
duration: 3min
completed: 2026-03-27
---

# Phase 1 Plan 04: AddCommand, LaunchCommand, CellarStore, and LogCommand Summary

**Full end-to-end Cellar CLI pipeline: bottle creation, GOG installer execution, recipe-based game launch with real-time log capture, SIGINT handling, quick-exit detection, and post-launch validation prompt**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-27T01:09:41Z
- **Completed:** 2026-03-27T01:12:41Z
- **Tasks:** 2 of 3 complete (Task 3 is human-verify checkpoint)
- **Files modified:** 6

## Accomplishments

- CellarStore persists games.json with ISO8601 dates, atomic writes, and graceful empty-file handling
- AddCommand: verifies installer exists, derives game ID from directory name via slugify, creates bottle, runs GOG installer with /VERYSILENT /SP- /SUPPRESSMSGBOXES, saves entry
- LogCommand: shows most recent log or lists all logs with --list flag
- LaunchCommand: full pipeline — dependency check, game lookup, bottle check, recipe load, recipe apply, log file setup, SIGINT handler, wine launch, elapsed timing, ValidationPrompt, result persistence
- ValidationPrompt: quick-exit detection (<2s threshold), wineserver shutdown prompt, menu-reach validation prompt, returns LaunchResult or nil

## Task Commits

Each task was committed atomically:

1. **Task 1: CellarStore, AddCommand, LogCommand** - `fdd9971` (feat)
2. **Task 2: LaunchCommand and ValidationPrompt** - `2126cdc` (feat)

## Files Created/Modified

- `Sources/cellar/Persistence/CellarStore.swift` - games.json read/write with ISO8601 dates, findGame/addGame/updateGame
- `Sources/cellar/Commands/AddCommand.swift` - Replaced stub: installer verification, bottle creation, GOG installer execution, game entry persistence
- `Sources/cellar/Commands/LogCommand.swift` - New command: show latest log or list all with --list flag
- `Sources/cellar/Commands/LaunchCommand.swift` - Replaced stub: full launch pipeline with SIGINT handling and validation
- `Sources/cellar/Core/ValidationPrompt.swift` - Post-launch prompts: quick-exit check, wineserver shutdown, menu validation
- `Sources/cellar/Cellar.swift` - Added LogCommand to subcommands array

## Decisions Made

- GOG install path is hardcoded as `drive_c/GOG Games/Cossacks - European Wars/` — GOG's installer consistently uses this path, and it's a trivial fix if it differs after real-world testing.
- SIGINT handler uses `wineserver -k` rather than `Process.terminate()` — WineProcess.run() is synchronous and doesn't expose the underlying Process handle, and wineserver -k is the correct Wine-aware way to terminate all processes in a prefix.
- slugify() strips to lowercase letters, numbers, and hyphens — produces stable IDs from arbitrary game folder names; e.g., "Cossacks European Wars" -> "cossacks-european-wars".

## Deviations from Plan

None — plan executed exactly as written. The `interrupted` variable in the SIGINT handler was removed (Rule 1: unused variable cleanup) before commit, but that was a minor self-correction during the write phase, not a plan deviation.

## Issues Encountered

- Swift compiler initially warned about the `interrupted` flag in the SIGINT handler being written but never read. Removed the flag and simplified the handler to directly call `killWineserver()` — the flag was never needed since `ValidationPrompt.run()` already handles post-exit logic.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Complete CLI pipeline ready for human testing: `cellar add /path/to/setup.exe` -> `cellar launch cossacks-european-wars`
- WineProcess streams output in real-time and captures to log file simultaneously
- ValidationPrompt fires after every exit >2s, records result in games.json
- Pending: Task 3 human-verify checkpoint — user should test with real Cossacks installer

---
*Phase: 01-cossacks-launches*
*Completed: 2026-03-27*

## Self-Check: PASSED

- Sources/cellar/Persistence/CellarStore.swift: FOUND
- Sources/cellar/Commands/AddCommand.swift: FOUND
- Sources/cellar/Commands/LogCommand.swift: FOUND
- Sources/cellar/Commands/LaunchCommand.swift: FOUND
- Sources/cellar/Core/ValidationPrompt.swift: FOUND
- Sources/cellar/Cellar.swift: FOUND
- Commit fdd9971 (Task 1): FOUND
- Commit 2126cdc (Task 2): FOUND
