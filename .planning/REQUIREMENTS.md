# Requirements: Cellar

**Defined:** 2026-03-25
**Core Value:** Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## v1.0 Requirements (Validated)

Shipped and confirmed in v1.0. See MILESTONES.md for details.

### Setup & Dependencies

- [x] **SETUP-01**: Cellar detects whether Homebrew is installed (ARM and Intel paths)
- [x] **SETUP-02**: Cellar detects whether Wine is installed via Gcenx Homebrew tap
- [x] **SETUP-03**: Cellar guides user through installing Homebrew if missing
- [x] **SETUP-04**: Cellar guides user through installing Wine (Gcenx tap) if missing
- [x] **SETUP-05**: Cellar detects whether GPTK is installed on the system

### Bottle Management

- [x] **BOTTLE-01**: Cellar creates an isolated WINEPREFIX per game automatically on first launch

### Recipe System

- [x] **RECIPE-01**: Cellar ships with a bundled recipe for Cossacks: European Wars
- [x] **RECIPE-02**: Recipes auto-apply on launch (registry edits, DLL overrides, env vars, launch args)
- [x] **RECIPE-03**: AI generates a candidate recipe for games without a bundled recipe
- [x] **RECIPE-04**: Cellar can try multiple recipe variants when a launch fails

### Launch & Logs

- [x] **LAUNCH-01**: User can launch a game via Wine with correct WINEPREFIX and recipe flags
- [x] **LAUNCH-02**: Cellar captures Wine stdout/stderr to per-launch log files
- [x] **LAUNCH-03**: After launch, Cellar asks user if the game reached the menu (validation prompt)
- [x] **LAUNCH-04**: AI interprets Wine crash logs and provides human-readable diagnosis

### Agentic Architecture (v1.0)

- [x] **AGENT-01** through **AGENT-12**: 18-tool Research-Diagnose-Adapt agent loop with web search, diagnostic traces, DLL management, success database

## v1.1 Requirements

Requirements for v1.1 Agentic Independence. Each maps to roadmap phases.

### Loop Resilience

- [x] **LOOP-01**: Agent recovers from max_tokens truncation — detects incomplete tool_use blocks and retries with higher max_tokens instead of sending broken continuation
- [x] **LOOP-02**: Agent retries on transient API errors — 3-attempt exponential backoff on 5xx and network errors; 4xx (except 429) are fatal
- [x] **LOOP-03**: Agent tracks token usage per session and prints total cost at end — configurable budget ceiling with 80% warning and halt at 100%
- [x] **LOOP-04**: Agent handles empty end_turn responses by sending continuation prompt instead of aborting

### Engine Detection

- [x] **ENGN-01**: Agent detects game engine type from file patterns (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard) with confidence levels
- [x] **ENGN-02**: Agent uses PE import table as secondary engine signal (ddraw.dll = DirectDraw, d3d9.dll = DX9, etc.)
- [x] **ENGN-03**: Agent pre-configures game settings before first launch based on detected engine — writes INI files and registry entries to skip renderer selection dialogs
- [x] **ENGN-04**: Agent constructs engine-aware web search queries using engine type, graphics API, and symptoms instead of just game name

### Dialog Detection

- [x] **DIAG-01**: trace_launch includes +msgbox in WINEDEBUG and parses MessageBoxW output into structured dialog info (title, message, type)
- [x] **DIAG-02**: Agent queries macOS window list (CGWindowListCopyWindowInfo) to detect window sizes and titles of Wine processes
- [x] **DIAG-03**: Agent uses hybrid signal (Wine traces + window list) to determine if game is stuck on a dialog vs running normally — with graceful degradation if Screen Recording permission is denied

### Research Quality

- [x] **RSRCH-01**: Agent extracts actionable fixes from web pages — exact env vars, registry paths, DLL names, winetricks verbs, INI changes (not general descriptions)
- [x] **RSRCH-02**: Agent queries success database by engine type and graphics API tags to find similar-game solutions for new games
- [x] **RSRCH-03**: fetch_page uses SwiftSoup for structured HTML parsing instead of string stripping — extracts content from known sources (WineHQ, PCGamingWiki, forums)

### Web Interface (v1.1)

- [x] **WEB-01**: User can view game library as a card grid in the browser at localhost:8080, showing game name, status, and last played date
- [x] **WEB-02**: User can add a game (providing installer path) and delete a game (with optional bottle cleanup) through the web interface
- [x] **WEB-03**: User can directly launch a game that has a working recipe or success record, with Wine output streamed to the browser via SSE
- [x] **WEB-04**: User can launch a game with the AI agent, with real-time agent loop events (iterations, tool calls, reasoning, cost) streamed to the browser via SSE
- [x] **WEB-05**: `cellar serve` subcommand starts a Vapor web server on localhost:8080, sharing all existing business logic without duplication

## v1.2 Requirements

Requirements for v1.2 Collective Agent Memory. Each maps to roadmap phases.

### Authentication

