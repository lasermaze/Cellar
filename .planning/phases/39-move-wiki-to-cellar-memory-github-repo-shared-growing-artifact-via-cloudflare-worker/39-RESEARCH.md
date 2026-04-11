# Phase 39: Move Wiki to cellar-memory GitHub Repo — Research

**Researched:** 2026-04-06
**Domain:** Swift service refactor + Cloudflare Worker extension + SPM resource removal
**Confidence:** HIGH — all code is local, no external library research needed

## Summary

Phase 39 is a refactor, not a greenfield build. Every piece of infrastructure already exists and works. The work is: (1) move the wiki directory from the SPM bundle into the cellar-memory GitHub repo, (2) rewrite WikiService reads to use `~/.cellar/wiki/` as a local cache with GitHub raw URL fetching (exact pattern from CollectiveMemoryService), (3) rewrite WikiService.ingest to POST to a new Cloudflare Worker endpoint (exact pattern from CollectiveMemoryWriteService), (4) add the new `/api/wiki/append` route to `worker/src/index.ts`, and (5) remove `.copy("wiki")` from Package.swift.

The primary risk is the ingest write model changing from synchronous local file writes (currently `appendIfNew` uses `FileHandle.seekToEndOfFile`) to async remote POSTs. The current ingest callers are synchronous (`static func ingest(record:)` returns `Void`, called in a non-async context). This requires either making the call site `async` or using `Task { }` fire-and-forget. The existing collective memory write path uses fire-and-forget `await` inside `AIService`, so `WikiService.ingest` should become `async` and be called with `await` alongside `CollectiveMemoryWriteService.push`.

The wiki write model (append to a specific markdown file in GitHub) is different from the collective memory write model (JSON array merge by environmentHash). The Worker needs a distinct `writeWikiPage` helper that: GETs current file content, appends the new entry if not already present (server-side dedup), PUTs back with commit message.

**Primary recommendation:** Mirror CollectiveMemoryService (read path) and CollectiveMemoryWriteService (write path) as closely as possible; add one new Worker route handler.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Storage Layout**
- Repo: Reuse existing `lasermaze/cellar-memory` GitHub repo
- Path: `wiki/` subdirectory in that repo (alongside existing `entries/` for collective memory JSONs)
- Structure: Same as current (SCHEMA.md, index.md, log.md, engines/, symptoms/, environments/)

**Read Path**
- Local cache: `~/.cellar/wiki/` (writable)
- Sync source: GitHub raw URLs (public read, no auth needed)
- Caching: Reuse CollectiveMemoryService pattern — 1-hour TTL, stale-on-failure
- On startup: WikiService checks cache freshness, fetches from GitHub if stale
- Fallback: If cache empty AND GitHub unreachable, return nil gracefully (agent continues without wiki)

**Write Path**
- Via Cloudflare Worker — reuse existing `worker/` infrastructure
- New endpoint: `POST /wiki/append` (or similar) that accepts page path + content to append
- Auth: Worker uses GitHub App private key to push (same as existing `/push` endpoint)
- Client: WikiService.ingest serializes updates and POSTs to Worker
- Dedup: Worker-side substring check before committing (move dedup from local to server)

**Removed**
- SPM resource bundle — remove `.copy("wiki")` from Package.swift
- Bundle.module reads — WikiService reads from `~/.cellar/wiki/` instead
- Initial seed content in repo source — move `Sources/cellar/wiki/` → `cellar-memory/wiki/` (git mv equivalent)

**First-Run Experience**
- On first run, cache is empty → sync from GitHub immediately (blocking, ~200ms)
- If offline on first run, wiki unavailable that session, cache populated next run

### Claude's Discretion
- Exact Worker endpoint names and request/response schemas
- Cache invalidation strategy (ETags? Last-modified? Simple TTL?)
- How WikiService handles partial sync failures (some pages fetched, some failed)
- Whether to sync on every launch or lazily on first WikiService call
- Whether to expose a manual sync command (`cellar wiki sync`)
- How log.md conflicts are resolved when multiple users ingest concurrently

