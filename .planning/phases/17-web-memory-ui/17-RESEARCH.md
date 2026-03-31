# Phase 17: Web Memory UI - Research

**Researched:** 2026-03-30
**Domain:** Vapor/Leaf web UI + GitHub Contents API aggregate reads
**Confidence:** HIGH

## Summary

Phase 17 adds two new web views that surface the collective memory repository: an aggregate stats page at `/memory` (WEBM-01) and a per-game detail page at `/memory/:gameId` (WEBM-02). Both views must degrade gracefully when the memory repo is unreachable — returning an empty state rather than a 500 error.

The project already has everything needed: Vapor + Leaf for the web layer, GitHubAuthService for authenticated API calls, CollectiveMemoryEntry for the data model, and a proven synchronous URLSession pattern for GitHub Contents API calls. The new work is (a) a MemoryController with two routes, (b) a MemoryStatsService that fetches the `entries/` directory listing and then each game file, (c) two Leaf templates that follow the `base.leaf` pattern, and (d) a nav link added to `base.leaf`.

The key architectural challenge is the aggregate stats view: computing "total games covered" and "total confirmations" requires listing the `entries/` directory (GitHub Contents API) and then fetching each individual game file. For a small collection (tens of games) this is acceptable synchronously. Error handling must treat any GitHub failure as an empty/degraded state rather than a server error.

**Primary recommendation:** Add a `MemoryStatsService` (stateless struct, mirrors `CollectiveMemoryService` pattern) with a synchronous `fetchStats()` method, register routes in a new `MemoryController`, create `memory.leaf` and `memory-game.leaf` templates, and add a "Memory" nav link to `base.leaf`.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WEBM-01 | Web UI shows collective memory stats (games covered, total confirmations, recent contributions) | GitHub Contents API `GET /repos/{owner}/{repo}/contents/entries` lists all game files; each file can be fetched for entry arrays to sum confirmations. `lastConfirmed` field in CollectiveMemoryEntry is the recency signal. |
| WEBM-02 | Web UI shows per-game memory entries with environment details and confidence scores | `GET /repos/{owner}/{repo}/contents/entries/{slug}.json` with `Accept: application/vnd.github.v3.raw` returns the `[CollectiveMemoryEntry]` array directly. `EnvironmentFingerprint` has arch, wineVersion, macosVersion, wineFlavor. `confirmations` is the confidence score. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vapor | already in SPM | HTTP routing, request/response | All web routes use this — no alternative |
| Leaf | already in SPM | HTML templating | All existing views use this — follow the pattern |
| URLSession | system | GitHub API HTTP calls | Used by CollectiveMemoryService and CollectiveMemoryWriteService |
| GitHubAuthService | project | Bearer token for API calls | Shared singleton — existing auth layer |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DispatchSemaphore | system | Synchronous URLSession wrapper | Used consistently in CollectiveMemory{Read,Write}Service — maintain the pattern |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Synchronous fetch with semaphore | async/await URLSession | Async requires Vapor async route handler, which is already used — but CollectiveMemory* services are sync structs. Keep sync to match existing pattern without refactor. |
| Fetching each game file individually | GitHub Search API | Search API has rate limits and is overkill for a small repo. Contents API directory listing + per-file fetches is direct and already proven. |

**Installation:**
No new dependencies. All required libraries are already in the project.

## Architecture Patterns

### Recommended Project Structure
New files to add:
```
Sources/cellar/Web/Controllers/MemoryController.swift
Sources/cellar/Web/Services/MemoryStatsService.swift
Sources/cellar/Resources/Views/memory.leaf
Sources/cellar/Resources/Views/memory-game.leaf
```

Modified files:
```
Sources/cellar/Web/WebApp.swift          -- register MemoryController
Sources/cellar/Resources/Views/base.leaf -- add Memory nav link
```

