# Phase 19: Import Lutris and ProtonDB Compatibility Databases - Research

**Researched:** 2026-03-31
**Domain:** External API integration, compatibility data extraction, agent context injection
**Confidence:** MEDIUM (API behavior verified from live endpoints; some Lutris installer field details inferred from documentation)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Data Source Strategy**
- Query Lutris and ProtonDB APIs on demand (no bulk import, no bundled snapshots)
- Single unified lookup fans out to both APIs in parallel, merges results into one compatibility report
- Name-based fuzzy search for game matching (Lutris and ProtonDB use different IDs than Cellar slugs)
- Both sources attempted — accept risk that ProtonDB's unofficial API may break; Lutris is the reliable source

**Data Extraction**
- Extract everything actionable from Lutris install scripts: env vars, DLL overrides, registry edits, winetricks verbs, Wine version notes
- From ProtonDB: extract tier rating (Platinum/Gold/Silver/Bronze/Borked) as confidence signal + actionable config tweaks from user notes
- Filter Proton-specific flags before showing to agent: strip PROTON_* env vars, Steam runtime references, and other Linux/Proton-only config. Only pass portable config hints (env vars, DLL overrides, registry, winetricks)

**Agent Integration**
- Both pre-diagnosis injection AND a new agent tool:
  - Auto-inject full compatibility extraction into initial agent context before any tool calls (like collective memory read path in Phase 15)
  - Add a `query_compatibility` tool the agent can call for deeper/updated lookups during diagnosis
- Full extraction injected (~500-1000 tokens) — agent rarely needs to call the tool
- Add explicit system prompt guidance telling the agent about Lutris/ProtonDB data and how to use it for initial config choices

**Freshness & Storage**
- 30-day cache TTL (Lutris scripts and ProtonDB ratings change infrequently)
- Cache inside existing `~/.cellar/research-cache/` with `lutris/` and `protondb/` subdirectories
- When APIs are unreachable (no internet, rate limited, API changed): log warning to console/agent log, proceed without compatibility data — do not interrupt the agent loop

### Claude's Discretion
- Exact Lutris API endpoints and query parameters
- ProtonDB endpoint strategy (Steam AppID-based or alternative)
- Fuzzy matching algorithm for game name search
- Exact format of the injected compatibility context block
- How to structure the unified CompatibilityReport model
- Whether to add a web UI view for compatibility data (nice-to-have, not required)

### Deferred Ideas (OUT OF SCOPE)
- Web UI view for browsing Lutris/ProtonDB compatibility data per game — could be added to the game detail page in a future phase
- Using ProtonDB data to auto-suggest Wine configs for games Cellar has never seen — requires confidence scoring beyond this phase's scope
</user_constraints>

---

## Summary

Phase 19 adds compatibility data from two community sources — Lutris (Linux gaming platform with curated install scripts) and ProtonDB (Proton/Steam Deck compatibility reports) — into the agent's context. The implementation follows the same pre-diagnosis injection pattern established in Phase 15 (collective memory), adding a parallel fetch path that assembles a `CompatibilityReport` struct and injects it into the initial agent message.

The Lutris API is publicly documented at `https://lutris.net/api/games` (search by name, returns slugs) and `https://lutris.net/api/installers?game={slug}` (returns installer scripts with Wine config fields). The ProtonDB source is an unofficial endpoint `https://www.protondb.com/api/v1/reports/summaries/{appId}.json` — it returns only a tier summary, not per-report notes. The key challenge is that ProtonDB uses Steam AppIDs while Cellar games may be GOG or CD installs with no Steam AppID. A name-based lookup against Lutris (which has a search parameter) is reliable; ProtonDB either requires the Steam AppID or must be skipped.

The recommended approach for fuzzy matching is a simple normalized-name comparison (lowercase, strip punctuation, split tokens) without adding any SPM dependency. This mirrors the pattern already used in `SuccessDatabase.swift`. The entire feature should be a single new file `CompatibilityService.swift` in `Sources/cellar/Core/`, plus two new subdirectory path entries in `CellarPaths`, a tool definition added to `AgentTools.toolDefinitions`, and injection logic in `AIService.runAgentLoop()` parallel to the existing `CollectiveMemoryService.fetchBestEntry` call.

