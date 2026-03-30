# Phase 14: Memory Entry Schema - Context

**Gathered:** 2026-03-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Lock the collective memory entry schema and establish the community repo structure. Define all types (CollectiveMemoryEntry, WorkingConfig, EnvironmentFingerprint), the slugify function for game IDs, and a static factory for environment detection. No reads or writes to GitHub — those are Phase 15 and 16.

</domain>

<decisions>
## Implementation Decisions

### Entry fields
- Minimal entry: working config + environment fingerprint + reasoning summary + metadata (no full SuccessRecord mirror)
- WorkingConfig contains: environment vars, DLL overrides, registry edits, launch args, setup deps
- Reasoning is a single summary string (natural language paragraph), not a structured step array
- Engine and graphicsApi included as optional top-level fields (enables cross-game matching in Phase 15)
- Game file is a flat JSON array of entries — no grouping by environment hash in the file structure
- Entries include: schemaVersion, gameId (slug), gameName, config, environment, environmentHash, reasoning, engine?, graphicsApi?, confirmations, lastConfirmed

### Game ID strategy
- Slugified game name: lowercase, strip special chars, hyphens for spaces, collapse multiples
- Slugify function owned by the schema module (not reusing GameEntry.id which is user-local)
- File path: `entries/{slug}.json`
- Collisions accepted — entries differentiated by environment fingerprint, not filename
- gameName field preserves original display name alongside the slug

### Forward compatibility
- Integer schemaVersion per entry (matches SuccessRecord pattern), starting at 1
- Unknown fields silently ignored by Swift JSONDecoder (default behavior, SCHM-03 satisfied)
- Entries with higher schemaVersion still used if all required v1 fields decode — schemaVersion is informational, not a gate
- Bump version only when adding new required fields; optional fields added freely

### Environment fingerprint
- 4 fields: arch (arm64/x86_64), wineVersion, macosVersion, wineFlavor
- Full version strings stored (e.g., "9.0.2" not "9.0") — precision retained, Phase 15 agent reasoning handles compatibility judgment
- SHA-256 hash (16-char hex prefix) of sorted canonical fields for dedup (stored as environmentHash)
- Static factory method `EnvironmentFingerprint.current(wineVersion:wineFlavor:)` captures arch and macOS version automatically

### Claude's Discretion
- Exact field naming conventions (camelCase Swift vs snake_case JSON via CodingKeys)
- Whether to use a single file or separate files for types (CollectiveMemoryEntry.swift vs split)
- Hash truncation length (16 hex chars recommended but flexible)
- Test approach for round-trip encoding/decoding

</decisions>

<specifics>
## Specific Ideas

- Flat array per game file: `entries/cossacks-european-wars.json` contains `[entry1, entry2, ...]`
- Slugify must be deterministic across all clients — same name always produces same slug
- `EnvironmentFingerprint.current()` detects arch via `uname -m` equivalent and macOS version via system APIs; Wine version and flavor are passed in (already known from WineProcess)
- Environment hash canonical format: `"arch=arm64|macosVersion=15.3.1|wineFlavor=game-porting-toolkit|wineVersion=9.0.2"` (sorted keys, pipe-separated)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `SuccessRecord` in SuccessDatabase.swift: existing schema with DLL overrides, registry, env vars, pitfalls — WorkingConfig mirrors a subset
- `GitHubModels.swift`: recently created Codable patterns with CodingKeys for snake_case mapping
- `GameEntry.swift`: game identity model (id, name, installPath) — gameName field can be derived from GameEntry.name
- `CellarPaths.defaultMemoryRepo`: centralized repo slug constant

### Established Patterns
- Codable structs with CodingKeys for JSON snake_case mapping (all models follow this)
- schemaVersion integer in SuccessRecord — same pattern for CollectiveMemoryEntry
- SuccessDatabase stores per-game JSON files at `~/.cellar/successdb/{gameId}.json` — analogous to `entries/{slug}.json`
- All models in Sources/cellar/Models/

### Integration Points
- Phase 15 (Read Path) will decode `CollectiveMemoryEntry` arrays from GitHub Contents API responses
- Phase 16 (Write Path) will encode entries and use environmentHash for dedup before PUT
- `EnvironmentFingerprint.current()` will be called by Phase 16's write flow with wineVersion/wineFlavor from WineProcess
- AgentTools.swift line ~1956 constructs SuccessRecord — Phase 16 will construct CollectiveMemoryEntry similarly

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 14-memory-entry-schema*
*Context gathered: 2026-03-30*
