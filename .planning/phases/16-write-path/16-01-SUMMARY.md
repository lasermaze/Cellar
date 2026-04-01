---
phase: 16-write-path
plan: 01
subsystem: collective-memory
tags: [github-api, collective-memory, write-path, opt-in, deduplication]

# Dependency graph
requires:
  - phase: 14-memory-entry-schema
    provides: CollectiveMemoryEntry, WorkingConfig, EnvironmentFingerprint, slugify()
  - phase: 15-read-path
    provides: CollectiveMemoryService patterns (URLSession + DispatchSemaphore, GitHubAuthService)
  - phase: 13-github-app-authentication
    provides: GitHubAuthService.shared.getToken(), memoryRepo
provides:
  - CollectiveMemoryWriteService with GET+merge+PUT flow against GitHub Contents API
  - CellarConfig.contributeMemory opt-in preference field with save()
  - AIService post-loop contribution hook with CLI opt-in prompt
affects: [17-web-memory-ui, settings-controller, collective-memory]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "DispatchSemaphore + ResultBox for synchronous HTTP (same as CollectiveMemoryService)"
    - "GET-merge-PUT pattern for GitHub Contents API with 409 retry"
    - "isWebContext flag passed to contribution hook to distinguish CLI vs web"

key-files:
  created:
    - Sources/cellar/Core/CollectiveMemoryWriteService.swift
  modified:
    - Sources/cellar/Persistence/CellarConfig.swift
    - Sources/cellar/Core/AIService.swift

key-decisions:
  - "isWebContext bool passed to handleContributionIfNeeded rather than checking tools.askUserHandler (which is always non-nil due to default value)"
  - "pushEntry() uses a MergeResult enum (ok/conflict/error) to communicate PUT outcome cleanly"
  - "logPushEvent() uses FileHandle.seekToEndOfFile() for append, creates file if missing"

patterns-established:
  - "Collective memory push: same environment hash increments confirmations, different hash appends new entry"
  - "Silent failure: all push errors logged to ~/.cellar/logs/memory-push.log, never surfaced to user"
  - "Opt-in preference: nil=unasked, true=opted-in, false=declined; saved to CellarConfig.contributeMemory"

requirements-completed: [WRIT-01, WRIT-02, WRIT-03]

# Metrics
duration: 3min
completed: 2026-03-30
---

# Phase 16 Plan 01: Write Path — Collective Memory Write Service Summary

**GitHub Contents API write service with GET+merge+PUT deduplication, opt-in CLI prompt, and silent failure handling — closes the community feedback loop after successful agent launches**

## Performance

- **Duration:** ~3 min
- **Started:** 2026-03-30T02:47:16Z
- **Completed:** 2026-03-30T02:50:10Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- CollectiveMemoryWriteService with complete GET+merge+PUT flow: same environment hash increments confirmations count; different hash appends new entry; new game creates file
- 409 conflict handling with one retry (re-fetch + re-merge + re-PUT with fresh SHA)
- CellarConfig extended with `contributeMemory: Bool?` field (nil=unasked, true=opted-in, false=declined) and atomic `save()` method
- AIService post-loop hook calls write service after `taskState == .savedAfterConfirm`; CLI shows yes/no prompt on first push opportunity; web skips prompt but still pushes if opted in

## Task Commits

1. **Task 1: CollectiveMemoryWriteService and CellarConfig extension** - `1f13e6c` (feat)
2. **Task 2: AIService post-loop contribution hook with opt-in prompt** - `ed098c5` (feat)

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `Sources/cellar/Core/CollectiveMemoryWriteService.swift` - GitHub Contents API write service: push(), GET+merge+PUT, 409 retry, logPushEvent()
- `Sources/cellar/Persistence/CellarConfig.swift` - Added contributeMemory: Bool? field with CodingKey contribute_memory; added save() static method
- `Sources/cellar/Core/AIService.swift` - Added handleContributionIfNeeded() private method; inserted hook in result.completed block before return .success

## Decisions Made

- **isWebContext flag:** `tools.askUserHandler` is always non-nil (has a default CLI implementation), so checking it as nil would never detect web context. Instead, `runAgentLoop`'s optional `askUserHandler` parameter is checked and `isWebContext: askUserHandler != nil` is passed explicitly to `handleContributionIfNeeded`.
- **MergeResult enum:** The `performMergeAndPut` helper returns `ok/conflict/error` to allow the caller to decide whether to retry on 409 vs log and return on error.
- **Log append pattern:** `FileHandle.seekToEndOfFile()` for appending to existing log; `Data.write(to:options:.atomic)` for creating new log file.

## Deviations from Plan

None — plan executed exactly as written. The `isWebContext` distinction was handled slightly differently (passing flag vs checking tools.askUserHandler) due to askUserHandler always having a default value, but this is implementation-level, not a scope change.

## Issues Encountered

None — build passed cleanly on first attempt for both tasks.

## User Setup Required

None — no external service configuration required. GitHub auth was handled in Phase 13.

## Next Phase Readiness

- Write path complete. Community configs will be pushed to the collective memory repo after successful agent sessions.
- Phase 17 (web memory UI) can now add a settings toggle for `contributeMemory` via SettingsController — the field is persisted in CellarConfig.
- The opt-in state (`contributeMemory`) is readable from web settings and can be toggled without touching the write service.

## Self-Check: PASSED

- FOUND: Sources/cellar/Core/CollectiveMemoryWriteService.swift
- FOUND: Sources/cellar/Persistence/CellarConfig.swift (modified)
- FOUND: Sources/cellar/Core/AIService.swift (modified)
- FOUND: .planning/phases/16-write-path/16-01-SUMMARY.md
- FOUND: commit 1f13e6c (Task 1)
- FOUND: commit ed098c5 (Task 2)

---
*Phase: 16-write-path*
*Completed: 2026-03-30*
