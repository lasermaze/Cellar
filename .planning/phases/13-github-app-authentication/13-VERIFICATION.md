---
phase: 13-github-app-authentication
verified: 2026-03-30T16:00:00Z
status: passed
score: 7/7 must-haves verified
re_verification: false
---

# Phase 13: GitHub App Authentication Verification Report

**Phase Goal:** The agent can authenticate to GitHub as a bot — generating RS256 JWTs, exchanging them for installation tokens, and refreshing those tokens automatically — so that all write operations in later phases have a working auth layer to depend on
**Verified:** 2026-03-30T16:00:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                 | Status     | Evidence                                                                                                |
| --- | ------------------------------------------------------------------------------------- | ---------- | ------------------------------------------------------------------------------------------------------- |
| 1   | GitHub App credential models round-trip through JSON encode/decode                    | VERIFIED   | `GitHubAppConfig` with explicit `CodingKeys` (`app_id`, `installation_id`) in `GitHubModels.swift`     |
| 2   | Placeholder resource files exist and parse without error                              | VERIFIED   | `github-app.json` is valid JSON with empty strings; `github-app.pem` starts with `-----BEGIN RSA PRIVATE KEY-----` |
| 3   | CellarPaths exposes `defaultMemoryRepo` for credential loading                        | VERIFIED   | `static let defaultMemoryRepo = "cellar-community/memory"` at line 107 of `CellarPaths.swift`          |
| 4   | GitHubAuthService produces a valid installation token from GitHub App credentials     | VERIFIED   | Complete RS256 JWT path: PEM strip → `SecKeyCreateWithData` → `SecKeyCreateSignature` → POST to GitHub API → `InstallationTokenResponse` decode |
| 5   | Token refreshes automatically when within 5 minutes of expiry (effective 55-min TTL) | VERIFIED   | `expiry > Date().addingTimeInterval(5 * 60)` at line 41; cache stored on hit at lines 48-49            |
| 6   | When credentials are absent or misconfigured, `getToken()` returns `.unavailable` — does not crash | VERIFIED | `catch GitHubAuthError.credentialsNotConfigured` at line 51 returns `.unavailable(reason:)`; empty `github-app.json` triggers this path |
| 7   | Credential priority cascade works: env var > `~/.cellar/.env` > bundled resource     | VERIFIED   | `loadEnvironmentVariables()` merges `ProcessInfo.processInfo.environment` with `.env` file (process env wins); `resolvePEM` checks `GITHUB_APP_KEY_PATH` → `Bundle.main` → CWD-relative; `loadCredentials` checks `GITHUB_APP_ID` / `GITHUB_INSTALLATION_ID` env vars before falling back to `github-app.json` |

**Score:** 7/7 truths verified

### Required Artifacts