### Pattern 1: Controller Registration (matches existing pattern)
**What:** A static enum with a `register(_ app: Application)` method.
**When to use:** All web controllers in this project follow this pattern.
**Example:**
```swift
// Source: Sources/cellar/Web/Controllers/GameController.swift (existing)
enum MemoryController {
    static func register(_ app: Application) throws {
        // GET /memory -- aggregate stats
        app.get("memory") { req async throws -> View in
            let stats = MemoryStatsService.fetchStats()
            return try await req.view.render("memory", MemoryController.MemoryContext(
                title: "Community Memory",
                stats: stats
            ))
        }

        // GET /memory/:gameSlug -- per-game entries
        app.get("memory", ":gameSlug") { req async throws -> View in
            guard let slug = req.parameters.get("gameSlug") else {
                throw Abort(.badRequest)
            }
            let gameDetail = MemoryStatsService.fetchGameDetail(slug: slug)
            return try await req.view.render("memory-game", MemoryController.MemoryGameContext(
                title: gameDetail?.gameName ?? slug,
                detail: gameDetail
            ))
        }
    }
}
```

### Pattern 2: MemoryStatsService — Stateless Struct with Graceful Degradation
**What:** A stateless struct with static methods that swallow all errors and return empty state on failure.
**When to use:** Mirrors `CollectiveMemoryService` exactly — never throws, caller gets usable data or nil/empty.
**Example:**
```swift
// Source: mirrors CollectiveMemoryService.swift pattern
struct MemoryStatsService {
    struct MemoryStats {
        let gameCount: Int
        let totalConfirmations: Int
        let recentContributions: [RecentContribution]
        let isAvailable: Bool  // false = memory repo unreachable
    }

    struct RecentContribution {
        let gameName: String
        let gameSlug: String
        let lastConfirmed: String
        let confirmations: Int
    }

    /// Returns stats or an "unavailable" placeholder — never throws.
    static func fetchStats() -> MemoryStats {
        // Auth check (same pattern as CollectiveMemoryService)
        let authResult = GitHubAuthService.shared.getToken()
        guard case .token(let token) = authResult else {
            return MemoryStats(gameCount: 0, totalConfirmations: 0, recentContributions: [], isAvailable: false)
        }
        // Fetch entries/ directory listing
        // For each file, fetch content and decode [CollectiveMemoryEntry]
        // Aggregate stats
        // On any failure: return empty MemoryStats with isAvailable: false
    }

    struct GameDetail {
        let gameName: String
        let gameSlug: String
        let entries: [CollectiveMemoryEntry]
    }

    /// Returns per-game detail or nil — never throws.
    static func fetchGameDetail(slug: String) -> GameDetail? {
        // Fetch single file via GitHub Contents API raw accept
        // Same pattern as CollectiveMemoryService.fetchBestEntry
    }
}
```

### Pattern 3: GitHub Contents API — Directory Listing
**What:** `GET /repos/{owner}/{repo}/contents/entries` returns an array of file objects (name, sha, download_url, etc.). The response uses the standard JSON Accept, not `.raw`.
**When to use:** Needed to enumerate all games for the aggregate stats view.
**Example:**
```swift
// Source: GitHub REST API docs (verified pattern)
// GET https://api.github.com/repos/{owner}/{repo}/contents/entries
// Accept: application/vnd.github+json
// Returns: [{"name": "cossacks-european-wars.json", "sha": "...", "type": "file", ...}, ...]

struct GitHubDirectoryEntry: Codable {
    let name: String   // filename: "cossacks-european-wars.json"
    let type: String   // "file" or "dir"
    let sha: String
}
```

Decode as `[GitHubDirectoryEntry]`. Filter to `type == "file"` and `.hasSuffix(".json")`. Extract slug from filename by dropping `.json` extension.

### Pattern 4: Leaf Templates — base.leaf Extension Pattern
**What:** All templates extend `base.leaf` using `#extend("base"):` / `#export("content"):`.
**When to use:** All templates in this project follow this pattern.
**Example:**
```leaf
{{!-- Source: Sources/cellar/Resources/Views/index.leaf (existing) --}}
#extend("base"):
  #export("content"):
    <section>
      <h2>Community Memory</h2>
      #if(stats.isAvailable):
        ...stats content...
      #else:
        <article>
          <p>Community memory is not available. Check your GitHub App credentials in Settings.</p>
        </article>
      #endif
    </section>
  #endexport
#endextend
```