**Primary recommendation:** Use `https://lutris.net/api/games?search={name}` for game lookup + `https://lutris.net/api/installers?game={slug}` for scripts. Use `https://www.protondb.com/api/v1/reports/summaries/{appId}.json` only when a Steam AppID can be found from the Lutris game object's `provider_games` array (which includes Steam entries). Build both lookups as a parallel URLSession fetch using the existing `DispatchSemaphore` + `ResultBox` pattern. No new SPM dependencies needed.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| URLSession (Foundation) | system | HTTP fetches to Lutris + ProtonDB APIs | Already used throughout; same `DispatchSemaphore` + `ResultBox` pattern as CollectiveMemoryService |
| SwiftSoup | existing dep | HTML parsing if scraping needed as fallback | Already a project dependency |
| Foundation JSONDecoder | system | Decode API JSON responses | No additional dep needed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| NSRegularExpression (Foundation) | system | Extract Wine fixes from ProtonDB user note text | Already used in `extractWineFixes()` in PageParser.swift |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled fuzzy match | Fuzzywuzzy_swift SPM package | Package adds build dependency; simple token-based match is sufficient for game names |
| ProtonDB community API (protondb.max-p.me) | Official protondb.com /api/v1 endpoint | Community API has better title search; official is more stable. Use official for tier, community for name search only if needed |

**Installation:** No new packages needed. All dependencies are in-tree.

---

## Architecture Patterns

### Recommended Project Structure

```
Sources/cellar/Core/
├── CompatibilityService.swift      # NEW: unified Lutris + ProtonDB fetch, cache, format
├── CollectiveMemoryService.swift   # EXISTING: reference for injection pattern
└── AgentTools.swift                # MODIFY: add query_compatibility tool definition + handler

Sources/cellar/Core/AIService.swift # MODIFY: call CompatibilityService.fetchReport() in runAgentLoop()
Sources/cellar/Persistence/CellarPaths.swift  # MODIFY: add lutrisCompatCacheDir, protondbCompatCacheDir

Cache layout:
~/.cellar/research-cache/lutris/{slug}.json         # 30-day TTL
~/.cellar/research-cache/protondb/{appId}.json      # 30-day TTL
```

### Pattern 1: Parallel Fan-out with ResultBox (mirrors existing patterns)

**What:** Fire both Lutris and ProtonDB fetches concurrently using two DispatchSemaphores. Merge results into a single `CompatibilityReport`. Return nil on total failure.

**When to use:** Any time both sources should be queried without one blocking the other.

```swift
// Source: existing AgentLoopProvider.swift / CollectiveMemoryService.swift pattern
final class ResultBox<T>: @unchecked Sendable {
    var value: T?
}

let lutrisBox = ResultBox<LutrisCompatData>()
let protonBox = ResultBox<ProtonDBSummary>()
let sem1 = DispatchSemaphore(value: 0)
let sem2 = DispatchSemaphore(value: 0)

URLSession.shared.dataTask(with: lutrisRequest) { data, _, _ in
    lutrisBox.value = data.flatMap { try? JSONDecoder().decode(LutrisCompatData.self, from: $0) }
    sem1.signal()
}.resume()

URLSession.shared.dataTask(with: protonRequest) { data, _, _ in
    protonBox.value = data.flatMap { try? JSONDecoder().decode(ProtonDBSummary.self, from: $0) }
    sem2.signal()
}.resume()

sem1.wait()
sem2.wait()
```

### Pattern 2: Cache-Check-Then-Fetch

**What:** Before any HTTP call, check if a valid cache file exists in `~/.cellar/research-cache/{source}/{id}.json` with a `fetchedAt` timestamp older than 30 days. Return cached result if fresh.

**When to use:** All CompatibilityService fetches — mirrors the existing `ResearchCache` struct in `AgentTools.swift`.

