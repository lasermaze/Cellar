---
phase: 45-split-agenttools-into-session-and-runtime-actor-consolidate-configuration-and-sandbox-pageparser-fixes-through-allowlist
plan: "02"
subsystem: agent-loop
tags: [swift, agenttools, configuration, refactor, session-context]

requires:
  - phase: 45-01
    provides: fetch_page domain allowlist via PolicyResources

provides:
  - SessionConfiguration struct wrapping the six injected AgentTools init params
  - AgentTools.init(config:) replacing six-parameter init
  - Unified config access pattern via self.config.X in all tool extensions

affects:
  - 45-03 (SessionState extraction — will move mutable state from AgentTools next)
  - Any code constructing AgentTools directly

tech-stack:
  added: []
  patterns:
    - "SessionConfiguration value type — immutable per-session context injected at construction, cleanly separates config from mutable state"
    - "self.config.X access pattern across all tool extension files for the six injected properties"

key-files:
  created:
    - Sources/cellar/Core/SessionConfiguration.swift
  modified:
    - Sources/cellar/Core/AgentTools.swift
    - Sources/cellar/Core/AIService.swift
    - Sources/cellar/Core/Tools/ConfigTools.swift
    - Sources/cellar/Core/Tools/LaunchTools.swift
    - Sources/cellar/Core/Tools/DiagnosticTools.swift
    - Sources/cellar/Core/Tools/SaveTools.swift
    - Sources/cellar/Core/Tools/ResearchTools.swift

key-decisions:
  - "SessionConfiguration is a struct (value type) — six let fields, no behavior, no conformances needed at this stage"
  - "AIService.runAgentLoop public signature unchanged — SessionConfiguration constructed internally at the AgentTools call site"
  - "captureHandoff updated to config.gameId/config.entry — only the two config properties it directly referenced"
  - "tools.config.gameId in AIService.handleContribution (line 1020) fixed as part of Task 1 — discovered by build, not plan"

patterns-established:
  - "Config separation pattern: AgentTools.config holds injected immutable context; mutable session state remains bare on AgentTools (to be moved in P03)"

requirements-completed:
  - CFG-01

duration: 7min
completed: 2026-05-03
---

# Phase 45 Plan 02: SessionConfiguration struct — consolidate six AgentTools init params

**SessionConfiguration struct introduced, AgentTools.init(config:) replaces six-parameter init, all tool extensions migrated to self.config.X; swift build clean, 234/235 tests pass**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-03T00:28:59Z
- **Completed:** 2026-05-03T00:35:59Z
- **Tasks:** 2
- **Files modified:** 7 + 1 created

## Accomplishments
- Created `SessionConfiguration.swift` with six immutable `let` fields (gameId, entry, executablePath, bottleURL, wineURL, wineProcess)
- Replaced six-param `AgentTools.init` with `init(config: SessionConfiguration)`; `AIService.runAgentLoop` public signature unchanged
- Migrated all five tool extension files from bare `self.gameId` / `self.bottleURL` etc. to `self.config.X`

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SessionConfiguration struct + update AgentTools.init** - `1a60966` (feat)
2. **Task 2: Migrate tool extensions self.X → self.config.X** - `4a343ec` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified
- `Sources/cellar/Core/SessionConfiguration.swift` — New struct with six `let` fields; Codable not added (not needed at this stage)
- `Sources/cellar/Core/AgentTools.swift` — Six `let` config props collapsed to `let config: SessionConfiguration`; `init(config:)` added; `captureHandoff` updated
- `Sources/cellar/Core/AIService.swift` — Construction site updated to `AgentTools(config: SessionConfiguration(...))`; `tools.gameId` at line 1020 fixed to `tools.config.gameId`
- `Sources/cellar/Core/Tools/ConfigTools.swift` — wineProcess, wineURL, bottleURL, executablePath migrated
- `Sources/cellar/Core/Tools/LaunchTools.swift` — executablePath, bottleURL, gameId, wineProcess migrated
- `Sources/cellar/Core/Tools/DiagnosticTools.swift` — gameId, executablePath, bottleURL, wineProcess migrated (most occurrences)
- `Sources/cellar/Core/Tools/SaveTools.swift` — gameId, executablePath migrated
- `Sources/cellar/Core/Tools/ResearchTools.swift` — gameId migrated

## Decisions Made
- SessionConfiguration is a plain struct — six `let` fields, no conformances, no behavior. Clean value type for injection.
- `AIService.runAgentLoop` public signature preserved unchanged — the six individual parameters are still accepted and passed internally to `SessionConfiguration(...)`. Only the internal `AgentTools` construction changes.
- `captureHandoff` uses `config.gameId` and `config.entry` (the two config properties it references directly). Mutable state properties (`accumulatedEnv`, `installedDeps`, `launchCount`) stay as bare `self.X` until P03.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed tools.gameId reference at AIService line 1020**
- **Found during:** Task 1 (after updating AgentTools struct, initial build revealed additional reference)
- **Issue:** `AIService.handleContribution` accessed `tools.gameId` directly; not in the plan's listed construction site
- **Fix:** Changed `tools.gameId` → `tools.config.gameId` at line 1020
- **Files modified:** Sources/cellar/Core/AIService.swift
- **Verification:** Build passed after fix
- **Committed in:** `1a60966` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug, missing reference in plan's listed construction site)
**Impact on plan:** Fix was necessary for correctness; same file as Task 1's planned change, zero scope creep.

## Issues Encountered
None beyond the auto-fixed AIService reference above.

## Next Phase Readiness
- SessionConfiguration struct is live; AgentTools.init(config:) compiles and all callers updated
- Ready for P03: extract mutable session state (accumulatedEnv, launchCount, installedDeps, etc.) into a separate SessionState actor/struct
- Pre-existing Kimi test failure ("Kimi default model is moonshot-v1-128k") is unrelated to this plan — documented in STATE.md

---
*Phase: 45-split-agenttools*
*Completed: 2026-05-03*
