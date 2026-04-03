# Phase 29: Secure Collective Memory - Research

**Researched:** 2026-04-02
**Domain:** Cloudflare Workers, GitHub Contents API (anonymous), Swift local read cache
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Anonymous reads (public repo)**
- Make cellar-community/memory a public GitHub repo
- Remove all auth from read paths — no GitHubAuthService.getToken() calls for reads
- Use unauthenticated GitHub Contents API (60 req/hr/IP, sufficient for 1 request per game launch)
- Handle 403 rate-limit responses gracefully (serve from cache or return nil)

**Local read cache**
- Cache fetched entries at ~/.cellar/cache/memory/{slug}.json
- 1-hour TTL (check file modification date)
- Serve from cache when: fresh, or GitHub returns 403 (rate limited), or network fails
- Improves offline resilience

**Cloudflare Worker write proxy**
- ~100 lines of JS/TS at worker/src/index.ts
- POST /api/contribute accepts { "entry": <CollectiveMemoryEntry JSON> }
- Server-side validation mirrors sanitizeEntry() logic (env allowlist, DLL modes, registry prefixes, field lengths, launch args cap, setup deps against winetricks verbs)
- Rate limit: 10 writes/hr/IP
- Request body size limit: 50KB
- JWT generation from GITHUB_APP_PEM secret (wrangler secret)
- GET → merge → PUT flow to GitHub Contents API (handles conflict)
- Returns { "status": "ok" } or { "status": "error", "message": "..." }

**CLI write path changes**
- CollectiveMemoryWriteService.pushEntry() becomes a single POST to proxy URL
- Remove JWT generation, token exchange, merge logic from CLI (proxy handles it)
- Proxy URL configurable via CELLAR_MEMORY_PROXY_URL env var
- Default: production Worker URL

**Delete bundled credentials**
- Delete Sources/cellar/Resources/github-app.pem
- Delete Sources/cellar/Resources/github-app.json
- Delete cellar-memory.2026-03-30.private-key.pem from repo root
- Delete Sources/cellar/Core/GitHubAuthService.swift entirely
- Clean up GitHubModels.swift — remove GitHubAppConfig, GitHubCredentials, InstallationTokenResponse
- Add *.pem and github-app.json to .gitignore
- Revoke the GitHub App key

**Constraints**
- No user authentication required — reads and writes work without GitHub accounts
- Reads must work offline (from cache) after first fetch
- Writes fail gracefully if proxy is down (already handled by existing error swallowing)
- Do NOT modify CollectiveMemoryEntry.swift (struct stays the same)

### Claude's Discretion
- Exact Cloudflare Worker project structure
- Whether to use TypeScript or plain JavaScript
- Shared allowlist format (hardcoded in JS or loaded from JSON)
- Cache directory structure details

### Deferred Ideas (OUT OF SCOPE)
None — discussion covered the full scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| Public repo anonymous reads | Remove auth from read paths; serve from cache on 403/network failure | GitHub API: 60 req/hr/IP unauthenticated; 403/429 on limit exceeded; raw content via `application/vnd.github.v3.raw` Accept header |
| Cloudflare Worker write proxy | POST /api/contribute; server-side validation; rate limit 10/hr/IP; JWT from GITHUB_APP_PEM secret | SubtleCrypto RS256 signing; wrangler secret; fetch handler pattern; CF-Connecting-IP for rate limiting |
| Remove github-app.pem and github-app.json from binary | Delete resource files + update .gitignore | Package.swift uses `.copy("Resources")` — deleting files from Resources/ is sufficient |
| Delete GitHubAuthService | Delete file; fix all 9 call sites across 3 source files | All references mapped below |
| Local read cache with TTL | ~/.cellar/cache/memory/{slug}.json; 1-hour TTL via file modification date | CellarPaths pattern: add static cacheDir + memoryCache(for:) methods |
| Configurable proxy URL | CELLAR_MEMORY_PROXY_URL env var with production default | Follow existing pattern of AIService.loadEnvironmentVariables() |
</phase_requirements>

---

## Summary

