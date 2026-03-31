# Roadmap: Cellar

## Milestones

- ✅ **v1.0 Research-Diagnose-Adapt** — Phases 1–7 (shipped 2026-03-28)
- ✅ **v1.1 Agentic Independence** — Phases 8–12 (shipped 2026-03-30)
- 🚧 **v1.2 Collective Agent Memory** — Phases 13–18 (in progress)

## Phases

<details>
<summary>✅ v1.0 Research-Diagnose-Adapt (Phases 1–7) — SHIPPED 2026-03-28</summary>

- [x] **Phase 1: Cossacks Launches** — Full pipeline: dependency check, bottle, recipe, launch, log capture, validation prompt (2026-03-27)
- [x] **Phase 1.1: Reactive Dependencies** (INSERTED) — Try-first/install-on-failure deps, winetricks timeout protection (2026-03-27)
- [x] **Phase 2: AI Intelligence** — AI log interpretation and AI recipe generation (2026-03-27)
- [x] **Phase 3: Repair Loop** — AI-driven retry loop with variant configs (2026-03-27)
- [x] **Phase 3.1: Advanced Repair** (INSERTED) — DLL replacements, registry edits, three-tier escalation system (2026-03-27)
- [x] **Phase 6: Agentic Loop** (INSERTED) — 18-tool agent loop replacing hardcoded LaunchCommand pipeline (2026-03-27)
- [x] **Phase 7: Research-Diagnose-Adapt** (INSERTED) — Web search, diagnostic traces, DLL verification, success database (2026-03-28)

</details>

<details>
<summary>✅ v1.1 Agentic Independence (Phases 8–12) — SHIPPED 2026-03-30</summary>

- [x] **Phase 8: Loop Resilience** — Fix max_tokens truncation bug, retry on transient errors, budget tracking with ceiling
- [x] **Phase 9: Engine Detection and Pre-configuration** — Detect game engine from file patterns and PE imports; pre-configure games before first launch to skip known dialogs
- [x] **Phase 10: Dialog Detection** — Wine trace:msgbox parsing and macOS window list monitoring to detect stuck-on-dialog state
- [x] **Phase 11: Smarter Research** — Actionable fix extraction from web pages, engine-aware search queries, cross-game success matching
- [x] **Phase 12: Web Interface for Game Management** — Browser-based game library management, CRUD, and live agent logs

</details>

### 🚧 v1.2 Collective Agent Memory (In Progress)

**Milestone Goal:** Build a shared knowledge layer so that when any Cellar agent solves a game, every other agent benefits — an agent-first collective memory backed by a Git repo.

- [x] **Phase 13: GitHub App Authentication** — RS256 JWT generation, installation token exchange, automatic refresh before expiry (completed 2026-03-30)
- [ ] **Phase 14: Memory Entry Schema** — Lock the collective memory entry schema and establish the repo structure before any community writes
- [ ] **Phase 15: Read Path** — Agent queries collective memory before diagnosis; environment-aware fit assessment before applying any stored config
- [ ] **Phase 16: Write Path** — Agent pushes configs after confirmed success; confidence accumulation with deduplication; opt-in contribution prompt
- [ ] **Phase 17: Web Memory UI** — Browser views for collective memory stats and per-game memory entries
- [ ] **Phase 18: Deepseek API Support** — Add Deepseek as an additional AI provider alongside Claude; users choose which provider for recipe generation, log interpretation, and the agent loop

## Phase Details

### Phase 8: Loop Resilience
**Goal**: The agent loop is correct and observable — it handles max_tokens truncation without corrupting state, retries transient failures, and reports session cost against a configurable budget
**Depends on**: Phase 7
**Requirements**: LOOP-01, LOOP-02, LOOP-03, LOOP-04
**Success Criteria** (what must be TRUE):
  1. When the API returns stop_reason="max_tokens" with an incomplete tool_use block, the agent retries with doubled max_tokens and does not append the truncated response to message history — the loop continues correctly
  2. When a 5xx or network error occurs, the agent retries up to 3 times with exponential backoff before surfacing the error; 4xx errors (except 429) abort immediately with a clear message
  3. At the end of an agent session, total token usage and estimated cost are printed; a configurable budget ceiling halts the session with a warning at 80% and stops at 100%
  4. When the API returns an empty end_turn response (no tool calls, no text), the agent sends a continuation prompt instead of silently aborting
