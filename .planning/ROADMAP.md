# Roadmap: Cellar

## Milestones

- ✅ **v1.0 Research-Diagnose-Adapt** — Phases 1–7 (shipped 2026-03-28)
- ✅ **v1.1 Agentic Independence** — Phases 8–12 (shipped 2026-03-30)
- ✅ **v1.2 Collective Agent Memory** — Phases 13–30 (shipped 2026-04-03)
- 🚧 **v1.3 Agent Loop Rewrite** — Phases 31–36 (in progress)

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

<details>
<summary>✅ v1.2 Collective Agent Memory (Phases 13–30) — SHIPPED 2026-04-03</summary>

- [x] **Phase 13: GitHub App Authentication** — RS256 JWT generation, installation token exchange, automatic refresh before expiry (completed 2026-03-30)
- [x] **Phase 14: Memory Entry Schema** — Lock the collective memory entry schema and establish the repo structure before any community writes (completed 2026-03-31)
- [x] **Phase 15: Read Path** — Agent queries collective memory before diagnosis; environment-aware fit assessment before applying any stored config (completed 2026-03-31)
- [x] **Phase 16: Write Path** — Agent pushes configs after confirmed success; confidence accumulation with deduplication; opt-in contribution prompt (completed 2026-03-31)
- [x] **Phase 17: Web Memory UI** — Browser views for collective memory stats and per-game memory entries (completed 2026-03-31)
- [x] **Phase 18: Deepseek API Support** — Add Deepseek as an additional AI provider alongside Claude (completed 2026-03-31)
- [x] **Phase 19: Import Lutris and ProtonDB compatibility databases** — Unified compatibility lookup tool with pre-diagnosis context injection (completed 2026-03-31)
- [x] **Phase 20: Smarter Wine log parsing and structured diagnostics** — Subsystem-grouped diagnostic engine with causal chains, noise filtering, trend tracking (completed 2026-03-31)
- [x] **Phase 21: Pre-flight dependency check from PE imports** — (completed)
- [x] **Phase 22: Seamless macOS UX** — Pre-flight permissions, game removal, actionable errors, first-run setup (completed 2026-04-01)
- [x] **Phase 23: Homebrew tap distribution with launcher .app** — Zero-friction install via brew, CI-built binary, post-install .app wrapper (completed 2026-04-02)
- [x] **Phase 24: Architecture and Code Quality Cleanup** — Async/await migration, AgentTools decomposition, KnownDLLRegistry expansion (completed 2026-04-02)
- [x] **Phase 25: Kimi model support** — Add Kimi (Moonshot AI) as AI provider (completed 2026-04-02)
- [x] **Phase 26: ISO disc image support for game installation** — Mount .iso/.bin/.cue, detect installer, run through existing pipeline (completed 2026-04-02)
- [x] **Phase 27: Distribution — GitHub Releases and Install Script** — Single-command install via curl|bash, release CI cleanup (completed 2026-04-02)
- [x] **Phase 28: Fix Collective Memory Prompt Injection Vulnerability** — Sanitize fields, allowlist env/registry, CSRF protection, .env permissions (completed 2026-04-02)
- [x] **Phase 29: Secure collective memory — Cloudflare Worker write proxy, remove bundled private key** — Public repo anonymous reads, server-side validation, GitHubAuthService deleted (completed 2026-04-03)
- [x] **Phase 30: Smart game name matching** — (placeholder, unused)

</details>

### 🚧 v1.3 Agent Loop Rewrite (In Progress)

**Milestone Goal:** Fix critical bugs in the agent loop (race conditions, unresponsive stop, lost saves) and modernize the architecture with typed results, thread-safe control, a middleware system, and structured event logging — so the loop is correct, observable, and maintainable.