- [x] **AUTH-01**: Agent authenticates to GitHub API using GitHub App credentials (RS256 JWT + installation token) shipped with CLI
- [x] **AUTH-02**: Agent token refreshes automatically before expiry (1-hour lifetime, refresh at 55 minutes)

### Schema

- [x] **SCHM-01**: Collective memory entry stores working config, agent reasoning chain, and environment fingerprint (Wine version, macOS version, CPU arch, wine flavor)
- [x] **SCHM-02**: Each game has one JSON file in the collective memory repo (`entries/{game-id}.json`), containing an array of entries from different agents/environments
- [x] **SCHM-03**: Entry includes schema version field for forward-compatible evolution

### Read Path

- [x] **READ-01**: Agent queries collective memory for the current game before starting diagnosis — if a matching entry exists, it's injected as context in the initial agent message
- [x] **READ-02**: Agent reasons about environment delta between stored entry and local environment before applying (not blind application)
- [x] **READ-03**: Agent flags entries as potentially stale when current Wine version is more than one major version ahead of last confirmation

### Write Path

- [x] **WRIT-01**: After user-confirmed successful launch, agent automatically pushes config + reasoning + environment to collective memory repo via GitHub Contents API
- [x] **WRIT-02**: Confidence counter increments when a different agent confirms the same config works (deduplicated by environment hash)
- [x] **WRIT-03**: User is prompted on first run to opt into collective memory contribution; preference saved in config

### Web Interface (v1.2)

- [x] **WEBM-01**: Web UI shows collective memory stats (games covered, total confirmations, recent contributions)
- [x] **WEBM-02**: Web UI shows per-game memory entries with environment details and confidence scores

### Deepseek API Support

- [x] **DSPK-01**: When `AI_PROVIDER=deepseek` is set in config or .env, Cellar uses the Deepseek API for all AI operations (recipe generation, log interpretation, agent loop) instead of Claude
- [x] **DSPK-02**: Web settings page allows selecting the active AI provider and entering the Deepseek API key
- [x] **DSPK-03**: When the configured provider's API key is missing, Cellar shows a clear error message naming the provider — not a generic "API key missing"

### Compatibility Databases

- [x] **COMPAT-01**: Agent queries Lutris API by game name with fuzzy matching and extracts actionable Wine config from installer scripts (env vars, DLL overrides, winetricks verbs, registry edits)
- [x] **COMPAT-02**: Agent queries ProtonDB for tier rating (Platinum/Gold/Silver/Bronze/Borked) using Steam AppID discovered from Lutris, with Proton-specific flags filtered out before agent sees them
- [x] **COMPAT-03**: Compatibility data is auto-injected into the agent's initial message before diagnosis, and a query_compatibility tool allows on-demand lookups during the agent loop

### Distribution

- [x] **DIST-01**: `brew tap <org>/cellar && brew install cellar` downloads a pre-built binary from GitHub Releases, installs it to the Homebrew bin, and the `cellar` command works immediately — no Xcode or Swift toolchain required on the user's machine
- [x] **DIST-02**: GitHub Actions workflow builds a universal (arm64 + x86_64) release binary on every tagged push, uploads it to GitHub Releases, and updates the bottle hash in the formula
- [x] **DIST-03**: After `brew install`, a `Cellar.app` exists that starts `cellar serve` if not running and opens `http://127.0.0.1:8080` — no terminal interaction required for subsequent use

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Interface

- **TUI-01**: Interactive TUI mode for browsing game library (lazygit/btop style)

### Game Library

- **GAME-01**: User can add a game by providing a directory path (`cellar add /path`)
- **GAME-02**: User can remove a game and optionally clean up its bottle (`cellar remove`)
- **GAME-03**: AI-powered game identification from EXE metadata and file hashes
- **GAME-04**: List games with metadata (`cellar list` with status, last played)

### Bottle Management

- **BOTTLE-02**: User can reset a game's bottle to a clean state (`cellar reset`)
- **BOTTLE-03**: User can open winecfg for a game's bottle (`cellar config`)

### CLI

- **CLI-01**: CLI commands: `add`, `launch`, `remove`, `reset`, `config`, `log`, `status`

### Recipe System

- **RECIPE-05**: Confidence scoring on recipes (track reliability across launches)

### Community

- **COMM-01**: User can export a working recipe as a shareable JSON file
- **COMM-02**: Debug bundle export (logs + config + system info in one command)
- **COMM-03**: Submit recipe via PR workflow guidance

### Advanced Detection

- **ADV-01**: Vision-based dialog detection via screenshot analysis and vision model
- **ADV-02**: Multi-session agent memory — persist reasoning across sessions
- **ADV-03**: ProtonDB integration for community compatibility reports

### Setup

- **SETUP-06**: Detect Wine architecture (ARM vs x86_64/Rosetta) and warn on mismatch
- **SETUP-07**: Wine version reporting and compatibility warnings

## Out of Scope

