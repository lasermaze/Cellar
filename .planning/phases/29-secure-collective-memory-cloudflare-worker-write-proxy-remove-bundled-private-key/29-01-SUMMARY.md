---
phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key
plan: 01
subsystem: infra
tags: [cloudflare-worker, typescript, jwt, subtlecrypto, github-api, rate-limiting, cors]

# Dependency graph
requires:
  - phase: 28-fix-collective-memory-prompt-injection-vulnerability
    provides: sanitizeEntry() validation rules and allowedEnvKeys that Worker mirrors server-side
provides:
  - Cloudflare Worker TypeScript project (worker/) ready for wrangler deploy
  - POST /api/contribute endpoint with server-side validation, rate limiting, JWT, and GitHub write
affects:
  - 29-02 (CLI write path — will POST to this Worker instead of directly to GitHub)
  - 29-03 (credential deletion — Worker holds private key, CLI no longer needs it)

# Tech tracking
tech-stack:
  added: [wrangler, @cloudflare/workers-types, typescript (worker devDeps)]
  patterns:
    - SubtleCrypto RS256 JWT generation (no npm crypto deps — native Web Crypto API)
    - In-memory rate limiting per Worker instance via Map<IP, timestamp[]>
    - GET+merge+PUT with single 409 retry for GitHub Contents API conflict handling

key-files:
  created:
    - worker/src/index.ts
    - worker/package.json
    - worker/tsconfig.json
    - worker/wrangler.toml
  modified: []

key-decisions:
  - "CELLAR_MEMORY_REPO default is lasermaze/cellar-memory in wrangler.toml [vars] — overridable without redeployment"
  - "Rate limiting in-memory Map resets on Worker restart — acceptable at this scale, avoids KV cost"
  - "409 retry limit of 1 attempt — prevents infinite loop on persistent conflicts"
  - "Content-Length check (51200) is advisory since CF may not always forward it; body parse then size check would be Belt-and-suspenders alternative — kept as-is per plan"

patterns-established:
  - "Worker validation mirrors Swift sanitizeEntry() field-for-field — same 13 env keys, same DLL modes, same registry prefixes, same truncation limits"
  - "makeJWT() strips both PKCS8 and PKCS1 PEM headers to handle either key format from wrangler secret"

requirements-completed:
  - Cloudflare Worker write proxy with server-side validation

# Metrics
duration: 10min
completed: 2026-04-03
---

# Phase 29 Plan 01: Cloudflare Worker Write Proxy Summary

**TypeScript Cloudflare Worker at worker/src/index.ts — POST /api/contribute validates entries server-side (13-key env allowlist, DLL modes, registry prefixes, field truncation), rate-limits 10/hr/IP, generates RS256 JWT via SubtleCrypto, and writes to GitHub Contents API with GET+merge+PUT and 409 retry**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-03T18:40:00Z
- **Completed:** 2026-04-03T18:50:48Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Complete Cloudflare Worker TypeScript project scaffold (package.json, tsconfig.json, wrangler.toml) ready for `wrangler deploy`
- POST /api/contribute handler with 50KB body cap, CORS preflight, JSON parse, and full input sanitization mirroring Swift's sanitizeEntry()
- RS256 JWT generation using SubtleCrypto (zero npm dependencies for crypto) with clock-skew buffer (iat-60, exp+510) matching GitHub recommendations
- GET+merge+PUT to GitHub Contents API: increments confirmations for matching environmentHash, appends new entries, retries on 409 conflict

## Task Commits

Each task was committed atomically:

1. **Task 1: Worker project scaffold and configuration** — `6ba7531` (chore)
2. **Task 2: Worker fetch handler with validation, JWT, and GitHub write** — `8b96bfe` (feat)

## Files Created/Modified
- `worker/src/index.ts` — Complete Cloudflare Worker: fetch handler, CORS, validation, rate limiting, JWT, GitHub write
- `worker/package.json` — cellar-memory-proxy project, module type, wrangler/typescript devDeps
- `worker/tsconfig.json` — ES2022, Bundler moduleResolution, @cloudflare/workers-types, strict, noEmit
- `worker/wrangler.toml` — name, main, compat date, CELLAR_MEMORY_REPO var, secrets documentation

## Decisions Made
- CELLAR_MEMORY_REPO default `lasermaze/cellar-memory` set in `[vars]` so it is overridable via wrangler env without code changes
- In-memory rate limiting Map resets on Worker restart — acceptable at this scale (Cloudflare Worker free tier, low write volume)
- 409 conflict retry capped at 1 attempt to prevent infinite loop on persistent conflicts
- Both PKCS8 ("PRIVATE KEY") and PKCS1 ("RSA PRIVATE KEY") PEM header formats stripped in makeJWT() to be resilient to key format variation from wrangler secret

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

Before deploying the Worker, set the three required secrets:

```sh
cd worker
npm install
wrangler secret put GITHUB_APP_PEM       # paste RSA private key PEM contents
wrangler secret put GITHUB_APP_ID        # numeric GitHub App ID
wrangler secret put GITHUB_INSTALLATION_ID  # installation ID for memory repo
wrangler deploy
```

The `CELLAR_MEMORY_REPO` var defaults to `lasermaze/cellar-memory` in wrangler.toml and can be overridden with `wrangler secret put` or a `[env.production]` block if needed.

## Next Phase Readiness
- Worker project is complete and deployable
- Plan 29-02 will update CollectiveMemoryWriteService to POST to this Worker URL instead of directly to GitHub
- Plan 29-03 will delete bundled credentials (GitHubAuthService, github-app.pem, github-app.json) from the CLI

---
*Phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key*
*Completed: 2026-04-03*
