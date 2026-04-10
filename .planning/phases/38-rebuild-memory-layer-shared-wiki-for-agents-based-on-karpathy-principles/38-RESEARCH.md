# Phase 38: Rebuild Memory Layer — Research

**Researched:** 2026-04-06
**Domain:** LLM-maintained knowledge base / agent memory architecture
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Architecture: Three-Layer Pattern (from Karpathy)**
- **Raw sources:** Immutable inputs (F5Bot emails, Reddit threads, game data, user configs)
- **The wiki:** LLM-generated markdown files — summaries, entity pages, concept pages, cross-references
- **The schema:** Configuration document defining wiki structure, conventions, and workflows

**Two Special Files**
- **index.md** — Content-oriented catalog of all wiki pages with one-line summaries, organized by category
- **log.md** — Append-only chronological record with consistent prefixes (e.g., `## [2026-04-09] ingest | Source Title`) for parseability

**Core Operations**
- **Ingest:** New sources processed → LLM reads, writes summaries, updates index and relevant pages, appends to log
- **Query:** Search relevant pages, synthesize answers with citations. Valuable findings can become new wiki pages
- **Lint:** Periodic health checks for contradictions, stale claims, orphan pages, missing cross-references

### Claude's Discretion
- Exact directory structure within repo
- Which existing Cellar data/configs migrate to wiki format
- Page format conventions (frontmatter schema, linking style)
- How agents discover and read wiki pages at runtime
- Integration with existing collective memory system
- Whether wiki lives in main repo or separate repo
- Search/indexing approach (simple grep vs something more)

### Deferred Ideas (OUT OF SCOPE)
- Advanced search infrastructure (BM25/vector hybrid search, LLM re-ranking)
- Obsidian integration / graph visualization
- Multi-agent concurrent wiki editing with conflict resolution
- Tiered memory density levels (L0/L1/L2)
</user_constraints>

---

## Summary

Phase 38 replaces the current collection of flat JSON config files (`~/.cellar/promo.json`, scattered session/successdb files, per-game research caches) with a structured, LLM-maintained markdown wiki stored in the repo. The Karpathy LLM Wiki pattern provides a three-layer architecture (raw sources → wiki → schema) with two special files (`index.md` and `log.md`) and three operations (ingest, query, lint).

The key insight is that Cellar's agents currently derive knowledge from scratch on every run — each new session re-fetches compatibility data, re-reads Wine logs, and has no persistent synthesis across games or users. A wiki allows knowledge compiled once (e.g., "DXVK 2.x works better than 1.x for DirectX 11 titles on Apple Silicon") to persist and compound, rather than each agent session re-deriving the same conclusions.

The primary implementation work is: (1) define the wiki schema/structure for Cellar's domain, (2) create the initial seed pages migrated from existing knowledge sources, (3) implement a `WikiService` that agents can query at runtime, and (4) implement ingest/lint CLI operations so the wiki grows over time. The wiki should live in the main repo under `wiki/` since it contains project-specific knowledge, not user game configs.

**Primary recommendation:** Store the wiki in the Cellar repo at `wiki/` with a `SCHEMA.md` at the root. Implement `WikiService` that reads `wiki/index.md` to locate pages, then reads relevant pages for context injection. Use `grep`-based search (not vector search) to find relevant pages by game name, engine, or symptom keyword.

---

## Standard Stack

### Core

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Swift Foundation | bundled | FileManager, String, Data | Already used throughout Cellar |
| Markdown files | plain text | Wiki page format | Human-readable, git-diffable, no dependencies |
| Git (repo) | system | Version history, collaboration | Comes free with the Cellar repo |

### Supporting

| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| NSRegularExpression | bundled | grep-style search in wiki pages | Finding relevant pages by keyword match |
| JSONEncoder/Decoder | bundled | Serializing ingest metadata | Tracking which sources have been ingested |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| grep/NSRegularExpression | SQLite FTS5 | SQLite adds complexity; grep sufficient at Cellar's scale |
| Repo-local `wiki/` | Separate repo | Separate repo adds auth complexity; wiki is project knowledge not user data |
| Plain markdown | YAML frontmatter | Frontmatter adds structure for indexing but requires parser; start plain, add if needed |