- [ ] **Phase 31: New Types** — ToolResult enum, AgentControl, LoopState, expanded AgentStopReason
- [ ] **Phase 32: Middleware System** — AgentMiddleware protocol, BudgetTracker, SpinDetector, EventLogger, JSONL event log
- [ ] **Phase 33: Rewrite the Loop** — New run() signature, extracted helpers, clean endTurn semantics, ≤150-line body
- [ ] **Phase 34: Update AgentTools** — execute() returns ToolResult, remove bare vars, post-loop save logic
- [ ] **Phase 35: Wire It Together** — AIService, ActiveAgents, LaunchController, prepareStep integration
- [ ] **Phase 36: Event Log Resume and SessionHandoff Integration** — Resume summary from event log, SessionHandoff fallback

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
**Plans:** 1/1 plans complete

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
**Plans:** 2/2 plans complete
Plans:
- [ ] 16-01-PLAN.md — CollectiveMemoryWriteService (GET+merge+PUT), CellarConfig contributeMemory, AIService post-loop hook with opt-in prompt
- [ ] 16-02-PLAN.md — Web settings toggle for collective memory contribution

### Phase 17: Web Memory UI
**Goal**: The web interface surfaces collective memory state — how many games are covered, recent contributions, and per-game entry details — giving users transparency into what the community has solved
**Depends on**: Phase 16
**Requirements**: WEBM-01, WEBM-02
**Success Criteria** (what must be TRUE):
  1. Navigating to `/memory` in the web UI shows aggregate stats: total games covered, total confirmations across all entries, and recent contributions
  2. Clicking a game in the memory view shows its individual entries with environment details (arch, Wine version, macOS version) and confidence scores (confirmation count)
  3. The memory views load without error when the collective memory repo is unreachable — they degrade to an empty state with an explanatory message, not a 500 error
**Plans:** 1/1 plans complete
Plans:
- [ ] 17-01-PLAN.md — MemoryStatsService, MemoryController, memory.leaf + memory-game.leaf templates, nav link

### Phase 18: Deepseek API Support
**Goal**: Users can choose Deepseek as an alternative AI provider to Claude for recipe generation, log interpretation, and the full agent loop — with provider selection in config and the web settings UI
**Depends on**: Phase 17
**Requirements**: DSPK-01, DSPK-02, DSPK-03
**Success Criteria** (what must be TRUE):
  1. When `AI_PROVIDER=deepseek` is set in config or .env, Cellar uses the Deepseek API for all AI operations (recipe generation, log interpretation, agent loop) instead of Claude
  2. The web settings page allows selecting the active AI provider and entering the Deepseek API key
  3. When the configured provider's API key is missing, Cellar shows a clear error message naming the provider — not a generic "API key missing"
**Plans:** 2/2 plans complete

Plans:
- [ ] 18-01-PLAN.md — Provider protocol + Anthropic and Deepseek implementations + OpenAI tool-use types
- [ ] 18-02-PLAN.md — AgentLoop refactor to use provider, AIService routing, CellarConfig, settings UI

### Phase 19: Import Lutris and ProtonDB compatibility databases

**Goal:** Give the agent access to Lutris and ProtonDB community compatibility data so it can make better config decisions before and during diagnosis — a single unified lookup queries both sources, extracts actionable config hints, and injects them into the agent's context with a new on-demand tool available during diagnosis
**Requirements**: COMPAT-01, COMPAT-02, COMPAT-03
**Depends on:** Phase 18
**Plans:** 2/2 plans complete

Plans:
- [ ] 19-01-PLAN.md — CompatibilityService data layer: Lutris + ProtonDB API fetch, cache, fuzzy name matching, Proton flag filtering, formatted context output
- [ ] 19-02-PLAN.md — Agent integration: query_compatibility tool, system prompt guidance, pre-diagnosis context injection in AIService

### Phase 20: Smarter Wine log parsing and structured diagnostics

**Goal:** Upgrade Wine log parsing from a flat 5-pattern array to a structured, subsystem-grouped diagnostic engine with positive success signals, causal chain detection, noise filtering, and cross-launch trend tracking — so the agent sees organized signal instead of raw noise and can evaluate whether its fixes are working
**Requirements**: DIAG-01, DIAG-02, DIAG-03, DIAG-04
**Depends on:** Phase 19
**Plans:** 2/2 plans complete

Plans:
- [ ] 20-01-PLAN.md — Parser expansion: WineDiagnostics types, 4 new subsystems, success signals, causal chains, noise filtering
- [ ] 20-02-PLAN.md — Integration: wire diagnostics into launchGame/traceLaunch/readLog, cross-launch tracking, previous-session injection, system prompt update