### Pattern 5: Leaf Content Types — Must Conform to `Content`
**What:** All context structs passed to `req.view.render()` must conform to `Content` (Vapor protocol, implies `Codable`).
**When to use:** Every view model struct.
**Example:**
```swift
// Source: Sources/cellar/Web/Controllers/GameController.swift (existing)
struct MemoryContext: Content {
    let title: String
    let stats: MemoryStats
}
```

`MemoryStats`, `RecentContribution`, and `GameDetail` must all conform to `Content`.

### Pattern 6: Nav Link in base.leaf
**What:** Add "Memory" link to the nav bar alongside "Games" and "Settings".
**When to use:** Any new top-level section.
**Example:**
```html
<!-- Source: Sources/cellar/Resources/Views/base.leaf (existing nav) -->
<ul>
    <li><a href="/">Games</a></li>
    <li><a href="/memory">Memory</a></li>
    <li><a href="/settings">Settings</a></li>
</ul>
```

### Anti-Patterns to Avoid
- **Throwing from route handler on GitHub failure:** The success criterion requires empty state, not 500 error. Always return a valid `MemoryStats` with `isAvailable: false` rather than throwing.
- **Storing MemoryStatsService state as instance properties:** All existing services are stateless structs. Keep this pattern.
- **Fetching all game entries in a loop without a file-count guard:** If the memory repo grows large (hundreds of games), fetching every file sequentially on page load will be slow. For v1.2, the repo will have very few entries so this is acceptable. Add a comment noting this is not optimised for large repos.
- **Leaf templates with nested complex types:** Leaf has limited support for deeply nested optional chains. Flatten view model structs — prefer `[RecentContribution]` over `[CollectiveMemoryEntry]` filtered inline in the template.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Authenticated GitHub API requests | Custom auth layer | `GitHubAuthService.shared.getToken()` | Already built and tested with token caching and refresh |
| Synchronous HTTP with timeout | Custom URLSession wrapper | The `performFetch` pattern from CollectiveMemoryService | Proven pattern; DispatchSemaphore + timeoutInterval = 5 already handles network timeout |
| Game slug generation | Custom slug function | `slugify()` from CollectiveMemoryEntry.swift | Already handles unicode, locale-independence, consistent output |
| JSON decoding of entries | Custom decoder | `JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)` | The model is already defined with correct CodingKeys |
| HTML templating | Manual string concatenation | Leaf templates extending `base.leaf` | Leaf handles escaping, theme, nav bar, responsive layout |

**Key insight:** The data layer (auth, HTTP, JSON models) is complete. Phase 17 is purely a presentation layer on top of existing infrastructure.

## Common Pitfalls

### Pitfall 1: GitHub Contents API Returns 404 for Empty Directory
**What goes wrong:** If `entries/` directory doesn't exist yet in the memory repo (no games contributed), the GitHub Contents API returns 404, not an empty array `[]`.
**Why it happens:** GitHub only creates directories implicitly when a file is added. An absent directory is a 404.
**How to avoid:** In `fetchStats()`, treat 404 as "no entries yet" — return `MemoryStats` with counts of 0 and `isAvailable: true` (repo is reachable, just empty). Only set `isAvailable: false` on auth failure or network error.
**Warning signs:** Test with a fresh memory repo — the stats page should show "0 games covered" not an error.

### Pitfall 2: GitHub Directory Listing Pagination
**What goes wrong:** GitHub Contents API caps directory listing at 1000 files. For large repos, subsequent files are omitted. The response doesn't include a Link header like the Search or List APIs.
**Why it happens:** GitHub Contents API is not designed for bulk enumeration.
**How to avoid:** For v1.2, this is not a concern (community repo will have far fewer than 1000 entries). Add a comment in the service noting the 1000-file ceiling. If/when needed, switch to the Git Trees API (`GET /git/trees/{tree_sha}?recursive=1`) for unlimited listing.
**Warning signs:** If game count appears lower than expected, check if repo exceeds 1000 entries.

