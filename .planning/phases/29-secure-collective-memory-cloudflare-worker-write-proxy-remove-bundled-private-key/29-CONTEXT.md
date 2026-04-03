# Phase 29: Secure Collective Memory - Context

**Gathered:** 2026-04-03
**Status:** Ready for planning
**Source:** Discussion with user about private key security

<domain>
## Phase Boundary

Remove the bundled GitHub App private key from the binary. Make the memory repo public for anonymous reads. Route writes through a Cloudflare Worker that holds the key and validates entries server-side. Delete GitHubAuthService and all bundled credentials. Add local read cache.

</domain>

<decisions>
## Implementation Decisions

### Anonymous reads (public repo)
- Make cellar-community/memory a public GitHub repo
- Remove all auth from read paths — no GitHubAuthService.getToken() calls for reads
- Use unauthenticated GitHub Contents API (60 req/hr/IP, sufficient for 1 request per game launch)
- Handle 403 rate-limit responses gracefully (serve from cache or return nil)

### Local read cache
- Cache fetched entries at ~/.cellar/cache/memory/{slug}.json
- 1-hour TTL (check file modification date)
- Serve from cache when: fresh, or GitHub returns 403 (rate limited), or network fails
- Improves offline resilience

### Cloudflare Worker write proxy
- ~100 lines of JS/TS at worker/src/index.ts
- POST /api/contribute accepts { "entry": <CollectiveMemoryEntry JSON> }
- Server-side validation mirrors sanitizeEntry() logic:
  - Env keys against allowlist (same 13 keys as AgentTools.allowedEnvKeys)
  - DLL modes in {"n", "b", "n,b", "b,n", ""}
  - Registry key prefixes (HKEY_CURRENT_USER\, HKEY_LOCAL_MACHINE\)
  - Field length truncation
  - Launch args cap (5 entries, 100 chars each)
  - Setup deps against known winetricks verbs
- Rate limit: 10 writes/hr/IP
- Request body size limit: 50KB
- JWT generation from GITHUB_APP_PEM secret (wrangler secret)
- GET → merge → PUT flow to GitHub Contents API (handles conflict)
- Returns { "status": "ok" } or { "status": "error", "message": "..." }

### CLI write path changes
- CollectiveMemoryWriteService.pushEntry() becomes a single POST to proxy URL
- Remove JWT generation, token exchange, merge logic from CLI (proxy handles it)
- Proxy URL configurable via CELLAR_MEMORY_PROXY_URL env var
- Default: production Worker URL

### Delete bundled credentials
- Delete Sources/cellar/Resources/github-app.pem
- Delete Sources/cellar/Resources/github-app.json
- Delete cellar-memory.2026-03-30.private-key.pem from repo root
- Delete Sources/cellar/Core/GitHubAuthService.swift entirely
- Clean up GitHubModels.swift — remove GitHubAppConfig, GitHubCredentials, InstallationTokenResponse
- Add *.pem and github-app.json to .gitignore
- Revoke the GitHub App key

### Constraints
- No user authentication required — reads and writes work without GitHub accounts
- Reads must work offline (from cache) after first fetch
- Writes fail gracefully if proxy is down (already handled by existing error swallowing)
- Do NOT modify CollectiveMemoryEntry.swift (struct stays the same)

### Claude's Discretion
- Exact Cloudflare Worker project structure
- Whether to use TypeScript or plain JavaScript
- Shared allowlist format (hardcoded in JS or loaded from JSON)
- Cache directory structure details

</decisions>

<code_context>
## Existing Code Insights

### Files to modify
1. Sources/cellar/Core/CollectiveMemoryService.swift — remove auth, add cache, anonymous reads
2. Sources/cellar/Core/CollectiveMemoryWriteService.swift — POST to proxy instead of direct GitHub API
3. Sources/cellar/Web/Services/MemoryStatsService.swift — remove auth headers
4. Sources/cellar/Models/GitHubModels.swift — remove auth-related types

### Files to delete
1. Sources/cellar/Core/GitHubAuthService.swift
2. Sources/cellar/Resources/github-app.pem
3. Sources/cellar/Resources/github-app.json
4. cellar-memory.2026-03-30.private-key.pem

### Files to create
1. worker/src/index.ts — Cloudflare Worker
2. worker/wrangler.toml — Worker config
3. worker/package.json — Worker dependencies

### Integration Points
- CollectiveMemoryService reads → anonymous GitHub API (no auth)
- CollectiveMemoryWriteService writes → POST to Cloudflare Worker → Worker writes to GitHub
- MemoryStatsService reads → anonymous GitHub API (no auth)

</code_context>

<specifics>
## Specific Ideas

- The Cloudflare Worker free tier gives 100K requests/day — more than enough
- Worker secrets are encrypted at rest on Cloudflare
- The sanitization logic in the Worker must mirror the Swift sanitizeEntry() rules exactly
- Consider generating the allowlist from a shared JSON checked into the memory repo to prevent drift

</specifics>

<deferred>
## Deferred Ideas

None — discussion covered the full scope.

</deferred>

---

*Phase: 29-secure-collective-memory-cloudflare-worker-write-proxy-remove-bundled-private-key*
*Context gathered: 2026-04-03 via discussion*