### Phase 21: Pre-flight dependency check from PE imports

**Goal:** [To be planned]
**Requirements**: TBD
**Depends on:** Phase 20
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 21 to break down)

### Phase 22: Seamless macOS UX

**Goal:** Remove every friction point between "user opens Cellar" and "game is running" — pre-flight permission detection with deep links, first-run auto-setup that eliminates manual dependency commands, game removal with full bottle cleanup, the hardcoded GOG path fix, and actionable error messages throughout — so that a non-technical user never has to leave the app to figure out what went wrong
**Depends on:** Phase 21
**Requirements**: UX-01, UX-02, UX-03, UX-04, UX-05
**Success Criteria** (what must be TRUE):
  1. Before launching a game, a pre-flight check surfaces missing Screen Recording permission with macOS deep links — the user resolves it in one pass, not across multiple failed launch attempts (Accessibility deferred: no current code uses Accessibility API)
  2. On first `cellar add` or web UI visit with missing dependencies, Cellar detects and offers inline installation with progress — no need to run `cellar status` first
  3. `cellar remove <game-id>` deletes the bottle, logs, recipes, success records, and registry entry; the web UI delete button does the same with confirmation
  4. LaunchCommand resolves executables from `entry.executablePath` and BottleScanner — the hardcoded GOG path is gone
  5. Every user-facing error message includes a concrete "Try this:" suggestion with a command or action to take
**Plans:** 3/3 plans complete

Plans:
- [ ] 22-01-PLAN.md — Pre-flight permission check + actionable error messages
- [ ] 22-02-PLAN.md — Game removal (CLI `cellar remove` + web delete upgrade)
- [ ] 22-03-PLAN.md — First-run auto-setup + hardcoded GOG path fix

### Phase 23: Homebrew tap distribution with launcher .app

**Goal:** Users install Cellar with a single `brew install` command that bypasses all Gatekeeper friction — a Homebrew tap repo hosts the formula, GitHub Actions builds release binaries, and a post-install step creates a minimal launcher `.app` in /Applications that starts `cellar serve` and opens the browser on double-click
**Depends on:** Phase 22
**Requirements**: DIST-01, DIST-02, DIST-03
**Success Criteria** (what must be TRUE):
  1. `brew tap <org>/cellar && brew install cellar` downloads a pre-built binary from GitHub Releases, installs it to the Homebrew bin, and the `cellar` command works immediately — no Xcode or Swift toolchain required on the user's machine
  2. GitHub Actions workflow builds a universal (arm64 + x86_64) release binary on every tagged push, uploads it to GitHub Releases, and updates the bottle hash in the formula
  3. After `brew install`, a `Cellar.app` exists in /Applications that on double-click starts `cellar serve` (if not already running) and opens `http://127.0.0.1:8080` in the default browser — no terminal interaction required for subsequent use
**Plans:** 2/2 plans complete

Plans:
- [ ] 23-01-PLAN.md — GitHub Actions release workflow + Homebrew tap formula with post_install .app creation
- [ ] 23-02-PLAN.md — `cellar install-app` subcommand for copying .app to ~/Applications

### Phase 24: Architecture & Code Quality Cleanup

**Goal:** Modernize codebase architecture — migrate to async/await, break up monoliths, expand registries, improve error reporting, and audit dependency weight.
**Requirements**: Swift async/await migration, AgentTools decomposition, KnownDLLRegistry expansion, GitHub API error reporting, Vapor dependency audit
**Depends on:** Phase 23
**Plans:** 3/3 plans complete

Key deliverables:
1. Replace DispatchSemaphore HTTP client with native async/await; remove @unchecked Sendable hacks
2. Split AgentTools.swift (2,500+ lines) into logical tool category files
3. Audit Vapor/Leaf dependency weight vs. lighter alternatives
4. Expand KnownDLLRegistry beyond the single cnc-ddraw entry (dgVoodoo2, dxwrapper, DXVK, etc.)
5. Add proper error reporting to CollectiveMemoryService/GitHubAuthService (replace silent nil returns)

Plans:
- [x] TBD (run /gsd:plan-phase 24 to break down) (completed 2026-04-02)

### Phase 25: Kimi model support

