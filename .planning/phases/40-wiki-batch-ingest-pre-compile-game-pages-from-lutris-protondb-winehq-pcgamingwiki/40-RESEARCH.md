# Phase 40: Wiki Batch Ingest — Research

**Researched:** 2026-04-06
**Domain:** Swift CLI subcommand, async pipeline, existing fetch/parse/write reuse
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- New subcommand group: `cellar wiki`
- `cellar wiki ingest "Game Name"` — ingest a single game
- `cellar wiki ingest --popular` — batch ingest top games from Lutris catalog
- `cellar wiki ingest --all-local` — ingest all games in local success database
- Output: creates/updates `wiki/games/{game-slug}.md` in cellar-memory repo
- Data sources: Lutris API via `CompatibilityService`, ProtonDB via `CompatibilityService`, WineHQ AppDB via `PageParser.WineHQParser`, PCGamingWiki via `PageParser.PCGamingWikiParser`
- Page format: one page per game at `wiki/games/{game-slug}.md`, sections for Compatibility (ProtonDB), Known Working Config (Lutris), Fixes (WineHQ/PCGW), Engine cross-ref, `Last updated:` footer
- Write path: existing Worker `POST /api/wiki/append` via `WikiService.postWikiAppend`
- Reuse: `CompatibilityService.fetchReport(for:)`, `PageParser` parsers, `WikiService.postWikiAppend`, `CellarPaths.slugify`

### Claude's Discretion

- How to discover WineHQ/PCGamingWiki URLs for a game (search_web or URL pattern)
- Rate limiting strategy for batch ingest (delay between games)
- How to handle games with no data from any source (skip? create minimal page?)
- Whether to merge new data with existing page or overwrite
- Error handling for individual source failures (partial page vs skip)

### Deferred Ideas (OUT OF SCOPE)

- Scheduled cron ingest via RemoteTrigger (can add after CLI works)
- Post-session automatic ingest (integrate into AIService flow)
- Incremental updates (only fetch sources newer than last ingest)
- Wiki page versioning / diff tracking
- Web UI for browsing ingested game pages
</user_constraints>

---

## Summary

All fetch and parse machinery already exists and is ready to reuse. `CompatibilityService.fetchReport(for:)` is a standalone `static async` function — no instance needed, takes a game name string. `PageParser` parsers (`WineHQParser`, `PCGamingWikiParser`) take a SwiftSoup `Document` + `URL` and return `ParsedPage` with `extractedFixes`. `WikiService.postWikiAppend` is a `private static async` helper — it needs to be promoted to `internal` (or a new public wrapper added) so the new command can call it.

The Worker's `/api/wiki/append` endpoint already supports creating new files: `writeWikiPage` does a `GET` first, and on a 404 it starts from empty string — so new game pages are created automatically on first append. The path allowlist `WIKI_PAGE_PATTERN` already includes `games/` subdirectory. This means the write path works without any Worker changes.

The main new work is: (1) a `WikiCommand` subcommand group with an `IngestCommand`, (2) a `WikiIngestService` that orchestrates fetch → parse → format → POST for a single game, (3) URL discovery for WineHQ/PCGW (direct URL pattern construction is reliable for both), and (4) batch logic for `--popular` (Lutris game listing API) and `--all-local` (`SuccessDatabase.loadAll()`).

**Primary recommendation:** Wire existing services with a thin orchestration layer. No new dependencies. Promote `postWikiAppend` to `internal static` and add a `games/` page formatter.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ArgumentParser | existing SPM dep | CLI subcommand group | Already used by all commands |
| Foundation | system | URLSession, async/await | Already used |
| SwiftSoup | existing SPM dep | HTML parsing for WineHQ/PCGW | Already used by PageParser |

No new dependencies. Everything is already in the SPM manifest.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/
├── Commands/
│   └── WikiCommand.swift         # cellar wiki + IngestCommand subcommand
├── Core/
│   └── WikiIngestService.swift   # fetch → parse → format → POST pipeline
```

`WikiCommand.swift` owns the CLI interface. `WikiIngestService.swift` owns the orchestration. `WikiService.postWikiAppend` is promoted to `internal` (or a new `internal` wrapper is added).

### Pattern 1: Subcommand Group (ArgumentParser)

**What:** A parent `ParsableCommand` with `subcommands:` array, where the parent has `abstract` only and no `run()`. Child commands implement the behavior.

**When to use:** When grouping related commands under a namespace (e.g., `cellar wiki ingest`).

```swift
struct WikiCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wiki",
        abstract: "Wiki management commands",
        subcommands: [IngestCommand.self]
    )
}