**Plans:** 2 plans
Plans:
- [ ] 08-01-PLAN.md — Data layer: usage decoding, extended AgentLoopResult, CellarConfig, model ID fix
- [ ] 08-02-PLAN.md — Loop logic: truncation recovery, retry with backoff, budget tracking, empty end_turn, cost display

### Phase 9: Engine Detection and Pre-configuration
**Goal**: The agent detects a game's engine and graphics API from files and PE imports, and pre-configures Wine settings before the first launch to eliminate renderer-selection and first-run dialogs for known engines
**Depends on**: Phase 8
**Requirements**: ENGN-01, ENGN-02, ENGN-03, ENGN-04
**Success Criteria** (what must be TRUE):
  1. The inspect_game tool result includes an engine field with detected engine family (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard), confidence level, detected signals, and a known-config hint
  2. PE import table analysis identifies the primary graphics API (ddraw.dll = DirectDraw, d3d9.dll = DX9, opengl32.dll = OpenGL) and includes it in the inspect_game result
  3. For a recognized engine, the agent writes INI and registry pre-configuration before the first launch attempt — the game directory has the expected ddraw.ini or equivalent without any agent iteration spent diagnosing the dialog
  4. Web search queries constructed after engine detection include engine name and graphics API in addition to game name — search results are visibly more targeted than game-name-only queries
**Plans:** 2 plans
Plans:
- [ ] 09-01-PLAN.md — Engine registry data model, detection logic, inspectGame() extension with binary string extraction
- [ ] 09-02-PLAN.md — System prompt update: engine-aware pre-configuration, search enrichment, success DB cross-referencing

### Phase 10: Dialog Detection
**Goal**: The agent can detect when a Wine game is stuck on a dialog box — via Wine trace:msgbox parsing as the primary signal and macOS window list inspection as an optional complement — and uses the combined signal to distinguish dialog-stuck from running-normally
**Depends on**: Phase 9
**Requirements**: DIAG-01, DIAG-02, DIAG-03
**Success Criteria** (what must be TRUE):
  1. When a Wine program displays a MessageBox, trace_launch captures the dialog title, message text, and type as structured fields in its result — without requiring any additional permissions
  2. When a Wine game is running, the agent can query the macOS window list to report window titles and sizes for Wine processes; when Screen Recording permission is denied, the tool returns bounds and owner name only (no silent failure or crash)
  3. After a launch_game call, the tool result indicates whether the game appeared stuck on a dialog (hybrid signal: dialog_detected from trace:msgbox and/or small-window heuristic from window list), distinct from a crash or normal exit
**Plans**: TBD

### Phase 11: Smarter Research
**Goal**: The agent extracts specific, actionable fixes from web pages rather than raw text dumps, finds cross-game solutions from the success database using engine and API tags, and uses structured HTML parsing via SwiftSoup
**Depends on**: Phase 10
**Requirements**: RSRCH-01, RSRCH-02, RSRCH-03
**Success Criteria** (what must be TRUE):
  1. fetch_page returns an extracted_fixes field containing specific env vars, registry paths, DLL names, winetricks verbs, and INI changes found on the page — not just raw text; raw text_content is still included as fallback
  2. When query_successdb is called with engine type and graphics API tags, it returns solutions from similar games (not just exact game matches) ranked by signal overlap
  3. fetch_page uses SwiftSoup CSS-selector extraction for known sources (WineHQ AppDB, PCGamingWiki, forums) — code blocks, tables, and list items are parsed structurally rather than stripped as plain text
**Plans:** 3/3 plans complete
Plans:
- [ ] 11-01-PLAN.md — SwiftSoup dependency + PageParser protocol, three parser implementations (WineHQ, PCGamingWiki, Generic), ExtractedFixes models, regex extraction
- [ ] 11-02-PLAN.md — Rewrite fetchPage() with SwiftSoup + PageParser, add queryBySimilarity() and similar_games to querySuccessdb()
- [ ] 11-03-PLAN.md — Research Quality methodology in agent system prompt