**Goal:** Add Kimi (Moonshot AI) as a supported AI provider alongside Claude and Deepseek — API integration, model detection, provider selection, and agent loop compatibility.
**Requirements**: Kimi API integration, AIProvider enum extension, AIService provider detection, AgentLoopProvider Kimi implementation, .env/config support
**Depends on:** Phase 24
**Plans:** 2/2 plans complete

Plans:
- [x] 25-01-PLAN.md — Add Kimi (Moonshot AI) as full AI provider: .kimi enum case, KimiAgentProvider, detectProvider cascade, callKimi(), error messages (completed 2026-04-02)

### Phase 26: ISO disc image support for game installation

**Goal:** Support .iso, .bin/.cue, and other disc image formats in `cellar add` — mount, detect installer, run through existing bottle/recipe pipeline, unmount.
**Requirements**: ISO/BIN/CUE detection in AddCommand, disc image mounting, installer discovery within mounted volumes, cleanup/unmount after install
**Depends on:** Phase 25
**Plans:** 2/2 plans complete

Plans:
- [ ] 26-01-PLAN.md -- DiscImageHandler struct: mount/discover/detach logic for .iso/.bin/.cue via hdiutil
- [ ] 26-02-PLAN.md -- AddCommand integration: disc image detection, routing, volume label naming, defer cleanup

### Phase 27: Distribution — GitHub Releases + Install Script

**Goal:** Make Cellar installable with a single command — clean up release CI workflow (checksum, smoke test, remove Homebrew step), create install.sh script (detect system, download, verify, install to ~/.cellar/bin, update PATH).
**Requirements**: Release workflow cleanup (checksum + smoke test), install.sh script (system detection, download, checksum verify, PATH update, idempotent), no Swift source changes
**Depends on:** Phase 26
**Plans:** 2/2 plans complete

Plans:
- [ ] 27-01-PLAN.md -- Release workflow cleanup: remove Homebrew step, add checksum + smoke test, enable auto release notes
- [ ] 27-02-PLAN.md -- install.sh script: macOS detection, GitHub API version fetch, download, checksum verify, PATH update, idempotent

### Phase 28: Fix Collective Memory Prompt Injection Vulnerability

**Goal:** Close prompt injection attack chain in collective memory — remove reasoning from agent prompt, allowlist env keys and registry prefixes on read+write, sanitize all injectable fields, update system prompt to treat memory as untrusted, add CSRF protection, set .env file permissions.
**Requirements**: Remove reasoning injection, env key allowlist (shared read+write), registry prefix validation, field truncation/sanitization, system prompt update, CSRF Origin middleware, .env chmod 600
**Depends on:** Phase 27
**Plans:** 2/2 plans complete

Plans:
- [ ] 28-01-PLAN.md — Shared env allowlist, reasoning removal, sanitizeEntry() helper, write-side env+registry validation
- [ ] 28-02-PLAN.md — System prompt hardening, CSRF Origin middleware, .env chmod 600

### Phase 29: Secure collective memory — Cloudflare Worker write proxy, remove bundled private key

**Goal:** Remove the bundled GitHub App private key from the binary. Make the memory repo public (anonymous reads, no auth). Route writes through a Cloudflare Worker that holds the key as a secret and validates entries server-side. Delete GitHubAuthService and all bundled credentials.
**Requirements**: Public repo anonymous reads, Cloudflare Worker write proxy with server-side validation, remove github-app.pem and github-app.json from binary, delete GitHubAuthService, local read cache with TTL, configurable proxy URL
**Depends on:** Phase 28
**Plans:** 3/3 plans complete

Plans:
- [x] TBD (run /gsd:plan-phase 29 to break down) (completed 2026-04-03)

### Phase 30: Smart game name matching — strip version numbers and prefixes from installer filenames

**Goal:** [To be planned — placeholder, unused in v1.2]
**Requirements**: TBD
**Depends on:** Phase 29
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd:plan-phase 30 to break down)