```swift
// Cache struct (mirrors ResearchCache in AgentTools.swift)
struct CompatibilityCache<T: Codable>: Codable {
    let fetchedAt: String   // ISO8601
    let data: T

    func isStale(ttlDays: Int = 30) -> Bool {
        guard let date = ISO8601DateFormatter().date(from: fetchedAt) else { return true }
        return Date().timeIntervalSince(date) > Double(ttlDays) * 86400
    }
}
```

### Pattern 3: Lutris Game Search + Installer Fetch (two-step)

**What:** First search by game name, pick the best slug match, then fetch installers for that slug.

**Endpoints:**
1. `GET https://lutris.net/api/games?search={urlEncodedName}` — returns `{ count, results: [{ id, name, slug, provider_games: [{ name, slug, service }] }] }`
2. `GET https://lutris.net/api/installers?game={slug}` — returns `{ count, results: [{ script: { system: { env }, wine: { overrides }, installer: [tasks] } }] }`

**Name matching:** Take the Lutris search results array, lowercase+normalize both the query and each result name, pick the highest-similarity result. A simple token overlap score (intersection / union) is sufficient and requires no SPM dependency.

```swift
func normalizeGameName(_ name: String) -> Set<String> {
    name.lowercased()
        .components(separatedBy: .punctuationCharacters).joined(separator: " ")
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .filter { !["the", "a", "an", "of", "and"].contains($0) }
        |> Set.init
}

func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
    guard !a.isEmpty || !b.isEmpty else { return 0 }
    return Double(a.intersection(b).count) / Double(a.union(b).count)
}
```

### Pattern 4: ProtonDB AppID Discovery via Lutris

**What:** ProtonDB requires a Steam AppID. The Lutris game object's `provider_games` array contains entries like `{ name: "Deus Ex GOTY", slug: "6910", service: "steam" }`. Extract the Steam AppID from this field.

**When Steam AppID is found:** query `https://www.protondb.com/api/v1/reports/summaries/{appId}.json`
**When not found (GOG/CD games):** skip ProtonDB entirely, log "No Steam AppID found for {name}, skipping ProtonDB lookup"

```swift
// Extract Steam AppID from Lutris provider_games array
let steamEntry = game.providerGames.first { $0.service == "steam" }
let steamAppId = steamEntry?.slug  // Lutris uses the AppID as the slug for Steam entries
```

### Pattern 5: Lutris Script Extraction

**What:** Parse the `script` object from each Lutris installer result and extract Wine-actionable config. Reuse the existing `ExtractedFixes` and `extractWineFixes()` machinery from `PageParser.swift`.

**Lutris script fields to extract:**
- `script.system.env` → dict of env vars (e.g., `"DXVK_HUD": "gpuload"`)
- `script.wine.overrides` → dict of DLL name → mode (e.g., `"l3codecx.acm": "n"`)
- `script.installer` array → tasks:
  - `{ name: "winetricks", app: "vcrun2010 dotnet48" }` → winetricks verbs
  - `{ name: "set_regedit", path: "HKCU\\...", key: "...", type: "REG_DWORD", value: "1" }` → registry edits
  - Notes/comments on `arch`, Wine version

**Filter Proton-specific flags** from extracted env vars before returning:
```swift
let protonOnlyPrefixes = ["PROTON_", "STEAM_", "SteamAppId", "SteamGameId", "LD_PRELOAD"]
let filteredEnv = envVars.filter { kv in
    !protonOnlyPrefixes.contains { kv.key.hasPrefix($0) }
}
```

### Pattern 6: Injection into Agent Initial Message (mirrors Phase 15)

**What:** In `AIService.runAgentLoop()`, call `CompatibilityService.fetchReport(gameName:)` after the existing `CollectiveMemoryService.fetchBestEntry()` call. Append the formatted context block to `contextParts` array before joining into `initialMessage`.

