---
phase: 40-wiki-batch-ingest
plan: 02
subsystem: wiki
tags: [wiki, ingest, cli, ArgumentParser, WikiCommand, IngestCommand, CompatibilityService, SuccessDatabase]

# Dependency graph
requires:
  - phase: 40-01
    provides: WikiIngestService.ingest(gameName:) pipeline and CompatibilityService.fetchPopularGames(limit:)
provides:
  - WikiCommand group (ParsableCommand) registered in Cellar subcommands
  - IngestCommand (AsyncParsableCommand) with single/--popular/--all-local modes
  - cellar wiki ingest CLI entry point wired to WikiIngestService and CompatibilityService
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Parent ParsableCommand group with AsyncParsableCommand subcommand (nested via extension)
    - validate() mode-count guard enforcing exactly-one-of-N flags

key-files:
  created:
    - Sources/cellar/Commands/WikiCommand.swift
  modified:
    - Sources/cellar/Cellar.swift

key-decisions:
  - "IngestCommand nested as WikiCommand extension (not top-level) for clean scoping"
  - "--all-local uses customLong('all-local') to produce kebab-case CLI flag matching convention"

patterns-established:
  - "WikiCommand: ParsableCommand group with no run(); subcommands are AsyncParsableCommand extensions"

requirements-completed: []

# Metrics
duration: 3min
completed: 2026-04-15
---

# Phase 40 Plan 02: Wiki CLI Command Summary

**WikiCommand group + IngestCommand CLI with single-game, --popular (Lutris top-50), and --all-local (SuccessDB) batch modes; registered in cellar subcommands**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-04-15T01:12:43Z
- **Completed:** 2026-04-15T01:15:32Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Created `WikiCommand.swift` with `WikiCommand` (ParsableCommand group) and `IngestCommand` (AsyncParsableCommand) as a nested extension
- `IngestCommand.validate()` enforces exactly one of three modes; `run()` implements all three: single game, `--popular` (top 50 Lutris games), `--all-local` (all SuccessDB records)
- Batch modes print `[N/total] Game Name...` progress and sleep 2 seconds between requests to respect the Worker rate limit
- Registered `WikiCommand.self` in `Cellar.swift` subcommands array; `cellar wiki ingest --help` is fully functional

## Task Commits

1. **Task 1: Create WikiCommand and IngestCommand** — `1158ad6` (feat)
2. **Task 2: Register WikiCommand in Cellar.swift** — `c6a4270` (feat)

## Files Created/Modified

- `/Users/peter/Documents/Cellar/Sources/cellar/Commands/WikiCommand.swift` — WikiCommand group + IngestCommand with all three modes, validate(), 2s sleep
- `/Users/peter/Documents/Cellar/Sources/cellar/Cellar.swift` — WikiCommand.self added to subcommands array

## Decisions Made

- IngestCommand nested inside WikiCommand as an extension — cleaner scoping than a separate top-level struct
- `--all-local` flag uses `.customLong("all-local")` to produce a kebab-case flag consistent with CLI conventions (the Swift property name `allLocal` would otherwise produce `--allLocal`)

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `cellar wiki ingest "Game Name"`, `cellar wiki ingest --popular`, and `cellar wiki ingest --all-local` are all functional
- Phase 40 is complete — wiki batch ingest pipeline (P01) and CLI command (P02) both shipped

---
*Phase: 40-wiki-batch-ingest*
*Completed: 2026-04-15*
