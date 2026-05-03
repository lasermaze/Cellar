---
phase: 44-collapse-memory-layer-into-single-knowledgestore-with-one-schema-and-local-plus-remote-adapters
plan: "03"
subsystem: memory-layer
tags: [knowledge-store, cache, github-raw, cloudflare-worker, tdd]
dependency_graph:
  requires: [44-01, 44-02]
  provides: [KnowledgeStoreLocal, KnowledgeStoreRemote, HTTPClient, CellarPaths.knowledgeCacheDir, CellarPaths.wikiProxyURL]
  affects: [CollectiveMemoryService, WikiService, AIService]
tech_stack:
  added: [HTTPClient protocol (URLSession seam for testing)]
  patterns: [injectable-http-mock, tdd-red-green, stale-on-failure-cache, policyresources-at-call-time]
key_files:
  created:
    - Sources/cellar/Core/KnowledgeStoreLocal.swift
    - Sources/cellar/Core/KnowledgeStoreRemote.swift
    - Tests/cellarTests/KnowledgeStoreLocalTests.swift
    - Tests/cellarTests/KnowledgeStoreRemoteTests.swift
  modified:
    - Sources/cellar/Persistence/CellarPaths.swift
decisions:
  - "KnowledgeStoreLocal stores configs as [CollectiveMemoryEntry] JSON array (matches wire format); enables merge/replace by environmentHash on re-write"
  - "HTTPClient protocol + MockHTTP/ThrowingMockHTTP strategy: URLSession extension conformance, zero-dep seam for tests"
  - "KnowledgeStoreRemote.write uses typed WorkerWriteEnvelope structs per kind rather than delegating to KnowledgeEntry Codable — allows overwrite:false for sessionLog and WikiAppendPayload shape for gamePage"
  - "sanitize() reads PolicyResources.shared at call time (not init time) — consistent with Phase 43 design; no allowlist duplication"
  - "fetchRecentSessions uses api.github.com listing + raw.githubusercontent.com fetch — same two-step pattern as WikiService.listRecentSessions"
  - "KnowledgeCache key convention: config/{gameId}.json, game-page/{slug}.md, session-log/{filename}.md"
metrics:
  duration: "~10 minutes"
  completed: "2026-05-03"
  tasks_completed: 2
  files_changed: 5
  new_tests: 18
---

# Phase 44 Plan 03: KnowledgeStore Adapter Implementations Summary

Two concrete adapter implementations behind the KnowledgeStore protocol, both with 1-hour TTL cache and stale-on-failure fallback. KnowledgeStoreLocal (pure filesystem) and KnowledgeStoreRemote (GitHub raw reads + Worker writes) with injectable HTTPClient for testability.

## What Was Built

### KnowledgeStoreLocal (cache-only)
- Pure filesystem adapter; no URLSession or network imports
- Cache layout: `~/.cellar/cache/knowledge/config/{gameId}.json`, `game-page/{slug}.md`, `session-log/{filename}.md`
- `fetchContext`: reads config + game-page + session-log sections, 4000-char combined cap, nil when all sources empty
- `write`: config stored as `[CollectiveMemoryEntry]` array (merge/replace by environmentHash); gamePage and sessionLog as raw markdown
- `list`: scans kind directories, slug-filter, mtime-sorted

### KnowledgeStoreRemote (network-backed)
- `HTTPClient: Sendable` protocol with `extension URLSession: HTTPClient {}` — zero boilerplate
- `fetchContext`: concurrent `async let` for config + gamePage + sessions; TTL cache check; stale fallback on 403/429/error
- `write(.config)`: sanitizes via `sanitizeConfigEntry` (PolicyResources.shared allowlists); POSTs `{kind: "config", entry: <CollectiveMemoryEntry>}`
- `write(.gamePage)`: POSTs `{kind: "gamePage", entry: {page: "games/slug.md", entry: <body>, overwrite: true}}`
- `write(.sessionLog)`: POSTs `{kind: "sessionLog", entry: {page: "sessions/filename.md", entry: <body>, overwrite: false}}`
- Errors swallowed; appended to `~/.cellar/logs/memory-push.log`
- `list`: queries `api.github.com/repos/{repo}/contents/{kind-path}`, parses GHItem array, returns KnowledgeEntryMeta

### CellarPaths additions
- `knowledgeCacheDir`: `~/.cellar/cache/knowledge/` (new root, separate from legacy `cache/memory/` and `wiki/`)
- `wikiProxyURL`: base Worker URL with `CELLAR_WIKI_PROXY_URL` env override