```swift
// After line ~820 in AIService.swift:
let compatContext = CompatibilityService.fetchReport(for: entry.name)

var contextParts: [String] = []
if let memoryContext = memoryContext { contextParts.append(memoryContext) }
if let compatContext = compatContext { contextParts.append(compatContext) }
if let previousSession = previousSession { contextParts.append(previousSession.formatForAgent()) }
contextParts.append(launchInstruction)
let initialMessage = contextParts.joined(separator: "\n\n")
```

### Anti-Patterns to Avoid

- **Blocking the main thread on both fetches sequentially:** Fire both fetches concurrently using two semaphores, wait for both, then merge.
- **Crashing on API failure:** All network calls must swallow errors and return nil — the agent loop must never be interrupted by a failed compatibility lookup.
- **Passing Proton-specific flags to the agent:** Strip `PROTON_*`, `STEAM_*`, `LD_PRELOAD` env vars before injection — the agent on macOS/Wine cannot use them and may be confused.
- **Hard-coding the game slug:** Always search by name — Cellar slugs (e.g., `deus-ex-goty`) may not match Lutris slugs (e.g., `deus-ex`).
- **Caching under the game's Cellar slug:** Cache under the Lutris slug (for Lutris) and Steam AppID (for ProtonDB) to allow reuse across similarly-named games.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Async HTTP bridging | Custom async wrapper | DispatchSemaphore + ResultBox (existing pattern) | Consistent with the entire codebase; avoid Concurrency complexity |
| HTML parsing for fallback | Custom HTML parser | SwiftSoup (already imported) | Already used in PageParser.swift |
| Wine fix extraction from text | New regex extraction | `extractWineFixes(from:context:)` in PageParser.swift | Already handles env vars, DLL overrides, registry, winetricks |
| Fuzzy name matching | External SPM package | Inline token-overlap Jaccard similarity | No dependency needed; game names are short, token match is sufficient |
| JSON caching | New cache layer | Mirror `ResearchCache` struct in AgentTools.swift | Pattern already proven; add `ttlDays` parameter |

**Key insight:** Almost everything needed already exists in the codebase. The new service is primarily glue: HTTP fetches, JSON decode, filter, format, inject.

---

## Common Pitfalls

### Pitfall 1: ProtonDB Has No Name Search
**What goes wrong:** ProtonDB's `api/v1/reports/summaries/{appId}.json` requires a numeric Steam AppID. There is no name-based search endpoint on the official protondb.com API.
**Why it happens:** ProtonDB is a Proton/Steam-centric tool — every game is identified by Steam AppID.
**How to avoid:** Get the Steam AppID from the Lutris game object's `provider_games` array (the entry with `service == "steam"`). If the game has no Steam entry in Lutris (e.g., GOG-only or CD game), skip ProtonDB and log a debug message.
**Warning signs:** Returning 404 from ProtonDB for a valid game name — the AppID is wrong or missing.

### Pitfall 2: Lutris Search Returns Multiple Results — Pick the Right One
**What goes wrong:** Searching `?search=deus+ex` returns 32 results including Deus Ex, Deus Ex Human Revolution, Deus Ex Mankind Divided, etc. Picking the wrong slug fetches irrelevant installer scripts.
**Why it happens:** The Lutris search is a broad substring match.
**How to avoid:** Score all results with token-overlap similarity against the query name. Require a minimum similarity threshold (>0.5) before accepting a match. If no result meets the threshold, skip Lutris lookup gracefully.
**Warning signs:** Installer scripts from a different game than expected (different game ID in `game_slug` field).

### Pitfall 3: ProtonDB Notes Are Linux/Proton-Specific — Filter Aggressively
**What goes wrong:** ProtonDB user notes contain instructions like "enable Proton Experimental", "set PROTON_USE_WINED3D=1", "add to Steam launch options: STEAM_COMPAT_DATA_PATH=...". If injected into Cellar's Wine agent on macOS, the agent may try to apply these and fail or break the config.
**Why it happens:** ProtonDB is explicitly a Linux + Proton tool. Notes assume Steam and the Proton runtime.
**How to avoid:** When parsing ProtonDB notes (if available), strip any note that mentions "Steam launch options", "Proton", "runtime", "Linux". Run the resulting text through `extractWineFixes()` to pull out portable fixes only. The `tier` rating (Platinum/Gold/etc.) is always portable — use it regardless.
**Warning signs:** Agent applying `PROTON_*` env vars or trying to install Steam runtime components.

