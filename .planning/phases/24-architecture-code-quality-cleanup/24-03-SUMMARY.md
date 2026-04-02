---
phase: 24-architecture-code-quality-cleanup
plan: 03
subsystem: core
tags: [known-dll, dgvoodoo2, dxwrapper, dxvk, error-logging, stderr, github-api]

# Dependency graph
requires:
  - phase: 16-write-path
    provides: CollectiveMemoryWriteService push flow
  - phase: 15-read-path
    provides: CollectiveMemoryService fetch flow
  - phase: 13-github-app-authentication
    provides: GitHubAuthService token management
provides:
  - KnownDLLRegistry with 4 entries: cnc-ddraw, dgvoodoo2, dxwrapper, dxvk
  - stderr error logging across CollectiveMemoryService, CollectiveMemoryWriteService, GitHubAuthService
affects: [agent, dll-placement, github-services]

# Tech tracking
tech-stack:
  added: []
  patterns: [fputs(message, stderr) for service error logging without affecting user output]

key-files:
  created: []
  modified:
    - Sources/cellar/Models/KnownDLLRegistry.swift
    - Sources/cellar/Core/CollectiveMemoryService.swift
    - Sources/cellar/Core/CollectiveMemoryWriteService.swift
    - Sources/cellar/Core/GitHubAuthService.swift

key-decisions:
  - "fputs(message, stderr) pattern used for all service error logging — keeps agent output clean while exposing failures via terminal stderr"
  - "404 not logged in CollectiveMemoryService — expected no-entry case, not a failure"
  - "409 conflict logged as informational in CollectiveMemoryWriteService — signals retry not an error"
  - "Auth unavailable path not logged — expected graceful degradation when GitHub App not configured"

patterns-established:
  - "fputs('[ServiceName] Descriptive message for context', stderr) as the canonical error logging pattern for GitHub-dependent services"

requirements-completed:
  - KnownDLLRegistry expansion
  - GitHub API error reporting

# Metrics
duration: 15min
completed: 2026-04-02
---

# Phase 24 Plan 03: DLL Registry Expansion and Service Error Logging Summary

**KnownDLLRegistry expanded from 1 to 4 entries (cnc-ddraw + dgVoodoo2 + dxwrapper + DXVK), and CollectiveMemoryService, CollectiveMemoryWriteService, and GitHubAuthService now log failures to stderr via fputs**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-02T15:00:00Z
- **Completed:** 2026-04-02T15:09:27Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Added 3 new DLL wrapper entries to KnownDLLRegistry: dgVoodoo2 (D3D11 wrapper with conf file), dxwrapper (DirectDraw compat wrapper with ini), and DXVK (Vulkan-based D3D9/10/11 for syswow64)
- Added fputs stderr logging to all non-expected failure paths in CollectiveMemoryService (4 call sites), CollectiveMemoryWriteService (6 call sites), and GitHubAuthService (4 call sites)
- Zero behavioral changes — no return types, control flow, or user-facing output modified

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand KnownDLLRegistry with dgVoodoo2, dxwrapper, and DXVK** - `c9e334f` (feat)
2. **Task 2: Add fputs stderr error logging to GitHub services** - `fd75b4b` (feat)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified
- `Sources/cellar/Models/KnownDLLRegistry.swift` - Added 3 new KnownDLL entries; registry now has 4 entries total
- `Sources/cellar/Core/CollectiveMemoryService.swift` - 4 fputs calls added on Wine detection failure, network error, non-404 HTTP error, JSON decode failure
- `Sources/cellar/Core/CollectiveMemoryWriteService.swift` - 6 fputs calls on push failures, network errors (GET/PUT), encode failure, 409 conflict (informational), and non-2xx PUT
- `Sources/cellar/Core/GitHubAuthService.swift` - 4 fputs calls on JWT signing failure, token decode failure, network errors, and non-2xx HTTP responses

## Decisions Made
- `fputs(message, stderr)` used throughout — not `print()` — so service errors are visible in terminal but never mixed into agent's stdout response output
- 404 in CollectiveMemoryService deliberately not logged — it means "no entry exists yet" which is normal expected behavior
- 409 conflict in CollectiveMemoryWriteService logged as informational (not error) since the service retries automatically
- Auth unavailable path in both services not logged — when GitHub App is not configured, silent degradation is the intended behavior

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

Pre-existing build errors in `Sources/cellar/Core/AIService.swift` and `Sources/cellar/Core/AgentLoop.swift` (async/await migration issues from Phase 24 plan scope). These are out of scope for this plan — deferred to their respective Phase 24 plans (24-01, 24-02).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- KnownDLLRegistry expansion is complete; agent can now request dgvoodoo2, dxwrapper, and dxvk DLL placements
- Service error logging is in place; debugging GitHub API failures is now possible via stderr
- Pre-existing async/await build errors in AIService and AgentLoop remain for Phase 24-01 and 24-02 to address

---
*Phase: 24-architecture-code-quality-cleanup*
*Completed: 2026-04-02*
