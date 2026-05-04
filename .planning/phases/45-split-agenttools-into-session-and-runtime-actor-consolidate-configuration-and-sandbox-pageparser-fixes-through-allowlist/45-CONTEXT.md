# Phase 45: Split AgentTools + Sandbox PageParser — Context

**Gathered:** 2026-05-04
**Status:** Ready for planning

<domain>
## Phase Boundary

Three bundled workstreams:

1. **AgentTools session/runtime split** — Extract the mutable session-scoped state (accumulatedEnv, launchCount, installedDeps, pendingActions, lastAppliedActions, previousDiagnostics, draftBuffer, hasSubstantiveFailure) from AgentTools into an isolated type. AgentTools retains infrastructure (wineURL, bottleURL, control, askUserHandler) and the dispatch coordinator role it has had since Phase 24.

2. **Configuration consolidation** — The per-session parameters injected into AgentTools (gameId, entry, executablePath, bottleURL, wineURL, wineProcess) are currently individual constructor arguments. Consolidate into a typed session-context value so call sites (AIService, LaunchController) pass one thing.

3. **Sandbox fetch_page through allowlist** — `fetch_page` currently fetches any URL without filtering. Add a domain allowlist backed by PolicyResources so the agent is restricted to known wine/gaming research sites.

Phase 44 has already extracted memory call sites from AgentTools (they now go through KnowledgeStoreContainer). This reduces the Phase 45 overlap noted in Phase 44's CONTEXT.md to zero — the split can proceed cleanly.

</domain>

<decisions>
## Implementation Decisions

### fetch_page domain policy
- **Strict known wine/gaming allowlist** — not a permissive "block-private-only" filter. The agent should stay focused on wine/gaming research sources.
- **PolicyResources JSON file** — domain list lives in `Sources/cellar/Resources/policy/fetch_page_domains.json`, loaded as `PolicyResources.shared.fetchPageAllowlist: Set<String>`. Consistent with Phase 43 pattern. Adding a new domain = update JSON, no recompile needed.
- **Explicit error on blocked URL** — return `{"error": "Domain not in allowlist", "url": "...", "hint": "Use search_web to find relevant pages first"}`. Agent receives a clear policy signal and can pivot to `search_web`.
- **Initial allowlist** — wine/gaming core: WineHQ, ProtonDB, PCGamingWiki, Steam community, GitHub, Reddit (reddit.com covers all subreddits). Covers ~95% of real agent research. Researcher should audit actual `search_web` result domains to confirm coverage.

### AgentTools split
- **Claude's Discretion** — whether to use a Swift `actor`, a `struct` extracted from the class, or an `@MainActor`-isolated type. The goal is: session-scoped mutable state is isolated from infrastructure. Call-site impact on AIService and LaunchController should be minimal.
- Existing coordinator role (dispatch in `execute()`, tool definitions, `jsonResult()`) stays in AgentTools.

### Configuration consolidation
- **Claude's Discretion** — scope is internal agent session state only (the injected constructor args). Does NOT touch CellarConfig (user-visible prefs). A `SessionConfiguration` or similar value type wrapping the current init parameters is the expected shape.

### Claude's Discretion
- Whether the session state type is `actor`, `struct`, or `class`
- Exact naming: `SessionState`, `AgentSession`, `SessionContext`
- Whether AIService and LaunchController pass a single `SessionConfiguration` value or still pass individual args (if the refactor stays internal to AgentTools)
- Specific subdomain matching strategy (e.g., does `github.com` cover `raw.githubusercontent.com`? researcher should verify)

</decisions>

<specifics>
## Specific Ideas

- The domain allowlist JSON file should follow the same pattern as `winetricks_verbs.json` (plain array, no schema_version wrapper) — established in Phase 44.
- The explicit blocked-URL error message includes a `"hint"` key pointing to `search_web` — this matches how other agent error responses guide the model.
- Phase 43's `PolicyResources` already handles the Bundle.module resource loading quirk (`resourcePath + manual path` fallback). The new `fetchPageAllowlist` property follows the same loading pattern.
- PageParser itself (WineHQParser, PCGamingWikiParser, GenericParser) is not being rewritten — only the URL gate before `fetchPage` calls it. "PageParser fixes" in the phase name refers to fixing the lack of sandboxing, not fixing parsing bugs.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `PolicyResources.swift` + `Resources/policy/*.json` — established pattern for JSON allowlists. `fetchPageAllowlist` adds a 4th field alongside `envAllowlist`, `registryAllowlist`, `winetricksVerbAllowlist`.
- `PageParser.swift` — `selectParser(for url: URL) -> PageParser` is already modular; the domain check slots in before this call in `ResearchTools.fetchPage`.
- `KnowledgeStoreContainer` singleton pattern (Phase 44) — same registration-at-loop-entry approach likely applies to a `SessionState` singleton or the session injection.

### Established Patterns
- PolicyResources loading: `Bundle.module` resourcePath fallback, plain JSON array, `Set<String>` property.
- AgentTools already has `@unchecked Sendable` — the session state split should improve this (remove the `@unchecked` if session state becomes a proper `actor`).
- Phase 24 decision: `AgentTools.swift` keeps only coordinator code — all tool logic in `Core/Tools/` extensions. The session split continues this direction.

### Integration Points
- `ResearchTools.fetchPage` — the URL gate goes here, before the URLRequest is built.
- `AIService.runAgentLoop` — creates AgentTools with current individual-arg init. Will need updating if SessionConfiguration is introduced.
- `LaunchController.swift` — also creates AgentTools. Same update scope.
- `PolicyResources.swift` + `Sources/cellar/Resources/policy/` — new `fetch_page_domains.json` file + new property.

</code_context>

<deferred>
## Deferred Ideas

- **Subdomain expansion of allowlist** — e.g., `raw.githubusercontent.com` as a separate entry from `github.com`. Researcher should verify and decide during planning.
- **Per-game session allowlist extension** — letting a game's wiki page declare additional allowed domains for that game's community. Deferred — current allowlist covers real usage.
- **HTTPS enforcement** — requiring `https://` for all fetched pages. Deferred — most targets already use HTTPS; enforcement adds complexity for edge cases.
- **Deletion of legacy services** (CollectiveMemoryService, WikiService wrappers) — explicitly deferred from Phase 44, belongs in a follow-up phase.
- **Removal of legacy Worker endpoints** (`/api/contribute`, `/api/wiki/append`) — also from Phase 44 deferral list.

</deferred>

---

*Phase: 45-split-agenttools-session-runtime-actor-sandbox-pageparser*
*Context gathered: 2026-05-04*