### Pitfall 4: Lutris API Rate Limiting / Downtime
**What goes wrong:** Lutris.net returns 503 or 429 during high-traffic periods. ProtonDB (unofficial) may go offline without notice.
**Why it happens:** Both are community-maintained services with no SLA.
**How to avoid:** Set a short timeout (5 seconds) on both requests. Wrap in try-catch. Return nil and log a warning — never throw. The 30-day cache means most requests hit the cache rather than the live API.
**Warning signs:** Agent loop delays. Check if timeout is causing the hang.

### Pitfall 5: Cache Directory Not Created Before Write
**What goes wrong:** `try? data.write(to: cacheFile)` silently fails if `~/.cellar/research-cache/lutris/` doesn't exist yet.
**Why it happens:** `FileManager.default.createDirectory` must be called with `withIntermediateDirectories: true` before writing.
**How to avoid:** Call `createDirectory` in the same block as the write, as done in `AgentTools.swift:2166`.

### Pitfall 6: Lutris Installer Script Format Varies Across Games
**What goes wrong:** Some installers have `script.wine.overrides`, others don't. Some use the `system.env` key, others don't. The `installer` task array may be absent.
**Why it happens:** Lutris install scripts are community-written YAML/JSON with no enforced schema.
**How to avoid:** All field access on the parsed script must be optional — use `?` chaining and nil-coalescing. Never force-unwrap. Merge results from multiple installer slugs for the same game (e.g., GOG and CD-ROM versions).

---

## Code Examples

Verified patterns from official sources and live API inspection:

### Lutris Game Search Request
```swift
// Source: Live API inspection of https://lutris.net/api/games?search=deus+ex
var components = URLComponents(string: "https://lutris.net/api/games")!
components.queryItems = [URLQueryItem(name: "search", value: gameName)]
let url = components.url!
var request = URLRequest(url: url)
request.timeoutInterval = 5
request.setValue("application/json", forHTTPHeaderField: "Accept")
```

### Lutris Game Object Fields (confirmed from live API)
```swift
struct LutrisGame: Codable {
    let id: Int
    let name: String
    let slug: String
    let year: Int?
    let providerGames: [LutrisProviderGame]

    enum CodingKeys: String, CodingKey {
        case id, name, slug, year
        case providerGames = "provider_games"
    }
}

struct LutrisProviderGame: Codable {
    let name: String
    let slug: String   // for Steam: this is the numeric AppID as a string
    let service: String  // "steam", "gog", "humble", etc.
}
```

### Lutris Installer Fetch + Script Extraction
```swift
// Source: Live API inspection of https://lutris.net/api/installers?game=deus-ex-cd-rom
struct LutrisInstaller: Codable {
    let id: Int
    let gameSlug: String
    let name: String
    let runner: String      // "wine", "dosbox", etc.
    let script: LutrisScript?

    enum CodingKeys: String, CodingKey {
        case id, name, runner, script
        case gameSlug = "game_slug"
    }
}

struct LutrisScript: Codable {
    let system: LutrisSystem?
    let wine: LutrisWineConfig?
    let installer: [LutrisTask]?   // task array
    let game: LutrisGameConfig?
}

struct LutrisSystem: Codable {
    let env: [String: String]?
}

struct LutrisWineConfig: Codable {
    let overrides: [String: String]?  // dll_name -> mode ("n", "b", "n,b", "disabled")
}

struct LutrisTask: Codable {
    let name: String?         // "winetricks", "set_regedit", "wineexec", "execute"
    let app: String?          // for winetricks: space-separated verbs
    let path: String?         // for set_regedit: registry key path
    let key: String?          // for set_regedit: value name
    let type: String?         // for set_regedit: "REG_DWORD", "REG_SZ"
    let value: String?        // for set_regedit: value data
}
```