### Deferred Ideas (OUT OF SCOPE)
- PR-based wiki writes (for human review before merging)
- Wiki versioning / page history beyond what git provides
- Search index build (BM25/vector) — keyword scoring is fine for now
- Multi-locale wiki pages
- Wiki page validation CI in cellar-memory repo
- Web UI for browsing wiki content
</user_constraints>

---

## Standard Stack

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| URLSession (async/await) | system | GitHub raw URL fetches | Already used in CollectiveMemoryService |
| FileManager | system | `~/.cellar/wiki/` cache management | Used throughout CellarPaths |
| Cloudflare Worker (TypeScript) | existing | Authenticated GitHub writes | Same worker as collective memory proxy |
| GitHub Contents API | v3 (2022-11-28) | GET/PUT file contents | Same API used by existing writeEntryToGitHub |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| CellarPaths | local | Path constants for wiki cache dir | Add `wikiCacheDir` + `wikiCacheFile(for:)` |
| ISO8601DateFormatter | system | Cache freshness timestamps | Same as CollectiveMemoryService.isCacheFresh |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Simple 1-hour TTL | ETags / If-Modified-Since | ETag is more accurate but adds round-trip; TTL is fine at this scale |
| Lazy sync on first call | Sync on startup | Lazy avoids penalizing startup; either works since wiki fetch is fast (~200ms) |
| Fire-and-forget Task {} for ingest | Blocking await | Fire-and-forget matches existing collective memory write pattern |

---

## Architecture Patterns

### Recommended File Changes

```
Sources/cellar/Persistence/CellarPaths.swift       — add wiki cache paths
Sources/cellar/Core/WikiService.swift               — full rewrite (read + write)
worker/src/index.ts                                 — add /api/wiki/append route
Package.swift                                       — remove .copy("wiki")
Sources/cellar/wiki/                                — delete entire directory (moved to cellar-memory repo)
```

### Pattern 1: Read Path — Mirror CollectiveMemoryService

WikiService.fetchContext and WikiService.search currently do `Bundle.module.url(forResource: "wiki", ...)`. After the refactor, they should:

1. Build the local cache path: `CellarPaths.wikiCacheDir.appendingPathComponent(relativePath)`
2. Check cache freshness (isCacheFresh — same 3600s TTL)
3. If stale: fetch each needed page from GitHub raw URL
4. If network error: serve stale cache (graceful degradation)
5. If cache empty + offline: return nil

GitHub raw URL pattern for wiki pages (public, no auth):
```
https://raw.githubusercontent.com/{repo}/main/wiki/{relativePath}
```

For example: `https://raw.githubusercontent.com/lasermaze/cellar-memory/main/wiki/index.md`

This is the same public-read pattern as collective memory reads. No auth header needed.

**Key difference from collective memory:** Wiki fetches multiple files (index + up to 3 pages) vs. one JSON file per game. The sync should fetch index.md first, then relevant pages on-demand. Pages that exist in cache and are fresh should not be re-fetched.

### Pattern 2: Write Path — Mirror CollectiveMemoryWriteService

WikiService.ingest currently writes directly to Bundle.module paths (fails silently on signed apps). After refactor:

```swift
// New signature — async to match collective memory write pattern
static func ingest(record: SuccessRecord) async {
    // Build list of (pagePath, entryLine) pairs same as today
    // POST each update to Worker via WikiWritePayload
    await postWikiAppend(pagePath: "symptoms/crash-on-launch.md", entry: line)
    // Also POST log.md update
}
```

The Worker endpoint accepts:
```json
POST /api/wiki/append
{
  "page": "symptoms/crash-on-launch.md",
  "entry": "- **Game Name**: symptom → fix (cause: ...)",
  "commitMessage": "wiki: ingest from Game Name session"
}
```