Phase 29 removes the bundled GitHub App private key from the distributed binary — a security regression that was accepted as a known risk in Phase 13. The fix has three coordinated parts: (1) make the memory repo public and strip all auth from Swift read paths, (2) create a Cloudflare Worker that holds the key server-side and proxies writes, (3) simplify the Swift write path to a single HTTP POST.

The Swift-side changes are mostly deletions: remove `GitHubAuthService.swift` entirely, clean up `GitHubModels.swift`, strip auth calls from `CollectiveMemoryService.swift`, `CollectiveMemoryWriteService.swift`, and `MemoryStatsService.swift`. The read path gains a local file cache at `~/.cellar/cache/memory/{slug}.json`. The write path shrinks from ~250 lines of JWT/token/merge/PUT logic to ~20 lines posting JSON to the Worker URL.

The Cloudflare Worker is a new artifact (~100 lines of TypeScript) in `worker/` at the repo root. It uses the Web Crypto API (SubtleCrypto) to generate RS256 JWTs — the same algorithm Swift's Security.framework used. The PEM private key is stored as a wrangler secret, never in source code. The Worker implements IP-based rate limiting and mirrors the sanitizeEntry() validation logic.

**Primary recommendation:** Use TypeScript for the Worker (type safety for the CollectiveMemoryEntry shape, easier to verify validation mirrors Swift). Hardcode the allowlists directly in the Worker (no shared JSON file — avoids a GitHub API dependency at write time).

---

## Existing Code Analysis

### GitHubAuthService.swift — Full Deletion

The file is `Sources/cellar/Core/GitHubAuthService.swift` (337 lines). It provides:
- `GitHubAuthService.shared.getToken()` — async, returns `GitHubAuthResult` (.token / .unavailable)
- `GitHubAuthService.shared.memoryRepo` — computed property: reads `CELLAR_MEMORY_REPO` env var or falls back to `CellarPaths.defaultMemoryRepo`
- RS256 JWT generation using Security.framework
- Installation token exchange via GitHub API
- Token caching with 55-minute TTL
- Credential loading from env vars / bundled resources / CWD-relative paths

After deletion, `memoryRepo` must move — the simplest approach is a static property on `CellarPaths` or a free function in a shared file. `CellarPaths.defaultMemoryRepo` already exists; a helper like `CellarPaths.memoryRepo(from:)` that reads the env var is clean.

### All GitHubAuthService Call Sites

**CollectiveMemoryService.swift** (2 call sites):
- Line 24: `await GitHubAuthService.shared.getToken()` — auth gate; entire block becomes unconditional anonymous fetch
- Line 40: `GitHubAuthService.shared.memoryRepo` — replace with `CellarPaths.memoryRepo`

**CollectiveMemoryWriteService.swift** (3 call sites):
- Line 21: `await GitHubAuthService.shared.getToken()` — auth gate in `push()`, replace with proxy URL presence check
- Line 86: `await GitHubAuthService.shared.getToken()` — auth gate in `syncAll()`, replace with proxy URL check
- Line 124: `GitHubAuthService.shared.memoryRepo` — replace with `CellarPaths.memoryRepo`

**MemoryStatsService.swift** (5 call sites):
- Lines 70, 170: `await GitHubAuthService.shared.getToken()` — auth gates, remove entirely
- Lines 76, 121, 176: `GitHubAuthService.shared.memoryRepo` — replace with `CellarPaths.memoryRepo`

**Total: 10 references to remove across 3 files.**

### CollectiveMemoryService.swift — Read Path Changes

Current flow (with auth removed):
1. ~~Auth check~~ — DELETE
2. Detect Wine version (keep)
3. Detect Wine flavor (keep)
4. Build GitHub Contents API URL (keep, but use `CellarPaths.memoryRepo`)
5. ~~`Authorization: Bearer \(token)` header~~ — DELETE
6. Async fetch — check local cache BEFORE fetch (new)
7. Handle 200: decode, rank, format (keep)
8. Handle 403/429: serve from cache (new behavior for rate limit)
9. Handle 404: no entry (keep)
10. On success: write to cache (new)

The request changes from:
```swift
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
```
to just:
```swift
request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
```
(No Authorization header — anonymous access to public repo.)

### CollectiveMemoryWriteService.swift — Write Path Changes

