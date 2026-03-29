# Phase 11: Smarter Research - Research

**Researched:** 2026-03-28
**Domain:** HTML parsing, structured data extraction, multi-signal database querying
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Fix extraction happens inside fetch_page — returns both `text_content` (existing, upgraded) and `extracted_fixes` (new)
- Only extract Wine-specific artifacts: env vars (WINEDEBUG, DXVK_*), registry paths (HKCU\Software\Wine), DLL names/modes (ddraw=native), winetricks verbs (vcrun2019), INI key=value pairs
- SwiftSoup CSS selectors first for known sources (WineHQ, PCGamingWiki), regex fallback on stripped text for unknown sources
- Upgrade text_content to use SwiftSoup too — extract meaningful text (paragraphs, headings, lists) instead of regex stripping
- Two dedicated SwiftSoup parsers: WineHQ AppDB and PCGamingWiki
- WineHQ AppDB: target test results table (Wine version, rating, distro) plus comment text from user reports
- PCGamingWiki: target fix tables and code blocks in fix sections
- Unknown/unrecognized sources: generic parser extracts `<pre>`, `<code>`, and `<table>` elements, then runs regex fix extraction
- Forums and other sources use the generic parser — no dedicated forum parser
- New `similar_games` composite query parameter added to query_successdb alongside existing query types
- Multi-signal overlap scoring: engine family match + graphics API match + tag overlap + symptom match
- Each matching signal increases the score; records ranked by total overlap count
- Return top 5 matches, consistent with existing query limits
- Existing separate query types preserved — no breaking changes
- `extracted_fixes` grouped by type: `env_vars`, `registry`, `dlls`, `winetricks`, `ini_changes` — each with context string
- Always return both `text_content` and `extracted_fixes`
- Update system prompt with research methodology: check extracted_fixes first, apply directly if confident, fall back to text_content

### Claude's Discretion
- SwiftSoup CSS selector specifics for each source (exact element paths, class names)
- Regex patterns for extracting Wine-specific artifacts
- Signal weighting in multi-signal overlap scoring
- How to organize source-specific parsers within the codebase
- text_content truncation limit (currently 8000 chars, may adjust)

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| RSRCH-01 | Agent extracts actionable fixes from web pages — exact env vars, registry paths, DLL names, winetricks verbs, INI changes | SwiftSoup CSS selectors for known sources + regex patterns for Wine artifact extraction; WineHQ/PCGamingWiki HTML structure documented |
| RSRCH-02 | Agent queries success database by engine type and graphics API tags to find similar-game solutions | `queryBySimilarity()` method combining existing query methods with overlap scoring; SuccessRecord already has all needed fields |
| RSRCH-03 | fetch_page uses SwiftSoup for structured HTML parsing instead of string stripping | SwiftSoup 2.13.4 via SPM; source-specific parsers + generic fallback; replaces current regex stripping in fetchPage() |
</phase_requirements>

## Summary

This phase upgrades the agent's web research pipeline from raw text extraction to structured fix extraction. The current `fetchPage()` uses regex to strip all HTML tags and return plain text (truncated to 8000 chars). SwiftSoup replaces this with proper DOM parsing, enabling CSS-selector-based extraction of specific content from WineHQ AppDB and PCGamingWiki pages.

The second component adds a `similar_games` composite query to `query_successdb` that scores records by multi-signal overlap (engine + graphics API + tags + symptoms) rather than querying each dimension separately. The existing `SuccessRecord` model already has all needed fields (`engine`, `graphicsApi`, `tags`, `pitfalls`).

**Primary recommendation:** Add SwiftSoup 2.13.4 as SPM dependency, create a `PageParser` protocol with three implementations (WineHQ, PCGamingWiki, Generic), and add `queryBySimilarity()` to SuccessDatabase. The parsers select based on URL domain matching.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftSoup | 2.13.4 | HTML parsing + CSS selector extraction | Only maintained pure-Swift HTML parser; jsoup-port with full CSS selector support; 104 releases, 9 years of development |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Foundation (NSRegularExpression) | built-in | Wine artifact regex extraction | Fallback on generic/unknown pages where CSS selectors are not applicable |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftSoup | libxml2 (via Foundation XMLParser) | XML-only, no CSS selectors, no HTML5 error recovery |
| SwiftSoup | Regex-only parsing (current approach) | Fragile, cannot handle nested structures, table extraction is unreliable |