struct IngestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Pre-compile game wiki pages from external sources"
    )

    @Argument(help: "Game name to ingest") var gameName: String?
    @Flag(help: "Ingest top games from Lutris catalog") var popular: Bool = false
    @Flag(help: "Ingest all games in local success database") var allLocal: Bool = false

    mutating func run() async throws { ... }
}
```

Then add `WikiCommand.self` to the `subcommands:` array in `Cellar.swift`.

### Pattern 2: WikiIngestService (fetch → format → POST)

**What:** Static struct with a single `ingest(gameName:)` async method that calls all four sources and POSTs a page.

**When to use:** All batch modes call this same method per game.

```swift
struct WikiIngestService {
    static func ingest(gameName: String) async -> IngestResult {
        // 1. Fetch CompatibilityReport (Lutris + ProtonDB)
        let report = await CompatibilityService.fetchReport(for: gameName)

        // 2. Discover + fetch WineHQ page
        let wineHQFixes = await fetchWineHQFixes(gameName: gameName)

        // 3. Discover + fetch PCGamingWiki page
        let pcgwFixes = await fetchPCGWFixes(gameName: gameName)

        // 4. Format page content
        let slug = CellarPaths.slugify(gameName)
        let page = formatGamePage(gameName: gameName, slug: slug,
                                   report: report, wineHQ: wineHQFixes, pcgw: pcgwFixes)

        // 5. POST to Worker (overwrite semantics)
        let pagePath = "games/\(slug).md"
        await WikiService.postWikiAppend(page: pagePath, entry: page, commitMessage: "wiki: ingest \(gameName)")

        // 6. Update index.md
        await WikiService.postWikiAppend(page: "index.md",
            entry: "- [games/\(slug).md](games/\(slug).md) — \(gameName)",
            commitMessage: "wiki: index \(gameName)")

        return .success
    }
}
```

### Pattern 3: URL Discovery for WineHQ and PCGamingWiki

**What:** Both sites have predictable URL patterns. Direct construction is faster and more reliable than DuckDuckGo search for these specific sites.

**WineHQ AppDB:** URL pattern requires a numeric appID, not a slug. The search endpoint is:
`https://appdb.winehq.org/objectManager.php?sClass=application&sTitle=<game_name_urlencoded>`

However, the appdb search returns HTML — a search hit gives an app page URL with a numeric ID like `https://appdb.winehq.org/objectManager.php?sClass=version&iId=12345`. Parsing the search result HTML to get the first app ID is the right approach.

**PCGamingWiki:** Direct URL pattern works reliably:
`https://www.pcgamingwiki.com/wiki/<Game_Name_With_Underscores>`

This is the standard MediaWiki URL pattern and matches PCGW's actual page URLs for almost all games.

**Recommendation:** For PCGamingWiki, construct URL directly from game name (replace spaces with underscores, capitalize first letter). For WineHQ, try direct slug-based URL first (`https://appdb.winehq.org/objectManager.php?sClass=application&sTitle=<name>`) and parse the first result.

**Fallback:** If either fetch returns a 404 or yields no `extractedFixes`, treat as nil — the page is still created with whatever data is available from other sources.

### Pattern 4: Page Overwrite vs Append

**Issue:** `WikiService.postWikiAppend` appends to an existing file. For game pages, we want to overwrite (re-ingest should replace stale content, not accumulate duplicates).

**Worker behavior:** `writeWikiPage` on the server does substring dedup (`existing.includes(entry.trim())`), but for full-page replacement this isn't enough.

**Solution options:**
1. Send the full page content as `entry`, with the page path starting with a sentinel header line (e.g., `# Game: Diablo`). On re-ingest, the Worker will skip if content unchanged (dedup), but won't replace on changes.
2. Add an `overwrite: true` field to the Worker `WikiAppendPayload` that triggers a full replace instead of append. **This requires a Worker change.**
3. For the initial phase, treat each ingest as idempotent: always send the full page as the single entry, and rely on the fact that new game pages are created from scratch. On re-ingest, content will be duplicated unless the new content exactly matches.

**Recommendation:** For phase 40, make `postWikiAppend` support an `overwrite` flag that sends a new `WikiAppendPayload` field `overwrite: true`. The Worker checks this flag and replaces file content entirely instead of appending. This is a small Worker change but eliminates a fundamental design problem with batch re-ingest.

**Alternative (no Worker change):** Only ingest a game page once — check `wiki/games/<slug>.md` existence via the GitHub raw URL before posting. If it exists and is recent (check `Last updated:` line), skip. This avoids the overwrite problem without touching the Worker.