### Phase 12: Web Interface for Game Management
**Goal**: Users can manage their game library, add/delete games, launch games (directly or with AI agent), and watch real-time agent logs — all from a browser-based web UI served on localhost:8080 via Vapor + HTMX
**Depends on**: Phase 11
**Requirements**: WEB-01, WEB-02, WEB-03, WEB-04, WEB-05
**Success Criteria** (what must be TRUE):
  1. `cellar serve` starts a Vapor web server on localhost:8080 that shares all existing business logic
  2. Users see a card-based game library showing game name, status, and last played date
  3. Users can add games (by installer path) and delete games (with optional bottle cleanup) from the browser
  4. Users can directly launch games with working recipes — Wine output streams to browser via SSE
  5. Users can launch games with AI agent — iteration count, tool calls, reasoning, and cost stream in real-time via SSE
**Plans:** 4/4 plans complete

Plans:
- [ ] 12-01-PLAN.md — Foundation: Vapor + Leaf deps, ServeCommand, WebApp, GameService actor, LaunchService, base.leaf
- [ ] 12-02-PLAN.md — AgentLoop streaming: AgentEvent enum, onOutput callback, replace print() calls
- [ ] 12-03-PLAN.md — Game library CRUD: GameController routes, index/card/add templates, HTMX partials
- [ ] 12-04-PLAN.md — Launch & SSE: LaunchController, direct + agent launch, SSE streaming, launch-log template

### Phase 13: GitHub App Authentication
**Goal**: The agent can authenticate to GitHub as a bot — generating RS256 JWTs, exchanging them for installation tokens, and refreshing those tokens automatically — so that all write operations in later phases have a working auth layer to depend on
**Depends on**: Phase 12
**Requirements**: AUTH-01, AUTH-02
**Success Criteria** (what must be TRUE):
  1. Running `cellar` with GitHub App credentials configured produces a valid installation access token from the GitHub API — no error, no manual steps
  2. After 55 minutes, the agent automatically fetches a fresh installation token without any user intervention or failed API calls
  3. When GitHub App credentials are absent or misconfigured, Cellar degrades gracefully: collective memory reads work (unauthenticated), writes are skipped with a clear message, and the agent loop is not interrupted
**Plans:** 2/2 plans complete

Plans:
- [ ] 13-01-PLAN.md — Data layer: GitHubModels (Codable types, error enum), placeholder resources (PEM + JSON), CellarPaths extension
- [ ] 13-02-PLAN.md — Service layer: GitHubAuthService with RS256 JWT signing, installation token exchange, in-memory cache with 55-min TTL, credential cascade, graceful degradation

### Phase 14: Memory Entry Schema
**Goal**: The collective memory entry schema is locked and the community repo structure is established — every field is specified, versioned, and forward-compatible before any entries are written
**Depends on**: Phase 13
**Requirements**: SCHM-01, SCHM-02, SCHM-03
**Success Criteria** (what must be TRUE):
  1. A `CollectiveMemoryEntry` value round-trips through JSON encode/decode with all fields intact — working config, reasoning chain, environment fingerprint (arch, Wine version, macOS version, Wine flavor), and schema version
  2. The collective memory repo contains an `entries/` directory where each game has one file at `entries/{game-id}.json` holding an array of entries from different agents
  3. A JSON file with unknown fields (simulating a future schema version) decodes without error — unknown fields are ignored and optional fields default gracefully
**Plans:** 1 plan

Plans:
- [ ] 14-01-PLAN.md — Schema types (CollectiveMemoryEntry, WorkingConfig, EnvironmentFingerprint), slugify(), environment hash, round-trip + forward-compat tests