## Public API Surface

```swift
// Both adapters (public struct conforming to KnowledgeStore)
struct KnowledgeStoreLocal: KnowledgeStore {
    init(cacheDir: URL = CellarPaths.knowledgeCacheDir)
}

struct KnowledgeStoreRemote: KnowledgeStore {
    init(
        cache: KnowledgeCache = KnowledgeCache(cacheDir: CellarPaths.knowledgeCacheDir),
        http: HTTPClient = URLSession.shared,
        memoryRepo: String = CellarPaths.memoryRepo,
        wikiProxyURL: URL = CellarPaths.wikiProxyURL
    )
}

// HTTP seam (public for test injection)
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

## HTTP Mocking Strategy

`HTTPClient` protocol with `extension URLSession: HTTPClient {}` for zero production overhead. Tests use:
- `MockHTTP`: stub array keyed by URL substring; captures `lastRequestBody` and `lastRequestURL`
- `ThrowingMockHTTP`: always throws `URLError(.notConnectedToInternet)` — tests graceful degradation

No need for any third-party mocking library.

## Cache Directory Layout

```
~/.cellar/cache/knowledge/
  config/
    {gameId}.json          # [CollectiveMemoryEntry] JSON array
  game-page/
    {slug}.md              # raw markdown body
  session-log/
    {filename}.md          # e.g. 2026-05-03-game-slug-abc12345.md
```

Rationale: new path avoids collision with legacy `cache/memory/{slug}.json` and `wiki/` during Plan 04 transition. Plan 04 can leave legacy paths as read-only fallbacks.

## Note for Plan 04 Author

**Where to register KnowledgeStoreContainer.shared:**

In `AIService.runAgentLoop()` before the first call, or at app startup in `Cellar.swift` / `AddCommand.swift`:

```swift
// At startup (once):
KnowledgeStoreContainer.shared = KnowledgeStoreRemote()
```

**Wrapper-style replacement for legacy services:**

```swift
// CollectiveMemoryService.fetchBestEntry(for:wineURL:) replacement:
let context = await KnowledgeStoreContainer.shared.fetchContext(for: gameName, environment: fingerprint)

// WikiService.fetchContext(engine:symptoms:) replacement:
let context = await KnowledgeStoreContainer.shared.fetchContext(for: engine ?? "", environment: fingerprint)

// CollectiveMemoryWriteService.push(record:gameName:wineURL:) replacement:
let entry = buildConfigEntry(from: record, wineURL: wineURL)
await KnowledgeStoreContainer.shared.write(.config(entry))

// WikiService.postSessionLog / postFailureSessionLog replacement:
await KnowledgeStoreContainer.shared.write(.sessionLog(sessionEntry))
```

## Remaining Gaps / Deferred Items

1. **`list()` pagination**: No pagination implemented — GitHub API returns up to 1000 items per request; beyond that, a `?per_page=` + Link header approach would be needed. Deferred since current repo sizes are well within limits.
2. **`KnowledgeStoreLocal.fetchContext` config ranking**: Returns `entries[0]` (most recently written) rather than environment-scored best match — acceptable for offline/test use; KnowledgeStoreRemote has full network ranking via the existing `CollectiveMemoryService` pattern in Plan 04 wiring.
3. **Session listing cache**: `fetchRecentSessions` always fetches the directory listing from api.github.com (no TTL on the listing itself). Individual session files are cached. A listing TTL would reduce API calls in heavy use.

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

Files exist:
- FOUND: Sources/cellar/Core/KnowledgeStoreLocal.swift
- FOUND: Sources/cellar/Core/KnowledgeStoreRemote.swift
- FOUND: Tests/cellarTests/KnowledgeStoreLocalTests.swift
- FOUND: Tests/cellarTests/KnowledgeStoreRemoteTests.swift

Commits exist:
- FOUND: 69ff2f6 (Task 1: KnowledgeStoreLocal + CellarPaths)
- FOUND: 642f5df (Task 2: KnowledgeStoreRemote)

Build: green (Build complete!)
Tests: 219 total, 218 passing, 1 pre-existing Kimi failure unrelated to this plan
New tests: 18 (9 KnowledgeStoreLocal + 9 KnowledgeStoreRemote)
KnowledgeStoreContainer.shared: still NoOp (Plan 04 wires the swap)