### Pattern 5: `--popular` Flag — Lutris Catalog

The Lutris API supports listing games sorted by popularity:
`GET https://lutris.net/api/games?ordering=-popularity&page_size=50`

This endpoint returns the same `LutrisSearchResponse` structure. Extract `results[].name` to get the top N game names, then call `ingest(gameName:)` for each.

The `fetchLutrisGame` function in `CompatibilityService` already normalizes and searches Lutris — for `--popular`, we bypass search and directly use the listed game names.

### Pattern 6: `--all-local` Flag

`SuccessDatabase.loadAll()` returns `[SuccessRecord]`. Each record has `gameName: String`. Iterate and call `ingest(gameName:)` for each.

```swift
let records = SuccessDatabase.loadAll()
for record in records {
    await WikiIngestService.ingest(gameName: record.gameName)
}
```

### Anti-Patterns to Avoid

- **Calling `search_web` for URL discovery:** The `searchWeb` function in `ResearchTools.swift` is an `AgentTools` extension method that requires a `gameId` context and uses a per-game cache. It is not standalone-callable from a CLI command. Use direct URL construction instead.
- **Re-implementing fetch logic:** `CompatibilityService.fetchReport` already handles Lutris + ProtonDB with caching. Do not re-fetch or duplicate this logic.
- **Parallel Worker posts for all games:** The Worker has a rate limit of 10 writes/hr/IP. Batch ingest must serialize posts with a small delay (1-2 seconds between games). Within a single game, sequential source fetches are fine; parallel fetching of sources per game is OK.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Lutris + ProtonDB fetch | Custom API client | `CompatibilityService.fetchReport(for:)` | Already caches, normalizes, fuzzy-matches |
| HTML parsing | Custom regex scraper | `WineHQParser`/`PCGamingWikiParser` + SwiftSoup | Already handles DOM structure, extracts fixes |
| Game name → slug | Custom slug function | `CellarPaths.slugify` (or `WikiService.slugify` private copy) | Consistent slugification across all paths |
| Worker POST | New URLSession code | `WikiService.postWikiAppend` (promoted to internal) | Handles auth, error logging, timeout |

**Note on slugify:** `WikiService` has a private `slugify` copy. `CellarPaths` does NOT have a public `slugify` — the method lives inside `WikiService` as `private static func slugify`. For `WikiIngestService`, either: (a) duplicate the 3-line function, or (b) promote `WikiService.slugify` to `internal static`. Option (b) is cleaner.

---

## Common Pitfalls

### Pitfall 1: Worker Rate Limit on Batch Ingest
**What goes wrong:** Batch ingest of 50+ games sends hundreds of POSTs rapidly — the in-memory rate limit (10/hr/IP) triggers 429 responses.
**Why it happens:** Each game page write = 1 POST for the game page + 1 for index.md + 1 for log.md = 3 POSTs/game. 50 games = 150 POSTs.
**How to avoid:** Either (a) skip index.md/log.md updates during batch and do one consolidated update at the end, or (b) add a rate limit exemption for batch operations (e.g., a shared secret header), or (c) add `Task.sleep(nanoseconds: 2_000_000_000)` between games and reduce per-game writes to 1 (only the game page itself). Rate limit is per Worker instance and resets on restart — in practice acceptable for self-hosted use.
**Warning signs:** 429 responses logged to stderr during batch run.

### Pitfall 2: PCGamingWiki URL Construction Fails for Games with Special Characters
**What goes wrong:** Game names with colons, apostrophes, or non-ASCII characters produce invalid PCGW URLs.
**Why it happens:** MediaWiki encodes page titles — "Baldur's Gate" → `Baldur%27s_Gate` but PCGW normalizes to `Baldur's_Gate`.
**How to avoid:** Use `addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)` after replacing spaces with underscores. Also handle 301/302 redirects (URLSession follows them by default).

### Pitfall 3: postWikiAppend is private
**What goes wrong:** `WikiService.postWikiAppend` is declared `private static` — it cannot be called from `WikiIngestService`.
**Why it happens:** It was only needed internally in `WikiService.ingest`.
**How to avoid:** Promote to `internal static` in the same WikiService refactor task. No API change — just remove `private`.

### Pitfall 4: Game Page Accumulates Duplicate Content on Re-ingest
**What goes wrong:** Running `cellar wiki ingest "Diablo"` twice produces a page with two copies of all sections.
**Why it happens:** `postWikiAppend` appends to existing file; Worker substring dedup only skips if exact same string is present — reformatted content with a new date won't match.
**How to avoid:** Add `overwrite: true` support to Worker + Swift payload, OR check for existing page before posting and skip if `Last updated:` is within TTL (e.g., 7 days).