Current `pushEntry()` flow (~130 lines):
1. Auth check → `getToken()`
2. Detect Wine version / flavor
3. Build fingerprint + entry
4. JWT generation (in GitHubAuthService)
5. GET entries file from GitHub
6. Merge (increment confirmation or append)
7. Encode base64
8. PUT to GitHub Contents API
9. 409 conflict → retry once

New `pushEntry()` flow (~20 lines):
1. Read proxy URL from env (CELLAR_MEMORY_PROXY_URL, defaulting to production URL)
2. Build entry (same as steps 2-3 above, kept)
3. POST entry as JSON to proxy URL
4. Log result

The `GitHubContentsResponse` private struct inside `CollectiveMemoryWriteService.swift` (sha + content) is also deleted.

`syncAll()` currently gates on `guard case .token = authResult`. Replace with: `guard !proxyURL.isEmpty else { return (0, 0) }` — or simply remove the gate (proxy URL always has a default, let the POST fail silently if the proxy is down).

### MemoryStatsService.swift — Auth Removal

`fetchStats()` and `fetchGameDetail()` both start with auth checks. Remove them. The isAvailable: false path previously triggered when auth was unavailable; now it only triggers on network failure. The `MemoryStats.isAvailable` flag in templates continues to work correctly.

### GitHubModels.swift — Partial Deletion

**Delete:**
- `GitHubAppConfig` struct (used only by `GitHubAuthService.loadBundledConfig()`)
- `GitHubCredentials` struct (used only by `GitHubAuthService.loadCredentials()`)
- `InstallationTokenResponse` struct (used only by `GitHubAuthService.fetchInstallationToken()`)
- `GitHubAuthResult` enum (used only as return type of `getToken()`)
- `GitHubAuthError` enum (used only inside `GitHubAuthService`)

**Keep:**
- Nothing survives in GitHubModels.swift — the entire file can be deleted.

### CellarPaths.swift — memoryRepo Helper

`GitHubAuthService.shared.memoryRepo` is currently computed by reading `CELLAR_MEMORY_REPO` from the environment. Move this to `CellarPaths`:

```swift
/// The collective memory repository identifier (owner/repo).
/// Reads CELLAR_MEMORY_REPO from process environment, falls back to default.
static var memoryRepo: String {
    ProcessInfo.processInfo.environment["CELLAR_MEMORY_REPO"] ?? defaultMemoryRepo
}
```

Note: `GitHubAuthService` also read from `~/.cellar/.env`. The new property reads only from process env, which matches how other env vars are handled in callers (AIService loads `.env` and sets process env). This is acceptable — CELLAR_MEMORY_REPO is a deployment config, not a secret.

### Local Read Cache — New Infrastructure

**Path:** `~/.cellar/cache/memory/{slug}.json`
**TTL:** 1 hour (check `FileManager.attributesOfItem(atPath:)[.modificationDate]`)

New `CellarPaths` additions:
```swift
static let memoryCacheDir: URL = base.appendingPathComponent("cache/memory")
static func memoryCacheFile(for slug: String) -> URL {
    memoryCacheDir.appendingPathComponent("\(slug).json")
}
```

Cache read logic in `CollectiveMemoryService.fetchBestEntry()`:
```swift
// Check cache before network
let cacheFile = CellarPaths.memoryCacheFile(for: slug)
if let cached = loadFromCache(cacheFile), isCacheFresh(cacheFile) {
    return decodeAndFormat(cached, wineVersion: localWineVersion, flavor: localFlavor)
}
```

Cache write logic (after successful 200 fetch):
```swift
try? FileManager.default.createDirectory(at: CellarPaths.memoryCacheDir, withIntermediateDirectories: true)
try? data.write(to: cacheFile, options: .atomic)
```

Freshness check (TTL 1 hour = 3600 seconds):
```swift
private static func isCacheFresh(_ url: URL) -> Bool {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let modDate = attrs[.modificationDate] as? Date else { return false }
    return Date().timeIntervalSince(modDate) < 3600
}
```