**Installation:** No new SPM dependencies required.

---

## Architecture Patterns

### Recommended Wiki Structure

```
wiki/
├── SCHEMA.md              # Defines conventions, page types, linking style (the "schema" layer)
├── index.md               # Catalog of all pages with one-line summaries, by category
├── log.md                 # Append-only ingest/lint history
├── games/
│   ├── lego-racers-2.md   # Per-game knowledge page
│   └── cossacks.md
├── engines/
│   ├── unity.md           # Engine-specific Wine patterns
│   ├── dxvk.md
│   └── directdraw.md
├── symptoms/
│   ├── black-screen.md    # Symptom → diagnosis → fix patterns
│   ├── crash-on-launch.md
│   └── d3d-errors.md
└── environments/
    ├── apple-silicon.md   # Platform-specific knowledge
    └── wine-stable-9.md
```

### Pattern 1: WikiService (Agent Read Path)

**What:** At agent session start, `WikiService.fetchContext(for:)` reads `wiki/index.md`, identifies relevant page paths by keyword match against game name/engine/symptoms, reads those pages, and returns a formatted context block for injection into the agent's initial message.

**When to use:** In `AIService.runAgentLoop()` alongside `CollectiveMemoryService.fetchBestEntry()` — wiki context is injected into the agent prompt before the loop starts.

**Example:**
```swift
// WikiService.swift
struct WikiService {
    static let wikiDir: URL = // bundle resource URL or repo-relative URL

    static func fetchContext(for gameName: String, symptoms: [String] = []) -> String? {
        // 1. Read index.md
        guard let index = try? String(contentsOf: wikiDir.appendingPathComponent("index.md")) else {
            return nil
        }
        // 2. Score pages by keyword relevance (game name words + symptom keywords)
        let keywords = extractKeywords(gameName: gameName, symptoms: symptoms)
        let pagePaths = findRelevantPages(in: index, keywords: keywords, limit: 3)
        guard !pagePaths.isEmpty else { return nil }
        // 3. Read and concatenate relevant pages (capped at ~3000 chars total)
        let content = pagePaths.compactMap { path -> String? in
            try? String(contentsOf: wikiDir.appendingPathComponent(path))
        }.joined(separator: "\n\n---\n\n")
        return "--- WIKI KNOWLEDGE ---\n\(content)\n--- END WIKI KNOWLEDGE ---"
    }
}
```

### Pattern 2: log.md Format

**What:** Append-only chronological record. Each entry uses a consistent header prefix enabling grep-based filtering.

**When to use:** Every ingest, lint, or significant query operation appends an entry.

**Example format:**
```markdown
## [2026-04-09] ingest | Reddit thread: LEGO Racers 2 black screen fix
Pages updated: games/lego-racers-2.md, symptoms/black-screen.md, engines/directdraw.md
Source: https://reddit.com/r/wine/...
Summary: DDraw wrapper (cnc-ddraw) resolves black screen on Wine 9+ with DirectDraw games.

## [2026-04-09] lint | Contradiction detected
Issue: games/cossacks.md claims DXVK not needed; engines/dxvk.md recommends it for DX9 titles.
Resolution: Kept games/cossacks.md — game-specific override is more accurate than general rule.
```

### Pattern 3: index.md Format

**What:** Human- and LLM-readable catalog. The LLM reads this first during queries to identify which pages to load. Organized by category with one-line summaries.

**Example format:**
```markdown
# Wiki Index

## Games
- [games/lego-racers-2.md](games/lego-racers-2.md) — LEGO Racers 2: DirectDraw + cnc-ddraw required, wine-stable 9.x
- [games/cossacks.md](games/cossacks.md) — Cossacks: European Wars: runs well, no special config needed

## Engines
- [engines/directdraw.md](engines/directdraw.md) — DirectDraw games: use cnc-ddraw wrapper, disable DXVK
- [engines/dxvk.md](engines/dxvk.md) — DXVK: DX9/10/11 → Vulkan; versions, known issues, Apple Silicon notes

## Symptoms
- [symptoms/black-screen.md](symptoms/black-screen.md) — Black screen on launch: common causes + fixes
- [symptoms/crash-on-launch.md](symptoms/crash-on-launch.md) — Crash before menu: PE imports, missing DLLs

## Environments
- [environments/apple-silicon.md](environments/apple-silicon.md) — Apple Silicon (arm64): Rosetta 2, GPTK, WoW64 notes
```