| Artifact                                               | Expected                                                  | Status   | Details                                                                                    |
| ------------------------------------------------------ | --------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------ |
| `Sources/cellar/Models/GitHubModels.swift`             | 5 Codable types + error enum                              | VERIFIED | 92 lines; contains `GitHubAppConfig`, `GitHubCredentials`, `InstallationTokenResponse`, `GitHubAuthResult`, `GitHubAuthError` with `LocalizedError` conformance |
| `Sources/cellar/Resources/github-app.pem`              | Placeholder RSA private key (PKCS#1)                      | VERIFIED | Starts with `-----BEGIN RSA PRIVATE KEY-----`; valid 2048-bit throw-away key               |
| `Sources/cellar/Resources/github-app.json`             | Placeholder config with `app_id` and `installation_id`   | VERIFIED | `{"app_id": "", "installation_id": ""}` — empty strings trigger `.unavailable` path       |
| `Sources/cellar/Core/GitHubAuthService.swift`          | Complete auth service callable via `getToken()`           | VERIFIED | 331 lines; singleton, JWT signing, token exchange, cache, credential cascade, env loading  |
| `Sources/cellar/Persistence/CellarPaths.swift`         | `defaultMemoryRepo` static property added                 | VERIFIED | Line 107: `static let defaultMemoryRepo = "cellar-community/memory"`                       |

### Key Link Verification

| From                            | To                                                  | Via                                                          | Status   | Details                                                                                          |
| ------------------------------- | --------------------------------------------------- | ------------------------------------------------------------ | -------- | ------------------------------------------------------------------------------------------------ |
| `GitHubAuthService.swift`       | `GitHubModels.swift`                                | Uses `GitHubCredentials`, `InstallationTokenResponse`, `GitHubAuthResult`, `GitHubAuthError`, `GitHubAppConfig` | WIRED    | All 5 types actively used — not just imported. `GitHubCredentials` returned from `loadCredentials`; `InstallationTokenResponse` decoded at line 183; `GitHubAuthResult` returned from `getToken`; `GitHubAuthError` thrown at 7 call sites; `GitHubAppConfig` decoded in `loadBundledConfig` |
| `GitHubAuthService.swift`       | `https://api.github.com/app/installations/{id}/access_tokens` | POST with JWT Bearer token                               | WIRED    | Line 169: URL constructed with `installationID`; lines 176-178: three required headers set (`Authorization: Bearer`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`) |
| `GitHubAuthService.swift`       | `Sources/cellar/Resources/github-app.pem`           | Multi-strategy: `Bundle.main` first, then CWD-relative      | WIRED    | Line 265: `Bundle.main.url(forResource: "github-app", withExtension: "pem")`; line 272-274: CWD fallback to `Sources/cellar/Resources/github-app.pem` |
| `GitHubAppConfig` (JSON struct) | `github-app.json`                                   | `CodingKeys` maps `app_id` and `installation_id`             | WIRED    | `GitHubModels.swift` line 13-16: `CodingKeys` with `app_id` / `installation_id`; JSON file uses same keys |

### Requirements Coverage

| Requirement | Source Plan | Description                                                                                          | Status    | Evidence                                                                                                                                        |
| ----------- | ----------- | ---------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| AUTH-01     | 13-01, 13-02 | Agent authenticates to GitHub API using GitHub App credentials (RS256 JWT + installation token)     | SATISFIED | `makeJWT()` generates RS256 JWTs using `Security.framework`; `fetchInstallationToken()` POSTs to GitHub API; full credential type contracts in `GitHubModels.swift` |
| AUTH-02     | 13-02       | Agent token refreshes automatically before expiry (1-hour lifetime, refresh at 55 minutes)          | SATISFIED | `getToken()` checks `expiry > Date().addingTimeInterval(5 * 60)` — forces refresh when within 5 minutes of expiry; `tokenExpiry` date parsed from GitHub's `expires_at` ISO 8601 field |

No orphaned requirements. Both requirements declared in PLANs match REQUIREMENTS.md entries for Phase 13.

### Anti-Patterns Found

| File                              | Line | Pattern       | Severity | Impact                                                                                                |
| --------------------------------- | ---- | ------------- | -------- | ----------------------------------------------------------------------------------------------------- |
| `GitHubAuthService.swift`         | 299  | `return nil`  | INFO     | End of `loadBundledConfig() -> GitHubAppConfig?`; `Optional` return is correct — caller handles nil by falling through to `.credentialsNotConfigured` |

No blockers. No stub patterns detected. No force-unwraps outside of guarded optionals. No `console.log`-only handlers.

### Human Verification Required

None for automated checks. The following items are noted as requiring real credentials to exercise end-to-end:

**1. Live token exchange**

**Test:** Set real `GITHUB_APP_ID`, `GITHUB_INSTALLATION_ID`, and `GITHUB_APP_KEY_PATH` in `~/.cellar/.env`, then run `cellar serve` and trigger a code path that calls `GitHubAuthService.shared.getToken()`.
**Expected:** `.token(String)` returned with a valid GitHub installation access token; subsequent calls within 55 minutes return cached token without a network call.
**Why human:** Requires a real GitHub App with installation — cannot verify token exchange against live API programmatically in this session.

**2. Token refresh at 55-minute boundary**

**Test:** After receiving a token, artificially set `tokenExpiry` to `Date().addingTimeInterval(4 * 60)` (within the 5-minute buffer) and call `getToken()` again.
**Expected:** Service fetches a fresh token rather than returning the cached one.
**Why human:** Requires runtime state manipulation; cannot inject time in static verification.

### Gaps Summary

No gaps. All automated must-haves pass at all three levels (exists, substantive, wired). Both AUTH-01 and AUTH-02 are satisfied. The build compiles cleanly with zero warnings. Commits `f42e81c`, `3be3c67`, and `f7bab62` exist in the repository and correspond to the artifacts.

The only item requiring attention before this phase ships is replacing the placeholder `github-app.pem` and populating `github-app.json` with real App ID and Installation ID values — but this is an expected operational step noted in both SUMMARYs and STATE.md, not a gap in the implementation.

---

_Verified: 2026-03-30T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
