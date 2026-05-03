# Phase 44: Collapse Memory Layer into Single KnowledgeStore — Research

**Researched:** 2026-05-03
**Domain:** Swift protocol design, discriminated union serialization, Cloudflare Worker TypeScript, GitHub Contents API
**Confidence:** HIGH — all findings drawn directly from source code audit of the current codebase

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Storage unification**
- One `KnowledgeStore` protocol with `read(query:)`, `write(entry:)`, `list(filter:)` methods. Local and Worker-backed adapters.
- Three entry kinds preserved as a discriminated union (`KnowledgeEntry.config | .gamePage | .sessionLog`), not collapsed into one shape.
- One schema file with all three kinds; Worker validates against it.

**Read path**
- `KnowledgeStore.fetchContext(for: gameName, environment:)` returns a unified context block — replaces both `WikiService.fetchContext` and `CollectiveMemoryService.fetchBestEntry` at the call site.
- Internal merging: for a given game, fetch best-matching config + most recent N session logs + curated game page, format as one block. Single budget cap (replaces today's two separate budgets).
- Same stale-on-failure caching behavior as today (1-hour TTL, fall back to expired cache on network error).

**Write path**
- All writes go through `KnowledgeStore.write(entry:)`. Worker remains the only thing holding the GitHub App key.
- Session writes (success + failure paths in AIService) call `store.write(.sessionLog(...))`.
- Config writes (post-loop save) call `store.write(.config(...))`.
- Game-page writes (`cellar wiki ingest`) call `store.write(.gamePage(...))`.
- Allowlists (env keys, DLL modes, registry prefixes) live in one place — `PolicyResources` (already extracted in Phase 43). Worker mirrors via build-time export.

**Wiki-as-real-wiki — locked decisions**
- Generalize `WIKI_PAGE_PATTERN` to allow `^[a-z0-9-]+(/[a-z0-9-]+)*\.md$` under `wiki/`. Removes the 5-folder cap. Path traversal still blocked (no `..`).
- Stop overwriting `wiki/games/{slug}.md` wholesale. Instead: scraped upstream content lives in a fenced section `<!-- AUTO BEGIN -->...<!-- AUTO END -->`; agent-authored content lives outside the fence and is preserved across ingests.
- Auto-generated `index.md`. Worker rebuilds it on each write by listing all `*.md` files under `wiki/` and pulling each H1 + first paragraph. Replaces today's hand-curated index.
- No new `create_page` / `edit_section` agent tools in this phase.

**Migration / compatibility**
- Existing data on disk in `entries/*.json`, `wiki/games/*.md`, `wiki/sessions/*.md` stays where it is — new adapters read existing locations. No data migration.
- `CollectiveMemoryService`, `WikiService`, `WikiIngestService` become thin wrappers over `KnowledgeStore` during this phase, then deleted in a follow-up.
- Worker contract: existing endpoints (`/api/contribute`, `/api/wiki/append`) continue to work for one release; new `/api/knowledge/write` lands alongside. Old endpoints removed in a later phase once Swift call sites are migrated.

### Claude's Discretion
- Exact Swift module layout for `KnowledgeStore` and adapters (one file vs. one per adapter).
- Whether `KnowledgeEntry` lives in its own file or alongside `KnowledgeStore`.
- Internal cache key shape (likely `{kind}/{slug}`).
- Test strategy — which adapters get unit tests vs. integration against the live Worker.
- Worker code organization — whether to add a `routes/` split now or keep `index.ts` flat.

### Deferred Ideas (OUT OF SCOPE)
- `create_page(path, body)` agent tool — let agents author arbitrary new pages.
- `edit_section(path, heading, body)` agent tool.
- Tag header / backlink graph.
- Human-facing wiki reader UI.
- Per-page locks / CRDT-style conflict resolution.
- Deletion of `WikiService` / `WikiIngestService` / `CollectiveMemoryService` / `CollectiveMemoryWriteService` — left as thin wrappers in this phase.
- Removal of legacy Worker endpoints (`/api/contribute`, `/api/wiki/append`).
- Data migration.
</user_constraints>

---

## Summary

Phase 44 unifies three parallel memory paths into one `KnowledgeStore` protocol. The audit confirms that **Phase 43 is complete** — `PolicyResources.shared` is live and serving `envAllowlist`, `registryAllowlist`, and `toolSchemas`. The new store can consume `PolicyResources.shared` from day one with no transitional duplication.

The three services have entirely separate read paths, write paths, and cache directories. `CollectiveMemoryService` reads/caches to `~/.cellar/cache/memory/{slug}.json`; `WikiService` reads/caches to `~/.cellar/wiki/{relativePath}`; `WikiIngestService` has no local cache (it reads TTL from GitHub raw and writes via the Worker). There are five distinct call sites in `AIService` and two in `AgentTools` (via `ResearchTools.swift`) that need rewiring. All five can be redirected to `KnowledgeStore` without touching any call-site signatures other than the method name.

The Cloudflare Worker (`worker/src/index.ts`) currently has `WIKI_PAGE_PATTERN` locked to five folders and two root files. The locked decision to generalize this regex is a one-line change that requires careful path-traversal validation (no `..` segments) and a new fenced-section merging function for `games/` overwrites. The Worker also needs a new `/api/knowledge/write` endpoint that accepts a discriminated-union payload with a `kind` discriminant field, plus the auto-`index.md` regeneration hook.

**Primary recommendation:** Build in 4 plans: (1) `KnowledgeStore` protocol + `KnowledgeEntry` enum + shared caching/TTL infrastructure, (2) `KnowledgeStoreLocal` + `KnowledgeStoreRemote` adapters, (3) Worker changes (`/api/knowledge/write`, loosened WIKI_PAGE_PATTERN, fenced sections, index rebuild), (4) call-site rewire (AIService, AgentTools, WikiIngestService) + thin wrappers on the three legacy services.

---

## Current State — Exact Shapes and Call Sites

### Service 1: CollectiveMemoryService

**Purpose:** Structured working configs — env vars, DLL overrides, registry, launch args.

**Read path:**
- `CollectiveMemoryService.fetchBestEntry(for: gameName, wineURL:) async -> String?`
- Reads `entries/{slug}.json` from GitHub (anonymous read from public repo)
- Fetches `https://api.github.com/repos/{memoryRepo}/contents/entries/{slug}.json`
  with `Accept: application/vnd.github.v3.raw`
- 1-hour TTL cache at `~/.cellar/cache/memory/{slug}.json`
- Stale-on-failure: returns expired cache on network error or 403/429
- 404 triggers fuzzy-match: lists `entries/` directory, scores by word overlap, fetches closest match

**Write path (separate service):**
- `CollectiveMemoryWriteService.push(record:gameName:wineURL:) async`
- Detects Wine version/flavor, builds `EnvironmentFingerprint`, constructs `CollectiveMemoryEntry`
- POSTs `{ "entry": CollectiveMemoryEntry }` to `https://cellar-memory-proxy.sook40.workers.dev/api/contribute`
- Env var override: `CELLAR_MEMORY_PROXY_URL`
- No return value — swallows all errors, logs to `~/.cellar/logs/memory-push.log`
- Worker does GET+merge+PUT to `entries/{slug}.json` (dedup by `environmentHash`, retry on 409)

**JSON schema (on-disk):** Snake_case keys via `toSnakeCaseEntry()` in Worker:
```
schema_version, game_id, game_name, config.{environment, dll_overrides, registry, launch_args, setup_deps},
environment.{arch, wine_version, macos_version, wine_flavor}, environment_hash,
reasoning, engine?, graphics_api?, confirmations, last_confirmed
```

**Sanitize path:** `CollectiveMemoryService.sanitizeEntry()` calls:
- `AgentTools.allowedEnvKeys` (now mirrored from `PolicyResources.shared.envAllowlist`)
- `PolicyResources.shared.registryAllowlist`
- Hard-coded valid DLL modes `{"n", "b", "n,b", "b,n", ""}`

**Call sites:**
- `AIService.runAgentLoop()` line 779: `WikiService.fetchContext(engine: entry.name)` (wiki context, not config)
- `AIService.handleContributionIfNeeded()` line 983: `CollectiveMemoryWriteService.push(record:gameName:wineURL:)`

Note: `CollectiveMemoryService.fetchBestEntry()` is NOT currently called in `AIService.runAgentLoop()`. The wiki context (`WikiService.fetchContext`) is called instead. The collective memory read path appears to have been superseded by wiki in the current code. Verify this before the plan — if `fetchBestEntry` is dead code at the AIService level, the read side is simpler.

---

### Service 2: WikiService

**Purpose:** Three duties in one struct:
1. **Read/search** wiki pages from cellar-memory GitHub repo
2. **Ingest** success-record learnings into engine/symptom category pages
3. **Session logs** — write per-session `.md` files to `wiki/sessions/`

**Read path:**
- `WikiService.fetchContext(engine:symptoms:maxPages:) async -> String?`
  - Fetches `wiki/index.md` first; extracts keyword-scored page paths; fetches up to 3 pages
  - Cache: `~/.cellar/wiki/{relativePath}`, 1-hour TTL, stale-on-failure (returns any cached copy)
  - Fetches from `https://raw.githubusercontent.com/{memoryRepo}/main/wiki/{relativePath}`
  - Budget: `maxContentLength = 4000` chars, `maxPages = 3`

- `WikiService.search(query:maxResults:) async -> String`
  - Same path/cache as `fetchContext`; also appends recent session snippets for matching slug
  - Session listing: `GET https://api.github.com/repos/{memoryRepo}/contents/wiki/sessions` (no cache)
  - Per-session file: `fetchPage("sessions/{dateStr}-{slug}-{shortId}.md")` (cached indefinitely — immutable)

**Write path:**
- `WikiService.postWikiAppend(page:entry:commitMessage:overwrite:) async`
  - POSTs `{ page, entry, commitMessage, overwrite }` to `/api/wiki/append`
  - Env var override: `CELLAR_WIKI_PROXY_URL`

- `WikiService.ingest(record:)` — writes to `engines/`, `symptoms/`, `log.md` category pages
- `WikiService.postSessionLog(record:outcome:duration:wineURL:midSessionNotes:) async`
- `WikiService.postFailureSessionLog(gameId:gameName:narrative:...) async`

**Call sites in AIService:**
- Line 779: `WikiService.fetchContext(engine: entry.name)` — initial context build
- Line 854: `WikiService.ingest(record: record)` — after successful save
- Line 856: `WikiService.postSessionLog(record:outcome:duration:wineURL:midSessionNotes:)` — success path
- Line 903: `WikiService.postFailureSessionLog(...)` — failure path

**Call sites in AgentTools (ResearchTools.swift):**
- `queryWiki` tool: `WikiService.search(query: query)`

---

### Service 3: WikiIngestService

**Purpose:** Pre-compile per-game pages from Lutris/ProtonDB/WineHQ/PCGamingWiki via `cellar wiki ingest`.

**Write path:**
- `WikiIngestService.ingest(gameName:) async -> Bool`
  - TTL: checks `wiki/games/{slug}.md` on GitHub raw for `**Last updated:** YYYY-MM-DD` — skips if < 7 days old
  - Fetches CompatibilityReport (Lutris+ProtonDB), WineHQ HTML, PCGamingWiki HTML
  - Formats `formatGamePage(...)` → POSTs to Worker as `overwrite: true` for `games/{slug}.md`
  - No local cache of its own — relies on WikiService.postWikiAppend

**Call sites:**
- `WikiCommand.IngestCommand` (CLI) — direct call
- Nowhere in AIService — the ingest is a separate CLI command only

**Fenced section risk:** Currently `WikiIngestService.ingest` posts with `overwrite: true` — the entire file is replaced. This is where the fenced-section logic must be added.

---

### SessionDraftBuffer (PRESERVE VERBATIM)

`Sources/cellar/Core/SessionDraftBuffer.swift` — final class, not a service.
- `init(shortId:)` — loads existing draft from `~/.cellar/cache/sessions/{shortId}.draft.md`
- `append(content:)` — appends note + persists to disk immediately
- `clearDraft()` — removes on-disk file after successful session log post
- Static `purgeOldDrafts(maxAge:)` — cleans up stale files at session start
- Wire: `AgentTools.draftBuffer` (lazy var), read by `AIService` at session end for `midSessionNotes`
- **No changes needed in this phase.**

---

### PolicyResources (Phase 43 output — COMPLETE)

`Sources/cellar/Core/PolicyResources.swift`

`PolicyResources.shared` exposes:
- `.envAllowlist: Set<String>` — 13 allowed env keys
- `.registryAllowlist: [String]` — allowed HKEY prefixes
- `.toolSchemas: [String: JSONValue]`
- `.systemPrompt: String`
- `.engineDefinitions: [EngineDefinition]`
- `.dllRegistry: [KnownDLL]`

The new `KnowledgeStore` sanitization must call `PolicyResources.shared.envAllowlist` and `.registryAllowlist` — NOT duplicate the allowlists inline. This is already how `CollectiveMemoryService.sanitizeEntry()` works.

The Worker currently has its own hardcoded `ALLOWED_ENV_KEYS`, `VALID_DLL_MODES`, and `ALLOWED_REGISTRY_PREFIXES` constants. The CONTEXT.md decision says "Worker mirrors via build-time export." This means the Worker's constants must be kept in sync (or exported from PolicyResources via a script). This is a risk to flag and decide how to handle.

---

### Cache Directory Layout

| Service | Cache Dir | TTL | Key |
|---------|-----------|-----|-----|
| CollectiveMemoryService | `~/.cellar/cache/memory/` | 1 hr | `{slug}.json` |
| WikiService (pages) | `~/.cellar/wiki/` | 1 hr | mirrors `wiki/{relativePath}` |
| WikiService (sessions) | `~/.cellar/wiki/sessions/` | indefinite | filename = content hash |

The new `KnowledgeStoreLocal` adapter can use a unified cache directory structure:
- `~/.cellar/cache/knowledge/config/{slug}.json` — maps to `entries/{slug}.json`
- `~/.cellar/cache/knowledge/game-page/{slug}.md` — maps to `wiki/games/{slug}.md`
- `~/.cellar/cache/knowledge/session-log/{slug}/` — maps to `wiki/sessions/...`

Or it can reuse the existing directories to avoid cache misses during the wrapper transition period. The planner should decide — both are valid.

---

## Architecture Patterns

### KnowledgeEntry Discriminated Union in Swift

Swift enums with associated values are the idiomatic discriminated union. For Codable round-trip with a `kind` discriminant in JSON:

```swift
// Source: Swift Evolution SE-0307 + standard Codable patterns
enum KnowledgeEntry: Codable {
    case config(ConfigEntry)    // replaces CollectiveMemoryEntry
    case gamePage(GamePageEntry)  // replaces wiki/games/{slug}.md
    case sessionLog(SessionLogEntry)  // replaces wiki/sessions/{dateStr}-{slug}-{shortId}.md

    private enum CodingKeys: String, CodingKey { case kind, payload }
    private enum Kind: String, Codable { case config, gamePage, sessionLog }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .config:     self = .config(try container.decode(ConfigEntry.self, forKey: .payload))
        case .gamePage:   self = .gamePage(try container.decode(GamePageEntry.self, forKey: .payload))
        case .sessionLog: self = .sessionLog(try container.decode(SessionLogEntry.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .config(let e):
            try container.encode(Kind.config, forKey: .kind)
            try container.encode(e, forKey: .payload)
        case .gamePage(let e):
            try container.encode(Kind.gamePage, forKey: .kind)
            try container.encode(e, forKey: .payload)
        case .sessionLog(let e):
            try container.encode(Kind.sessionLog, forKey: .kind)
            try container.encode(e, forKey: .payload)
        }
    }
}
```

This produces `{"kind": "config", "payload": {...}}` over the wire to `/api/knowledge/write`. The Worker validates `kind` then dispatches to the appropriate existing write function.

**Alternative (inline discriminant):** Put `kind` at the top level of the flat object rather than using a `payload` wrapper. This is more natural for JSON consumers but requires custom decode. Both work; the `payload` pattern is simpler to implement correctly.

**Recommendation:** Use flat inline discriminant — put `kind` alongside the existing fields. Reasons: (a) the Worker already has a flat `CollectiveMemoryEntry` shape, (b) avoids an extra nesting level that increases payload size, (c) simpler Worker-side validation with no nested dispatch.

Flat inline pattern:
```swift
func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .config(let e):
        var obj = try JSONEncoder().encode(e)   // encode payload fields
        // inject "kind": "config" — use AnyCodable or a wrapper struct
    }
}
```

In practice, the cleanest Swift approach for flat inline is a wrapper struct:
```swift
struct KnowledgeWriteRequest: Encodable {
    let kind: String
    let entry: KnowledgeEntry  // enum case carries payload
}
```
Worker receives `{"kind":"config","entry":{...}}` or `{"kind":"gamePage","entry":{...}}`.

---

### KnowledgeStore Protocol

```swift
// Confidence: HIGH — this follows the locked design in CONTEXT.md
protocol KnowledgeStore {
    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String?
    func write(_ entry: KnowledgeEntry) async
    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta]
}

struct KnowledgeListFilter {
    var kind: KnowledgeEntry.Kind?
    var slug: String?
    var maxResults: Int
}

struct KnowledgeEntryMeta {
    let kind: KnowledgeEntry.Kind
    let slug: String
    let lastModified: Date?
    let path: String  // relative path in GitHub repo
}
```

The `fetchContext` method encapsulates the current multi-service logic:
1. Fetch config entry for slug (replaces `CollectiveMemoryService.fetchBestEntry`)
2. Fetch game page (replaces `WikiService.fetchContext`)
3. Fetch recent session logs (replaces `WikiService.listRecentSessions` + per-file fetch)
4. Merge with a single character budget cap (replaces the separate 4000-char budgets)

---

### Adapter Pattern: Shared Cache Logic

Both `LocalAdapter` and `RemoteAdapter` need the 1-hour TTL + stale-on-failure pattern. Extract to a `KnowledgeCache` helper struct:

```swift
struct KnowledgeCache {
    let cacheDir: URL
    static let ttl: TimeInterval = 3600

    func read(key: String) -> Data? { ... }
    func write(key: String, data: Data) { ... }
    func isFresh(key: String) -> Bool { ... }
    func readStale(key: String) -> Data? { ... }  // ignores TTL — for stale-on-failure
}
```

`KnowledgeStoreRemote` uses `KnowledgeCache` for all three entry kinds under `~/.cellar/cache/knowledge/`.
`KnowledgeStoreLocal` (if needed) reads directly from disk files in the existing cache dirs.

**Note:** The locked decision says "local + remote adapters." In this codebase, "local" likely means "reads the local `~/.cellar/cache/` copies" and "remote" means "fetches from GitHub raw + writes via Worker." There may not be a pure offline-only use case. The planner should clarify whether `KnowledgeStoreLocal` is for testing purposes (mock) or a real offline-first adapter.

---

### Wrapper Pattern for Backward Compatibility

The three legacy services become one-liner wrappers during this phase:

```swift
// CollectiveMemoryService (thin wrapper)
struct CollectiveMemoryService {
    static func fetchBestEntry(for gameName: String, wineURL: URL) async -> String? {
        let fp = EnvironmentFingerprint.current(wineVersion: detectWineVersion(wineURL: wineURL) ?? "",
                                                 wineFlavor: detectWineFlavor(wineURL: wineURL))
        return await AppContainer.knowledgeStore.fetchContext(for: gameName, environment: fp)
    }
}
```

This requires a shared `KnowledgeStore` instance accessible to both `AIService` and the wrapper types. Options:
1. **Singleton via a static var on `KnowledgeStore`** — mirrors `PolicyResources.shared` pattern
2. **Passed via `AIService.runAgentLoop` parameter** — more testable but requires threading through
3. **Static factory on `KnowledgeStore` protocol via extension** — clean but Swift-specific

**Recommendation:** Use a singleton `KnowledgeStore.shared` for the wrapper transition period. Replace with DI in a later cleanup phase. This matches the `PolicyResources.shared` established pattern.

---

### Worker Changes — Concrete Design

#### 1. Loosen WIKI_PAGE_PATTERN

Current (line 481 of `worker/src/index.ts`):
```typescript
const WIKI_PAGE_PATTERN = /^(engines|symptoms|environments|games|sessions)\/[a-z0-9-]+\.md$|^log\.md$|^index\.md$/;
```

New:
```typescript
const WIKI_PAGE_PATTERN = /^[a-z0-9-]+(\/[a-z0-9-]+)*\.md$/;

function isPathSafe(page: string): boolean {
    // No path traversal
    if (page.includes("..")) return false;
    // Must match pattern
    if (!WIKI_PAGE_PATTERN.test(page)) return false;
    // Must not exceed reasonable depth (protect against deeply nested junk)
    const depth = page.split("/").length;
    if (depth > 4) return false;
    return true;
}
```

This replaces the `WIKI_PAGE_PATTERN.test(payload.page)` check in `handleWikiAppend`.

#### 2. Fenced Section Preservation for `wiki/games/*.md`

When `overwrite: true` and the page is under `wiki/games/`, apply fenced-section merge instead of full overwrite:

```typescript
function applyFencedUpdate(existing: string, newAutoContent: string): string {
    const BEGIN = "<!-- AUTO BEGIN -->";
    const END = "<!-- AUTO END -->";
    const fenceStart = existing.indexOf(BEGIN);
    const fenceEnd = existing.indexOf(END);

    if (fenceStart === -1 || fenceEnd === -1) {
        // No fence on existing file — wrap new content in fence, append agent content (none yet)
        return `${BEGIN}\n${newAutoContent.trim()}\n${END}\n`;
    }

    // Replace fenced region; preserve everything outside
    const before = existing.slice(0, fenceStart);
    const after = existing.slice(fenceEnd + END.length);
    return `${before}${BEGIN}\n${newAutoContent.trim()}\n${END}${after}`;
}
```

The `writeWikiPage` function checks: if `overwrite && page.startsWith("games/")` → use `applyFencedUpdate`, otherwise use existing append or replace logic.

**Migration on first write:** Existing `wiki/games/*.md` files have no fence markers. On the first ingest after this change, the new content wraps itself in fence markers and preserves no agent content (none exists yet). This is correct behavior.

#### 3. Auto-`index.md` Regeneration

After every successful write to `wiki/`, rebuild `wiki/index.md`:

```typescript
async function rebuildIndex(token: string, repo: string): Promise<void> {
    // List all .md files under wiki/ via GitHub tree API
    const treeResp = await fetch(
        `https://api.github.com/repos/${repo}/git/trees/HEAD:wiki?recursive=1`,
        { headers }
    );
    // Filter to .md files, extract first H1 + first para from each
    // Assemble index.md content
    // PUT to wiki/index.md
}
```

**Caveat:** The GitHub tree API (`git/trees`) is a different API than the contents API and doesn't require a separate auth call. However it returns blob SHAs, not content — a second fetch per file would be needed for H1/para extraction, which is expensive (N+1 round trips). A practical alternative is to only update the index with the new page's H1 and append it, rather than rebuilding from scratch. This is simpler and avoids the N+1 problem.

**Recommendation:** For the index, use an append-to-index strategy on each write rather than a full rebuild. The full rebuild is complex and expensive. Reserve it for an explicit `cellar wiki rebuild-index` command if ever needed.

#### 4. `/api/knowledge/write` Endpoint

New endpoint that accepts discriminated-union payload:

```typescript
interface KnowledgeWritePayload {
    kind: "config" | "gamePage" | "sessionLog";
    entry: CollectiveMemoryEntry | WikiAppendPayload | SessionLogPayload;
}
```

Internally dispatches:
- `kind: "config"` → existing `writeEntryToGitHub()` logic (from `/api/contribute`)
- `kind: "gamePage"` → `writeWikiPage()` with `overwrite: true`, fenced-section logic applied
- `kind: "sessionLog"` → `writeWikiPage()` with `overwrite: false`

This allows the new Swift `KnowledgeStoreRemote` to call a single endpoint rather than two separate ones.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Env var allowlist validation | Custom array in KnowledgeStore | `PolicyResources.shared.envAllowlist` | Already extracted in Phase 43; duplication re-creates drift risk |
| Registry prefix validation | Custom array in KnowledgeStore | `PolicyResources.shared.registryAllowlist` | Same as above |
| Cache TTL/stale logic | New TTL implementation | Extract `KnowledgeCache` helper from existing `CollectiveMemoryService.isCacheFresh/loadFromCache` | The pattern is already proven across two services |
| JSON discriminant encoding | Complex manual Codable | Wrapper struct `KnowledgeWriteRequest { kind, entry }` | Simpler than custom encode/decode |
| `index.md` full rebuild on every write | N+1 GitHub API calls | Append single-entry to index on each write | Rebuild = O(N) fetches; append = O(1) |

---

## Common Pitfalls

### Pitfall 1: Missing `fetchBestEntry` Call Site
**What goes wrong:** Searching for `fetchBestEntry` in AIService.swift returns 0 results. The collective memory READ path was superseded by `WikiService.fetchContext` and is not being called in the current `runAgentLoop`.
**Why it happens:** The wiki replaced the direct entry fetch as the primary context source. `CollectiveMemoryService.fetchBestEntry` now has zero call sites in `AIService`.
**How to avoid:** The `KnowledgeStore.fetchContext` must fold the config-entry fetch BACK IN alongside the wiki context. This is not "migrating" an existing call — it's restoring a capability that was dropped. The planner should verify whether this is intentional or an oversight.
**Warning signs:** If `KnowledgeStore.fetchContext` only returns wiki content, the config (env vars, DLL overrides, registry) context will be missing from agent sessions.

### Pitfall 2: Worker Allowlist Drift
**What goes wrong:** Worker `ALLOWED_ENV_KEYS` (line 12-26 of `index.ts`) is hardcoded and diverges from `PolicyResources.env_allowlist.json` over time.
**Why it happens:** Phase 43 extracted the Swift-side allowlist into a versioned file, but the Worker still has its own copy.
**How to avoid:** The CONTEXT.md says "Worker mirrors via build-time export." This implies a build step that reads `env_allowlist.json` and generates a TypeScript constant. Either implement this in `wrangler.toml` (via a pre-deploy script) or accept it as a manual sync and add a comment noting the dependency. The planner must pick one approach and document it.
**Warning signs:** A new env key added to `env_allowlist.json` silently fails validation at the Worker if not also added to `ALLOWED_ENV_KEYS`.

### Pitfall 3: Cache Key Collision During Wrapper Transition
**What goes wrong:** `CollectiveMemoryService` still caches to `~/.cellar/cache/memory/{slug}.json`; `KnowledgeStoreRemote` caches config entries to a new path. Two code paths write different data to different locations for the same game.
**Why it happens:** Wrapper transition — both the wrapper and the new store are live simultaneously.
**How to avoid:** Option A: `KnowledgeStoreRemote` reuses the SAME existing cache paths. Option B: `KnowledgeStoreRemote` uses a new path and the wrapper delegates entirely (no separate cache write). Option A is safer during transition.
**Warning signs:** Cache misses or stale data after first hit with new store.

### Pitfall 4: `wiki/games/*.md` First-Write Fence Absence
**What goes wrong:** Existing game pages (written before this phase) have no `<!-- AUTO BEGIN -->` / `<!-- AUTO END -->` fence markers. The first ingest after the Worker update applies fenced logic to an unfenced file.
**Why it happens:** Migration-on-first-write semantics.
**How to avoid:** The `applyFencedUpdate` function must handle the no-fence case gracefully — wrap the new auto-content in fence markers and output just the fenced block (no agent content exists yet). This is the correct behavior: the first write creates the fence structure; subsequent writes respect it.
**Warning signs:** If the no-fence case throws or returns empty, game pages go blank on first ingest.

### Pitfall 5: Path Traversal with Loosened WIKI_PAGE_PATTERN
**What goes wrong:** New regex `^[a-z0-9-]+(\/[a-z0-9-]+)*\.md$` technically blocks `..` via character class (only `[a-z0-9-]` and `/` allowed), but the explicit `..` check should still be added as defense-in-depth.
**Why it happens:** Regex alone is fragile against edge cases in URI-encoded paths or double-slash sequences.
**How to avoid:** Add an explicit check `if (page.includes("..") || page.startsWith("/"))` before pattern validation in `handleWikiAppend`.
**Warning signs:** A path like `games/../../.env` would fail the character class but the explicit check is clearer.

### Pitfall 6: `agentValidWinetricksVerbs` Dependency in Sanitize
**What goes wrong:** `CollectiveMemoryService.sanitizeEntry()` calls `AIService.agentValidWinetricksVerbs` (line 442). This is an inter-service dependency that would break if the wrapper is deleted.
**Why it happens:** The winetricks verb allowlist is in `AIService`, not `PolicyResources`.
**How to avoid:** Phase 43 may or may not have moved `agentValidWinetricksVerbs` to `PolicyResources`. Verify before planning. If not moved, the `KnowledgeStore` sanitizer must either (a) inline the verb list, (b) call `AIService.agentValidWinetricksVerbs`, or (c) add a `winetricksVerbs` field to `PolicyResources`.

### Pitfall 7: `WikiService.search` Returns `String`, Not `String?`
**What goes wrong:** `queryWiki` in `ResearchTools.swift` calls `WikiService.search(query:)` which returns a plain `String` (never nil). The call site does not guard on nil.
**Why it happens:** The API was designed to always return a human-readable no-match message.
**How to avoid:** The `KnowledgeStore.list()` method returns `[KnowledgeEntryMeta]`. The `queryWiki` tool will need to format this into a string. The non-nil contract must be preserved in the wrapper.

---

## Code Examples

### Current AIService runAgentLoop — Memory Call Sites

```swift
// Source: AIService.swift lines 779-984 (audited 2026-05-03)

// READ: Wiki context for game (line 779)
if let wikiContext = await WikiService.fetchContext(engine: entry.name) {
    contextParts.append(wikiContext)
}

// WRITE: After success — ingest learnings, post session log (lines 853-865)
if let record = SuccessDatabase.load(gameId: gameId) {
    await WikiService.ingest(record: record)
    await WikiService.postSessionLog(
        record: record,
        outcome: .success,
        duration: Date().timeIntervalSince(sessionStartTime),
        wineURL: wineURL,
        midSessionNotes: tools.draftBuffer.notes
    )
    tools.draftBuffer.clearDraft()
}

// WRITE: Failure session log (line 903)
await WikiService.postFailureSessionLog(
    gameId: gameId,
    gameName: entry.name,
    narrative: trimmedFinal,
    actionsAttempted: actions,
    launchCount: tools.launchCount,
    duration: Date().timeIntervalSince(sessionStartTime),
    wineURL: wineURL,
    stopReason: stopReasonStr,
    midSessionNotes: tools.draftBuffer.notes
)

// WRITE: Config push (line 983)
await CollectiveMemoryWriteService.push(record: record, gameName: gameName, wineURL: wineURL)
```

### Proposed KnowledgeStore call sites

```swift
// READ: Unified context fetch (replaces line 779)
if let knowledgeContext = await KnowledgeStore.shared.fetchContext(
    for: entry.name,
    environment: EnvironmentFingerprint.current(wineVersion: ..., wineFlavor: ...)
) {
    contextParts.append(knowledgeContext)
}

// WRITE: Session log (replaces lines 856-864)
await KnowledgeStore.shared.write(.sessionLog(SessionLogEntry(
    gameName: record.gameName,
    outcome: .success,
    duration: duration,
    wineURL: wineURL,
    record: record,
    midSessionNotes: tools.draftBuffer.notes
)))
tools.draftBuffer.clearDraft()

// WRITE: Config (replaces line 983)
await KnowledgeStore.shared.write(.config(ConfigEntry(record: record, gameName: gameName, wineURL: wineURL)))
```

### Worker: Fenced-Section Apply (TypeScript)

```typescript
// Source: design derived from existing writeWikiPage + locked decisions
function applyFencedUpdate(existing: string, newAutoContent: string): string {
    const BEGIN = "<!-- AUTO BEGIN -->";
    const END = "<!-- AUTO END -->";
    const start = existing.indexOf(BEGIN);
    const end = existing.indexOf(END);

    if (start === -1 || end === -1) {
        // First write: no existing fence — output just the fenced block
        return `${BEGIN}\n${newAutoContent.trim()}\n${END}\n`;
    }

    const before = existing.slice(0, start);
    const after = existing.slice(end + END.length);
    return `${before}${BEGIN}\n${newAutoContent.trim()}\n${END}${after}`;
}
```

### Worker: New `/api/knowledge/write` Dispatch

```typescript
// New endpoint alongside existing /api/contribute and /api/wiki/append
if (request.method === "POST" && url.pathname === "/api/knowledge/write") {
    return handleKnowledgeWrite(request, env);
}

async function handleKnowledgeWrite(request: Request, env: Env): Promise<Response> {
    const body = await request.json() as { kind: string; entry: unknown };
    const token = await getInstallationToken(env);
    const repo = env.CELLAR_MEMORY_REPO;

    switch (body.kind) {
        case "config": {
            const result = validateAndSanitize(body.entry);
            if (typeof result === "string") return errorResponse(400, result);
            await writeEntryToGitHub(result, token, repo);
            return okResponse();
        }
        case "gamePage": {
            // body.entry is WikiAppendPayload shape with overwrite:true
            // apply fenced section logic for games/ paths
            const p = body.entry as WikiAppendPayload;
            if (!isPathSafe(p.page)) return errorResponse(400, "invalid_page");
            await writeWikiPageFenced(p.page, p.entry, p.commitMessage ?? "...", token, repo);
            return okResponse();
        }
        case "sessionLog": {
            const p = body.entry as WikiAppendPayload;
            if (!isPathSafe(p.page)) return errorResponse(400, "invalid_page");
            await writeWikiPage(p.page, p.entry, p.commitMessage ?? "...", token, repo, false);
            return okResponse();
        }
        default:
            return errorResponse(400, "unknown_kind");
    }
}
```

---

## Phase 45 Overlap

Phase 45 plans to split `AgentTools` into session/runtime actor + sandbox PageParser. Known overlap with Phase 44:

| Touch Point | Phase 44 | Phase 45 | Recommendation |
|-------------|----------|----------|----------------|
| `ResearchTools.swift` — `queryWiki` tool | Rewires to `KnowledgeStore.shared.search()` | May be moved to a different actor | Phase 44 does the minimum rewire; Phase 45 relocates if needed |
| `AgentTools.draftBuffer` (SessionDraftBuffer) | No change (preserve verbatim) | May be relocated to session actor | No conflict — SessionDraftBuffer is final class, location change is additive |
| `SaveTools.swift` — `save_success` / `save_failure` | These remain tools in AgentTools; AIService calls `KnowledgeStore.write()` post-loop | Phase 45 may restructure tool dispatch | Phase 44 only touches the AIService post-loop path, not the tool implementations |
| `AIService.runAgentLoop()` call sites | Five memory call sites rewired | Phase 45 may refactor loop structure | Phase 44 minimal rewire; Phase 45 can restructure around new KnowledgeStore |

**Coordination:** Phase 44 does NOT need to wait for Phase 45. Phase 45 can consume the new `KnowledgeStore.shared` interface without any changes to Phase 44's output.

---

## Test Strategy

The project uses **Swift Testing** (`@Suite`, `@Test`) — NOT XCTest. Test command: `swift test`. Tests live in `Tests/cellarTests/`. 186 tests currently green (1 pre-existing Kimi model failure unrelated).

| Seam | Test Type | What to Test | Automated? |
|------|-----------|--------------|------------|
| `KnowledgeEntry` Codable round-trip | Unit | All three cases encode+decode with no data loss | Yes — `swift test` |
| `KnowledgeEntry` JSON discriminant | Unit | `kind` field present in encoded JSON; correct case deserialized | Yes |
| `KnowledgeCache` TTL logic | Unit | Fresh/stale/missing file cases | Yes |
| `KnowledgeStoreLocal` read | Unit | Returns nil on empty cache dir; returns formatted string on hit | Yes |
| `KnowledgeStore` thin wrapper (`CollectiveMemoryService`) | Compilation smoke test | Wrapper delegates to store; no dead code | Build check |
| Worker `applyFencedUpdate` | Unit test in Worker | No-fence case, existing fence case, fence without agent content | `vitest` or `jest` if Worker tests exist; else manual |
| Worker `isPathSafe` | Unit | Traversal attempts blocked; valid paths pass | Same as above |
| `/api/knowledge/write` dispatching | Integration | Requires live Worker; skip for automated CI | Manual |

**Existing test files relevant to Phase 44:**
- `Tests/cellarTests/CollectiveMemoryEntryTests.swift` — round-trip tests for `CollectiveMemoryEntry` (will inform `ConfigEntry` tests)
- `Tests/cellarTests/PolicyResourcesTests.swift` — verifies PolicyResources loading (no changes needed)

**Wave 0 gaps (test files to create):**
- `Tests/cellarTests/KnowledgeEntryTests.swift` — covers `KnowledgeEntry` Codable round-trip for all three kinds
- `Tests/cellarTests/KnowledgeCacheTests.swift` — covers TTL helpers (can mock filesystem dates)

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Three separate service types with separate protocols | One `KnowledgeStore` protocol + three adapters | All call sites use one API; future entry kinds are additive |
| Two separate 4000-char context budgets | Single budget cap in `fetchContext` | Agent sees more coherent context without double-counting |
| Five-folder hard cap in Worker | Regex-based path allowlist | Agents can write to new page namespaces without Worker redeploy |
| Full overwrite of `wiki/games/*.md` | Fenced-section preservation | Ingest no longer destroys agent-authored game notes |
| `ALLOWED_ENV_KEYS` duplicated in Swift + TypeScript | `PolicyResources.json` + Worker mirrors | Single source of truth for security policy |

---

## Open Questions

1. **Is `CollectiveMemoryService.fetchBestEntry` dead code at the AIService level?**
   - What we know: `AIService.runAgentLoop` does NOT call `fetchBestEntry`; it only calls `WikiService.fetchContext`.
   - What's unclear: Was this intentional (wiki replaced config context) or an oversight?
   - Recommendation: Check git history for when `fetchBestEntry` was removed from `runAgentLoop`. If intentional, the new `KnowledgeStore.fetchContext` should still integrate config data — it just wasn't being surfaced before. If oversight, Phase 44 restores it.

2. **`agentValidWinetricksVerbs` in `AIService` — is it in `PolicyResources`?**
   - What we know: `CollectiveMemoryService.sanitizeEntry()` calls `AIService.agentValidWinetricksVerbs` for `setupDeps` validation.
   - What's unclear: Phase 43 may or may not have moved this to `PolicyResources`.
   - Recommendation: Grep for `agentValidWinetricksVerbs` before planning. If not in `PolicyResources`, add a `winetricksVerbAllowlist` field to `PolicyResources` in Wave 0.

3. **Worker allowlist sync — build-time export or manual?**
   - What we know: CONTEXT.md says "Worker mirrors via build-time export."
   - What's unclear: No build script exists today.
   - Recommendation: For Phase 44, add a comment in `worker/src/index.ts` pointing to the source-of-truth JSON files. Implement a build-time sync script in a follow-up. The risk of drift is low in the short term (allowlists change rarely).

4. **`index.md` regeneration strategy — append or full rebuild?**
   - What we know: Full rebuild requires N+1 GitHub API calls per write.
   - What's unclear: How large will the wiki be? 50 pages? 500 pages?
   - Recommendation: Append a single link entry to `index.md` on each new page write. Do not rebuild from scratch unless explicitly requested. This is O(1) per write and consistent with how `log.md` is appended.

5. **`KnowledgeStoreLocal` purpose — offline cache or test mock?**
   - What we know: CONTEXT.md specifies "local + remote adapters."
   - What's unclear: Whether "local" means a real offline-first adapter or a test double.
   - Recommendation: Implement `KnowledgeStoreLocal` as a cache-only adapter that reads existing `~/.cellar/cache/` paths without network access. This enables offline testing and a degraded-but-functional mode when GitHub is unreachable. `KnowledgeStoreRemote` uses the network and writes back to cache.

---

## Sources

### Primary (HIGH confidence)
- `Sources/cellar/Core/CollectiveMemoryService.swift` — audited 2026-05-03, exact method signatures and cache paths
- `Sources/cellar/Core/WikiService.swift` — audited 2026-05-03, read/write/session paths
- `Sources/cellar/Core/WikiIngestService.swift` — audited 2026-05-03, TTL logic and overwrite behavior
- `Sources/cellar/Core/CollectiveMemoryWriteService.swift` — audited 2026-05-03, Worker payload shape
- `Sources/cellar/Core/AIService.swift` — audited 2026-05-03, exact call site lines 779/854/856/903/983
- `Sources/cellar/Core/AgentTools.swift` + `Tools/ResearchTools.swift` — audited 2026-05-03
- `Sources/cellar/Core/Tools/SaveTools.swift` — audited 2026-05-03
- `Sources/cellar/Core/SessionDraftBuffer.swift` — audited 2026-05-03, preserve verbatim
- `Sources/cellar/Core/PolicyResources.swift` — audited 2026-05-03, confirmed Phase 43 complete
- `worker/src/index.ts` — audited 2026-05-03, exact WIKI_PAGE_PATTERN and endpoint list
- `Sources/cellar/Persistence/CellarPaths.swift` — audited 2026-05-03, exact cache directory paths
- `.planning/STATE.md` — Phase 43 confirmed complete (all 3 plans, 186 tests green)
- `Tests/cellarTests/CollectiveMemoryEntryTests.swift` — audited 2026-05-03, existing test patterns
- `.planning/config.json` — `nyquist_validation` not present (workflow.nyquist_validation absent, skip Validation Architecture section)

### Secondary (MEDIUM confidence)
- `.planning/phases/44-collapse-memory-layer-into-single-knowledgestore-with-one-schema-and-local-plus-remote-adapters/44-CONTEXT.md` — locked decisions
- Swift Evolution SE-0307 (resultBuilder) — enum Codable patterns are standard Swift

---

## Metadata

**Confidence breakdown:**
- Current state mapping: HIGH — direct code audit
- KnowledgeStore protocol design: HIGH — follows locked decisions + established patterns
- Worker changes: HIGH — direct reading of worker/src/index.ts
- Test strategy: HIGH — existing test infrastructure audited directly

**Research date:** 2026-05-03
**Valid until:** 2026-06-03 (stable Swift codebase, no external library dependencies)