### Pattern 4: Ingest Operation

**What:** A CLI command `cellar wiki ingest <source>` processes a new source (URL, file, or stdin) and updates the wiki. The LLM reads the source, identifies which wiki pages to update, writes changes, and appends to `log.md`.

**Integration point:** The `promo` skill (F5Bot email reader) already processes Reddit/web content — ingest is the wiki-native version of this pipeline.

**Existing data to migrate on first ingest:**
- `~/.cellar/successdb/*.json` → per-game wiki pages (games/ category)
- `~/.cellar/research/*.json` → compatibility research summaries
- `promo.json` seen_urls → already-ingested source tracking

### Pattern 5: Wiki as Agent Tool

**What:** Add a `query_wiki` tool to `AgentTools` so agents can search the wiki mid-session (not just at startup).

**When to use:** When the agent encounters a specific symptom or error it wants to cross-reference with accumulated wiki knowledge.

**Integration:** Follows the same pattern as `query_compatibility` and `query_successdb` — returns plain text for agent injection.

```swift
// In ResearchTools.swift extension
func queryWiki(input: JSONValue) -> String {
    guard let query = input["query"]?.asString else {
        return jsonResult(["error": "query required"])
    }
    return WikiService.fetchContext(for: query) ?? "No relevant wiki pages found for '\(query)'"
}
```

### Anti-Patterns to Avoid

- **One giant wiki file:** Karpathy explicitly recommends separate pages per entity/concept — enables targeted reads without loading everything into context.
- **Wiki stored in `~/.cellar/`:** That directory holds mutable user runtime state. The wiki is project knowledge — it belongs in the repo where it's version-controlled and ships with Cellar.
- **Agents writing wiki pages directly at runtime:** Runtime agents should not modify wiki pages during a game launch session. Wiki maintenance (ingest/lint) is an explicit offline operation.
- **Replacing collective memory (GitHub repo) with wiki:** These serve different purposes. Collective memory = user-contributed working configs with environment fingerprints. Wiki = synthesized knowledge/patterns. Both should coexist.
- **Overloading agents with all wiki context:** Read `index.md` to identify relevant pages, then load 2-3 pages max. Don't dump all wiki content into every agent context window.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Markdown parsing | Custom parser | String scanning / line splitting | Pages are simple enough for grep-style matching; no AST needed |
| Full-text search | Inverted index, BM25 | NSRegularExpression / String.contains | Wiki is small at Cellar's scale; DEFERRED for advanced search per constraints |
| Frontmatter parsing | YAML decoder | String prefix extraction | Keep pages human-writable; structured frontmatter is optional |
| Wiki page generation | Template engine | LLM-authored pages | The whole point is LLMs write the wiki — don't hand-roll page templates |

**Key insight:** The wiki's value is in the LLM-maintained content, not the infrastructure. Keep the infrastructure (Swift service layer) minimal.

---

## Common Pitfalls

### Pitfall 1: Wiki Living in `~/.cellar/` Instead of the Repo

**What goes wrong:** If wiki pages live in `~/.cellar/wiki/`, they are: (a) not version-controlled per repo, (b) not shipped with Cellar updates, (c) not shareable across contributors.
**Why it happens:** It seems natural alongside other Cellar state in `~/.cellar/`.
**How to avoid:** Store the wiki in the repo at `wiki/`. The wiki is project knowledge, not user runtime state. Agents read from the bundled wiki; users can add local pages if needed.
**Warning signs:** If you find yourself adding `CellarPaths.wikiDir`, you're in the wrong location.

### Pitfall 2: Injecting All Wiki Context Into Every Agent

**What goes wrong:** Loading 20+ wiki pages into every agent context window wastes tokens, can exceed context limits, and dilutes the relevant signal.
**Why it happens:** "More context is better" intuition.
**How to avoid:** Read `index.md` first, score pages by keyword relevance (game name words + symptom keywords), load max 2-3 pages (~2000-3000 tokens total).
**Warning signs:** WikiService returns more than 5KB.

