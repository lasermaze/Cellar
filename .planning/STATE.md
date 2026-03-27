# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-25)

**Core value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.
**Current focus:** Phase 1 — Cossacks Launches

## Current Position

Phase: 1 of 5 (Cossacks Launches)
Plan: 1 of ? in current phase
Status: In progress
Last activity: 2026-03-27 — Plan 01 complete: Swift package scaffold + DependencyChecker

Progress: [█░░░░░░░░░] 5%

## Performance Metrics

**Velocity:**
- Total plans completed: 1
- Average duration: 7 min
- Total execution time: 0.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-cossacks-launches | 1 | 7 min | 7 min |

**Recent Trend:**
- Last 5 plans: 7 min
- Trend: —

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Pre-planning: Wine via Gcenx tap (not bundled) — wine-stable deprecated Sep 2026
- Pre-planning: wined3d/OpenGL for DX8/DX9 — only viable path for old-game wedge
- Pre-planning: API-first AI — simpler than local inference for MVP
- Pre-planning: Cossacks: European Wars as flagship test game
- 2026-03-25: Roadmap restructured from horizontal layers to vertical functional slices — Phase 1 delivers the full pipeline for one game rather than foundation infrastructure only
- 2026-03-27 (01-01): macOS 14 minimum required for Swift Testing framework on Command Line Tools
- 2026-03-27 (01-01): DependencyChecker uses testable init(existingPaths:) pattern instead of protocol injection — simpler, avoids Sendable complexity in Swift 6
- 2026-03-27 (01-01): swift test requires -Xswiftc -F flag to find Testing.framework on Command Line Tools

### Pending Todos

None.

### Blockers/Concerns

- Swift TUI ecosystem is weak — v1 is CLI-only (TUI deferred to v2), but raw ANSI may be needed for good UX
- Gcenx tap is a single-maintainer dependency — worth monitoring
- macOS OpenGL is deprecated — only DX8/DX9 path, could break in a future macOS version
- `swift test` requires framework search path flag for Swift Testing — future plans should document this or configure it in Package.swift

## Session Continuity

Last session: 2026-03-27
Stopped at: Completed 01-01-PLAN.md — package scaffold, models, CellarPaths, DependencyChecker
Resume file: None