### Pitfall 3: Leaf Does Not Support Optional Chaining or Computed Properties
**What goes wrong:** Trying to render `#(entry.environment.wineVersion)` in a loop works only if Leaf can traverse the nested struct. Leaf uses Codable reflection — nested `Content`-conforming structs do work, but computed properties (like `canonicalString` and `computeHash()` on `EnvironmentFingerprint`) are not serialized.
**Why it happens:** Leaf serialises via `Codable` — only stored properties with `CodingKeys` are visible.
**How to avoid:** Create flat view model structs for the template. Do not pass `CollectiveMemoryEntry` directly to a Leaf loop — create a `MemoryEntryViewData: Content` struct with all fields flattened to `String`.
**Warning signs:** Template rendering crashes or silently outputs empty string for computed property access.

### Pitfall 4: Auth Unavailable Does Not Mean Repo Unreachable
**What goes wrong:** Conflating "GitHub App credentials not configured" with "the memory repo is down" produces a misleading error message.
**Why it happens:** `GitHubAuthService.shared.getToken()` returns `.unavailable` both when credentials are missing and when the token exchange fails.
**How to avoid:** When `isAvailable: false`, show a message that guides the user to Settings: "Community memory requires GitHub App credentials. Configure them in Settings." This is more actionable than "memory repo unreachable."
**Warning signs:** Users reporting confusion about what to do when the memory page shows an empty state.

### Pitfall 5: Content Struct Requires All Nested Types to Be Codable
**What goes wrong:** Passing a struct that contains a non-`Codable` type to `req.view.render()` causes a compile error (Content requires Codable).
**Why it happens:** Vapor's `Content` = `Codable + ResponseEncodable + RequestDecodable`.
**How to avoid:** Ensure `MemoryStats`, `RecentContribution`, and any other view model types all have stored properties of only `Codable` types (String, Int, Bool, Array, and other Codable structs).
**Warning signs:** Compiler error on the `MemoryContext: Content` definition.

## Code Examples

Verified patterns from official sources:

### GitHub Directory Listing — Request Pattern
```swift
// Source: mirrors CollectiveMemoryService.performFetch (project codebase)
let urlString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries"
var request = URLRequest(url: URL(string: urlString)!)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
request.timeoutInterval = 5
```

### Decoding Directory Listing
```swift
// GitHub directory entry — minimal fields needed
struct GitHubDirectoryEntry: Codable {
    let name: String   // "cossacks-european-wars.json"
    let type: String   // "file" | "dir"
}

// Decode and filter
let entries = try JSONDecoder().decode([GitHubDirectoryEntry].self, from: data)
let gameFiles = entries.filter { $0.type == "file" && $0.name.hasSuffix(".json") }
let slugs = gameFiles.map { String($0.name.dropLast(5)) }  // drop ".json"
```

### Fetching Per-Game Entries (raw accept — already proven)
```swift
// Source: CollectiveMemoryService.fetchBestEntry (project codebase)
let urlString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries/\(slug).json"
var request = URLRequest(url: URL(string: urlString)!)
request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")  // returns raw file content
request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
request.timeoutInterval = 5
// Decode: [CollectiveMemoryEntry]
```

### Flat View Model for Leaf
```swift
// Flatten CollectiveMemoryEntry for safe Leaf rendering
struct MemoryEntryViewData: Content {
    let arch: String
    let wineVersion: String
    let macosVersion: String
    let wineFlavor: String
    let confirmations: Int
    let lastConfirmed: String
    let engine: String       // "" if nil
    let graphicsApi: String  // "" if nil
}
```

### Empty State Context
```swift
// isAvailable: false triggers the "not configured" message in the template
struct MemoryStats: Content {
    let gameCount: Int
    let totalConfirmations: Int
    let recentContributions: [RecentContribution]
    let isAvailable: Bool
}

// Degraded state — never throws, returned on any failure
static let unavailable = MemoryStats(
    gameCount: 0,
    totalConfirmations: 0,
    recentContributions: [],
    isAvailable: false
)
```

