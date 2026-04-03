---
phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key
plan: 03
subsystem: auth
tags: [cloudflare-workers, github-app, collective-memory, security, proxy]

# Dependency graph
requires:
  - phase: 29-02
    provides: CollectiveMemoryService read path using CELLAR_MEMORY_REPO env var
provides:
  - CollectiveMemoryWriteService posts entry JSON to Cloudflare Worker proxy (no private key in binary)
  - CELLAR_MEMORY_PROXY_URL env var configures proxy endpoint with production default
  - GitHubAuthService and all related types fully deleted
  - .gitignore blocks future *.pem and github-app.json commits
affects: [collective-memory, write-path, security, distribution]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Proxy-based write path: CollectiveMemoryWriteService POSTs {"entry": ...} to Worker; no auth infrastructure in binary

key-files:
  created: []
  modified:
    - Sources/cellar/Core/CollectiveMemoryWriteService.swift
    - .gitignore
  deleted:
    - Sources/cellar/Core/GitHubAuthService.swift
    - Sources/cellar/Models/GitHubModels.swift
    - Sources/cellar/Resources/github-app.pem
    - Sources/cellar/Resources/github-app.json

key-decisions:
  - "CELLAR_MEMORY_PROXY_URL env var overrides production Worker URL — consistent with other CellarPaths env var patterns"
  - "ProxyPayload wrapper struct encodes {\"entry\": ...} matching Worker's expected request body shape"
  - "Resources/ directory retained in Package.swift .copy(\"Resources\") — Public/ and Views/ remain"

patterns-established:
  - "Proxy write pattern: POST entry JSON to Worker; Worker holds private key server-side"

requirements-completed:
  - Remove github-app.pem and github-app.json from binary
  - Delete GitHubAuthService
  - Configurable proxy URL

# Metrics
duration: 8min
completed: 2026-04-02
---

# Phase 29 Plan 03: Secure Collective Memory Write Path Summary

**GitHub App private key removed from binary — all writes now POST to Cloudflare Worker proxy via CELLAR_MEMORY_PROXY_URL, with GitHubAuthService and all credential files deleted**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-04-02T00:00:00Z
- **Completed:** 2026-04-02T00:08:00Z
- **Tasks:** 2
- **Files modified:** 2 (modified) + 5 (deleted)

## Accomplishments
- Rewrote CollectiveMemoryWriteService from 384 lines to ~195 lines — replaces GET+merge+PUT GitHub API flow with single POST to Cloudflare Worker proxy
- Deleted GitHubAuthService.swift (RS256 JWT + token exchange), GitHubModels.swift (all credential types), github-app.pem, github-app.json, and root-level PEM file — private key no longer ships with binary
- Added *.pem and github-app.json patterns to .gitignore to prevent future credential leaks
- swift build succeeds with zero references to deleted types

## Task Commits

1. **Task 1: Simplify CollectiveMemoryWriteService to POST to proxy** - `d15b615` (feat)
2. **Task 2: Delete GitHubAuthService, GitHubModels, credential files, update .gitignore** - `75a92b5` (feat)

## Files Created/Modified
- `Sources/cellar/Core/CollectiveMemoryWriteService.swift` - Rewritten: proxyURL constant, postToProxy() replacing pushEntry/performMergeAndPut, auth dependency removed
- `.gitignore` - Added *.pem and github-app.json patterns

## Files Deleted
- `Sources/cellar/Core/GitHubAuthService.swift` - Entire JWT + token exchange service gone
- `Sources/cellar/Models/GitHubModels.swift` - GitHubAppConfig, GitHubCredentials, InstallationTokenResponse, GitHubAuthResult, GitHubAuthError gone
- `Sources/cellar/Resources/github-app.pem` - Bundled private key gone
- `Sources/cellar/Resources/github-app.json` - Bundled App ID/installation ID gone

## Decisions Made
- CELLAR_MEMORY_PROXY_URL env var overrides production Worker URL — consistent with other CellarPaths env var patterns
- ProxyPayload wrapper struct encodes `{"entry": ...}` matching Worker's expected request body shape
- Resources/ directory retained in Package.swift `.copy("Resources")` — Public/ and Views/ subdirectories remain and are still needed

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

The Cloudflare Worker (deployed in plan 29-01) must have the following secrets configured via `wrangler secret put`:
- `GITHUB_APP_PEM` — GitHub App private key
- `GITHUB_APP_ID` — GitHub App ID
- `GITHUB_INSTALLATION_ID` — Installation ID

After deploying the Worker, update `CELLAR_MEMORY_PROXY_URL` in `~/.cellar/.env` with the actual Worker URL, or set it in the environment before running Cellar.

## Next Phase Readiness

Phase 29 complete. The binary no longer contains any GitHub App credentials. All writes route through the Cloudflare Worker proxy. The collective memory system is now safe to distribute publicly.

## Self-Check: PASSED

- FOUND: Sources/cellar/Core/CollectiveMemoryWriteService.swift
- FOUND: GitHubAuthService.swift deleted
- FOUND: GitHubModels.swift deleted
- FOUND: 29-03-SUMMARY.md
- FOUND: d15b615 (Task 1 commit)
- FOUND: 75a92b5 (Task 2 commit)

---
*Phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key*
*Completed: 2026-04-02*