**Installation (Package.swift):**
```swift
dependencies: [
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.0"),
],
// In target dependencies:
.product(name: "SwiftSoup", package: "SwiftSoup"),
```

**Note on version:** CONTEXT.md references SwiftSoup 2.8.7 from earlier roadmap planning. The current latest stable is **2.13.4** (March 2025). Use `from: "2.13.0"` to get bugfixes while staying on the same major API surface.

## Architecture Patterns

### Recommended Structure

The phase touches three files plus one new file:

```
Sources/cellar/Core/
├── PageParser.swift          # NEW: Parser protocol + WineHQ/PCGamingWiki/Generic implementations
├── AgentTools.swift          # MODIFY: fetchPage() uses PageParser, querySuccessdb() adds similar_games
├── SuccessDatabase.swift     # MODIFY: add queryBySimilarity() static method
└── AIService.swift           # MODIFY: add Research Quality methodology to system prompt
```

### Pattern 1: Source-Specific Parser Dispatch

**What:** A protocol with `canHandle(url:)` and `parse(document:)` methods, with concrete implementations for each known source. `fetchPage()` selects the first parser that matches the URL domain.

**When to use:** When different HTML sources have fundamentally different structures.

**Example:**
```swift
import SwiftSoup

protocol PageParser {
    func canHandle(url: URL) -> Bool
    func parse(document: Document) throws -> ParsedPage
}

struct ParsedPage {
    let textContent: String
    let extractedFixes: ExtractedFixes
}

struct ExtractedFixes {
    var envVars: [ExtractedEnvVar]      // [{name, value, context}]
    var registry: [ExtractedRegistry]    // [{path, value, context}]
    var dlls: [ExtractedDLL]            // [{name, mode, context}]
    var winetricks: [ExtractedVerb]     // [{verb, context}]
    var iniChanges: [ExtractedINI]      // [{file, key, value, context}]
}
```

Dispatch in `fetchPage()`:
```swift
let parsers: [PageParser] = [WineHQParser(), PCGamingWikiParser(), GenericParser()]
let parser = parsers.first { $0.canHandle(url: pageURL) } ?? GenericParser()
let doc = try SwiftSoup.parse(rawHTML)
let result = try parser.parse(document: doc)
```

### Pattern 2: WineHQ AppDB CSS Selectors

**What:** Target the known HTML structure of WineHQ AppDB version pages.

**Verified HTML structure (from AppDB source code):**
- Test results table: `table.whq-table.whq-table-full` with header class `historyHeader`
- Column order: Operating system, Test date, Wine version, Installs?, Runs?, Used Workaround?, Rating, Submitter
- Rating cells have dynamic CSS classes: "Platinum", "Gold", "Silver", "Bronze", "Garbage"
- Comments: `div.panel.panel-default.panel-forum` with `div.panel-heading` (subject) and `div.panel-body` (comment text)

**CSS selectors for WineHQ:**
```swift
// Test results table
let testRows = try doc.select("table.whq-table tr")

// Comment bodies (where actual fixes live)
let comments = try doc.select("div.panel-forum .panel-body")

// Extract text, then run regex fix extraction on comment text
for comment in comments {
    let text = try comment.text()
    extractFixes(from: text, context: "WineHQ AppDB comment")
}
```

**Confidence:** HIGH — selectors derived from AppDB PHP source code at `gitlab.winehq.org/winehq/appdb`.

### Pattern 3: PCGamingWiki CSS Selectors

**What:** Target the MediaWiki-based HTML structure of PCGamingWiki.

**Known structure (MediaWiki standard):**
- All content wrapped in `div.mw-parser-output`
- Fix tables: `table.wikitable` elements within fix sections
- Code blocks: `pre` and `code` elements (often inside `div.mw-highlight`)
- Section headings: `h2 > span.mw-headline` and `h3 > span.mw-headline`
- Fix content often under headings like "Issues fixed", "Workarounds", "Essential improvements"

**CSS selectors for PCGamingWiki:**
```swift
// All tables in the article body
let tables = try doc.select(".mw-parser-output table.wikitable")

// Code blocks
let codeBlocks = try doc.select(".mw-parser-output pre, .mw-parser-output code")

// Section-aware extraction: find fix-related headings, extract content until next heading
let headings = try doc.select(".mw-parser-output h2, .mw-parser-output h3")
```

**Confidence:** MEDIUM — based on standard MediaWiki patterns. PCGamingWiki may use custom templates. Selectors should be validated against actual pages during implementation.

### Pattern 4: Generic Parser

