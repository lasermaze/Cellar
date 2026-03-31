---
phase: 16-write-path
plan: "02"
subsystem: ui
tags: [vapor, leaf, settings, collective-memory, config]

# Dependency graph
requires:
  - phase: 16-01
    provides: CellarConfig.contributeMemory field and CellarConfig.load()/save() API
provides:
  - Web settings toggle for collective memory contribution opt-in/out
  - POST /settings/config route persisting to config.json via CellarConfig
affects: [collective-memory, web-ui]

# Tech tracking
tech-stack:
  added: []
  patterns: [hidden-input-checkbox for boolean form fields in Leaf templates]

key-files:
  created: []
  modified:
    - Sources/cellar/Web/Controllers/SettingsController.swift
    - Sources/cellar/Resources/Views/settings.leaf

key-decisions:
  - "Separate POST /settings/config route from /settings/keys — config.json fields vs .env fields have different persistence layers"
  - "ConfigInput decodes contributeMemory as Bool? so missing field leaves existing config unchanged"

patterns-established:
  - "Hidden input + checkbox pattern: hidden false input before checkbox ensures unchecked sends false to server"

requirements-completed: [WRIT-03]

# Metrics
duration: 1min
completed: 2026-03-30
---

# Phase 16 Plan 02: Settings Community Toggle Summary

**Web settings page gains a Community section with a checkbox to opt in/out of collective memory contribution, persisting via CellarConfig to config.json**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-31T02:52:44Z
- **Completed:** 2026-03-31T02:53:30Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added `contributeMemory: Bool` to `SettingsContext`, loaded from `CellarConfig.load()` in the GET /settings handler
- Added `POST /settings/config` route that decodes `ConfigInput` and persists via `CellarConfig.save()`
- Added Community section to `settings.leaf` with hidden-input + checkbox pattern and help text

## Task Commits

Each task was committed atomically:

1. **Task 1: Settings controller config route and template toggle** - `aa1a536` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `Sources/cellar/Web/Controllers/SettingsController.swift` - Added contributeMemory to SettingsContext, POST /settings/config route, ConfigInput struct
- `Sources/cellar/Resources/Views/settings.leaf` - Added Community section with checkbox toggle

## Decisions Made

- Separate POST /settings/config from POST /settings/keys: config.json and .env are distinct persistence layers; mixing them would conflate concerns
- ConfigInput uses `Bool?` so a missing field leaves the existing config value unchanged

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 16 write path is now complete: CollectiveMemoryWriteService, AIService contribution hook, and web settings toggle are all done
- The full contribution flow (prompt on CLI, toggle on web, write service, GitHub push) is wired end-to-end
- Ready for any remaining v1.2 phases or integration testing

---
*Phase: 16-write-path*
*Completed: 2026-03-30*