Response:
- `200 {"status": "ok"}` — appended and committed
- `200 {"status": "skipped"}` — entry already present (server-side dedup)
- `400 {"status": "error", "message": "..."}` — bad request
- `429` — rate limited
- `502` — GitHub API error

### Pattern 3: Worker Route Handler

The existing Worker has one route: `POST /api/contribute`. The new wiki route is `POST /api/wiki/append`.

The `writeWikiPage` Worker function:
1. GET current file via GitHub Contents API: `GET /repos/{repo}/contents/wiki/{page}`
2. Base64-decode content
3. If entry substring already present → return `{status: "skipped"}` (server-side dedup)
4. Append `\n{entry}\n` to content
5. Base64-encode updated content
6. PUT back with SHA and commit message
7. On 409 conflict: retry once (same as `writeEntryToGitHub`)

The `handleWikiAppend` function follows the same shape as `handleContribute`:
- Same CORS headers
- Same body size cap (50KB)
- Same IP rate limiting (shared `rateLimitMap`)
- Same `getInstallationToken` call
- Same error response shapes

**Path validation:** The Worker must validate `page` field against an allowlist or path pattern to prevent arbitrary file writes. Use: `^(engines|symptoms|environments|games)/[a-z0-9-]+\.md$|^log\.md$|^index\.md$`

### Pattern 4: CellarPaths Additions

Following the existing `memoryCacheDir` / `memoryCacheFile(for:)` pattern:

```swift
/// Directory for cached wiki pages — mirrors cellar-memory/wiki/ structure
static let wikiCacheDir: URL = base.appendingPathComponent("wiki")

/// Cache file path for a given wiki page relative path (e.g. "engines/directdraw.md")
static func wikiCacheFile(for relativePath: String) -> URL {
    wikiCacheDir.appendingPathComponent(relativePath)
}
```

### Pattern 5: ingest Call Site Update in AIService

Current (synchronous):
```swift
WikiService.ingest(record: record)
```

After (async, mirrors CollectiveMemoryWriteService.push):
```swift
WikiService.ingest(record: record)  // if made async
await WikiService.ingest(record: record)
```

The call is inside `didSave` block in AIService which is already in an async context. See AIService line ~1096-1099 — it's inside an `if let record = SuccessDatabase.load(gameId:)` guard. No structural change needed to AIService beyond adding `await`.

### Anti-Patterns to Avoid

- **Don't sync all wiki pages on startup:** Only fetch index.md on launch; fetch individual pages lazily when search/fetchContext is called. Avoids downloading all 11 pages every hour.
- **Don't block main agent prompt build on wiki network failure:** If GitHub is unreachable and cache is empty, return nil (current behavior), don't throw or retry.
- **Don't put dedup logic only in Swift client:** Move it to the Worker (server-side). The current `appendIfNew` local check was needed because reads/writes were local; with a shared GitHub repo, multiple users can see the same page, so dedup must be server-side to avoid duplicates from different users.
- **Don't use GitHub Contents API raw download for ingest write path:** Use the Worker proxy (same as collective memory writes) — the GitHub App token is only in the Worker.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| GitHub App JWT auth | Custom JWT + GitHub API calls in Swift | Existing Worker (`getInstallationToken`) | Private key lives in Cloudflare secrets; never ship key in binary |
| File content GET+PUT with SHA | Custom GitHub API client | `writeWikiPage` in Worker (pattern from `writeEntryToGitHub`) | Existing function handles conflict retry, base64 encoding |
| Cache freshness logic | Custom mtime check | Copy `isCacheFresh` from CollectiveMemoryService | Already tested, uses `attributesOfItem` modificationDate |
| Rate limiting | Per-user KV tracking | Existing in-memory `rateLimitMap` | Same shared map; no additional billing |

---

## Common Pitfalls

### Pitfall 1: Subdirectory Cache Files
**What goes wrong:** `wikiCacheFile(for: "engines/directdraw.md")` returns `~/.cellar/wiki/engines/directdraw.md` but the `engines/` subdirectory doesn't exist yet.
**Why it happens:** FileManager won't create intermediate directories automatically on write.
**How to avoid:** Before writing any cache file, call `try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)`.
**Warning signs:** Silent write failures — file never appears in cache.

