# Phase 19: Import Lutris and ProtonDB Compatibility Databases - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Give the agent access to Lutris and ProtonDB community compatibility data so it can make better config decisions before and during diagnosis. A single unified lookup queries both sources, extracts actionable config hints, and injects them into the agent's context. A new tool allows deeper on-demand queries.

</domain>

<decisions>
## Implementation Decisions

### Data Source Strategy
- Query Lutris and ProtonDB APIs on demand (no bulk import, no bundled snapshots)
- Single unified lookup fans out to both APIs in parallel, merges results into one compatibility report
- Name-based fuzzy search for game matching (Lutris and ProtonDB use different IDs than Cellar slugs)
- Both sources attempted — accept risk that ProtonDB's unofficial API may break; Lutris is the reliable source

### Data Extraction
- Extract everything actionable from Lutris install scripts: env vars, DLL overrides, registry edits, winetricks verbs, Wine version notes
- From ProtonDB: extract tier rating (Platinum/Gold/Silver/Bronze/Borked) as confidence signal + actionable config tweaks from user notes
- Filter Proton-specific flags before showing to agent: strip PROTON_* env vars, Steam runtime references, and other Linux/Proton-only config. Only pass portable config hints (env vars, DLL overrides, registry, winetricks)

### Agent Integration
- Both pre-diagnosis injection AND a new agent tool:
  - Auto-inject full compatibility extraction into initial agent context before any tool calls (like collective memory read path in Phase 15)
  - Add a `query_compatibility` tool the agent can call for deeper/updated lookups during diagnosis
- Full extraction injected (~500-1000 tokens) — agent rarely needs to call the tool
- Add explicit system prompt guidance telling the agent about Lutris/ProtonDB data and how to use it for initial config choices

### Freshness & Storage
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

</decisions>

<specifics>
## Specific Ideas

- ProtonDB's API is unofficial — endpoints like `/api/v1/reports/game/{appid}` exist but aren't documented. Build with graceful degradation in mind.
- Lutris has a documented public API at `lutris.net/api/` — game search, install script details, runner configs.
- The existing PageParser protocol can be extended for site-specific extraction if scraping is needed as a fallback.
- ProtonDB is Linux/Proton-focused — the filtering of Proton-specific config is important so the agent doesn't try to apply incompatible settings on macOS/Wine.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PageParser` protocol (`Core/PageParser.swift`): Extensible HTML parsing architecture — can add Lutris/ProtonDB parsers
- `SuccessDatabase` (`Core/SuccessDatabase.swift`): Multi-signal similarity scoring pattern for game matching
- `CollectiveMemoryService` (`Core/CollectiveMemoryService.swift`): Environment-aware scoring and pre-diagnosis injection pattern
- Research cache (`CellarPaths.researchCacheDir`): 7-day TTL cache for web fetches — extend for 30-day compat cache
- SwiftSoup: Already a dependency for structured HTML parsing

### Established Patterns
- Pre-diagnosis injection: Collective memory read path injects context before agent tool calls (Phase 15)
- Tool definition pattern: JSON Schema definitions in `AgentTools.swift` for new tools
- Graceful degradation: Collective memory returns nil on failure, agent proceeds normally
- URLSession + DispatchSemaphore + ResultBox: Synchronous bridge pattern for async HTTP calls

### Integration Points
- `AIService.runAgentLoop()`: Where pre-diagnosis context is assembled (add compatibility data alongside collective memory)
- `AgentTools.toolDefinitions`: Where new `query_compatibility` tool would be registered
- `AgentTools` system prompt: Where guidance about Lutris/ProtonDB data would be added
- `CellarPaths`: Where `researchCacheDir` subdirectory paths would be defined

</code_context>

<deferred>
## Deferred Ideas

- Web UI view for browsing Lutris/ProtonDB compatibility data per game — could be added to the game detail page in a future phase
- Using ProtonDB data to auto-suggest Wine configs for games Cellar has never seen — requires confidence scoring beyond this phase's scope

</deferred>

---

*Phase: 19-import-lutris-and-protondb-compatibility-databases*
*Context gathered: 2026-03-31*