**What:** Fallback for unknown sources. Extracts structural elements that commonly contain fix content.

```swift
// Code blocks (most likely to contain actual commands/configs)
let codeBlocks = try doc.select("pre, code")

// Tables
let tables = try doc.select("table")

// List items (forum-style instructions)
let listItems = try doc.select("li")

// Then run regex fix extraction on extracted text
```

### Pattern 5: Wine Artifact Regex Extraction

**What:** Regex patterns to identify Wine-specific fix artifacts from text content.

```swift
// Environment variables: KEY=value patterns for known Wine vars
let envVarPattern = #"(WINE(?:DEBUG|DLLOVERRIDES|_CPU_TOPOLOGY)|DXVK_\w+|MESA_\w+|STAGING_\w+)\s*=\s*([^\s,;]+)"#

// Registry paths
let registryPattern = #"(HKCU|HKLM|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE)\\[\\A-Za-z0-9_ ]+"#

// DLL override modes: dllname=mode
let dllPattern = #"(\w+\.dll)\s*=\s*(native|builtin|n,b|b,n|n|b|disabled)"#
// Also: WINEDLLOVERRIDES="dll1=n,b;dll2=native"
let dllOverridePattern = #"WINEDLLOVERRIDES\s*=\s*["\']?([^"'\n]+)"#

// Winetricks verbs (match against known verb list)
let winetricksPattern = #"winetricks\s+((?:\w+\s*)+)"#

// INI changes: key=value in context of .ini file references
let iniPattern = #"(\w+)\s*=\s*(\w+)"#  // Too broad alone; only apply when near .ini/.cfg file references
```

**Key insight:** Regex extraction is applied AFTER SwiftSoup extracts relevant text elements. Running regex on the full raw HTML would produce too many false positives. The pipeline is: SwiftSoup selects elements -> extract text -> regex finds artifacts.

### Anti-Patterns to Avoid
- **Parsing HTML with regex alone:** The current approach. SwiftSoup handles malformed HTML, nested tags, entity decoding. Regex cannot.
- **Running fix regex on full page text:** Must scope to relevant elements first (code blocks, comments, fix sections) to avoid false positives from navigation, ads, unrelated content.
- **Hardcoding CSS selectors without fallback:** Sites change structure. Always have the generic parser as fallback.
- **Blocking on SwiftSoup parse for huge pages:** SwiftSoup parses synchronously. The existing `fetchPage()` is already synchronous (semaphore pattern), so this is consistent.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTML parsing | Regex tag stripping (current) | SwiftSoup | Entity decoding, malformed HTML recovery, DOM tree |
| CSS selectors | Manual DOM traversal | SwiftSoup `select()` | Full CSS3 selector support including pseudo-classes |
| HTML entity decoding | Manual `&amp;` replacement (current) | SwiftSoup `text()` | Handles all named + numeric entities automatically |
| Text extraction | Regex whitespace collapsing (current) | SwiftSoup `text()` / `wholeText()` | Preserves meaningful whitespace, strips tags correctly |

**Key insight:** The current `fetchPage()` has five separate regex operations to strip scripts, styles, tags, decode entities, and collapse whitespace. SwiftSoup replaces ALL of these with `doc.text()` for plain text or targeted `select().text()` for structured extraction.

## Common Pitfalls

### Pitfall 1: SwiftSoup + Swift 6 Strict Concurrency
**What goes wrong:** SwiftSoup types (Document, Element, Elements) are reference types that do not conform to Sendable. In Swift 6 strict concurrency mode, passing them across isolation boundaries causes compiler errors.
**Why it happens:** SwiftSoup removed Sendable conformance in PR #330 (Aug 2025) because its internal state is mutable and not thread-safe.
**How to avoid:** Use `@preconcurrency import SwiftSoup` if needed. More practically: SwiftSoup parsing happens entirely within the synchronous `fetchPage()` method — Document and Elements never cross isolation boundaries, so this should not be an issue. The project already uses `@unchecked Sendable` for its ResultBox pattern.
**Warning signs:** Compiler errors about "cannot conform to Sendable" when building.

### Pitfall 2: WineHQ AppDB Rate Limiting / 403 Errors
**What goes wrong:** WineHQ AppDB returns 403 Forbidden for automated requests.
**Why it happens:** AppDB may block non-browser User-Agent strings or detect scraping patterns.
**How to avoid:** The existing `fetchPage()` already sets a browser-like User-Agent header. If 403 persists, the parser gracefully falls back to the generic parser (which works on whatever HTML is returned) or returns empty extracted_fixes with an error note in text_content.
**Warning signs:** WebFetch during research returned 403 for appdb.winehq.org pages.