| Feature | Reason |
|---------|--------|
| Game store / purchasing | Not a store — users bring their own game files |
| Steam/Epic/GOG integration | Massive scope increase, not core to the recipe layer |
| Cloud streaming | Everything runs locally on user's Mac |
| Bundled Wine | Maintenance trap — contributed to Whisky burnout |
| D3DMetal redistribution | Apple EULA prohibits it — detect-only |
| Custom graphics layer | Rely on Wine's wined3d and existing translation |
| Wine fork | Use upstream Wine via Gcenx Homebrew tap |
| Multi-platform | macOS-only |
| DX11/DX12 game support (v1) | Wedge is old DX8/DX9 games; GPTK detect for future |
| Native GUI (SwiftUI) | CLI-first for simplicity; TUI in v2 |
| Automatic game downloads | Legal issues — user provides their own files |
| Automated dialog button clicking | Requires Accessibility API, fragile, dangerous |
| Virtual desktop mode | Does not work on macOS winemac.drv |
| Wine version switching | Gcenx provides one build; not viable repair |
| Mass winetricks pre-install | Breaks bottles, masks deps, wastes time |
| Parallel multi-config testing | Wine processes share winemac; causes corruption |
| Screenshot-based success detection | Expensive, requires permissions, high false positives |
| Vector search / embeddings for memory lookup | Overkill for structured game data — game ID, engine, tags are reliable keys |
| Human approval workflow for contributions | Kills automatic contribution — WineHQ AppDB's staleness proves this |
| Centralized backend API for memory | Git repo is zero-cost, forkable, survives project abandonment |
| User identity / attribution in entries | Privacy concern — environment hash is sufficient contributor identity |
| Token proxy service (v1.2) | Accepted risk: ship GitHub App key with CLI. Rotate if abused |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SETUP-01 | Phase 1 | Complete |
| SETUP-02 | Phase 1 | Complete |
| SETUP-03 | Phase 1 | Complete |
| SETUP-04 | Phase 1 | Complete |
| SETUP-05 | Phase 1 | Complete |
| BOTTLE-01 | Phase 1 | Complete |
| RECIPE-01 | Phase 1 | Complete |
| RECIPE-02 | Phase 1 | Complete |
| LAUNCH-01 | Phase 1 | Complete |
| LAUNCH-02 | Phase 1 | Complete |
| LAUNCH-03 | Phase 1 | Complete |
| RECIPE-03 | Phase 2 | Complete |
| LAUNCH-04 | Phase 2 | Complete |
| RECIPE-04 | Phase 3 | Complete |
| AGENT-01–12 | Phase 6-7 | Complete |
| LOOP-01 | Phase 8 | Complete |
| LOOP-02 | Phase 8 | Complete |
| LOOP-03 | Phase 8 | Complete |
| LOOP-04 | Phase 8 | Complete |
| ENGN-01 | Phase 9 | Complete |
| ENGN-02 | Phase 9 | Complete |
| ENGN-03 | Phase 9 | Complete |
| ENGN-04 | Phase 9 | Complete |
| DIAG-01 | Phase 10 | Complete |
| DIAG-02 | Phase 10 | Complete |
| DIAG-03 | Phase 10 | Complete |
| RSRCH-01 | Phase 11 | Complete |
| RSRCH-02 | Phase 11 | Complete |
| RSRCH-03 | Phase 11 | Complete |
| WEB-01 | Phase 12 | Complete |
| WEB-02 | Phase 12 | Complete |
| WEB-03 | Phase 12 | Complete |
| WEB-04 | Phase 12 | Complete |
| WEB-05 | Phase 12 | Complete |
| AUTH-01 | Phase 13 | Complete |
| AUTH-02 | Phase 13 | Complete |
| SCHM-01 | Phase 14 | Complete |
| SCHM-02 | Phase 14 | Complete |
| SCHM-03 | Phase 14 | Complete |
| READ-01 | Phase 15 | Complete |
| READ-02 | Phase 15 | Complete |
| READ-03 | Phase 15 | Complete |
| WRIT-01 | Phase 16 | Complete |
| WRIT-02 | Phase 16 | Complete |
| WRIT-03 | Phase 16 | Complete |
| WEBM-01 | Phase 17 | Complete |
| WEBM-02 | Phase 17 | Complete |
| DSPK-01 | Phase 18 | Complete |
| DSPK-02 | Phase 18 | Complete |
| DSPK-03 | Phase 18 | Complete |
| COMPAT-01 | Phase 19 | Planned |
| COMPAT-02 | Phase 19 | Planned |
| COMPAT-03 | Phase 19 | Planned |
| DIST-01 | Phase 23 | Planned |
| DIST-02 | Phase 23 | Planned |
| DIST-03 | Phase 23 | Planned |

**Coverage:**
- v1.0 requirements: 15 total (all complete)
- v1.1 requirements: 19 total (all complete)
- v1.2 requirements: 16 total (all complete)
- Phase 19 requirements: 3 total
- Phase 23 requirements: 3 total
- Mapped to phases: 22
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-25*
*Last updated: 2026-03-29 after v1.2 roadmap creation (phases 13–17)*