### Pitfall 5: WineHQ AppDB Search Returns No Results
**What goes wrong:** Many older games are not indexed in WineHQ AppDB, or the search HTML structure has changed.
**Why it happens:** WineHQ coverage is incomplete; DOM structure may differ from what `WineHQParser` expects.
**How to avoid:** Treat WineHQ as optional — if fetch or parse yields empty `extractedFixes`, continue without WineHQ section. Don't fail the whole ingest.

### Pitfall 6: CellarPaths.slugify Does Not Exist
**What goes wrong:** `CellarPaths` has no `slugify` method — the planner might assume it does based on CONTEXT.md.
**Why it happens:** CONTEXT.md says "CellarPaths.slugify — game name to slug conversion" but inspection shows the slugify logic lives in `WikiService` as a private method, not in `CellarPaths`.
**How to avoid:** In the implementation plan, add a task to either: expose `WikiService.slugify` as `internal static`, or add `static func slugify(_ name: String) -> String` to `CellarPaths`. The 3-line implementation is identical in both places.

---

## Code Examples

### Promoting postWikiAppend to internal
```swift
// In WikiService.swift — change from:
private static func postWikiAppend(page: String, entry: String, commitMessage: String) async {
// To:
static func postWikiAppend(page: String, entry: String, commitMessage: String) async {
```

### WikiCommand structure
```swift
// Sources/cellar/Commands/WikiCommand.swift
import ArgumentParser

struct WikiCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wiki",
        abstract: "Wiki management commands",
        subcommands: [IngestCommand.self]
    )
}

struct IngestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ingest",
        abstract: "Pre-compile game wiki pages from external sources"
    )

    @Argument(help: "Game name to ingest (omit for --popular or --all-local)")
    var gameName: String?

    @Flag(name: .long, help: "Ingest top games from Lutris catalog")
    var popular: Bool = false

    @Flag(name: .long, help: "Ingest all games in local success database")
    var allLocal: Bool = false

    mutating func validate() throws {
        let modes = [gameName != nil, popular, allLocal].filter { $0 }.count
        if modes == 0 { throw ValidationError("Provide a game name, --popular, or --all-local") }
        if modes > 1 { throw ValidationError("Provide only one of: game name, --popular, --all-local") }
    }

    mutating func run() async throws {
        if let name = gameName {
            await WikiIngestService.ingest(gameName: name)
        } else if popular {
            let games = await WikiIngestService.fetchPopularGames(limit: 50)
            for game in games {
                await WikiIngestService.ingest(gameName: game)
                try? await Task.sleep(nanoseconds: 2_000_000_000) // rate limit buffer
            }
        } else if allLocal {
            let records = SuccessDatabase.loadAll()
            for record in records {
                await WikiIngestService.ingest(gameName: record.gameName)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}
```

### Fetching popular games from Lutris
```swift
// In WikiIngestService
static func fetchPopularGames(limit: Int = 50) async -> [String] {
    guard let url = URL(string: "https://lutris.net/api/games?ordering=-popularity&page_size=\(limit)") else { return [] }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = 10
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          let http = response as? HTTPURLResponse, http.statusCode == 200,
          let decoded = try? JSONDecoder().decode(LutrisSearchResponse.self, from: data) else {
        return []
    }
    return decoded.results.map { $0.name }
}
```

Note: `LutrisSearchResponse` is `private` in `CompatibilityService.swift` — it needs to be promoted to `internal` or duplicated, OR the popular games fetch can be added as a static method directly in `CompatibilityService`.

### PCGamingWiki URL construction
```swift
static func pcgwURL(for gameName: String) -> URL? {
    let titleCase = gameName
        .split(separator: " ")
        .map { String($0.prefix(1).uppercased() + $0.dropFirst()) }
        .joined(separator: "_")
    let encoded = titleCase.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? titleCase
    return URL(string: "https://www.pcgamingwiki.com/wiki/\(encoded)")
}
```

### Game page format
```markdown
# {Game Name}

**Last updated:** {ISO date} | Sources: Lutris, ProtonDB, WineHQ, PCGamingWiki

## Compatibility

**ProtonDB:** {tier} ({confidence}, {total} reports)

## Known Working Configuration (Lutris)

**Environment variables:**
{list or "(none)"}

**DLL overrides:**
{list or "(none)"}

**Winetricks:**
{list or "(none)"}

## Fixes (WineHQ / PCGamingWiki)

**Environment variables:**
{list or "(none)"}

**DLL overrides:**
{list or "(none)"}

**Winetricks:**
{list or "(none)"}

**INI changes:**
{list or "(none)"}
```