### Pitfall 3: PCGamingWiki Custom Templates
**What goes wrong:** CSS selectors target standard MediaWiki classes but PCGamingWiki uses custom templates that generate different HTML.
**Why it happens:** PCGamingWiki extends MediaWiki with custom extensions and templates for game data.
**How to avoid:** Test selectors against multiple actual PCGamingWiki pages during implementation. Include fallback to generic parser if expected elements are not found.
**Warning signs:** `select()` returns empty Elements for expected selectors.

### Pitfall 4: False Positive Fix Extraction
**What goes wrong:** Regex matches env var patterns in unrelated content (e.g., documentation about Wine internals, code examples showing what NOT to do).
**Why it happens:** Patterns like `KEY=value` are common in many contexts.
**How to avoid:** Only run fix extraction on text from relevant elements (code blocks, fix sections, user comments). Include context string with each extracted fix so the agent can evaluate relevance. Keep the existing `text_content` as fallback.
**Warning signs:** Extracted fixes include settings from unrelated games or documentation examples.

### Pitfall 5: Over-Counting Similarity Signals
**What goes wrong:** `queryBySimilarity()` matches too broadly, returning irrelevant games.
**Why it happens:** Tag overlap can match on generic tags like "rts" or "old-game" that don't indicate Wine compatibility similarity.
**How to avoid:** Weight engine and graphics_api matches higher than tag matches. Engine + graphics API overlap is a strong signal; tag overlap alone is weak. Require at least engine OR graphics_api match for a result to be returned.
**Warning signs:** Querying for a DirectDraw game returns results from OpenGL games with matching genre tags.

## Code Examples

### SwiftSoup Basic Parsing
```swift
import SwiftSoup

let html = "<html><body><div class='content'><p>Set WINEDEBUG=-all</p></div></body></html>"
let doc = try SwiftSoup.parse(html)

// CSS selector
let content = try doc.select("div.content p").first()
let text = try content?.text()  // "Set WINEDEBUG=-all"

// Extract attribute
let links = try doc.select("a[href]")
for link in links {
    let href = try link.attr("href")
    let linkText = try link.text()
}

// Iterate table rows
let rows = try doc.select("table.wikitable tr")
for row in rows {
    let cells = try row.select("td")
    // cells[0], cells[1], etc.
}
```

### Multi-Signal Overlap Scoring
```swift
static func queryBySimilarity(
    engine: String?,
    graphicsApi: String?,
    tags: [String],
    symptom: String?
) -> [(record: SuccessRecord, score: Int)] {
    let allRecords = loadAll()

    return allRecords.compactMap { record in
        var score = 0

        // Engine match (strongest signal)
        if let engine = engine, let recordEngine = record.engine,
           recordEngine.lowercased().contains(engine.lowercased()) {
            score += 3
        }

        // Graphics API match (strong signal)
        if let api = graphicsApi, let recordApi = record.graphicsApi,
           recordApi.lowercased().contains(api.lowercased()) {
            score += 2
        }

        // Tag overlap
        let lowerTags = Set(tags.map { $0.lowercased() })
        let recordTags = Set(record.tags.map { $0.lowercased() })
        score += lowerTags.intersection(recordTags).count

        // Symptom match (if provided)
        if let symptom = symptom {
            let queryWords = Set(symptom.lowercased().split(separator: " ")
                .map(String.init).filter { $0.count > 2 })
            for pitfall in record.pitfalls {
                let pitfallWords = Set(pitfall.symptom.lowercased().split(separator: " ")
                    .map(String.init).filter { $0.count > 2 })
                if !queryWords.intersection(pitfallWords).isEmpty {
                    score += 1
                    break
                }
            }
        }

        return score > 0 ? (record, score) : nil
    }
    .sorted { $0.score > $1.score }
    .prefix(5)
    .map { ($0.record, $0.score) }
}
```

