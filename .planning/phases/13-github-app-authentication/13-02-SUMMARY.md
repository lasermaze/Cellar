---
phase: 13-github-app-authentication
plan: 02
subsystem: auth
tags: [github-app, jwt, rs256, security-framework, swift, installation-token, token-cache]

requires:
  - phase: 13-github-app-authentication plan 01
    provides: GitHubModels.swift with GitHubCredentials, GitHubAppConfig, InstallationTokenResponse, GitHubAuthResult, GitHubAuthError; placeholder github-app.json and github-app.pem; CellarPaths.defaultMemoryRepo

provides:
  - GitHubAuthService.swift — complete GitHub App auth service callable via getToken()
  - RS256 JWT generation using Security.framework SecKeyCreateWithData + SecKeyCreateSignature
  - Installation token exchange via POST /app/installations/{id}/access_tokens
  - In-memory token cache with 55-minute effective TTL (5-minute refresh buffer)
  - Credential priority cascade: GITHUB_APP_KEY_PATH env > bundled .pem > cwd-relative .pem
  - Graceful degradation: returns .unavailable(reason:) when credentials absent or misconfigured
  - memoryRepo computed property for collective memory repo identifier

affects:
  - 14-collective-memory-read (calls GitHubAuthService.shared.getToken() for API auth)
  - 15-collective-memory-write (calls GitHubAuthService.shared.getToken() for write auth)

tech-stack:
  added: []  # Security.framework — already available, no SPM additions
  patterns:
    - "Singleton pattern: GitHubAuthService.shared with @unchecked Sendable + NSLock for thread safety"
    - "DispatchSemaphore + ResultBox for synchronous HTTP — mirrors AIService.callAPI pattern"
    - "Multi-strategy resource loading: Bundle.main > cwd-relative (mirrors RecipeEngine pattern)"
    - "loadEnvironmentVariables() mirrors AIService.loadEnvironment: process env + ~/.cellar/.env"
    - "JWT payload with [String: Any] + JSONSerialization (not JSONEncoder) for mixed Int/String types"

key-files:
  created:
    - Sources/cellar/Core/GitHubAuthService.swift
  modified: []

key-decisions:
  - "@unchecked Sendable conformance on GitHubAuthService — NSLock provides the external synchronization Security.framework requires"
  - "JWT iat = now - 60 (60-second clock skew buffer per GitHub recommendation) and exp = now + 510 (8.5 min)"
  - "loadCredentials() throws .credentialsNotConfigured when appID or installationID is empty — placeholder json returns .unavailable not a crash"
  - "resetCache() uses same lock+defer pattern as getToken() — safe for future testing or token invalidation"

patterns-established:
  - "GitHub App auth result: .token(String) vs .unavailable(reason: String) — never throws at the public API boundary"
  - "PEM stripping: remove both PKCS#1 (BEGIN RSA PRIVATE KEY) and PKCS#8 (BEGIN PRIVATE KEY) headers defensively"

requirements-completed: [AUTH-01, AUTH-02]

duration: 2min
completed: 2026-03-30
---

# Phase 13 Plan 02: GitHub App Authentication Service Summary

**RS256 JWT generation via Security.framework + installation token exchange + 55-minute TTL cache with graceful degradation when GitHub App credentials are absent**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-30T15:34:37Z
- **Completed:** 2026-03-30T15:36:30Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- GitHubAuthService.swift: complete standalone auth service for Phase 14/15 to call via `getToken()`
- RS256 JWT signing uses Security.framework (`SecKeyCreateWithData` + `SecKeyCreateSignature`) — no external dependencies
- Token cache with 55-minute effective TTL; automatic refresh when within 5 minutes of expiry
- Placeholder credentials (empty app_id/installation_id in github-app.json) return `.unavailable` without any HTTP call

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement GitHubAuthService** - `f7bab62` (feat)
2. **Task 2: Verify graceful degradation + resetCache()** — no code changes; verification confirmed resetCache() present in Task 1 commit

## Files Created/Modified

- `Sources/cellar/Core/GitHubAuthService.swift` — 331 lines: JWT signing, token exchange, cache, credential cascade, env loading, memoryRepo property

## Decisions Made

- `@unchecked Sendable` on the class: NSLock provides the required external synchronization. The Swift 6 concurrency checker requires explicit acknowledgment when a class holds mutable state protected by a lock rather than actor isolation.
- `iat = now - 60` and `exp = now + 510`: GitHub's recommended clock skew offset with 8.5-minute JWT window (under 10-minute max).
- `[String: Any]` + `JSONSerialization` for JWT payload: `iss` is String, `iat`/`exp` are Int — JSONEncoder requires homogeneous Codable types and would serialize Int as String.
- Self-contained credential and environment loading: copied the 10-line `.env` parser from AIService rather than sharing a private method, to keep GitHubAuthService independently testable.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Added `@unchecked Sendable` conformance to fix Swift 6 concurrency error**
- **Found during:** Task 1 (build verification)
- **Issue:** `static let shared = GitHubAuthService()` triggered `MutableGlobalVariable` error — non-Sendable type cannot be stored in a static property in Swift 6 strict concurrency
- **Fix:** Added `: @unchecked Sendable` to the class declaration. NSLock already serializes all mutable state access, so the annotation is accurate and safe.
- **Files modified:** Sources/cellar/Core/GitHubAuthService.swift
- **Verification:** `swift build` completes with zero warnings
- **Committed in:** f7bab62 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Swift 6 concurrency conformance)
**Impact on plan:** Required for compilation under Swift 6 strict concurrency. No scope creep. NSLock already provided the needed thread safety.

## Issues Encountered

- Swift 6 strict concurrency requires `@unchecked Sendable` on any class with mutable state stored in a static property. The NSLock was already in place per the plan; only the type annotation was missing. Fixed inline.

## User Setup Required

None — no external service configuration required at this stage. Real credentials (App ID, Installation ID, PEM key) will be injected before Phase 13 ships.

## Next Phase Readiness

- `GitHubAuthService.shared.getToken()` ready for Phase 14 (Read Path) and Phase 15 (Write Path)
- Placeholder credentials return `.unavailable` — app runs without real GitHub App credentials
- `GitHubAuthService.shared.memoryRepo` returns `"cellar-community/memory"` default
- GitHub App ID, Installation ID, and PEM key still need concrete values before Phase 13 ships (noted in STATE.md blockers)

---
*Phase: 13-github-app-authentication*
*Completed: 2026-03-30*
