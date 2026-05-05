# Cellar Architecture

A comprehensive reference for the Cellar codebase. Reading this document should give you a full understanding of the system without reading source code.

**Last updated:** 2026-05-04
**Source:** ~16,200 lines across 81 Swift files + ~1,250 lines TypeScript (Cloudflare Worker)
**Tests:** ~3,600 lines across 26 test files (235 tests)

---

## 1. Overview

Cellar is a macOS CLI + web app that runs old Windows PC games via Wine, using an AI agent to automatically configure and troubleshoot games. The agent follows a **Research-Diagnose-Adapt** loop: research the game online, run diagnostic traces, apply targeted fixes (env vars, DLL overrides, registry edits, winetricks), and iterate until the game works.

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 6.0, macOS 14+ (strict Sendable) |
| CLI | swift-argument-parser |
| Web | Vapor + Leaf templates |
| HTML parsing | SwiftSoup |
| Testing | swift-testing (`@Test` macros) |
| AI providers | Anthropic (Claude), DeepSeek, Kimi (Moonshot AI) |
| Wine | wine-crossover via Homebrew (gcenx/wine) |
| Remote storage | Cloudflare Worker → GitHub repo |

---

## 2. Directory Structure

```
Sources/cellar/
├── Cellar.swift              — @main entry, 9 subcommands
├── Commands/                 — CLI commands (10 files, 1,176 lines)
│   ├── StatusCommand          check deps (Wine, winetricks)
│   ├── AddCommand             install game from .exe/.iso/.bin/.cue
│   ├── LaunchCommand          launch game with AI agent
│   ├── RemoveCommand          remove game from library
│   ├── LogCommand             view session logs
│   ├── ServeCommand           start web UI server
│   ├── SyncCommand            sync game library
│   ├── WikiCommand            wiki ingest (popular, classic, per-game)
│   └── InstallAppCommand      install system dependencies
│
├── Core/                     — Business logic (~12,000 lines)
│   ├── AgentLoop.swift        while-loop driver, ToolResult enum, LoopState
│   ├── AgentTools.swift       tool coordinator (dispatch only, 172 lines)
│   ├── AgentToolName.swift    typed enum for 24 tools + metadata table
│   ├── AgentControl.swift     thread-safe abort/confirm (OSAllocatedUnfairLock)
│   ├── AgentMiddleware.swift  BudgetTracker, SpinDetector hooks
│   ├── AgentEventLog.swift    JSONL session log (~/.cellar/logs/)
│   ├── AgentProvider.swift    ProviderAdapter protocol + type-erased wrapper
│   ├── AgentSession.swift     mutable per-session state (11 properties)
│   ├── SessionConfiguration.swift  immutable per-session context (6 fields)
│   ├── SessionHandoff.swift   cross-session continuation
│   ├── SessionDraftBuffer.swift  mid-session wiki draft buffer
│   ├── AIService.swift        orchestrator: provider init, loop setup, post-loop save
│   ├── PolicyResources.swift  versioned allowlists from Resources/policy/
│   │
│   ├── Tools/                — agent tool implementations (5 files, 1,835 lines)
│   │   ├── DiagnosticTools    inspect_game, read_log, trace_launch, etc.
│   │   ├── ConfigTools        set_environment, set_registry, install_winetricks, place_dll
│   │   ├── LaunchTools        launch_game (max 8), ask_user, list_windows
│   │   ├── SaveTools          save_success, save_failure, query_successdb
│   │   └── ResearchTools      search_web, fetch_page (domain-gated), query_wiki
│   │
│   ├── Providers/            — AI provider adapters (3 files, 616 lines)
│   │   ├── AnthropicAdapter   Anthropic Messages API
│   │   ├── DeepseekAdapter    OpenAI-compat (strips reasoning_content)
│   │   └── KimiAdapter        OpenAI-compat (Moonshot AI)
│   │
│   ├── KnowledgeStore.swift   protocol: fetchContext, write, list
│   ├── KnowledgeEntry.swift   discriminated union: .config | .gamePage | .sessionLog
│   ├── KnowledgeStoreLocal.swift   cache-only adapter (no network)
│   ├── KnowledgeStoreRemote.swift  GitHub raw reads + Worker writes, 1h TTL
│   ├── KnowledgeCache.swift   shared TTL cache backend
│   │
│   ├── WineProcess.swift      Wine subprocess execution
│   ├── WineErrorParser.swift  error diagnosis + fix suggestion
│   ├── WineDiagnostics.swift  DLL trace analysis
│   ├── WineActionExecutor.swift  execute WineFix actions
│   ├── WinetricksRunner.swift winetricks integration
│   ├── BottleManager.swift    bottle creation
│   ├── BottleScanner.swift    find executables in bottles
│   ├── DiscImageHandler.swift mount .iso/.bin/.cue/.img
│   ├── GuidedInstaller.swift  interactive install flow
│   ├── PEReader.swift         PE32 vs PE32+ detection
│   │
│   ├── CollectiveMemoryService.swift    thin wrapper → KnowledgeStore
│   ├── CollectiveMemoryWriteService.swift  thin wrapper → KnowledgeStore
│   ├── WikiService.swift      thin wrapper → KnowledgeStore
│   ├── WikiIngestService.swift  scrape Lutris/ProtonDB/WineHQ/PCGamingWiki
│   ├── CompatibilityService.swift  Lutris + ProtonDB API queries
│   ├── SuccessDatabase.swift  local success cache (~/.cellar/successdb/)
│   ├── PageParser.swift       SwiftSoup HTML extraction (WineHQ, PCGamingWiki, generic)
│   └── ...
│
├── Models/                   — Data types (9 files, 967 lines)
│   ├── AIModels.swift         AIProvider enum, request/response Codable types
│   ├── ModelCatalog.swift     model pricing + provider mapping
│   ├── AgentToolCall.swift    tool invocation struct
│   ├── CollectiveMemoryEntry.swift  WorkingConfig + EnvironmentFingerprint
│   ├── GameEntry.swift        game library record
│   ├── Recipe.swift           Wine configuration recipe
│   ├── EngineRegistry.swift   game engine profiles
│   ├── KnownDLLRegistry.swift DLL download metadata
│   └── LaunchResult.swift     launch outcome
│
├── Persistence/              — Storage (3 files, 300 lines)
│   ├── CellarPaths.swift      all filesystem paths (~/.cellar/)
│   ├── CellarStore.swift      games.json CRUD
│   └── CellarConfig.swift     user preferences
│
├── Web/                      — Vapor web UI (8 files, 1,139 lines)
│   ├── WebApp.swift           Vapor setup, CSRF middleware, routes
│   ├── Controllers/
│   │   ├── GameController      library CRUD + install SSE
│   │   ├── LaunchController    agent SSE, abort/confirm/answer
│   │   ├── SettingsController  API keys, model selection
│   │   └── MemoryController    collective memory stats
│   └── Services/
│       ├── LaunchService       Wine process helper
│       ├── GameService         library helper
│       └── MemoryStatsService  memory stats computation
│
└── Resources/
    ├── policy/               — versioned allowlists (JSON)
    │   ├── env_allowlist.json
    │   ├── registry_allowlist.json
    │   ├── dll_registry.json
    │   ├── winetricks_verbs.json
    │   ├── fetch_page_domains.json
    │   └── tool_schemas/       per-tool JSON Schema files
    ├── recipes/              — bundled game recipes
    ├── Views/                — Leaf HTML templates
    └── Public/               — static web assets

worker/                       — Cloudflare Worker (TypeScript)
├── src/index.ts              — wiki write endpoint, GitHub App JWT auth
├── src/helpers.ts            — isPathSafe, applyFencedUpdate
└── test/knowledge.test.ts    — 22 vitest tests
```