### WebApp.swift Registration
```swift
// Source: Sources/cellar/Web/WebApp.swift (existing pattern)
try MemoryController.register(app)
```

### "Recent Contributions" Computation
```swift
// Sort all entries across all games by lastConfirmed descending
// Take top N (e.g. 10) for the recent contributions list
// lastConfirmed is ISO 8601 string — lexicographic sort works correctly
let allEntries: [(slug: String, entry: CollectiveMemoryEntry)] = ...
let recent = allEntries
    .sorted { $0.entry.lastConfirmed > $1.entry.lastConfirmed }
    .prefix(10)
    .map { RecentContribution(
        gameName: $0.entry.gameName,
        gameSlug: $0.slug,
        lastConfirmed: $0.entry.lastConfirmed,
        confirmations: $0.entry.confirmations
    )}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No memory UI | `/memory` aggregate + `/memory/:slug` detail | Phase 17 | Users can see community contribution health |
| Memory only used by agent loop | Memory surfaced in web UI | Phase 17 | Transparency into what the community has solved |

## Open Questions

1. **Should `/memory/:gameSlug` be linkable from the game library?**
   - What we know: The game library (index.leaf / game-card.leaf) shows game cards. Each game has an `id` field. The memory slug is derived from game name via `slugify()`, not from the game's `id`.
   - What's unclear: Whether to add a "View Memory" link on each game card. Not specified in requirements but would improve discoverability.
   - Recommendation: Planner should decide. The simplest approach is to link from the memory stats page (click a game row) rather than modifying game cards. This keeps Phase 17 self-contained.

2. **How many entries to show under "recent contributions"?**
   - What we know: WEBM-01 says "recent contributions" — no count specified.
   - What's unclear: Top 5? Top 10?
   - Recommendation: Top 10 is a reasonable default. Implement as a constant in MemoryStatsService.

3. **Should the `/memory/:gameSlug` route handle unknown slugs gracefully?**
   - What we know: Success criterion 3 requires no 500 errors when the repo is unreachable. An unknown slug would get a 404 from GitHub.
   - What's unclear: Return a 404 HTTP response or render an empty detail page?
   - Recommendation: Render an empty detail page with "No entries found for this game" rather than a Vapor 404 abort — consistent with the graceful-degradation theme.

## Sources

### Primary (HIGH confidence)
- Project codebase — `CollectiveMemoryService.swift`: synchronous fetch pattern, auth check, error swallowing
- Project codebase — `CollectiveMemoryWriteService.swift`: GET+parse directory/file pattern, `GitHubContentsResponse` struct
- Project codebase — `CollectiveMemoryEntry.swift`: full data model with all fields
- Project codebase — `GitHubAuthService.swift`: `getToken()` pattern and `GitHubAuthResult` enum
- Project codebase — `GameController.swift`: controller registration, view model pattern, `Content` conformance
- Project codebase — `base.leaf`, `index.leaf`, `settings.leaf`: Leaf template patterns

### Secondary (MEDIUM confidence)
- GitHub REST API docs (verified pattern): `GET /repos/{owner}/{repo}/contents/{path}` returns `[{name, type, sha, ...}]` for directories; `Accept: application/vnd.github.v3.raw` returns raw file content for files
- GitHub REST API docs: 1000-file ceiling on Contents API directory listings; Git Trees API as alternative for large repos

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; existing Vapor/Leaf/URLSession/GitHubAuthService
- Architecture: HIGH — directly mirrors existing CollectiveMemoryService and GameController patterns
- Pitfalls: HIGH — Leaf Codable constraints and GitHub 404-for-empty-dir are well-understood from existing code
- GitHub API behavior: MEDIUM — directory listing pagination ceiling documented but not tested at scale

**Research date:** 2026-03-30
**Valid until:** 2026-04-30 (stable — no new dependencies, no fast-moving ecosystem components)