### ProtonDB Summary Request
```swift
// Source: Live API verification - returns HTTP 200 with JSON
// Confirmed response: { bestReportedTier, confidence, score, tier, total, trendingTier }
struct ProtonDBSummary: Codable {
    let tier: String              // "platinum", "gold", "silver", "bronze", "borked"
    let bestReportedTier: String
    let trendingTier: String
    let confidence: String        // "strong", "moderate", "low"
    let score: Double
    let total: Int
}

// Fetch URL: https://www.protondb.com/api/v1/reports/summaries/{steamAppId}.json
```

### Proton Flag Filter
```swift
// Strip Linux/Proton-specific env vars from extracted fixes
let protonOnlyPrefixes = ["PROTON_", "STEAM_", "SteamAppId", "SteamGameId", "LD_PRELOAD",
                           "WINEDLLPATH", "WINELOADERNOEXEC", "DXVK_FILTER_DEVICE_NAME"]
// Note: DXVK_HUD and MESA_* are safe to pass through — they work on macOS Wine too
func filterPortableEnvVars(_ vars: [ExtractedEnvVar]) -> [ExtractedEnvVar] {
    vars.filter { ev in
        !protonOnlyPrefixes.contains { ev.name.hasPrefix($0) }
    }
}
```

### CompatibilityReport Model
```swift
struct CompatibilityReport {
    let gameName: String
    let lutrisSlug: String?
    let steamAppId: String?

    // From Lutris
    let lutrisEnvVars: [ExtractedEnvVar]
    let lutrisDlls: [ExtractedDLL]
    let lutrisWinetricks: [ExtractedVerb]
    let lutrisRegistry: [ExtractedRegistry]
    let installerCount: Int       // how many Lutris installers were found

    // From ProtonDB
    let protonTier: String?       // "platinum", "gold", etc.
    let protonConfidence: String? // "strong", "moderate", "low"
    let protonTotal: Int?

    var isEmpty: Bool {
        lutrisEnvVars.isEmpty && lutrisDlls.isEmpty && lutrisWinetricks.isEmpty
        && lutrisRegistry.isEmpty && protonTier == nil
    }
}
```

### Formatted Context Block (agent injection)
```
--- COMPATIBILITY DATA ---
Community compatibility data for 'Deus Ex GOTY':

## ProtonDB Rating
Tier: Platinum (confidence: strong, 154 reports)
Trending: Platinum

## Lutris Configuration (from 3 installer scripts)
Environment variables:
  (none found)
DLL overrides:
  (none found)
Winetricks:
  vcrun2010, dotnet48
Registry edits:
  HKCU\Software\Wine\DllOverrides  l3codecx.acm = n

Note: ProtonDB reports are from Linux+Proton users. Config hints above are filtered for Wine/macOS compatibility.
--- END COMPATIBILITY DATA ---
```