### Pitfall 2: ingest Becomes Async — AIService Call Site
**What goes wrong:** `WikiService.ingest` is currently synchronous. Making it async without updating AIService will cause a compile error.
**Why it happens:** Swift 6 strict concurrency — can't call async from sync context.
**How to avoid:** Add `await` at the call site in AIService (it's already in an async closure). Or wrap in `Task { await WikiService.ingest(record: record) }` if fire-and-forget is preferred.
**Warning signs:** Compiler error `expression is 'async' but is not marked with 'await'`.

### Pitfall 3: Bundle.module Removal Breaks Tests
**What goes wrong:** Tests that exercise WikiService might use `Bundle.module` paths that no longer exist after removing `Sources/cellar/wiki/`.
**Why it happens:** Test target may indirectly call WikiService functions.
**How to avoid:** Check for any test that calls WikiService. With the refactor, WikiService reads from `~/.cellar/wiki/` which is writable — tests should set up fixture files there or mock the cache.
**Warning signs:** Test compile errors after `Sources/cellar/wiki/` removal; test failures looking for bundle resources.

### Pitfall 4: log.md Concurrent Append Conflicts
**What goes wrong:** Two users ingest at the same moment → both GET log.md, both append, both PUT → one overwrites the other (GitHub 409 or lost write).
**Why it happens:** Non-atomic read-modify-write on shared log.md in a public repo.
**How to avoid:** The Worker already handles 409 with a single retry. For log.md specifically, the worst case is one ingest entry being lost — acceptable. The dedup check prevents duplicate entries from the same user.
**Warning signs:** log.md entries sporadically missing; 409 errors in Worker logs.

### Pitfall 5: Worker Path Validation — Directory Traversal
**What goes wrong:** A malicious or buggy client POSTs `"page": "../../.github/workflows/deploy.yml"` and the Worker writes to that path.
**Why it happens:** No input validation on the `page` field.
**How to avoid:** Validate `page` against regex `^(engines|symptoms|environments|games)/[a-z0-9-]+\.md$|^log\.md$|^index\.md$` in the Worker before calling `writeWikiPage`.
**Warning signs:** GitHub API returning unexpected paths; Pages outside `wiki/` being modified.

### Pitfall 6: GitHub Raw URL Caching (Cache-Control)
**What goes wrong:** GitHub raw content URLs are served with a 5-minute CDN cache. Freshly-ingest pages may not be immediately visible to other users.
**Why it happens:** GitHub CDN headers on raw.githubusercontent.com.
**How to avoid:** Acceptable — the 1-hour local TTL is a floor, not a ceiling. Users will see ingest results within ~5 minutes. No action needed.
**Warning signs:** None — this is expected behavior.

### Pitfall 7: First-Run Blocking Fetch
**What goes wrong:** On first run with empty cache, `fetchContext` is called synchronously (it was `static func fetchContext` not `async`) but now needs to fetch from GitHub.
**Why it happens:** Current `WikiService.fetchContext` and `.search` are synchronous. The refactor must make them `async` since they now do network I/O.
**How to avoid:** Make `fetchContext` and `search` async. Update callers in AIService (already async context) and AgentTools (execute() is async).
**Warning signs:** Deadlock or stale data if URLSession is called synchronously; compiler errors in callers.

---

## Code Examples

### CellarPaths additions (HIGH confidence — mirrors existing pattern)
```swift
// In Sources/cellar/Persistence/CellarPaths.swift
static let wikiCacheDir: URL = base.appendingPathComponent("wiki")

static func wikiCacheFile(for relativePath: String) -> URL {
    wikiCacheDir.appendingPathComponent(relativePath)
}
```

### WikiService read path sketch (HIGH confidence — mirrors CollectiveMemoryService)
```swift
static func fetchPageFromCache(_ relativePath: String) -> String? {
    let cacheFile = CellarPaths.wikiCacheFile(for: relativePath)
    guard isCacheFresh(cacheFile) else { return nil }
    return try? String(contentsOf: cacheFile, encoding: .utf8)
}

static func fetchPageFromGitHub(_ relativePath: String) async -> String? {
    let urlString = "https://raw.githubusercontent.com/\(CellarPaths.memoryRepo)/main/wiki/\(relativePath)"
    guard let url = URL(string: urlString) else { return nil }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
    // Write to cache
    let cacheFile = CellarPaths.wikiCacheFile(for: relativePath)
    try? FileManager.default.createDirectory(at: cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: cacheFile, options: .atomic)
    return String(data: data, encoding: .utf8)
}
```

### Worker wiki append endpoint shape (HIGH confidence — mirrors handleContribute)
```typescript
// New interface
interface WikiAppendPayload {
  page: string;      // e.g. "symptoms/crash-on-launch.md"
  entry: string;     // the line(s) to append
  commitMessage?: string;
}

// Path validation regex
const WIKI_PAGE_PATTERN = /^(engines|symptoms|environments|games)\/[a-z0-9-]+\.md$|^log\.md$|^index\.md$/;

async function writeWikiPage(
  page: string,
  entry: string,
  commitMessage: string,
  token: string,
  repo: string,
  attempt = 0
): Promise<"ok" | "skipped"> {
  const path = `wiki/${page}`;
  const apiBase = `https://api.github.com/repos/${repo}/contents/${path}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "cellar-memory-proxy/1.0",
  };

  const getResp = await fetch(apiBase, { headers });
  let sha: string | undefined;
  let existing = "";

  if (getResp.ok) {
    const data = (await getResp.json()) as { sha: string; content: string };
    sha = data.sha;
    existing = atob(data.content.replace(/\s/g, ""));
  } else if (getResp.status !== 404) {
    throw new Error(`GitHub GET failed: ${getResp.status}`);
  }

  // Server-side dedup
  if (existing.includes(entry)) return "skipped";

  const updated = existing + "\n" + entry + "\n";
  const content = btoa(unescape(encodeURIComponent(updated)));
  const putBody: Record<string, unknown> = { message: commitMessage, content };
  if (sha) putBody.sha = sha;

  const putResp = await fetch(apiBase, {
    method: "PUT", headers, body: JSON.stringify(putBody),
  });

  if (putResp.status === 409 && attempt === 0) {
    return writeWikiPage(page, entry, commitMessage, token, repo, 1);
  }
  if (!putResp.ok) throw new Error(`GitHub PUT failed: ${putResp.status}`);
  return "ok";
}
```

### WikiService write payload (HIGH confidence — mirrors ProxyPayload pattern)
```swift
struct WikiAppendPayload: Encodable {
    let page: String
    let entry: String
    let commitMessage: String
}
```

### Worker route dispatch addition (HIGH confidence)
```typescript
// In main fetch handler, add alongside existing /api/contribute check:
if (request.method === "POST" && url.pathname === "/api/wiki/append") {
  return handleWikiAppend(request, env);
}
```

---

## Implementation Scope Summary

### Plan P01: Swift read path + CellarPaths
- Add `wikiCacheDir` and `wikiCacheFile(for:)` to CellarPaths
- Rewrite `WikiService.fetchContext` and `WikiService.search` to use cache + async GitHub fetch
- Make `fetchContext` and `search` async
- Update call sites in AIService and AgentTools

### Plan P02: Swift write path (WikiService.ingest)
- Make `WikiService.ingest` async
- Remove local `appendIfNew` file writes
- Add `WikiAppendPayload` struct + `postWikiAppend` helper mirroring `CollectiveMemoryWriteService.postToProxy`
- Update AIService call site to `await WikiService.ingest(record: record)`
- Add env var `CELLAR_WIKI_PROXY_URL` (same worker, different path, but override pattern still useful for tests)

### Plan P03: Cloudflare Worker — add /api/wiki/append
- Add `WikiAppendPayload` interface
- Add `WIKI_PAGE_PATTERN` validation regex
- Add `writeWikiPage` function (GET+dedup+PUT+retry)
- Add `handleWikiAppend` function (CORS, size cap, rate limit, getInstallationToken, writeWikiPage)
- Wire into main fetch handler

### Plan P04: Migration — move wiki files + remove SPM bundle
- Remove `.copy("wiki")` from Package.swift
- Delete `Sources/cellar/wiki/` directory (files move to cellar-memory repo manually)
- Document: the wiki files must be committed to `lasermaze/cellar-memory/wiki/` before deploying

---

## Open Questions

1. **Should `fetchContext` and `search` become async?**
   - What we know: Both call local file I/O only today. After refactor they need network I/O.
   - What's unclear: `WikiService.search` is called from `AgentTools.execute()` which is already async. `fetchContext` is called in AIService which is also async. Both callers are in async contexts.
   - Recommendation: Yes, make both async. No structural changes to callers needed — just add `await`.

2. **When to populate the wiki cache — on startup or lazily?**
   - What we know: CONTEXT.md says "sync on startup" but also "lazily on first WikiService call" is Claude's discretion.
   - What's unclear: If startup sync is blocking, it adds ~200ms to every launch even when wiki isn't needed.
   - Recommendation: Lazy — fetch index.md only when `fetchContext` or `search` is first called. Don't add startup overhead. This is consistent with collective memory which also fetches lazily.

3. **Does the wiki need a separate rate limit bucket in the Worker?**
   - What we know: Existing `rateLimitMap` is shared across all routes (10 writes/hr/IP). Wiki appends should count against the same budget.
   - Recommendation: Use the shared `rateLimitMap`. A single IP doing wiki appends + collective memory contributions is still bounded at 10/hr total.

4. **How does the cellar-memory repo get the initial wiki/ directory?**
   - What we know: `Sources/cellar/wiki/` has 11 markdown files that need to move.
   - What's unclear: This is a git operation outside the Swift build — needs manual step or a one-time script.
   - Recommendation: Document as a manual prerequisite in the plan. The executor must push `wiki/` to the cellar-memory repo before P04 (Package.swift change) is deployed. Include a note in P04.

---

## Validation Architecture

`nyquist_validation` is not present in `.planning/config.json` — skip this section.

---

## Sources

### Primary (HIGH confidence)
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/CollectiveMemoryService.swift` — read path pattern with GitHub raw URL fetch, 1-hour TTL cache, stale fallback
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/CollectiveMemoryWriteService.swift` — write path pattern via Cloudflare Worker POST
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/WikiService.swift` — current implementation (Bundle.module reads, synchronous, local appendIfNew)
- `/Users/peter/Documents/Cellar/worker/src/index.ts` — existing Worker with `handleContribute`, `writeEntryToGitHub`, `getInstallationToken`, rate limiting, validation
- `/Users/peter/Documents/Cellar/Sources/cellar/Persistence/CellarPaths.swift` — path helpers; `memoryCacheDir`/`memoryCacheFile` pattern to mirror
- `/Users/peter/Documents/Cellar/Package.swift` — `.copy("wiki")` resource declaration to remove
- `/Users/peter/Documents/Cellar/.planning/phases/39-.../39-CONTEXT.md` — locked decisions

### Secondary (MEDIUM confidence)
- GitHub raw content URL pattern: `https://raw.githubusercontent.com/{owner}/{repo}/{branch}/{path}` — well-known public read path, no auth required

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all infrastructure exists, no new dependencies
- Architecture: HIGH — directly mirrors existing working patterns in the codebase
- Pitfalls: HIGH — derived from reading actual code and reasoning about edge cases
- Worker endpoint design: HIGH — pattern is a direct copy of `handleContribute` with wiki-specific logic

**Research date:** 2026-04-06
**Valid until:** Stable indefinitely (no external libraries; only internal code patterns)
