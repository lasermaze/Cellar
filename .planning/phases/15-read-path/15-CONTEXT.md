# Phase 15: Read Path - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

The agent queries collective memory before starting diagnosis and reasons about whether a stored config fits the local environment. Agents on new machines benefit from prior solutions without blindly applying them. Writing to collective memory is Phase 16.

</domain>

<decisions>
## Implementation Decisions

### Memory injection
- Pre-fetch memory before spawning AgentLoop — extend AIService.swift:784 initial message construction
- Full entry dump: include complete WorkingConfig + reasoning + environment as structured text in the initial message
- System prompt instructs agent: "A community-verified config exists. Try it first before researching from scratch."
- Agent launches only — direct launches use existing recipe/success record path, no memory lookup

### Environment matching
- Arch mismatch (arm64 vs x86_64) is hard incompatible — entry is dropped entirely, not shown to agent
- Wine version staleness: major version only — flag when local major version is >1 ahead of entry's last confirmation (e.g., Wine 9.x entry on Wine 11.x)
- Wine flavor (game-porting-toolkit vs regular Wine) is a soft factor — different flavor gets a warning annotation but entry is still shown
- All filtering happens in code (pre-agent), not in agent reasoning — agent gets clean, pre-assessed data

### Multi-entry handling
- Best match only — pick the single entry with the highest confirmations count (tiebreaker: closest Wine version)
- If no entries pass the arch filter, skip entirely — no memory context, agent proceeds with normal R-D-A
- No "all compatible" or "top 3" — one clear recommendation

### Failure behavior
- Silent skip when collective memory is unreachable (network, auth, API error) — log internally, user never sees an error
- 5-second timeout on the GitHub Contents API fetch
- No local caching — always fetch fresh from GitHub on each agent launch

### Claude's Discretion
- Exact format of the memory context block in the initial message
- System prompt wording for "try stored config first" instruction
- Internal logging format for silent skip
- How to extract major version number from Wine version string

</decisions>

<specifics>
## Specific Ideas

- Integration point is AIService.swift line 784 where `initialMessage` is built — memory context appended here
- Use `slugify(entry.name)` to construct `entries/{slug}.json` path for GitHub Contents API GET
- Use `GitHubAuthService.shared.getToken()` for auth — if `.unavailable`, silent skip
- Ranking: filter by arch → sort by confirmations desc → tiebreak by Wine version proximity → take first
- The agent's initial message should clearly separate the memory context from the launch instruction so the agent can reason about it

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `GitHubAuthService.shared.getToken()`: returns `.success(token)` or `.unavailable` — ready-made auth with graceful degradation
- `GitHubAuthService.shared.memoryRepo`: repo slug for Contents API calls
- `CollectiveMemoryEntry` + `WorkingConfig` + `EnvironmentFingerprint`: full schema from Phase 14
- `slugify()`: deterministic game ID → file path mapping
- `EnvironmentFingerprint.current(wineVersion:wineFlavor:)`: captures local environment for comparison

### Established Patterns
- URLSession + DispatchSemaphore for synchronous HTTP calls (AIService, GitHubAuthService)
- Codable JSON decoding for API responses (AnthropicToolResponse, GitHubModels)
- Graceful degradation: GitHubAuthService already returns .unavailable cleanly

### Integration Points
- `AIService.runAgentLoop()` at line 784: initialMessage construction — append memory context here
- GitHub Contents API: `GET /repos/{memoryRepo}/contents/entries/{slug}.json` with Accept: application/vnd.github.v3.raw
- `EnvironmentFingerprint.current()` for local environment capture (needs wineVersion/wineFlavor from existing WineProcess detection)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 15-read-path*
*Context gathered: 2026-03-30*