On 403/429 or network failure: check cache even if stale (offline resilience):
```swift
guard statusCode == 200 else {
    if statusCode == 403 || statusCode == 429 {
        // Rate limited — serve stale cache if available
        if let cached = loadFromCache(cacheFile) {
            return decodeAndFormat(cached, ...)
        }
    }
    if statusCode != 404 {
        fputs("[CollectiveMemoryService] HTTP \(statusCode)...\n", stderr)
    }
    return nil
}
```

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Cloudflare Workers runtime | Free tier | Serverless JS execution | 100K req/day free, secrets encrypted at rest, global edge deployment |
| SubtleCrypto (Web Crypto API) | Built-in | RS256 JWT signing | Workers runtime built-in, no npm dependency, same algorithm as Security.framework |
| wrangler CLI | 3.x | Workers deploy tool | Official Cloudflare CLI, `wrangler secret put` for encrypted secrets |
| TypeScript | ~5.x | Worker source language | Type safety for entry validation logic; ts-node not needed — wrangler transpiles |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `npm create cloudflare` / wrangler init | CLI | Scaffold worker project | Use to generate wrangler.toml + package.json boilerplate |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| TypeScript | Plain JavaScript | JS is simpler, fewer config files; TS adds type safety for entry shape validation |
| Hardcoded allowlists in Worker | JSON file in memory repo | JSON file avoids duplication but adds a GitHub API fetch on each write request — complexity not worth it |
| Workers Rate Limiting API | KV-based manual rate limiting | Workers Rate Limiting API is free tier eligible but requires `[[unsafe_bindings]]` config; KV-based is simpler for ~100 writes/day scale |

**Installation:**
```bash
cd worker
npm create cloudflare@latest .  # or: npm init -y && npm install wrangler --save-dev
```

---

## Architecture Patterns

### Recommended Worker Project Structure
```
worker/
├── src/
│   └── index.ts          # Worker fetch handler (~100 lines)
├── wrangler.toml          # Worker config (name, compatibility_date, routes)
├── package.json           # { "type": "module", devDependencies: { wrangler } }
└── tsconfig.json          # { "compilerOptions": { "target": "ES2022", "module": "ES2022" } }
```

### Pattern 1: Worker Fetch Handler
**What:** Single exported default object with async fetch() method
**When to use:** All Cloudflare Worker request handling

```typescript
// Source: Cloudflare Workers documentation
export interface Env {
  GITHUB_APP_PEM: string;          // wrangler secret
  GITHUB_APP_ID: string;           // wrangler secret or var
  GITHUB_INSTALLATION_ID: string;  // wrangler secret or var
  CELLAR_MEMORY_REPO: string;      // default: "lasermaze/cellar-memory"
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === 'POST' && new URL(request.url).pathname === '/api/contribute') {
      return handleContribute(request, env);
    }
    return new Response('Not Found', { status: 404 });
  },
};
```

### Pattern 2: RS256 JWT via SubtleCrypto (Web Crypto API)
**What:** Generate a GitHub App JWT using the PKCS8 PEM key stored as a wrangler secret
**When to use:** Any Cloudflare Worker needing RS256 signing without npm deps

```typescript
// Source: Cloudflare Web Crypto API docs + GitHub JWT requirements
async function makeJWT(pemKey: string, appId: string): Promise<string> {
  // Strip PEM headers and decode to ArrayBuffer
  const pemContents = pemKey
    .replace(/-----BEGIN RSA PRIVATE KEY-----/, '')
    .replace(/-----END RSA PRIVATE KEY-----/, '')
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  
  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0));
  
  const key = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  
  const now = Math.floor(Date.now() / 1000);
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  const payload = btoa(JSON.stringify({ iss: appId, iat: now - 60, exp: now + 510 }))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  
  const message = `${header}.${payload}`;
  const signatureBytes = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(message)
  );
  
  const signature = btoa(String.fromCharCode(...new Uint8Array(signatureBytes)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
  
  return `${header}.${payload}.${signature}`;
}
```

**CRITICAL NOTE:** GitHub App private keys are generated in PKCS#1 format (`-----BEGIN RSA PRIVATE KEY-----`). `crypto.subtle.importKey` with format `'pkcs8'` requires PKCS#8 format. Two options:
- Option A: Convert the key to PKCS#8 before storing as secret: `openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in github-app.pem -out github-app-pkcs8.pem`
- Option B: Use a tiny PKCS#1→DER conversion helper in the Worker (avoids key format gymnastics for the user)