### ExtractedFixes Output Structure
```swift
struct ExtractedEnvVar: Codable {
    let name: String      // "WINEDEBUG"
    let value: String     // "-all"
    let context: String   // "From WineHQ AppDB comment by user123"
}

struct ExtractedRegistry: Codable {
    let path: String      // "HKCU\\Software\\Wine\\Direct3D"
    let value: String?    // "MaxVersionGL" or raw match
    let context: String
}

struct ExtractedDLL: Codable {
    let name: String      // "ddraw"
    let mode: String      // "native"
    let context: String
}

struct ExtractedVerb: Codable {
    let verb: String      // "vcrun2019"
    let context: String
}

struct ExtractedINI: Codable {
    let file: String?     // "ddraw.ini" (if detectable)
    let key: String       // "renderer"
    let value: String     // "opengl"
    let context: String
}

struct ExtractedFixes: Codable {
    var envVars: [ExtractedEnvVar]
    var registry: [ExtractedRegistry]
    var dlls: [ExtractedDLL]
    var winetricks: [ExtractedVerb]
    var iniChanges: [ExtractedINI]

    var isEmpty: Bool {
        envVars.isEmpty && registry.isEmpty && dlls.isEmpty &&
        winetricks.isEmpty && iniChanges.isEmpty
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Regex HTML stripping | SwiftSoup DOM parsing | This phase | Proper entity handling, structural extraction, CSS selectors |
| Single-dimension DB queries | Multi-signal similarity scoring | This phase | Cross-game solution discovery based on engine+API similarity |
| Raw text dump from pages | Structured fix extraction | This phase | Agent gets actionable fixes directly, not buried in 8KB of text |

## Open Questions

1. **SwiftSoup version vs CONTEXT reference**
   - What we know: CONTEXT.md says "SwiftSoup 2.8.7 is the already-decided SPM dependency for v1.1 (from roadmap planning)." Current latest is 2.13.4.
   - What's unclear: Whether there is a specific reason to pin to 2.8.7 or if the roadmap used an older version reference.
   - Recommendation: Use `from: "2.13.0"` — the API surface is backward-compatible and 2.13.x has important bugfixes including compound attribute selector regression fixes.

2. **PCGamingWiki actual HTML structure**
   - What we know: Uses MediaWiki engine with standard classes (mw-parser-output, wikitable). Has custom templates for game infoboxes.
   - What's unclear: Exact CSS classes/structure of fix sections. WebFetch returned 403 during research.
   - Recommendation: During implementation, fetch a real PCGamingWiki page via the app itself (using the existing fetchPage User-Agent) and inspect the HTML to finalize selectors. Start with standard MediaWiki selectors and refine.

3. **Similarity scoring weights**
   - What we know: Engine and graphics API are the strongest signals for Wine compatibility similarity.
   - What's unclear: Optimal weight values. Should engine match = 3 and API match = 2, or should they be equal?
   - Recommendation: Start with engine=3, graphics_api=2, tag=1 each, symptom=1. Simple integer scoring. Can be tuned later with real data.

4. **DuckDuckGo rate limiting for multi-query sessions**
   - What we know: STATE.md flags this as needing validation. search_web already uses DuckDuckGo HTML search.
   - What's unclear: Whether multiple search_web + fetch_page calls in one agent session trigger anti-bot responses.
   - Recommendation: This is an existing concern not specific to this phase. The research cache (7-day TTL) already mitigates repeated searches. Not a blocker for Phase 11 implementation.

## Sources

### Primary (HIGH confidence)
- WineHQ AppDB source code (gitlab.winehq.org/winehq/appdb) — `include/testData.php` for test results HTML structure, `include/comment.php` for comment HTML structure
- SwiftSoup GitHub releases (github.com/scinfu/SwiftSoup/releases) — version 2.13.4 confirmed as latest stable
- Existing codebase: `AgentTools.swift`, `SuccessDatabase.swift`, `AIService.swift` — current implementation patterns

### Secondary (MEDIUM confidence)
- SwiftSoup GitHub README — API examples, SPM installation, platform support
- MediaWiki standard HTML structure — `mw-parser-output`, `wikitable` classes for PCGamingWiki
- Wine environment variable documentation (winehq.org) — env var names and patterns for regex extraction

### Tertiary (LOW confidence)
- SwiftSoup Swift 6 Sendable status — PR #330 removed Sendable, but exact impact on this project's Swift 6 build needs validation during implementation
- PCGamingWiki fix section HTML structure — could not fetch actual pages during research; selectors based on MediaWiki standards need validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - SwiftSoup is the only viable option, well-maintained, API well-documented
- Architecture: HIGH - Parser protocol pattern is straightforward; WineHQ HTML structure verified from source
- Pitfalls: HIGH - Swift 6 concurrency, false positives, and 403 errors are well-understood risks with clear mitigations

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain, no fast-moving dependencies)
