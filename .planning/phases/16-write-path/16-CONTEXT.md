# Phase 16: Write Path - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

After a user confirms a game reached the menu (successful agent launch), the agent's working config is automatically pushed to the collective memory repo — or if a matching entry already exists, the confirmation count is incremented. Users opt in on first push opportunity. Writing only happens for agent launches, not direct launches with existing recipes. Reading collective memory is Phase 15; web interface for memory is Phase 17.

</domain>

<decisions>
## Implementation Decisions

### Contribution trigger
- Push happens post-loop in AIService, after the agent loop exits and taskState == .savedAfterConfirm
- Trigger is tied to user confirmation that the game actually launched (the "did the game reach the menu?" prompt)
- Agent launches only — direct launches with existing recipes do not push (no new data to contribute)
- Data source: load the just-saved SuccessRecord from local SuccessDatabase, transform to CollectiveMemoryEntry
- Synchronous push — completes before AIService returns, consistent with existing sync HTTP patterns (5s timeout max per request, 10s total for write flow)

### Opt-in flow
- Prompt appears on first successful push opportunity (user just confirmed a game works, before pushing)
- Simple yes/no: "Share this working config with the Cellar community? Other users will benefit when setting up this game. [y/N]"
- Default: no (user must explicitly opt in)
- Stored in CellarConfig as `contributeMemory: Bool?` — nil = not asked yet, true/false = decided
- Also toggleable in web settings page alongside AI provider selection
- Preference checked before every push — if nil, prompt; if false, skip silently; if true, push

### Merge & conflict handling
- Same environmentHash already exists in the file → increment confirmations count + update lastConfirmed timestamp. No new entry appended.
- Different environmentHash → append new entry to the array
- New game (file doesn't exist / 404) → create new file with single-entry array
- On 409 conflict: re-fetch latest version, re-apply merge logic, PUT again with new SHA. One retry only — if it conflicts again, give up silently.
- Separate read-for-write method (GET with standard JSON Accept header, returns SHA + content) for the merge flow. Read path keeps its raw mode.
- Commit messages: "Add {game-name} entry" for new files, "Update {game-name} (+1 confirmation)" or "Update {game-name} (new environment)" for updates

### Failure resilience
- Silent skip on any push failure (network, auth, timeout, conflict after retry) — user sees nothing
- Failure logged internally to ~/.cellar/logs/ for debugging
- No queue, no retry-on-next-launch — fire and forget. Next successful launch will push fresh data anyway.
- 10-second timeout for the full write operation (GET + merge + PUT)
- Local SuccessRecord save is completely independent — happens first in save_success, GitHub push is a separate optional step after agent loop exits

### Claude's Discretion
- Exact structure of CollectiveMemoryWriteService (or extend existing CollectiveMemoryService)
- How to extract Wine version and flavor for EnvironmentFingerprint construction at push time
- Internal logging format for push success/failure
- SuccessRecord → CollectiveMemoryEntry transformation details (field mapping)
- Whether opt-in prompt uses print/readLine or goes through a helper

</decisions>

<specifics>
## Specific Ideas

- Integration point is AIService.runAgentLoop() after the agent loop returns and before the method returns to caller
- Flow: agent loop exits → check taskState == .savedAfterConfirm → check CellarConfig.contributeMemory → if nil, prompt → if true, load SuccessRecord → transform → push
- GitHub Contents API PUT: `PUT /repos/{memoryRepo}/contents/entries/{slug}.json` with body `{ "message": "...", "content": base64(...), "sha": "..." }`
- For new files (404 on GET), PUT without SHA field creates the file
- EnvironmentFingerprint.current(wineVersion:wineFlavor:) already exists from Phase 14 — use it to build the fingerprint at push time
- environmentHash from EnvironmentFingerprint.computeHash() for dedup matching

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `CollectiveMemoryService.fetchBestEntry()`: read-path service with GitHub API patterns — write service can follow same auth/HTTP approach
- `GitHubAuthService.shared.getToken()`: returns `.token(String)` or `.unavailable` — same auth for writes
- `SuccessDatabase.load(gameId:)`: loads local SuccessRecord after save_success completes
- `CollectiveMemoryEntry` + `WorkingConfig` + `EnvironmentFingerprint`: full schema from Phase 14
- `slugify()`: game name → file path mapping
- `EnvironmentFingerprint.current(wineVersion:wineFlavor:)`: captures local environment
- `CellarConfig`: existing Codable config with load/save — extend with `contributeMemory` field

### Established Patterns
- URLSession + DispatchSemaphore for synchronous HTTP (CollectiveMemoryService, GitHubAuthService)
- GitHub API headers: `Authorization: Bearer {token}`, `X-GitHub-Api-Version: 2022-11-28`
- Silent degradation: read path returns nil on any failure, write path should follow same pattern
- CellarConfig priority: env var > ~/.cellar/config.json > default

### Integration Points
- `AIService.runAgentLoop()`: after agent loop returns `.success` with taskState == .savedAfterConfirm — hook write-back here
- `AgentTools.taskState`: tracks `.savedAfterConfirm` for trigger condition
- `SuccessRecord` fields map to `CollectiveMemoryEntry`: environment → config.environment, dllOverrides → config.dllOverrides, registry → config.registry, resolutionNarrative → reasoning, engine → engine, graphicsApi → graphicsApi
- Web settings (SettingsController): add contributeMemory toggle alongside existing aiProvider and budgetCeiling controls

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 16-write-path*
*Context gathered: 2026-03-30*