### Phase 31: New Types
**Goal**: The foundational types for the new agent loop architecture exist and compile — ToolResult enum, AgentControl thread-safe channel, LoopState struct, and expanded AgentStopReason replace the old string matching and bare-var patterns
**Depends on**: Phase 30
**Requirements**: ARCH-01, ARCH-02, ARCH-03, BUG-04
**Success Criteria** (what must be TRUE):
  1. Tool execution results are expressed as a `ToolResult` enum (success/stop/error) — no string matching on "STOP": true anywhere in the control flow
  2. Web routes can call `AgentControl.abort()` and `AgentControl.confirm()` from any thread without data races — the underlying flags are protected by a lock
  3. All mutable loop state (iteration count, token totals, cost, max tokens) lives in one `LoopState` struct — no scattered local vars across the loop body
  4. `AgentStopReason` includes userAborted, userConfirmed, budgetExhausted, maxIterations, completed, and apiError cases — callers distinguish why the loop stopped
**Plans**: TBD

### Phase 32: Middleware System
**Goal**: The middleware system and JSONL event log exist as independent, composable units — BudgetTracker, SpinDetector, and EventLogger are implemented against the AgentMiddleware protocol, and the event log appends structured records to disk
**Depends on**: Phase 31
**Requirements**: MW-01, MW-02, MW-03, MW-04, LOG-01, LOG-02
**Success Criteria** (what must be TRUE):
  1. The `AgentMiddleware` protocol is defined with `beforeTool`, `afterTool`, and `afterStep` hooks — any middleware can be added or removed without touching the loop body
  2. After an agent session, the JSONL file at `~/.cellar/logs/<gameId>-<timestamp>.jsonl` contains one record per event including sessionStarted, llmCalled, toolInvoked, toolCompleted, budgetWarning, spinDetected, and sessionEnded
  3. `BudgetTracker` middleware fires warnings at 50% and 80% of the budget ceiling and halts at 100% — the loop body contains none of this threshold logic
  4. `SpinDetector` middleware identifies repeating tool call patterns and injects a pivot nudge message — spin detection is not inline in the loop
**Plans**: TBD

### Phase 33: Rewrite the Loop
**Goal**: The main agent loop body is ≤150 lines, delegates all cross-cutting concerns to middleware, handles endTurn as a clean stop with no tug-of-war, and provides a prepareStep hook for per-iteration adjustments
**Depends on**: Phase 32
**Requirements**: ARCH-04, BUG-03
**Success Criteria** (what must be TRUE):
  1. `AgentLoop.run()` is ≤150 lines — no inline budget tracking, spin detection, or logging logic anywhere in the body
  2. When the LLM returns `endTurn`, the loop exits immediately — there is no retry-on-endTurn logic and no scenario where the agent is forced to continue after deciding to stop
  3. The `prepareStep` hook is called at the start of each iteration before the LLM call — callers can inject messages or trim context without modifying the loop
  4. The new loop signature accepts `AgentControl` and a middleware chain — it does not read bare vars from AgentTools
**Plans**: TBD

### Phase 34: Update AgentTools
**Goal**: AgentTools.execute() returns a typed ToolResult, all bare synchronization vars (shouldAbort, userForceConfirmed, taskState) are removed, and the post-loop save is the single save path with no fire-and-forget
**Depends on**: Phase 33
**Requirements**: ARCH-01, BUG-01
**Success Criteria** (what must be TRUE):
  1. `AgentTools.execute()` returns `ToolResult` — no caller reads a raw String and pattern-matches on "STOP" anywhere
  2. AgentTools has no `shouldAbort`, `userForceConfirmed`, or `taskState` vars — these are gone from the type entirely
  3. When a user clicks "Game Works" in the web UI, the memory save completes with `await` before the session ends — no fire-and-forget Task, no race between two save paths
**Plans**: TBD

### Phase 35: Wire It Together
**Goal**: AIService, ActiveAgents, and LaunchController are updated to use AgentControl and the middleware chain — web routes call AgentControl methods, the stop button halts the agent within one iteration, and prepareStep is available for context injection
**Depends on**: Phase 34
**Requirements**: INT-01, INT-02, INT-03, INT-04, BUG-02
**Success Criteria** (what must be TRUE):
  1. `AIService.runAgentLoop()` creates the middleware chain, event log, and AgentControl; performs post-loop save with `await`; no fire-and-forget anywhere in the call site
  2. `ActiveAgents` stores `AgentControl` alongside `AgentTools` — web routes call `control.abort()` and `control.confirm()` to stop or confirm the agent
  3. When a user clicks the stop button, the agent loop exits within one iteration — it is not blocked by an in-flight API call that takes 10–30 seconds
  4. `prepareStep` hook is wired and callable from AIService for context trimming and message injection before each iteration
