# Phase 11: Smarter Research - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Enhance the agent's web research to extract specific, actionable fixes from web pages (not raw text dumps), enable cross-game success database queries ranked by signal overlap, and add structured HTML parsing via SwiftSoup for known sources. The existing fetch_page, query_successdb, and search_web tools are enhanced — no new tools are added.

</domain>

<decisions>
## Implementation Decisions

### Fix Extraction Strategy
- Fix extraction happens inside fetch_page — returns both `text_content` (existing, upgraded) and `extracted_fixes` (new)
- Only extract Wine-specific artifacts: env vars (WINEDEBUG, DXVK_*), registry paths (HKCU\Software\Wine), DLL names/modes (ddraw=native), winetricks verbs (vcrun2019), INI key=value pairs
- SwiftSoup CSS selectors first for known sources (WineHQ, PCGamingWiki), regex fallback on stripped text for unknown sources
- Upgrade text_content to use SwiftSoup too — extract meaningful text (paragraphs, headings, lists) instead of regex stripping

### Source-Specific Parsing
- Two dedicated SwiftSoup parsers: WineHQ AppDB and PCGamingWiki
- WineHQ AppDB: target test results table (Wine version, rating, distro) plus comment text from user reports — these contain the actual fixes
- PCGamingWiki: target fix tables and code blocks in fix sections — well-structured compatibility/fix tables
- Unknown/unrecognized sources: generic parser extracts `<pre>`, `<code>`, and `<table>` elements, then runs regex fix extraction on those elements
- Forums and other sources use the generic parser — no dedicated forum parser

### Cross-Game DB Ranking
- New `similar_games` composite query parameter added to query_successdb alongside existing query types (game_id, tags, engine, graphics_api, symptom)
- Multi-signal overlap scoring: engine family match + graphics API match + tag overlap + symptom match
- Each matching signal increases the score; records ranked by total overlap count
- Return top 5 matches, consistent with existing query limits
- Existing separate query types preserved — no breaking changes

### Output Structure
- `extracted_fixes` grouped by type: `env_vars: [{name, value, context}]`, `registry: [{path, value, context}]`, `dlls: [{name, mode, context}]`, `winetricks: [{verb, context}]`, `ini_changes: [{file, key, value, context}]`
- Each fix includes a short context string (e.g., "From WineHQ test result by user123", "From PCGamingWiki fix table")
- Always return both `text_content` and `extracted_fixes` — agent has structured data AND can fall back to raw text for context
- Update system prompt with research methodology: check extracted_fixes first, apply directly if confident, fall back to text_content for context

### Claude's Discretion
- SwiftSoup CSS selector specifics for each source (exact element paths, class names)
- Regex patterns for extracting Wine-specific artifacts
- Signal weighting in multi-signal overlap scoring
- How to organize source-specific parsers within the codebase
- text_content truncation limit (currently 8000 chars, may adjust)

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `fetchPage()` (AgentTools.swift:1995): Current regex-based HTML stripping — will be replaced with SwiftSoup parsing
- `querySuccessdb()` (AgentTools.swift:1686): Priority-based query dispatch — add similar_games branch
- `SuccessDatabase` (SuccessDatabase.swift:87): Has `queryByEngine`, `queryByGraphicsApi`, `queryByTags`, `queryBySymptom` — add `queryBySimilarity` combining all four
- `SuccessRecord` model: Already has `engine`, `graphicsApi`, `tags`, `pitfalls` fields needed for multi-signal matching

### Established Patterns
- Tool dispatch: `toolDefinitions` array + `execute()` switch in AgentTools.swift
- JSON result format: All tools return via `jsonResult()` helper
- System prompt methodology: Sections placed in logical order (Engine-Aware, Dialog Detection, etc.) in AIService.swift
- Phase 9/10 pattern: New methodology sections added to system prompt between existing sections

### Integration Points
- Package.swift: Add SwiftSoup 2.8.7 as SPM dependency
- AgentTools.swift `fetchPage()`: Replace regex stripping with SwiftSoup parsing + fix extraction
- AgentTools.swift `querySuccessdb()`: Add `similar_games` parameter handling
- SuccessDatabase.swift: Add `queryBySimilarity()` static method
- AIService.swift system prompt: Add Research Quality methodology section

</code_context>

<specifics>
## Specific Ideas

- SwiftSoup 2.8.7 is the already-decided SPM dependency for v1.1 (from roadmap planning)
- The system prompt research methodology should follow the same pattern as Engine-Aware Methodology (Phase 9) and Dialog Detection (Phase 10) — a dedicated section with a heuristic table
- STATE.md flag: DuckDuckGo anti-bot rate limiting under multiple queries per session needs validation during research

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-smarter-research*
*Context gathered: 2026-03-29*