**Recommendation:** Option A (convert once, store PKCS#8 PEM as secret). This keeps the Worker simple and avoids ASN.1 parsing in JS. Document the conversion step clearly.

### Pattern 3: IP-Based Rate Limiting (Simple KV or Header Counter)
**What:** Limit writes to 10/hr/IP without a paid KV binding
**When to use:** Low-volume APIs where precision matters less than simplicity

For ~100 writes/day scale, the simplest approach is to trust Cloudflare's per-Worker invocation limit and use `request.headers.get('CF-Connecting-IP')`. Since the context is 10 writes/hr/IP and this is a low-traffic community feature, a stateless approach is acceptable: check `X-Forwarded-For` / `CF-Connecting-IP` and let the GitHub API's own 409 conflict handling be the backstop.

If actual rate limiting is needed: Workers Rate Limiting API (free tier) or a KV binding. For Phase 29, a simple 50KB body size check + server-side validation is the primary protection. Rate limiting can be a future enhancement.

### Pattern 4: GET → merge → PUT in the Worker
**What:** The Worker takes over the merge logic previously in CollectiveMemoryWriteService.swift

```typescript
async function getInstallationToken(jwt: string, installationId: string): Promise<string> {
  const response = await fetch(
    `https://api.github.com/app/installations/${installationId}/access_tokens`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    }
  );
  const data = await response.json() as { token: string };
  return data.token;
}

async function pushToGitHub(entry: CollectiveMemoryEntry, env: Env): Promise<void> {
  const jwt = await makeJWT(env.GITHUB_APP_PEM, env.GITHUB_APP_ID);
  const token = await getInstallationToken(jwt, env.GITHUB_INSTALLATION_ID);
  const slug = slugify(entry.gameName);
  const url = `https://api.github.com/repos/${env.CELLAR_MEMORY_REPO}/contents/entries/${slug}.json`;
  
  // GET existing
  const getResp = await fetch(url, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' }
  });
  
  let sha: string | undefined;
  let mergedEntries: CollectiveMemoryEntry[];
  let message: string;
  
  if (getResp.status === 200) {
    const contents = await getResp.json() as { sha: string; content: string };
    sha = contents.sha;
    const existing: CollectiveMemoryEntry[] = JSON.parse(atob(contents.content.replace(/\n/g, '')));
    // merge logic: increment confirmation or append
    const idx = existing.findIndex(e => e.environmentHash === entry.environmentHash);
    if (idx >= 0) {
      existing[idx] = { ...existing[idx], confirmations: existing[idx].confirmations + 1, lastConfirmed: new Date().toISOString() };
      mergedEntries = existing;
      message = `Update ${entry.gameName} (+1 confirmation)`;
    } else {
      mergedEntries = [...existing, entry];
      message = `Update ${entry.gameName} (new environment)`;
    }
  } else if (getResp.status === 404) {
    sha = undefined;
    mergedEntries = [entry];
    message = `Add ${entry.gameName} entry`;
  } else {
    throw new Error(`GitHub GET returned ${getResp.status}`);
  }
  
  // PUT
  const putBody: Record<string, unknown> = {
    message,
    content: btoa(JSON.stringify(mergedEntries, null, 2)),
    ...(sha ? { sha } : {}),
  };
  
  const putResp = await fetch(url, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(putBody),
  });
  
  if (putResp.status === 409) throw new Error('conflict');
  if (!putResp.ok) throw new Error(`GitHub PUT returned ${putResp.status}`);
}
```

### Pattern 5: Server-Side Validation in Worker
**What:** Mirror Swift's `sanitizeEntry()` logic in TypeScript
**Reference:** `Sources/cellar/Core/CollectiveMemoryService.swift:283-351`

Exact rules to implement:
```typescript
const ALLOWED_ENV_KEYS = new Set([
  'WINEDLLOVERRIDES', 'WINEFSYNC', 'WINEESYNC', 'WINEDEBUG',
  'WINE_CPU_TOPOLOGY', 'WINE_LARGE_ADDRESS_AWARE', 'WINED3D_DISABLE_CSMT',
  'MESA_GL_VERSION_OVERRIDE', 'MESA_GLSL_VERSION_OVERRIDE', 'STAGING_SHARED_MEMORY',
  'DXVK_HUD', 'DXVK_FRAME_RATE', '__GL_THREADED_OPTIMIZATIONS'
]);