---

## 3. Agent Loop

The agent runs a tool-use loop against an LLM (Claude, DeepSeek, or Kimi):

```
AIService.runAgentLoop()
  → creates AgentTools(config:) + AgentLoop + middleware
  → AgentLoop.run():
      while not stopped:
        1. prepareStep hook (middleware can inject/override)
        2. provider.callAPI() → response
        3. for each toolCall: AgentTools.executeTool() → ToolResult
        4. afterTool / afterStep hooks
        5. check: endTurn | budget | maxIterations | abort
  → post-loop: save session log, config, handoff
```

**Key types:**
- `ToolResult` — `.success(content)`, `.stop(content, reason)`, `.error(content)` — replaces string matching
- `AgentControl` — thread-safe abort/confirm signals via `OSAllocatedUnfairLock`
- `AgentMiddleware` — `BudgetTracker` (50%/80% warnings), `SpinDetector` (pivot nudge after repeated launches)
- `AgentSession` — mutable state: `accumulatedEnv`, `launchCount`, `installedDeps`, `pendingActions`, `draftBuffer`

### 24 Agent Tools

| # | Tool | Category |
|---|------|----------|
| 1 | `inspect_game` | Diagnostic |
| 2 | `read_log` | Diagnostic |
| 3 | `read_registry` | Diagnostic |
| 4 | `trace_launch` | Diagnostic |
| 5 | `check_file_access` | Diagnostic |
| 6 | `verify_dll_override` | Diagnostic |
| 7 | `set_environment` | Config |
| 8 | `set_registry` | Config |
| 9 | `install_winetricks` | Config |
| 10 | `place_dll` | Config |
| 11 | `write_game_file` | Config |
| 12 | `read_game_file` | Config |
| 13 | `launch_game` | Launch (max 8) |
| 14 | `ask_user` | Launch |
| 15 | `list_windows` | Launch |
| 16 | `save_recipe` | Save |
| 17 | `save_success` | Save |
| 18 | `save_failure` | Save |
| 19 | `query_successdb` | Research |
| 20 | `search_web` | Research (cached 7d) |
| 21 | `fetch_page` | Research (domain-gated) |
| 22 | `query_compatibility` | Research |
| 23 | `query_wiki` | Research |
| 24 | `update_wiki` | Research |