### Pitfall 3: Conflating Wiki With Collective Memory

**What goes wrong:** The collective memory system (GitHub JSON repo) tracks community-contributed working configs with environment fingerprints. The wiki tracks synthesized patterns and knowledge. Merging them loses the structure of both.
**Why it happens:** Both are "persistent memory" conceptually.
**How to avoid:** Maintain both systems. Collective memory = exact configs per game/environment. Wiki = pattern knowledge ("DirectDraw games need cnc-ddraw on Wine 9+"). The wiki can reference collective memory entries as evidence.

### Pitfall 4: Wiki Growing Stale Without Lint

**What goes wrong:** Early pages become outdated (e.g., a DXVK version recommendation that's been superseded), but no one notices because there's no freshness signal.
**Why it happens:** Ingest adds new pages but nobody removes/updates old claims.
**How to avoid:** Implement lint as a real operation from the start, even if it's just a CLI command that prints warnings. Include `last_updated` header in page frontmatter.

### Pitfall 5: Circular Dependency Between Wiki Init and Agent

**What goes wrong:** WikiService is called in `AIService.runAgentLoop()`, but `wiki/index.md` doesn't exist yet (wiki not seeded), causing a silent nil return and no context injection.
**Why it happens:** The wiki needs to exist before agents can use it.
**How to avoid:** WikiService gracefully returns nil when `wiki/index.md` is missing (already noted in the pattern). Seed the wiki with initial pages as part of this phase. Document that wiki absence = graceful degradation.

### Pitfall 6: LLM-Generated Wiki Amplifying Errors

**What goes wrong:** The CONTEXT.md explicitly flags this: "LLM-generated intermediate artifacts can amplify factual errors."
**Why it happens:** LLM synthesizes from raw sources and can hallucinate or over-generalize.
**How to avoid:** Keep raw sources (successdb JSON, compatibility reports) as the ground truth. Wiki pages cite their source material. Agents should verify wiki claims with `query_successdb` or live diagnostics rather than treating wiki as authoritative.

---

## Code Examples

### WikiService — index.md keyword scoring

```swift
// Verified pattern based on existing CollectiveMemoryService approach
private static func findRelevantPages(in indexContent: String, keywords: [String], limit: Int) -> [String] {
    // Each line in index.md looks like:
    // - [games/lego-racers-2.md](games/lego-racers-2.md) — LEGO Racers 2: DirectDraw
    let lines = indexContent.components(separatedBy: .newlines)
    let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
    let regex = try? NSRegularExpression(pattern: linkPattern)

    var scored: [(path: String, score: Int)] = []

    for line in lines {
        guard let match = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
        let pathRange = Range(match.range(at: 2), in: line)!
        let path = String(line[pathRange])
        let lowLine = line.lowercased()
        let score = keywords.reduce(0) { acc, kw in acc + (lowLine.contains(kw.lowercased()) ? 1 : 0) }
        if score > 0 { scored.append((path: path, score: score)) }
    }

    return scored.sorted { $0.score > $1.score }.prefix(limit).map { $0.path }
}
```

### log.md append

```swift
// Append-only log write — mirrors AgentEventLog pattern
static func appendToLog(wikiDir: URL, operation: String, title: String, detail: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let dateStr = formatter.string(from: Date())
    let entry = "\n## [\(dateStr)] \(operation) | \(title)\n\(detail)\n"
    let logURL = wikiDir.appendingPathComponent("log.md")
    if let data = entry.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logURL.path) {
            guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
```

### Agent tool injection (in AIService)

```swift
// In AIService.runAgentLoop(), after CollectiveMemoryService fetch:
// Source: existing pattern from CollectiveMemoryService injection
var contextParts: [String] = []
if let wikiContext = WikiService.fetchContext(for: entry.name, symptoms: []) {
    contextParts.append(wikiContext)
}
if let memoryContext = await CollectiveMemoryService.fetchBestEntry(for: entry.name, wineURL: wineURL) {
    contextParts.append(memoryContext)
}
// Inject into initialMessage as prefix
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Re-derive knowledge every agent session | Pre-compiled wiki read once at startup | Phase 38 | Knowledge compounds across runs |
| Per-game JSON successdb + flat session files | Structured wiki with cross-references | Phase 38 | Patterns transcend individual games |
| Static collective memory (config repo) | Static collective memory + dynamic wiki | Phase 38 | Wiki adds synthesized pattern layer |
| Agent reads compatibility reports raw | Agent reads synthesized wiki + raw reports | Phase 38 | Faster agent orientation, less redundant research |

**Deprecated/outdated:**
- `promo.json` seen_urls: Wiki `log.md` tracks ingested sources — `promo.json` becomes redundant after ingest integration.

---

## Open Questions

1. **Where does the wiki live relative to the Swift binary?**
   - What we know: The wiki must be readable at runtime by the Swift CLI. If it lives in `wiki/` in the repo, it needs to be either bundled in the app package or read from the repo clone path.
   - What's unclear: Cellar is distributed as a Homebrew binary. The binary won't have `wiki/` next to it unless we ship the wiki as a bundled resource.
   - Recommendation: Two options — (a) bundle `wiki/` as a resource in the Swift package, read via `Bundle.module.url(forResource:)`, or (b) default to `~/.cellar/wiki/` as the wiki location with a `cellar wiki update` command to pull latest from the repo. Option (b) is simpler for v1 and matches the `~/.cellar/` pattern for user-local data. The wiki would be seeded on first run if missing.

2. **How does the wiki get updated in production?**
   - What we know: The repo has a `wiki/` directory. Users install Cellar via Homebrew binary (not a git clone).
   - What's unclear: When new wiki pages are added to the repo, users get them via `brew upgrade cellar` — but only if pages are bundled resources. If wiki lives in `~/.cellar/wiki/`, users need a separate sync command.
   - Recommendation: Start with bundled resources (Swift Package resource files). This ensures the wiki ships with the binary and users get updates on brew upgrade. Investigate `Bundle.module` for SPM resource access.

3. **What's the right initial wiki seed content?**
   - What we know: Cellar has `~/.cellar/successdb/*.json` with actual verified configs, `~/.cellar/research/*.json` with compatibility data, and the `promo.json` seen URLs as processed sources.
   - What's unclear: Which of this data should become wiki pages vs. remain in its current format?
   - Recommendation: Migrate general patterns to wiki pages (engines/, symptoms/), keep game-specific configs in successdb (they already serve well as structured JSON). Create wiki pages for: DXVK setup, DirectDraw games, common symptoms (black screen, crash on launch), Apple Silicon notes.

4. **How does WikiService know which wiki files to ship?**
   - What we know: Swift Package Manager supports resource bundles via `resources: [.copy("wiki/")]` in Package.swift.
   - What's unclear: Whether copying a directory of markdown files as a bundle resource is standard practice and handles updates cleanly.
   - Recommendation: LOW confidence on exact SPM resource syntax — verify `Package.swift` resource declaration before implementing.

---

## Validation Architecture

> `workflow.nyquist_validation` is not set in `.planning/config.json` — skip this section.

---

## Sources

### Primary (HIGH confidence)
- Karpathy LLM Wiki gist (https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — fetched 2026-04-06; three-layer architecture, special files, operations, philosophy
- Cellar codebase (current) — CollectiveMemoryService.swift, AgentEventLog.swift, CellarPaths.swift, AgentTools.swift, SuccessDatabase.swift — existing patterns for context injection, append-only logs, agent tools

### Secondary (MEDIUM confidence)
- CONTEXT.md (38-CONTEXT.md) — user decisions locked before this research
- STATE.md accumulated decisions — existing architectural patterns (env injection ordering, nil-on-failure, fputs for service errors)

### Tertiary (LOW confidence)
- SPM bundled resources pattern — from training data; verify `Bundle.module.url(forResource:)` against Swift 5.9+ docs before implementing

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; pure markdown + existing Swift Foundation patterns
- Architecture: HIGH — Karpathy pattern fetched directly from source; existing Cellar patterns well-understood
- Pitfalls: HIGH — derived from direct codebase reading and Karpathy's explicit accuracy warning
- SPM resource bundling: LOW — verify before implementing open question #4

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (stable domain — markdown files, Foundation APIs)