---

## Key API Findings

### Worker `/api/wiki/append` — Confirmed Behaviors

From `worker/src/index.ts`:

1. **Creates new files:** On 404, starts from empty string and creates the file via GitHub Contents API PUT. No separate "create" endpoint needed.
2. **Path allowlist:** `WIKI_PAGE_PATTERN = /^(engines|symptoms|environments|games)\/[a-z0-9-]+\.md$|^log\.md$|^index\.md$/` — `games/` subdirectory is already allowed.
3. **Server-side dedup:** Skips if `existing.includes(entry.trim())` — exact substring match. Re-ingests with updated dates will NOT be deduped, causing accumulation.
4. **Rate limit:** 10 writes/hr/IP via shared `rateLimitMap`. Batch ingest needs to respect this.
5. **Payload shape:** `{ page: string, entry: string, commitMessage?: string }` — exactly what `WikiService.postWikiAppend` already sends.
6. **Overwrite not supported:** No `overwrite` flag exists. Adding one requires a Worker deployment.

### CompatibilityService — Public API

- `static func fetchReport(for gameName: String) async -> CompatibilityReport?` — fully public, standalone callable
- Returns `nil` if empty (no data found)
- `CompatibilityReport` has all fields needed: `protonTier`, `protonConfidence`, `protonTotal`, `lutrisEnvVars`, `lutrisDlls`, `lutrisWinetricks`, `lutrisRegistry`, `installerCount`
- `LutrisSearchResponse` is `private` — need to expose or duplicate for `--popular` games listing

### PageParser — API

- `WineHQParser().parseHTML(_ html: String, url: URL)` — convenience method via extension on `PageParser` protocol
- `PCGamingWikiParser().parseHTML(_ html: String, url: URL)` — same
- Returns `ParsedPage(textContent: String, extractedFixes: ExtractedFixes)`
- `ExtractedFixes` has: `envVars`, `registry`, `dlls`, `winetricks`, `iniChanges`

### WikiService — Access Control Changes Needed

- `postWikiAppend` is `private static` — must be promoted to `internal static`
- `slugify` is `private static` — promote to `internal static` OR add to `CellarPaths`

---

## Open Questions

1. **Worker overwrite support**
   - What we know: `/api/wiki/append` appends; re-ingest creates duplicate content
   - What's unclear: Is adding `overwrite: true` to the Worker in scope for phase 40, or defer?
   - Recommendation: Include a Worker change as one task in phase 40. It's 5 lines of code and prevents a fundamental re-ingest problem. Alternatively, implement a "skip if recently ingested" check on the Swift side.

2. **WineHQ URL discovery**
   - What we know: AppDB uses numeric IDs, no predictable slug URL
   - What's unclear: Whether a direct search-and-parse approach will be reliable at batch scale
   - Recommendation: For the initial phase, attempt a simple search URL and parse the first result's href. If it fails, skip WineHQ for that game — it's the least critical source (PCGamingWiki + Lutris provide more actionable fix data).

3. **LutrisSearchResponse private visibility**
   - What we know: `LutrisSearchResponse` is `private struct` in `CompatibilityService.swift`
   - Recommendation: Add `static func fetchPopularGames(limit:) async -> [String]` directly to `CompatibilityService` so the private type is not exposed.

---

## Sources

### Primary (HIGH confidence)
- Direct code inspection of `Sources/cellar/Core/CompatibilityService.swift` — public API, data structures
- Direct code inspection of `Sources/cellar/Core/PageParser.swift` — parser API, ExtractedFixes shape
- Direct code inspection of `Sources/cellar/Core/WikiService.swift` — postWikiAppend signature, access control
- Direct code inspection of `worker/src/index.ts` — Worker endpoint behavior, path allowlist, rate limiting
- Direct code inspection of `Sources/cellar/Persistence/CellarPaths.swift` — slugify absence confirmed
- Direct code inspection of `Sources/cellar/Core/SuccessDatabase.swift` — loadAll() API
- Direct code inspection of `Sources/cellar/Cellar.swift` — subcommand registration pattern

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in project, no new deps
- Architecture: HIGH — all service APIs verified by direct code inspection
- Worker behavior: HIGH — full Worker source read and analyzed
- Pitfalls: HIGH — derived from actual code inspection (private access, dedup logic, rate limits)

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (stable codebase, no external API version risk)