`fetch_page` is gated by a domain allowlist in `PolicyResources` — only known wine/gaming sites (WineHQ, ProtonDB, PCGamingWiki, Steam, GitHub, Reddit) are allowed. Blocked URLs return an error with a hint to use `search_web` first.

---

## 4. Knowledge Store

Three knowledge kinds unified behind one protocol:

```
KnowledgeStore (protocol)
├── KnowledgeStoreLocal    — cache-only, no network
└── KnowledgeStoreRemote   — GitHub raw reads + Worker writes
                             1-hour TTL, stale-on-failure fallback

KnowledgeEntry (discriminated union)
├── .config(ConfigEntry)     — working Wine configurations
├── .gamePage(GamePageEntry)  — curated game reference pages
└── .sessionLog(SessionLogEntry) — per-session agent journals
```

`KnowledgeStoreContainer.shared` is wired at `runAgentLoop` entry. All reads/writes from AIService and AgentTools go through it. Legacy services (`CollectiveMemoryService`, `WikiService`, etc.) are thin wrappers delegating to the store.

---

## 5. Policy Resources

`PolicyResources.shared` loads versioned JSON files from `Resources/policy/` at startup:

| File | Property | Used by |
|------|----------|---------|
| `env_allowlist.json` | `envAllowlist` | ConfigTools, sanitizer |
| `registry_allowlist.json` | `registryAllowlist` | ConfigTools, sanitizer |
| `dll_registry.json` | `dllRegistry` | DLLDownloader |
| `winetricks_verbs.json` | `winetricksVerbAllowlist` | WinetricksRunner |
| `fetch_page_domains.json` | `fetchPageAllowlist` | ResearchTools |
| `tool_schemas/*.json` | `toolSchemas` | AgentToolName |

Single source of truth for all allowlists. Worker mirrors the same values.

---

## 6. Provider Adapters

```
ProviderAdapter (protocol, AnyObject-bound)
├── AnthropicAdapter   — Anthropic Messages API
├── DeepseekAdapter    — OpenAI-compatible (strips reasoning_content)
└── KimiAdapter        — OpenAI-compatible (Moonshot AI)

AgentProvider (struct) — non-mutating value-type wrapper
```

Each adapter owns its message array, handles retries (3 attempts, exponential backoff), and normalizes responses to `AgentLoopProviderResponse`.

---

## 7. Wine Integration

- **Bottles**: `~/.cellar/bottles/{gameId}/` — isolated Wine prefixes per game
- **WineProcess**: runs commands with `WINEPREFIX`, captures stderr, logs to file
- **WineErrorParser**: maps stderr patterns to `WineFix` suggestions
- **WineDiagnostics**: `WINEDEBUG=+loaddll` trace analysis
- **DiscImageHandler**: mounts `.iso`/`.bin`/`.cue`/`.img` via `hdiutil`
- **PEReader**: detects 32-bit vs 64-bit executables

---

## 8. Web UI

Vapor 4 server with Leaf templates, started via `cellar serve`.

| Route | Controller | Purpose |
|-------|-----------|---------|
| `GET /` | GameController | game library |
| `POST /games` | GameController | install game (SSE progress) |
| `DELETE /games/{id}` | GameController | remove game |
| `POST /api/launch/{id}` | LaunchController | start agent session |
| `GET /api/launch/{id}/stream` | LaunchController | SSE agent events |
| `POST /api/launch/{id}/answer` | LaunchController | user response to ask_user |
| `POST /api/launch/{id}/abort` | LaunchController | stop agent |
| `GET /settings` | SettingsController | API keys + model selection |
| `GET /memory` | MemoryController | collective memory stats |

`LaunchGuard` (actor) serializes launches — Wine doesn't handle parallel sessions.

---

## 9. Cloudflare Worker

TypeScript worker at `worker/src/` handles remote writes to the `cellar-memory` GitHub repo:

- `POST /api/knowledge/write` — dispatches by `kind` (config, gamePage, sessionLog)
- `POST /api/contribute` — legacy config write (kept for one release)
- `POST /api/wiki/append` — legacy wiki append (kept for one release)
- GitHub App JWT authentication for repo writes
- Rate limiting: 100 req/hr per IP (in-memory)
- `isPathSafe()` — blocks path traversal, enforces slug-only paths
- `applyFencedUpdate()` — preserves agent-authored content in `<!-- AUTO BEGIN/END -->` fences

---

## 10. Data Flow

```
User → cellar launch game
  → AIService.runAgentLoop()
    → KnowledgeStore.fetchContext()     ← GitHub raw / local cache
    → CompatibilityService.fetchReport() ← Lutris + ProtonDB APIs
    → AgentLoop.run()
      → LLM API (Claude/DeepSeek/Kimi)
      → AgentTools.executeTool()
        → WineProcess (traces, launches)
        → search_web / fetch_page (domain-gated)
    → KnowledgeStore.write(.sessionLog)  → Worker → GitHub
    → KnowledgeStore.write(.config)      → Worker → GitHub
    → SuccessDatabase.save()             → ~/.cellar/successdb/
```