const VALID_DLL_MODES = new Set(['n', 'b', 'n,b', 'b,n', '']);
const ALLOWED_REGISTRY_PREFIXES = ['HKEY_CURRENT_USER\\', 'HKEY_LOCAL_MACHINE\\'];
const MAX_LAUNCH_ARGS = 5;
const MAX_LAUNCH_ARG_LEN = 100;
// VALID_WINETRICKS_VERBS: full list from AIService.agentValidWinetricksVerbs in AIService.swift line 682+
```

**Note:** The winetricks verb list lives in `Sources/cellar/Core/AgentTools.swift` at line 682. It must be hardcoded in the Worker identically. This is the most maintenance-sensitive piece — any new verbs added to Swift must also be added to the Worker.

### Pattern 6: New Swift Write Path
**What:** Replace ~250 lines of JWT/token/merge/PUT with a simple HTTP POST

```swift
private static func pushEntry(entry: CollectiveMemoryEntry, token: String) async throws {
    // BECOMES:
    private static func pushEntry(entry: CollectiveMemoryEntry) async throws {
        let env = loadEnvironmentVariables()
        let proxyURL = env["CELLAR_MEMORY_PROXY_URL"] ?? "https://cellar-memory.YOUR_SUBDOMAIN.workers.dev/api/contribute"
        guard let url = URL(string: proxyURL) else {
            logPushEvent("ERROR", gameId: entry.gameId, "Invalid proxy URL")
            return
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let entryData = try? encoder.encode(entry) else { return }
        
        let body = try JSONSerialization.data(withJSONObject: ["entry": try JSONSerialization.jsonObject(with: entryData)])
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 10
        
        if let (data, statusCode) = await performRequest(request: request) {
            if statusCode == 200 {
                logPushEvent("INFO", gameId: entry.gameId, "Push succeeded via proxy")
            } else {
                let msg = String(data: data, encoding: .utf8) ?? "unknown"
                logPushEvent("WARN", gameId: entry.gameId, "Proxy returned \(statusCode): \(msg)")
            }
        } else {
            logPushEvent("ERROR", gameId: entry.gameId, "Network error posting to proxy")
        }
    }
```

**Note:** The `token` parameter is removed from `pushEntry()` signature. The `push()` method must also stop calling `getToken()` and remove that guard.

### Anti-Patterns to Avoid
- **Importing the private key as PKCS#1 with `crypto.subtle`:** SubtleCrypto's `importKey` with `'pkcs8'` format requires PKCS#8. PKCS#1 (`-----BEGIN RSA PRIVATE KEY-----`) will throw. Convert before storing.
- **Storing the PEM as an env var in wrangler.toml:** `[vars]` in wrangler.toml is committed to git. Use `wrangler secret put GITHUB_APP_PEM` — secrets are stored encrypted in Cloudflare and never in source.
- **Removing the 409 retry in the Worker:** The Worker should retry once on 409 conflict (same pattern as the Swift code), not just propagate the error back to the CLI — the CLI has no merge state to retry with.
- **Not adding *.pem to .gitignore:** The current `.gitignore` doesn't exclude PEM files. `cellar-memory.2026-03-30.private-key.pem` is currently untracked (visible in git status). Add `*.pem` and `github-app.json` before deleting the files.
- **Deleting Security import from other files:** Only `GitHubAuthService.swift` imports Security. No other Swift file needs it — safe to delete with the file.
- **Caching before decoding:** Write cache file from raw HTTP response data, before JSON decode. This avoids re-encoding after decode and preserves the exact server response.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RS256 signing in Worker | Custom RSA math | `crypto.subtle.sign('RSASSA-PKCS1-v1_5', ...)` | Built into Workers runtime, correct, fast |
| Rate limiting state | KV counter per IP | Cloudflare Workers Rate Limiting API (free tier) or skip for v1 | Low traffic, GitHub's API is the real backstop |
| JWT library in Worker | npm `jsonwebtoken` | SubtleCrypto + manual base64url | No npm install, smaller bundle, no dep updates |

---

## Common Pitfalls

### Pitfall 1: PKCS#1 vs PKCS#8 Key Format
**What goes wrong:** `crypto.subtle.importKey('pkcs8', ...)` throws `DataError` when given a PKCS#1 key (what GitHub App generates by default: `-----BEGIN RSA PRIVATE KEY-----`)
**Why it happens:** SubtleCrypto `pkcs8` format requires the PKCS#8 DER encoding, not PKCS#1
**How to avoid:** Convert the key once: `openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in github-app.pem -out github-app-pkcs8.pem` — store the PKCS#8 version as the wrangler secret
**Warning signs:** `DataError: Failed to execute 'importKey' on 'SubtleCrypto'` in Worker logs

### Pitfall 2: `syncAll()` Still Gates on Auth
**What goes wrong:** `syncAll()` calls `GitHubAuthService.shared.getToken()` on line 86 and gates on `.token`. After deleting GitHubAuthService, this line needs removal but `syncAll()` is also called from `SettingsController.swift:57`.
**Why it happens:** The auth gate pattern is duplicated — both `push()` and `syncAll()` check auth independently.
**How to avoid:** In the new `push()`, check only for `contributeMemory == true` (same check already at the top of `syncAll()`). Remove the inner auth gate from `syncAll()` entirely.

### Pitfall 3: MemoryStats.isAvailable Semantics Change
**What goes wrong:** Web UI was showing "Settings guidance" when auth was unavailable. After removing auth, `isAvailable: false` now only means "network failure" — the Leaf templates may still show misleading messaging.
**Why it happens:** `MemoryStats.isAvailable: false` was dual-purpose: auth missing OR network failure. Now it's only network failure.
**How to avoid:** Review `Resources/Views/memory*.leaf` templates and update any auth-specific messaging to say "memory repo unavailable" instead of "configure GitHub credentials".

### Pitfall 4: Package.swift Resources Bundling
**What goes wrong:** After deleting `github-app.pem` and `github-app.json` from `Sources/cellar/Resources/`, the `.copy("Resources")` rule in Package.swift still works — it copies whatever exists. No Package.swift change needed.
**Why it happens:** The Resources rule is not a file-by-file enumeration; it copies the directory.
**How to avoid:** Confirm by checking that no code still references `Bundle.main.url(forResource: "github-app", ...)` — all such code is in GitHubAuthService.swift which is being deleted.

### Pitfall 5: cellar-memory.2026-03-30.private-key.pem in Repo Root
**What goes wrong:** The private key PEM at the repo root is currently untracked (git status shows `??`). It's NOT committed to history, so `git rm` won't work. It should be deleted with `rm` and then `.gitignore` updated to prevent future accidents.
**Why it happens:** The file was generated and placed in the working directory but never staged.
**How to avoid:** `rm cellar-memory.2026-03-30.private-key.pem` + add `*.pem` to `.gitignore` in the same commit wave.

### Pitfall 6: `detectWineVersion` Duplication
**What goes wrong:** `detectWineVersion` and `detectWineFlavor` are private static methods duplicated identically in both `CollectiveMemoryService.swift` and `CollectiveMemoryWriteService.swift`. They're unaffected by this phase but worth noting for a potential future cleanup.
**How to avoid:** Out of scope for Phase 29 — note in code comment if desired.

---

## wrangler.toml Structure

```toml
name = "cellar-memory"
main = "src/index.ts"
compatibility_date = "2024-09-23"

[vars]
CELLAR_MEMORY_REPO = "lasermaze/cellar-memory"

# Secrets (not in wrangler.toml — set via wrangler secret put):
# GITHUB_APP_PEM
# GITHUB_APP_ID
# GITHUB_INSTALLATION_ID
```

## Wrangler Secret Setup Commands

```bash
# One-time setup (run from worker/ directory):
npx wrangler secret put GITHUB_APP_PEM        # paste PKCS#8 PEM content
npx wrangler secret put GITHUB_APP_ID         # GitHub App numeric ID
npx wrangler secret put GITHUB_INSTALLATION_ID # installation ID

# Deploy:
npx wrangler deploy

# Tail logs:
npx wrangler tail
```

## Anonymous GitHub Contents API

For public repos, no Authorization header is required. Relevant details:
- **Rate limit:** 60 requests/hour per IP (unauthenticated)
- **Rate limited response:** HTTP 403 or 429 + `x-ratelimit-remaining: 0`
- **Raw content:** Use `Accept: application/vnd.github.v3.raw` — response body is the raw file content (JSON array)
- **Standard JSON response:** `Accept: application/vnd.github+json` — response includes `sha` and base64 `content` fields (needed by the Worker's GET step, but NOT by the CLI read path)
- **URL pattern:** `https://api.github.com/repos/{owner}/{repo}/contents/{path}`

The read path in Swift uses `application/vnd.github.v3.raw` (returns raw JSON bytes directly) — this is unchanged, just without the Authorization header.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Bundled PEM in binary | Cloudflare Worker holds key | Phase 29 | Key no longer shipped in binary or git history |
| Authenticated GitHub API reads | Anonymous public repo reads | Phase 29 | No credentials needed for read path |
| 60-line JWT flow in Swift | SubtleCrypto in Worker | Phase 29 | JWT logic moves server-side |
| GET+merge+PUT in Swift (~130 lines) | GET+merge+PUT in Worker (~60 lines) | Phase 29 | Swift write path shrinks to ~20 lines |

---

## Open Questions

1. **Production Worker URL**
   - What we know: Will be something like `https://cellar-memory.{subdomain}.workers.dev`
   - What's unclear: The exact URL won't be known until first `wrangler deploy` runs
   - Recommendation: Use a placeholder in code and document that the user must run `wrangler deploy` and update `CELLAR_MEMORY_PROXY_URL` in their env (or hardcode the real URL after first deploy)

2. **GitHub App key revocation timing**
   - What we know: The old key (cellar-memory.2026-03-30.private-key.pem) must be revoked; a new PKCS#8 key should be used for the Worker
   - What's unclear: Whether to generate a new key or convert the existing one
   - Recommendation: Generate a new key from the GitHub App settings page (revoke old simultaneously); convert to PKCS#8 via openssl; store as wrangler secret. Document the rotation procedure in a comment or README.

3. **Winetricks verb list drift**
   - What we know: The Worker must hardcode the same verb list as `AIService.agentValidWinetricksVerbs` (AIService.swift:682)
   - What's unclear: How to prevent the lists from diverging in future phases
   - Recommendation: Add a comment in both files pointing to the other; accept the duplication for Phase 29. A shared source of truth (e.g., a JSON file in the memory repo) is a future improvement but adds a GitHub API call on every write.

---

## Sources

### Primary (HIGH confidence)
- Cloudflare Workers docs (developers.cloudflare.com/workers) — fetch handler signature, wrangler.toml structure, secret management, SubtleCrypto RS256
- GitHub REST API docs (docs.github.com/rest) — anonymous rate limits (60/hr/IP), 403/429 on limit exceeded, Contents API headers
- Direct source code inspection — all GitHubAuthService call sites, GitHubModels types, CollectiveMemoryService/WriteService full flows

### Secondary (MEDIUM confidence)
- SubtleCrypto PKCS8 import format requirement — derived from MDN + Cloudflare Web Crypto docs; PKCS#1 vs PKCS#8 issue is well-documented in Web Crypto literature

### Tertiary (LOW confidence)
- Worker Rate Limiting API availability on free tier — documented as "available" but exact free tier limits not confirmed in docs fetched

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Cloudflare Workers + wrangler is the clear standard; SubtleCrypto is built-in
- Architecture: HIGH — All call sites and data flows verified from source code; Worker patterns verified from official docs
- Pitfalls: HIGH — PKCS#1 vs PKCS#8 is a known concrete issue; other pitfalls derived from reading actual code

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (Cloudflare Workers API is stable; GitHub API rate limits rarely change)