### Phase 15: Read Path
**Goal**: The agent queries collective memory before starting diagnosis and reasons about whether a stored config fits the local environment — so that agents on new machines benefit from prior solutions without blindly applying them
**Depends on**: Phase 14
**Requirements**: READ-01, READ-02, READ-03
**Success Criteria** (what must be TRUE):
  1. When launching a game that has a collective memory entry, the agent's initial message includes the stored config and reasoning chain as context — before any tool calls are made
  2. The agent's reasoning explicitly compares the stored entry's environment (arch, Wine version, macOS version) against the local environment before applying any config — entries for a different CPU arch are flagged as incompatible, not silently applied
  3. When the local Wine major version is more than one ahead of the version recorded in the entry's last confirmation, the agent flags the entry as potentially stale in its reasoning
  4. When collective memory is unavailable (network down, repo not configured), the agent proceeds with normal diagnosis — no error is surfaced to the user and launch is not blocked
**Plans**: TBD

### Phase 16: Write Path
**Goal**: After a user confirms a game reached the menu, the agent automatically pushes the working config and reasoning chain to collective memory — and if an entry already exists for that game and environment, increments the confirmation count rather than creating a duplicate
**Depends on**: Phase 15
**Requirements**: WRIT-01, WRIT-02, WRIT-03
**Success Criteria** (what must be TRUE):
  1. After a user answers "yes" to the launch validation prompt, a new or updated entry appears in the collective memory repo within the same session — no manual action required
  2. When a second agent on a different machine confirms the same config for the same game, the existing entry's confirmation count increments and no duplicate entry is created — deduplication is by environment hash
  3. On first run, the user sees a prompt asking whether to contribute working configs to the community; their choice is saved to config and not asked again; contribution can be toggled later
  4. When a push fails (network error, conflict), the failure is logged and the agent session completes normally — the user's success confirmation is not blocked or re-prompted
**Plans**: TBD

### Phase 17: Web Memory UI
**Goal**: The web interface surfaces collective memory state — how many games are covered, recent contributions, and per-game entry details — giving users transparency into what the community has solved
**Depends on**: Phase 16
**Requirements**: WEBM-01, WEBM-02
**Success Criteria** (what must be TRUE):
  1. Navigating to `/memory` in the web UI shows aggregate stats: total games covered, total confirmations across all entries, and recent contributions
  2. Clicking a game in the memory view shows its individual entries with environment details (arch, Wine version, macOS version) and confidence scores (confirmation count)
  3. The memory views load without error when the collective memory repo is unreachable — they degrade to an empty state with an explanatory message, not a 500 error
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 13 → 14 → 15 → 16 → 17 → 18

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–7. v1.0 phases | v1.0 | All complete | Complete | 2026-03-28 |
| 8. Loop Resilience | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Engine Detection and Pre-configuration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. Dialog Detection | v1.1 | 2/2 | Complete | 2026-03-29 |
| 11. Smarter Research | v1.1 | 3/3 | Complete | 2026-03-29 |
| 12. Web Interface for Game Management | v1.1 | 4/4 | Complete | 2026-03-30 |
| 13. GitHub App Authentication | 2/2 | Complete    | 2026-03-30 | - |
| 14. Memory Entry Schema | v1.2 | 0/? | Not started | - |
| 15. Read Path | v1.2 | 0/? | Not started | - |
| 16. Write Path | v1.2 | 0/? | Not started | - |
| 17. Web Memory UI | v1.2 | 0/? | Not started | - |
| 18. Deepseek API Support | 1/2 | In Progress|  | - |

### Phase 18: Deepseek API Support
**Goal**: Users can choose Deepseek as an alternative AI provider to Claude for recipe generation, log interpretation, and the full agent loop — with provider selection in config and the web settings UI
**Depends on**: Phase 17
**Requirements**: DSPK-01, DSPK-02, DSPK-03
**Success Criteria** (what must be TRUE):
  1. When `AI_PROVIDER=deepseek` is set in config or .env, Cellar uses the Deepseek API for all AI operations (recipe generation, log interpretation, agent loop) instead of Claude
  2. The web settings page allows selecting the active AI provider and entering the Deepseek API key
  3. When the configured provider's API key is missing, Cellar shows a clear error message naming the provider — not a generic "API key missing"
**Plans:** 1/2 plans executed

Plans:
- [ ] 18-01-PLAN.md — Provider protocol + Anthropic and Deepseek implementations + OpenAI tool-use types
- [ ] 18-02-PLAN.md — AgentLoop refactor to use provider, AIService routing, CellarConfig, settings UI