### System Prompt Addition (agent guidance)
```
## Compatibility Data
When a COMPATIBILITY DATA block appears in the initial message, use it as follows:
- ProtonDB Platinum/Gold tier: high confidence this game runs well under Wine-compatible configs
- ProtonDB Bronze/Borked: expect significant effort; research thoroughly before launching
- Lutris winetricks/DLL hints: apply these during Phase 1 config before first launch_game call
- Lutris registry hints: apply alongside winetricks in Phase 1
- Ignore any Proton-specific instructions (PROTON_* vars, Steam runtime) — they don't apply on macOS/Wine
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| ProtonDB JSON dumps (bulk download) | API on-demand with `/api/v1/reports/summaries/{appId}.json` | ProtonDB always online-only; no official API changes | No bulk download needed; on-demand per-game is the right model |
| Lutris CLI client syncs full game DB | REST API `?search=name` query | Lutris API always available; client is Linux-only | REST search is the correct integration path |

**Deprecated/outdated:**
- ProtonDB community API at `protondb.max-p.me`: Functional but unofficial relay; the direct `protondb.com/api/v1` endpoint is more stable. Use the direct endpoint.
- Lutris JSON scraping: The Lutris website moved away from bulk JSON exports; use the REST API instead.

---

## Open Questions

1. **Can Lutris installer scripts reliably yield Wine-portable hints?**
   - What we know: The `/api/installers?game={slug}` endpoint returns `script.wine.overrides` and `script.system.env` and task arrays. Many installers for old Windows games include winetricks verbs and DLL overrides.
   - What's unclear: How many Wine-runner installers actually have non-trivial env/DLL config vs. just `create_prefix` and `wineexec` tasks? The live API inspection of the Deus Ex CD-ROM installer showed minimal config in that particular script.
   - Recommendation: Fetch all installers for a game slug and merge across all results. Even if individual scripts are sparse, the union of all scripts for a game should yield something useful for older titles.

2. **ProtonDB notes vs. tier: is the tier alone sufficient?**
   - What we know: The `/api/v1/reports/summaries/{appId}.json` returns only aggregated tier data (Platinum/Gold/etc.) — it does NOT return individual user notes or note text.
   - What's unclear: Whether per-report notes (available via the unofficial community API) are worth fetching given the filtering complexity.
   - Recommendation: For Phase 19, use tier + confidence only from ProtonDB. This is a confidence signal for the agent ("expect this to work" vs. "expect challenges"). Individual notes are Linux/Proton-specific and the filtering burden outweighs the value. This is consistent with the CONTEXT.md decision that ProtonDB is "the less reliable source."

3. **Cache directory path: `research/` vs. `research-cache/`**
   - What we know: `CellarPaths.researchCacheDir` is `~/.cellar/research/` (not `research-cache/`). The CONTEXT.md says "Cache inside existing `~/.cellar/research-cache/`" but the code uses `research/`.
   - Recommendation: Follow the code, not the CONTEXT.md description. Use `~/.cellar/research/lutris/` and `~/.cellar/research/protondb/`. Extend `CellarPaths` with two new computed properties for these subdirectories.

---

## Sources

### Primary (HIGH confidence)
- Live API fetch: `https://lutris.net/api/games?search=deus+ex` — confirmed response schema: count, results[], fields: id/name/slug/provider_games
- Live API fetch: `https://lutris.net/api/installers?game=deus-ex-cd-rom` — confirmed installer script structure with wine.overrides, system.env, installer task array
- Live API fetch: `https://www.protondb.com/api/v1/reports/summaries/6910.json` — confirmed response: bestReportedTier, confidence, score, tier, total, trendingTier
- `Sources/cellar/Core/CollectiveMemoryService.swift` — pre-diagnosis injection pattern reference
- `Sources/cellar/Core/PageParser.swift` — `extractWineFixes()` reuse target, `ExtractedFixes` model
- `Sources/cellar/Core/AIService.swift` — `runAgentLoop()` integration point (lines ~819-841)
- `Sources/cellar/Persistence/CellarPaths.swift` — cache path conventions

### Secondary (MEDIUM confidence)
- `https://github.com/lutris/website/wiki/API-Documentation` — official Lutris API wiki (partial, mostly endpoint listing)
- `https://protondb.max-p.me/` — ProtonDB community API endpoint documentation (confirmed it relays same protondb.com data)

### Tertiary (LOW confidence)
- WebSearch results on ProtonDB per-report notes format — not verified against live data; notes endpoint may not be publicly accessible on the official API

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies, all patterns already in codebase
- Architecture: HIGH — direct application of Phase 15 injection pattern + parallel fetch
- Lutris API fields: MEDIUM — confirmed from live fetch but installer script completeness varies per game
- ProtonDB API: HIGH for tier endpoint; LOW for note text (no accessible endpoint confirmed)
- Fuzzy matching: HIGH — simple token overlap, no external library needed
- Pitfalls: MEDIUM — based on API behavior observation and codebase analysis

**Research date:** 2026-03-31
**Valid until:** 2026-04-30 (Lutris API stable; ProtonDB unofficial endpoint could change at any time)