**Plans**: TBD

### Phase 36: Event Log Resume and SessionHandoff Integration
**Goal**: The JSONL event log can generate a resume summary for injection into the next session's initial message, and SessionHandoff remains as a working fallback when no event log exists
**Depends on**: Phase 35
**Requirements**: LOG-03, LOG-04
**Success Criteria** (what must be TRUE):
  1. When a game session is resumed, the initial message includes a summary derived from the JSONL event log — tools called, outcomes, configs tried, and what the agent was doing when the session ended
  2. When no event log exists for a game (first session, or log deleted), SessionHandoff provides the resume context — the session starts with the handoff summary instead of an empty context
  3. The event log resume summary is richer than the SessionHandoff snapshot — it reflects the full sequence of tool calls and outcomes, not just the final state
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 13 → 14 → 15 → 16 → 17 → 18 → 19 → 20 → 21 → 22 → 23 → 24 → 25 → 26 → 27 → 28 → 29 → 30 → 31 → 32 → 33 → 34 → 35 → 36

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1–7. v1.0 phases | v1.0 | All complete | Complete | 2026-03-28 |
| 8. Loop Resilience | v1.1 | 2/2 | Complete | 2026-03-29 |
| 9. Engine Detection and Pre-configuration | v1.1 | 2/2 | Complete | 2026-03-29 |
| 10. Dialog Detection | v1.1 | 2/2 | Complete | 2026-03-29 |
| 11. Smarter Research | v1.1 | 3/3 | Complete | 2026-03-29 |
| 12. Web Interface for Game Management | v1.1 | 4/4 | Complete | 2026-03-30 |
| 13. GitHub App Authentication | v1.2 | 2/2 | Complete | 2026-03-30 |
| 14. Memory Entry Schema | v1.2 | 1/1 | Complete | 2026-03-31 |
| 15. Read Path | v1.2 | 2/2 | Complete | 2026-03-31 |
| 16. Write Path | v1.2 | 2/2 | Complete | 2026-03-31 |
| 17. Web Memory UI | v1.2 | 1/1 | Complete | 2026-03-31 |
| 18. Deepseek API Support | v1.2 | 2/2 | Complete | 2026-03-31 |
| 19. Import Lutris and ProtonDB | v1.2 | 2/2 | Complete | 2026-03-31 |
| 20. Smarter Wine log parsing | v1.2 | 2/2 | Complete | 2026-03-31 |
| 21. Pre-flight dependency check | v1.2 | — | Complete | — |
| 22. Seamless macOS UX | v1.2 | 3/3 | Complete | 2026-04-01 |
| 23. Homebrew tap distribution | v1.2 | 2/2 | Complete | 2026-04-02 |
| 24. Architecture cleanup | v1.2 | 3/3 | Complete | 2026-04-02 |
| 25. Kimi model support | v1.2 | 2/2 | Complete | 2026-04-02 |
| 26. ISO disc image support | v1.2 | 2/2 | Complete | 2026-04-02 |
| 27. Distribution — GitHub Releases | v1.2 | 2/2 | Complete | 2026-04-02 |
| 28. Fix prompt injection | v1.2 | 2/2 | Complete | 2026-04-02 |
| 29. Secure collective memory | v1.2 | 3/3 | Complete | 2026-04-03 |
| 30. Smart game name matching | v1.2 | 0 | Unused placeholder | — |
| 31. New Types | 1/2 | In Progress|  | - |
| 32. Middleware System | v1.3 | 0/TBD | Not started | - |
| 33. Rewrite the Loop | v1.3 | 0/TBD | Not started | - |
| 34. Update AgentTools | v1.3 | 0/TBD | Not started | - |
| 35. Wire It Together | v1.3 | 0/TBD | Not started | - |
| 36. Event Log Resume and SessionHandoff | v1.3 | 0/TBD | Not started | - |
