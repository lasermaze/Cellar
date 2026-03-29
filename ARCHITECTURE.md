# Cellar Architecture

A comprehensive reference for the entire Cellar codebase. Reading this document should allow someone to understand the full system without reading source code.

**Last updated:** 2026-03-29
**Total source lines:** ~6,500 (31 Swift files) + ~600 test lines (4 test files)

---

## 1. Project Overview

Cellar is a macOS CLI tool that launches old Windows PC games via Wine, with an AI agent (Claude) that automatically configures and troubleshoots games. It uses a "research-diagnose-adapt" loop: the AI inspects the game, queries knowledge bases, runs diagnostic Wine launches, applies fixes (environment variables, DLL overrides, registry edits, winetricks), and iterates until the game works.

### Tech Stack

| Component | Technology | Details |
|-----------|-----------|---------|
| Language | Swift 6.0 | macOS 14+ target, strict Sendable compliance |
| Package Manager | Swift Package Manager | `Package.swift` at project root |
| CLI Framework | swift-argument-parser 1.7+ | Subcommand routing |
| HTML Parsing | SwiftSoup 2.13+ | Web page content extraction |
| Testing | swift-testing 0.12+ | `@Test` macro-based tests |
| AI Provider | Anthropic (Claude Opus 4.6) | Primary; OpenAI as fallback for non-agent features |
| Wine Runtime | wine-crossover via Homebrew (gcenx/wine) | Homebrew tap `gcenx/wine` |
| API | Anthropic Messages API v2023-06-01 | Tool-use protocol for agent loop |

### Key Dependencies (External)

- **Homebrew** — package manager for installing Wine and winetricks
- **Wine** (wine-crossover) — Windows compatibility layer
- **winetricks** — automated Wine component installer
- **GPTK** (Game Porting Toolkit) — optional, detected but not required

---

## 2. Directory Structure

```
Cellar/
├── Package.swift                    # SPM manifest: macOS 14+, 3 dependencies
├── ARCHITECTURE.md                  # This file
├── recipes/                         # Bundled game recipes (JSON)
│   └── cossacks-european-wars.json  # Example bundled recipe
├── Sources/cellar/
│   ├── Cellar.swift                 # @main entry point (18 lines)
│   ├── Commands/                    # CLI subcommands
│   │   ├── AddCommand.swift         # `cellar add` — install game (298 lines)
│   │   ├── LaunchCommand.swift      # `cellar launch` — play game (162 lines)
│   │   ├── LogCommand.swift         # `cellar log` — view logs (60 lines)
│   │   └── StatusCommand.swift      # `cellar status` — check deps (99 lines)
│   ├── Core/                        # Business logic
│   │   ├── AgentLoop.swift          # AI tool-use iteration cycle (424 lines)
│   │   ├── AgentTools.swift         # All 19 tool implementations (2231 lines)
│   │   ├── AIService.swift          # AI provider abstraction + system prompt (923 lines)
│   │   ├── BottleManager.swift      # Wine bottle creation (33 lines)
│   │   ├── BottleScanner.swift      # Post-install EXE discovery (97 lines)
│   │   ├── DependencyChecker.swift  # Homebrew/Wine/winetricks detection (86 lines)
│   │   ├── DLLDownloader.swift      # GitHub release DLL download + cache (134 lines)
│   │   ├── GuidedInstaller.swift    # Interactive dep installation (197 lines)
│   │   ├── PageParser.swift         # Web page parsing with fix extraction (409 lines)
│   │   ├── RecipeEngine.swift       # Recipe load/save/apply (111 lines)
│   │   ├── SuccessDatabase.swift    # Game config knowledge base (221 lines)
│   │   ├── ValidationPrompt.swift   # Post-launch user feedback (49 lines)
│   │   ├── WineActionExecutor.swift # WineFix action dispatch (130 lines)
│   │   ├── WineErrorParser.swift    # Stderr pattern matching (141 lines)
│   │   ├── WineProcess.swift        # Wine process management (235 lines)
│   │   └── WinetricksRunner.swift   # Winetricks verb installer (127 lines)
│   ├── Models/                      # Data types
│   │   ├── AIModels.swift           # All API types + JSONValue (379 lines)
│   │   ├── EngineRegistry.swift     # Game engine fingerprinting (242 lines)
│   │   ├── GameEntry.swift          # Game metadata (12 lines)
│   │   ├── KnownDLLRegistry.swift   # DLL download registry (48 lines)
│   │   ├── LaunchResult.swift       # Launch outcome (8 lines)
│   │   ├── Recipe.swift             # Wine recipe schema (55 lines)
│   │   └── WineResult.swift         # Wine run result (11 lines)
│   └── Persistence/                 # Storage layer
│       ├── CellarConfig.swift       # Budget + settings (30 lines)
│       ├── CellarPaths.swift        # All file paths (105 lines)
│       └── CellarStore.swift        # games.json CRUD (68 lines)
└── Tests/cellarTests/
    ├── DependencyCheckerTests.swift  # Path detection tests (171 lines)
    ├── DialogParsingTests.swift      # Msgbox parsing tests (81 lines)
    ├── EngineRegistryTests.swift     # Engine detection tests (148 lines)
    └── PageParserTests.swift         # HTML extraction tests (207 lines)
```

### Filesystem Layout at Runtime (`~/.cellar/`)

```
~/.cellar/
├── .env                # API key configuration (ANTHROPIC_API_KEY)
├── .ai-tip-shown       # Sentinel: AI setup tip was displayed
├── config.json         # User config (budget ceiling)
├── games.json          # Game registry (array of GameEntry)
├── bottles/            # Wine prefixes, one per game
│   └── {game-id}/      # Full WINEPREFIX (drive_c/, user.reg, system.reg)
├── logs/               # Launch logs
│   └── {game-id}/      # Timestamped .log files per game
├── recipes/            # AI-generated user recipes
│   └── {game-id}.json  # Saved Recipe JSON
├── successdb/          # Success database
│   └── {game-id}.json  # SuccessRecord JSON
├── research/           # Web research cache
│   └── {game-id}.json  # Cached search results (7-day TTL)
└── dlls/               # Downloaded DLL cache
    └── {dll-name}/     # e.g., cnc-ddraw/ddraw.dll
```

---

## 3. Module Map

### Entry Point

**`Sources/cellar/Cellar.swift`** (18 lines)
- `@main struct Cellar: ParsableCommand` — registers 4 subcommands
- `static func main()` — calls `CellarPaths.refuseRoot()` and `CellarPaths.checkOwnership()` before parsing
- Subcommands: `StatusCommand`, `AddCommand`, `LaunchCommand`, `LogCommand`
- Default subcommand: `StatusCommand`

### Commands

**`Commands/StatusCommand.swift`** (99 lines)
- `struct StatusCommand: ParsableCommand` — default command (`cellar` with no args)
- Calls `DependencyChecker().checkAll()` and prints status
- Offers guided install via `GuidedInstaller` for missing deps (Homebrew -> Wine -> winetricks, in order)

**`Commands/AddCommand.swift`** (298 lines)
- `struct AddCommand: ParsableCommand` — `cellar add /path/to/setup.exe`
- Arguments: `installerPath: String`, `--force-proactive-deps` flag
- Flow: verify installer -> check deps -> derive game ID (slugify filename) -> create bottle -> find/load recipe -> run installer (with silent flags `/VERYSILENT /SP- /SUPPRESSMSGBOXES`) -> reactive dep diagnosis on failure -> post-install scan (`BottleScanner`) -> AI recipe generation if no bundled recipe -> save `GameEntry`
- Key function: `slugify(_:)` — lowercases, replaces `_` and spaces with hyphens, strips non-alphanumeric

**`Commands/LaunchCommand.swift`** (162 lines)
- `struct LaunchCommand: ParsableCommand` — `cellar launch <game-id>`
- Flow: check deps -> find game -> verify bottle -> resolve executable path -> try agent loop -> fall back to recipe-only launch on agent failure/unavailability
- Agent result handling: `.success` prints summary, `.failed` dispatches on stop reason tags (`[STOP:budget]`, `[STOP:iterations]`, `[STOP:api_error]`)
- `recipeFallbackLaunch()` — single-attempt recipe-only launch with SIGINT handler (Ctrl+C kills wineserver, still shows validation prompt) and `ValidationPrompt.run()`

**`Commands/LogCommand.swift`** (60 lines)
- `struct LogCommand: ParsableCommand` — `cellar log <game-id> [--list]`
- Shows most recent log or lists all log files sorted by creation date

### Core — AI Agent

**`Core/AgentLoop.swift`** (424 lines)
- `struct AgentLoop` — drives the Anthropic tool-use send-execute-return cycle
- Properties: `apiKey`, `model` (default: `"claude-opus-4-6"`), `tools: [ToolDefinition]`, `systemPrompt`, `maxIterations` (default: 20, agent uses 30), `maxTokens` (default: 4096, agent uses 16384), `budgetCeiling` (default: $5.00, agent uses $8.00 from config)
- `func run(initialMessage:toolExecutor:) -> AgentLoopResult` — main loop
- **Budget system:**
  - Pricing: Opus 4.6 at $5/$25 per MTok (input/output)
  - 50% threshold: prints alert
  - 80% threshold: injects warning message into next tool result
  - 100% threshold: injects halt directive, allows one final API call for saving, then returns `.budgetExhausted`
  - Budget-aware max_tokens escalation: if doubling would exceed 80% budget, uses continuation prompt instead
- **Stop reason handling:**
  - `"end_turn"`: returns completed (or sends continuation if empty response)
  - `"tool_use"`: executes each tool, collects results, appends to messages
  - `"max_tokens"`: if incomplete tool_use and below ceiling (32768), doubles `currentMaxTokens` and retries (does NOT increment iteration count); if at ceiling, sends continuation prompt
- **Retry logic:** `callAnthropicWithRetry()` — 3 attempts, exponential backoff (1s, 2s, 4s), retries 5xx/429/network errors, aborts on 4xx (except 429)
- **HTTP:** Synchronous URLSession via `DispatchSemaphore` + `ResultBox` (class for Swift 6 Sendable)
- `AgentLoopResult`: `finalText`, `iterationsUsed`, `completed`, `stopReason`, `totalInputTokens`, `totalOutputTokens`, `estimatedCostUSD`
- `enum AgentStopReason`: `.completed`, `.budgetExhausted`, `.maxIterations`, `.apiError(String)`
- `enum AgentLoopError`: `.httpError`, `.decodingError`, `.noResponse`, `.apiUnavailable`

**`Core/AgentTools.swift`** (2231 lines) — **Largest file in the codebase**
- `final class AgentTools` — reference type for mutable state across tool calls
- Injected context: `gameId`, `entry`, `executablePath`, `bottleURL`, `wineURL`, `wineProcess`
- Mutable state: `accumulatedEnv: [String: String]`, `launchCount: Int`, `maxLaunches: Int = 8`, `installedDeps: Set<String>`, `lastLogFile: URL?`
- `static let toolDefinitions: [ToolDefinition]` — JSON Schema definitions for all 19 tools
- `func execute(toolName:input:) -> String` — dispatch by name, returns JSON string, never throws

**All 19 Tools:**

| # | Tool | Purpose | Key Behaviors |
|---|------|---------|---------------|
| 1 | `inspect_game` | Examine game setup | Runs `/usr/bin/file` for PE type (PE32/PE32+), lists game dir files, checks system32 DLLs, runs `/usr/bin/objdump -p` for PE imports, detects bottle type (wow64 vs standard), extracts binary strings via `/usr/bin/strings -n 10`, runs `EngineRegistry.detect()` and `detectGraphicsApi()` |
| 2 | `read_log` | Read Wine stderr log | Returns last 8000 chars of most recent log file |
| 3 | `read_registry` | Read Wine .reg files | Parses `user.reg` (HKCU) or `system.reg` (HKLM) directly as text, normalizes key abbreviations, supports section listing or specific value lookup |
| 4 | `ask_user` | Interactive question | Prints question + optional numbered options, reads `readLine()` |
| 5 | `set_environment` | Set Wine env var | Accumulates into `accumulatedEnv` dict, persists across launches |
| 6 | `set_registry` | Write registry value | Generates .reg file content, writes to temp file, applies via `wineProcess.applyRegistryFile()` |
| 7 | `install_winetricks` | Install winetricks verb | Validates against 23-verb allowlist, skips duplicates, uses `WinetricksRunner` |
| 8 | `place_dll` | Download + place DLL | Looks up `KnownDLLRegistry`, downloads from GitHub releases via `DLLDownloader`, auto-detects placement target (game_dir/system32/syswow64), writes companion files (e.g., ddraw.ini), auto-applies WINEDLLOVERRIDES |
| 9 | `launch_game` | Launch with Wine | **Blocks until game exits** (by design). Pre-flight checks (exe exists, DLL files present for native overrides). Max 8 real launches per session (diagnostic launches are free). Parses +loaddll and +msgbox from stderr. **Auto-prompts user via readLine when game runs >10s** — adds `user_feedback` and `IMPORTANT` fields to result. Returns exit_code, elapsed, stderr_tail, detected_errors, loaded_dlls, dialogs, log_file |
| 10 | `save_recipe` | Save user recipe | Builds `Recipe` from accumulated state, saves via `RecipeEngine.saveUserRecipe()` |
| 11 | `write_game_file` | Write config file | Paths relative to game EXE dir, auto-converts backslashes, security check (path traversal denied) |
| 12 | `trace_launch` | Diagnostic Wine launch | Kills game after timeout (default 5s). Captures stderr via real-time `readabilityHandler`. Kill sequence: `process.terminate()` -> `killWineserver()` -> SIGKILL after 2s if still alive. Hard timeout via `DispatchSemaphore.wait()` at timeout+5s. Closes pipes immediately (does NOT call `readDataToEndOfFile` — Wine children hold descriptors). Returns structured DLL load analysis, dialogs, errors |
| 13 | `check_file_access` | Verify file existence | Checks paths relative to game EXE directory |
| 14 | `verify_dll_override` | Verify DLL override works | Checks configured override in env, checks native DLL file locations (game_dir/system32/syswow64), runs a trace launch, compares configured vs actual load path/type, returns explanation |
| 15 | `query_successdb` | Query success database | Supports: game_id (exact), tags (any overlap), engine (substring), graphics_api (substring), symptom (fuzzy keyword), similar_games (composite: engine weight 3, graphics_api weight 2, tags weight 1, symptom weight 1) |
| 16 | `save_success` | Save success record | Comprehensive record: environment, DLL overrides with placement, game config files, registry, pitfalls (symptom/cause/fix/wrong_fix), resolution narrative, tags. Also saves backward-compatible user recipe |
| 17 | `search_web` | Web search | DuckDuckGo HTML search, caches results per game for 7 days in `~/.cellar/research/`, parses HTML with regex for result links and snippets, returns up to 8 results |
| 18 | `fetch_page` | Fetch + parse URL | Uses SwiftSoup + `selectParser()` for structured extraction. Returns `text_content` (8000 char limit) + `extracted_fixes` (env vars, DLLs, registry, winetricks verbs, INI changes). Specialized parsers for WineHQ AppDB and PCGamingWiki; generic fallback |
| 19 | `list_windows` | Query macOS window list | Uses `CGWindowListCopyWindowInfo` from CoreGraphics. Filters for Wine process names. Reports owner, width, height, likely_dialog (w<640 && h<480), title (requires Screen Recording permission) |

**`Core/AIService.swift`** (923 lines)
- `struct AIService` — static methods for all AI interactions
- `detectProvider() -> AIProvider` — checks `ANTHROPIC_API_KEY` then `OPENAI_API_KEY` from process env then `~/.cellar/.env`
- `diagnose(stderr:gameId:) -> AIResult<AIDiagnosis>` — single-shot diagnosis with retry
- `generateRecipe(gameName:gameId:installedFiles:) -> AIResult<Recipe>` — AI recipe generation
- `generateVariants(...)  -> AIResult<AIVariantResult>` — variant generation with escalation levels (1: env vars only, 2: + winetricks/DLL overrides, 3: + place_dll/registry)
- `runAgentLoop(gameId:entry:executablePath:wineURL:bottleURL:wineProcess:) -> AIResult<String>` — **main agent entry point**, Anthropic-only (OpenAI not supported for tool-use)
  - Creates `AgentTools` instance and `AgentLoop` with model `"claude-opus-4-6"`, maxIterations 30, maxTokens 16384, budgetCeiling from `CellarConfig`
  - System prompt: ~180 lines defining the Research-Diagnose-Adapt workflow, engine-aware methodology, dialog detection heuristics, macOS+Wine domain knowledge, and constraints
  - Initial message instructs agent to follow R-D-A workflow and move quickly to real launch
- `showAITipIfNeeded()` — one-time tip about setting API key, uses `.ai-tip-shown` sentinel
- Helper: `extractJSON(from:)` — strips markdown code fences, finds first `{` to last `}`
- Helper: `parseWineFix(fixType:arg1:arg2:)` and `parseWineFix(from:)` — converts AI responses to `WineFix` enum
- Winetricks allowlist: 23 verbs (dotnet48, dotnet40, dotnet35, vcrun2019, vcrun2015, vcrun2013, vcrun2010, vcrun2008, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, dinput8, dinput, quartz, wmp9, wmp10, dsound, xinput, physx, xact, xactengine3_7)

### Core — Wine Process Management

**`Core/WineProcess.swift`** (235 lines)
- `struct WineProcess` — wraps Wine binary execution with WINEPREFIX isolation
- Properties: `wineBinary: URL`, `winePrefix: URL`
- `func run(binary:arguments:environment:logFile:) throws -> WineResult` — main launch method
  - Sets CWD to binary's parent directory (fixes relative path issues)
  - Inherits process environment, sets WINEPREFIX, merges additional env
  - Always adds `+msgbox` to WINEDEBUG (captures dialog text in stderr)
  - Real-time streaming: `readabilityHandler` on stdout/stderr pipes -> terminal + log file + capture buffer
  - **Stale output timeout: 5 minutes** — polls every 2s, kills process + wineserver if no output
  - Post-exit: disables readabilityHandler, closes pipe write ends (Wine children hold descriptors), drains remaining data
  - Thread-safe helpers: `OutputMonitor` (NSLock-guarded timestamp), `StderrCapture` (NSLock-guarded string buffer), both `@unchecked Sendable`
- `func initPrefix() throws` — runs `wineboot --init`, suppresses Gecko/Mono install (WINEDLLOVERRIDES=mscoree,mshtml=)
- `func applyRegistryFile(at:) throws` — runs `wine regedit <file>`
- `func killWineserver() throws` — runs `wineserver -k` with **5-second timeout** via DispatchSemaphore, terminates if hung

**`Core/WinetricksRunner.swift`** (127 lines)
- `struct WinetricksRunner` — runs winetricks with `-q` (unattended mode)
- Same stale-output timeout pattern (5 minutes) as WineProcess
- Returns `WinetricksResult`: verb, success, timedOut, exitCode, elapsed

### Core — Recipe System

**`Core/RecipeEngine.swift`** (111 lines)
- `static func findBundledRecipe(for:) throws -> Recipe?` — search order:
  1. `Bundle.main` (release builds)
  2. `recipes/` relative to CWD (development)
  3. `~/.cellar/recipes/` (user-generated)
  4. Substring match on recipe filenames (e.g., recipe `cossacks-european-wars` matches game ID `gog-galaxy-cossacks-european-wars`)
- `static func saveUserRecipe(_:) throws` — saves to `~/.cellar/recipes/{id}.json`
- `func apply(recipe:wineProcess:) throws -> [String: String]` — applies registry entries via temp .reg files, returns environment dict

### Core — Engine Detection

**`Models/EngineRegistry.swift`** (242 lines)
- `struct EngineRegistry` — data-driven engine detection with weighted scoring
- 8 engine definitions: GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard
- Each `EngineDefinition` has: name, family, filePatterns, peImportSignals, stringSignatures, typicalGraphicsApi
- Detection scoring: file patterns (unique +0.6, common +0.3), PE imports (+0.25), binary strings (+0.15), cross-type multiplier (1.2x when multiple signal types agree)
- Confidence thresholds: high (>=0.6), medium (>=0.35), low (>=0.15)
- `static func detectGraphicsApi(peImports:) -> String?` — priority: d3d11 > d3d9 > d3d8 > ddraw > opengl

### Core — Dialog Detection

**`AgentTools.parseMsgboxDialogs(from:)`** (lines 1361-1381 in AgentTools.swift)
- Parses `trace:msgbox:MSGBOX_OnInit` lines from Wine stderr
- Extracts text between `L"` and closing `"`, unescapes `\n`, `\t`, `\\`
- Returns array of `["message": ..., "source": "trace:msgbox"]`

**`list_windows` tool** (lines 2145-2208 in AgentTools.swift)
- Uses `CGWindowListCopyWindowInfo` to query macOS window list
- Filters for Wine process names: wine, wine64, wineserver, wine-preloader, wine64-preloader, start.exe
- Reports: owner, width, height, likely_dialog (w<640 && h<480), title (requires Screen Recording)
- System prompt defines multi-signal heuristic combining exit behavior + dialogs array + window list

### Core — Page Parsing

**`Core/PageParser.swift`** (409 lines)
- `protocol PageParser` — `canHandle(url:)` + `parse(document:url:) throws -> ParsedPage`
- 3 implementations:
  - `WineHQParser` — extracts from `table.whq-table tr` and `div.panel-forum .panel-body`
  - `PCGamingWikiParser` — extracts from `.mw-parser-output pre/code`, `table.wikitable`, fix-related headings
  - `GenericParser` — extracts from `pre`, `code`, `table`, body text
- `func extractWineFixes(from:context:) -> ExtractedFixes` — regex extraction of:
  - WINEDLLOVERRIDES compound values
  - Environment variables (WINE*, DXVK_*, MESA_*, STAGING_*)
  - Individual DLL overrides (dll=native/builtin/n,b patterns)
  - Winetricks verbs (with stop word filtering)
  - Registry paths (HKCU/HKLM backslash paths)
  - INI changes (key=value near .ini/.cfg file references)
- `func selectParser(for:) -> PageParser` — returns first matching parser

### Core — Success Database

**`Core/SuccessDatabase.swift`** (221 lines)
- File-backed JSON store in `~/.cellar/successdb/`
- `SuccessRecord` (lines 59-81): schemaVersion, gameId, gameName, gameVersion, source, engine, graphicsApi, verifiedAt, wineVersion, bottleType, os, executable (ExecutableInfo), workingDirectory, environment, dllOverrides, gameConfigFiles, registry, gameSpecificDlls, pitfalls, resolutionNarrative, tags
- Supporting types: `ExecutableInfo`, `WorkingDirectoryInfo`, `DLLOverrideRecord`, `GameConfigFile`, `RegistryRecord`, `GameSpecificDLL`, `PitfallRecord`
- Query methods:
  - `queryByGameId(_:)` — exact match
  - `queryByTags(_:)` — any overlap
  - `queryByEngine(_:)` — substring match
  - `queryByGraphicsApi(_:)` — substring match
  - `queryBySymptom(_:)` — keyword overlap fuzzy matching (>0.3 threshold)
  - `queryBySimilarity(engine:graphicsApi:tags:symptom:)` — composite scoring: engine weight 3, graphics_api weight 2, tags weight 1 each, symptom weight 1. Requires engine OR graphicsApi match. Returns top 5

### Core — Other

**`Core/BottleManager.swift`** (33 lines)
- `createBottle(gameId:)` — creates directory + runs `wineProcess.initPrefix()`
- `bottleExists(gameId:)` — checks directory exists

**`Core/BottleScanner.swift`** (97 lines)
- `static func scanForExecutables(bottlePath:)` — recursive scan of `drive_c/`, skips Wine system dirs (windows, programdata, users), skips known non-game EXEs (unins000, setup, vcredist, etc.), skips utility suffixes (_config, _editor, etc.), sorts by path depth (shallowest first)
- `static func findExecutable(named:in:)` — case-insensitive filename match

**`Core/DependencyChecker.swift`** (86 lines)
- `struct DependencyChecker` — supports test injection via `init(existingPaths:)`
- Detection paths: Homebrew at `/opt/homebrew/bin/brew` (ARM) or `/usr/local/bin/brew` (Intel)
- Wine: `wine64` then `wine` in same bin dir as brew
- GPTK: checks `/usr/local/bin/gameportingtoolkit` and `/opt/homebrew/bin/gameportingtoolkit`

**`Core/DLLDownloader.swift`** (134 lines)
- Downloads from GitHub Releases API: `GET /repos/{owner}/{repo}/releases/latest`
- Extracts zip via `/usr/bin/ditto -xk`
- Caches to `~/.cellar/dlls/{name}/{file}`
- `place(cachedDLL:into:)` — copies to target dir (removes existing first)

**`Core/GuidedInstaller.swift`** (197 lines)
- `installHomebrew()` — runs official install script via `/bin/bash -c "$(curl ...)"`
- `installWine()` — `brew tap gcenx/wine` + `brew install gcenx/wine/wine-crossover` + Gatekeeper quarantine removal
- `installWinetricks()` — `brew install winetricks`
- All with retry-on-failure and manual fallback instructions

**`Core/ValidationPrompt.swift`** (49 lines)
- Quick-exit detection: <2s = likely crash
- Wineserver shutdown prompt
- "Did the game reach the menu?" prompt
- "What did you see?" observation collection

**`Core/WineActionExecutor.swift`** (130 lines)
- `func execute(_:envConfigs:configIndex:installedDeps:) -> Bool` — dispatches `WineFix` enum cases
- Handles: installWinetricks, setEnvVar, setDLLOverride, placeDLL (with `KnownDLLRegistry` + `DLLDownloader`), setRegistry, compound

**`Core/WineErrorParser.swift`** (141 lines)
- `static func parse(_:) -> [WineError]` — 5 patterns:
  1. Missing DLL: `err:module:import_dll.*Library\s+(\S+)` -> maps to winetricks verb
  2. Crash: `virtual_setup_exception` or `unhandled exception` -> suggests `WINE_CPU_TOPOLOGY=1:0`
  3. Graphics: `err:x11` or display-related `err:winediag`
  4. Configuration: `err:reg` or `err:setupapi`
  5. DirectDraw failure: `DirectDraw Init Failed` -> compound fix: `placeDLL("cnc-ddraw") + setDLLOverride("ddraw", "n,b")`
- `WineFix` enum: `installWinetricks(String)`, `setEnvVar(String, String)`, `setDLLOverride(String, String)`, `placeDLL(String, DLLPlacementTarget)`, `setRegistry(String, String, String)`, `compound([WineFix])`
- `DLLPlacementTarget`: `.gameDir`, `.system32`, `.syswow64` with `autoDetect()` (syswow64 for 32-bit system DLLs in wow64 bottles)

### Models

**`Models/AIModels.swift`** (379 lines)
- `enum AIProvider`: `.anthropic(apiKey:)`, `.openai(apiKey:)`, `.unavailable`
- `enum AIServiceError`: `.httpError`, `.decodingError`, `.unavailable`, `.allRetriesFailed`
- `struct AIDiagnosis`: explanation + optional WineFix
- `struct AIVariant`: description + environment + [WineFix] actions
- `struct AIVariantResult`: variants + reasoning
- `enum AIResult<T>`: `.success(T)`, `.unavailable`, `.failed(String)`
- `AnthropicRequest`/`AnthropicResponse` — simple messages API types
- `OpenAIRequest`/`OpenAIResponse` — chat completions API types
- `indirect enum JSONValue: Codable` — recursive JSON (string/number/bool/null/array/object). **Critical: decodes Bool before Double** to prevent true/false -> 1.0/0.0
- `enum ToolContentBlock: Codable` — tagged union: `.text(String)`, `.toolUse(id:name:input:)`, `.toolResult(toolUseId:content:isError:)`
- `enum MessageContent: Codable` — `.text(String)` or `.blocks([ToolContentBlock])`
- `struct ToolDefinition: Encodable` — name, description, inputSchema (JSONValue)
- `struct AnthropicToolRequest: Encodable` — model, maxTokens, system, messages, tools
- `struct AnthropicToolResponse: Decodable` — content, stopReason, usage
- `struct AnthropicToolUsage: Decodable` — inputTokens, outputTokens

**`Models/GameEntry.swift`** (12 lines)
```swift
struct GameEntry: Codable {
    let id: String
    let name: String
    let installPath: String
    var executablePath: String?
    let recipeId: String?
    let addedAt: Date
    var lastLaunched: Date?
    var lastResult: LaunchResult?
}
```

**`Models/LaunchResult.swift`** (8 lines)
```swift
struct LaunchResult: Codable {
    let timestamp: Date
    let reachedMenu: Bool
    let attemptCount: Int
    let diagnosis: String?
}
```

**`Models/Recipe.swift`** (55 lines)
```swift
struct Recipe: Codable {
    let id, name, version, source, executable: String
    let wineTested: String?
    let environment: [String: String]
    let registry: [RegistryEntry]    // description + reg_content
    let launchArgs: [String]
    let notes: String?
    let setupDeps: [String]?         // winetricks verbs
    let installDir: String?          // expected install dir in drive_c
    let retryVariants: [RetryVariant]?  // description + environment + optional actions
}
```

**`Models/WineResult.swift`** (11 lines)
```swift
struct WineResult {
    let exitCode: Int32
    let stderr: String
    let elapsed: TimeInterval
    let logPath: URL?
    let timedOut: Bool
}
```

**`Models/KnownDLLRegistry.swift`** (48 lines)
- Currently contains 1 entry: `cnc-ddraw` (DirectDraw replacement from FunkyFr3sh/cnc-ddraw GitHub)
- `KnownDLL`: name, dllFileName, githubOwner, githubRepo, assetPattern, description, requiredOverrides, companionFiles (ddraw.ini with renderer=opengl), preferredTarget, isSystemDLL, variants

### Persistence

**`Persistence/CellarPaths.swift`** (105 lines)
- All path constants rooted at `~/.cellar/`
- `refuseRoot()` — aborts if UID 0 or username "root"
- `checkOwnership()` — warns if `~/.cellar/` or `~/.cache/winetricks` are root-owned (from previous sudo run)
- Path helpers for: games.json, bottles, logs, recipes, config, successdb, research cache, DLL cache, repair reports

**`Persistence/CellarConfig.swift`** (30 lines)
- `struct CellarConfig: Codable` — currently just `budgetCeiling: Double`
- Load priority: `CELLAR_BUDGET` env var > `~/.cellar/config.json` > default ($8.00)

**`Persistence/CellarStore.swift`** (68 lines)
- JSON array in `~/.cellar/games.json`, ISO8601 dates
- CRUD: `loadGames()`, `saveGames(_:)`, `findGame(id:)`, `addGame(_:)`, `updateGame(_:)`

---

## 4. Data Flow — `cellar launch <game-id>`

```
User runs: cellar launch cossacks-european-wars
│
├── 1. LaunchCommand.run()
│   ├── DependencyChecker().checkAll() → verify Wine + winetricks exist
│   ├── CellarStore.findGame(id:) → load GameEntry from ~/.cellar/games.json
│   ├── BottleManager.bottleExists(gameId:) → verify bottle directory
│   └── Resolve executable path (stored path or recipe lookup)
│
├── 2. AIService.runAgentLoop(...)
│   ├── detectProvider() → check ANTHROPIC_API_KEY (env or ~/.cellar/.env)
│   │   └── If unavailable → return .unavailable → recipeFallbackLaunch()
│   │
│   ├── Create AgentTools (class, mutable state)
│   ├── Create AgentLoop (model: claude-opus-4-6, maxIter: 30, maxTokens: 16384, budget: $8)
│   │
│   └── agentLoop.run(initialMessage, toolExecutor)
│       │
│       ├── 3. ITERATION LOOP (up to 30 iterations)
│       │   │
│       │   ├── POST https://api.anthropic.com/v1/messages (with retry)
│       │   │
│       │   ├── Accumulate token usage, check budget thresholds
│       │   │
│       │   ├── Handle stop_reason:
│       │   │   ├── "end_turn" → return completed
│       │   │   ├── "tool_use" → execute tools, append results
│       │   │   └── "max_tokens" → double maxTokens and retry, or continuation
│       │   │
│       │   └── Tool execution (Agent typically calls):
│       │       │
│       │       ├── Phase 1 - Research:
│       │       │   ├── query_successdb → check local knowledge
│       │       │   ├── inspect_game → PE type, imports, engine, files
│       │       │   ├── search_web → DuckDuckGo for Wine compat info
│       │       │   └── fetch_page → parse WineHQ/PCGamingWiki pages
│       │       │
│       │       ├── Phase 2 - Diagnose:
│       │       │   ├── trace_launch → 5s diagnostic run, DLL analysis
│       │       │   ├── check_file_access → verify relative paths
│       │       │   └── verify_dll_override → confirm override works
│       │       │
│       │       └── Phase 3 - Adapt:
│       │           ├── set_environment → accumulate env vars
│       │           ├── set_registry → write via wine regedit
│       │           ├── install_winetricks → install runtime deps
│       │           ├── place_dll → download + place DLL replacement
│       │           ├── write_game_file → create config files
│       │           ├── launch_game → FULL LAUNCH (blocks until exit)
│       │           │   ├── WineProcess.run() → streams output
│       │           │   ├── If elapsed > 10s → auto-asks user feedback
│       │           │   └── Returns exit_code, stderr, DLL loads, dialogs
│       │           ├── read_log → examine Wine stderr
│       │           ├── list_windows → check window sizes/titles
│       │           ├── ask_user → interactive questions
│       │           ├── save_success → comprehensive success record
│       │           └── save_recipe → user recipe file
│       │
│       └── Return AgentLoopResult
│
├── 4. Handle result:
│   ├── .success → print summary, update lastLaunched
│   ├── .unavailable → recipeFallbackLaunch()
│   └── .failed → print stop reason, recipeFallbackLaunch()
│
└── 5. recipeFallbackLaunch() (no AI):
    ├── RecipeEngine.findBundledRecipe() + apply()
    ├── WineProcess.run() with SIGINT handler
    ├── ValidationPrompt.run()
    └── CellarStore.updateGame()
```

---

## 5. Agent Architecture — Deep Dive

### System Prompt Structure (defined in `AIService.runAgentLoop()`, lines 510-686)

The system prompt is ~180 lines and defines:

1. **Three-Phase Workflow** — Research (query_successdb + inspect_game + search_web + fetch_page) -> Diagnose (trace_launch, max 2 iterations) -> Adapt (configure + launch_game + iterate on feedback)

2. **Engine-Aware Methodology** — Pre-configuration rules per engine family:
   - DirectDraw games (GSC, Build, Westwood, Blizzard): place cnc-ddraw + verify ddraw.ini
   - id Tech 2/3: MESA_GL_VERSION_OVERRIDE=4.5 for rendering issues
   - Unreal 1: renderer INI configuration
   - Unity: registry/prefs to skip screen dialog
   - UE4/5: modern, fewer tweaks

3. **Dialog Detection** — Multi-signal heuristic combining:
   - `dialogs` array from trace:msgbox parsing
   - `list_windows` CGWindowListCopyWindowInfo data
   - Exit timing (<5s = crash or dialog-blocked; >10s = likely running)

4. **Research Quality** — `extracted_fixes` from fetch_page should be checked before `text_content`; cross-game solution matching via `similar_games` query

5. **macOS + Wine Domain Knowledge** — 12 specific rules including:
   - Never suggest virtual desktop (winemac.drv doesn't support it)
   - wow64 bottles: 32-bit system DLLs go in syswow64, NOT system32
   - cnc-ddraw REQUIRES ddraw.ini with renderer=opengl (macOS has no D3D9)
   - CWD must be EXE's parent directory
   - Wine stderr is always noisy — never trust exit codes alone

6. **Constraints** — max 8 launches, diagnostic launches free, winetricks allowlist only, known DLL registry only

### Budget System

```
$0.00 ─────── $4.00 ────── $6.40 ────── $8.00
              (50%)        (80%)        (100%)
              alert        warn msg     HALT
              printed      injected     1 final call
                           into tools   then stop
```

- Default ceiling: $8.00 (configurable via `CELLAR_BUDGET` env or `~/.cellar/config.json`)
- Pricing: Opus 4.6 at $5/MTok input, $25/MTok output
- At 100%: injects `[BUDGET LIMIT REACHED]` message, agent gets one final API call to save progress

### max_tokens Recovery

When the API returns `stop_reason: "max_tokens"`:
1. If response contains incomplete `tool_use` blocks AND `currentMaxTokens < 32768`:
   - Check if doubling would push projected cost past 80% budget
   - If yes: use continuation prompt instead
   - If no: double `currentMaxTokens`, retry same messages (iteration count NOT incremented)
2. If at ceiling (32768) or text-only truncation: send continuation prompt

---

## 6. Error Handling and Resilience

### API Retry
- 3 attempts with exponential backoff: 1s, 2s, 4s
- Retries: 5xx errors, 429 (rate limit), network errors (URLError)
- Fatal (no retry): 4xx errors except 429
- After 3 failures: `AgentLoopError.apiUnavailable` — "Your game state is unchanged"

### Process Timeout and Pipe Handling
- **WineProcess stale timeout:** 5 minutes of no output -> terminate + killWineserver
- **trace_launch timeout:** configurable (default 5s) -> terminate + killWineserver + SIGKILL after 2s + hard DispatchSemaphore timeout at N+5s
- **Pipe handling critical pattern:** After process exit, disable readabilityHandler, close write ends (Wine children inherit descriptors), then drain remaining data. trace_launch does NOT call readDataToEndOfFile (hangs on Wine children).
- **killWineserver timeout:** 5 seconds via DispatchSemaphore, then terminate

### launch_game User Feedback
- When game runs >10 seconds, `launch_game` tool auto-prompts user via `readLine()`: "Did the game work? (yes / no / describe any issues)"
- Response is included in tool result as `user_feedback` field plus `IMPORTANT` field instructing agent NOT to re-ask via `ask_user`

### Stop Reason Reporting
- `[STOP:budget]` — budget ceiling exhausted
- `[STOP:iterations]` — max iterations (30) reached
- `[STOP:api_error]` — API unreachable after retries
- All result in fallback to `recipeFallbackLaunch()`

---

## 7. Testing

4 test files, 607 total lines, using swift-testing framework (`@Test` macro):

**`DependencyCheckerTests.swift`** (171 lines)
- Tests `DependencyChecker` with injected mock paths (`init(existingPaths:)`)
- Covers: ARM + Intel Homebrew detection, wine64 before wine fallback, winetricks detection, GPTK detection, `allRequired` logic, empty/partial scenarios

**`DialogParsingTests.swift`** (81 lines)
- Tests `AgentTools.parseMsgboxDialogs(from:)`
- Covers: single msgbox, multiple msgboxes, newline/tab unescaping, non-matching lines, empty input

**`EngineRegistryTests.swift`** (148 lines)
- Tests `EngineRegistry.detect()` and `detectGraphicsApi()`
- Covers: GSC engine (fsgame.ltx), Build engine (*.grp + *.art), Unity (UnityPlayer.dll), Unreal 1, id Tech 2/3, multi-signal bonus, no match, mixed signals, graphics API priority

**`PageParserTests.swift`** (207 lines)
- Tests `extractWineFixes(from:context:)` function
- Covers: WINEDLLOVERRIDES compound extraction, individual DLL overrides, environment variables (WINEDEBUG, MESA_*, etc.), winetricks verb parsing with stop word filtering, registry path extraction, INI changes near .ini references, deduplication, generic word filtering, PCGamingWiki parser on real HTML structure

---

## 8. Known Design Decisions

These are intentional behaviors, not bugs:

1. **`launch_game` blocks until game exits** — by design, the agent waits for the game to finish so it can analyze the result. The user plays the game; the agent observes.

2. **`launch_game` auto-prompts user via readLine when game runs >10s** — this is a deliberate UX decision so the agent gets user feedback without needing a separate `ask_user` call. The `IMPORTANT` field in the result prevents the agent from redundantly asking again.

3. **`trace_launch` kills game after timeout** — this is diagnostic only. Default 5 seconds. The agent uses this to observe DLL loading and dialog behavior without requiring user interaction.

4. **`killWineserver` has 5s timeout** — wineserver -k can hang if Wine children won't die. After 5 seconds, the process is terminated.

5. **Root/sudo refused at startup** — `CellarPaths.refuseRoot()` calls `_Exit(1)` if running as root. Creates root-owned files that break Wine. `checkOwnership()` warns if previous sudo run left root-owned directories.

6. **Wine stderr is always noisy — never trust exit codes alone** — the system prompt explicitly states this. Games can work perfectly with non-zero exit codes and pages of stderr warnings. The agent is instructed to rely on user feedback and elapsed time, not exit codes.

7. **Budget default is $8.00** — configurable via `CELLAR_BUDGET` env var or `~/.cellar/config.json`. The agent gets 30 iterations and up to $8 of API cost.

8. **Anthropic-only for agent loop** — `runAgentLoop` requires Anthropic API key. OpenAI is only supported for non-agent features (diagnose, generateRecipe, generateVariants) because the tool-use API differs significantly.

9. **Winetricks allowlist (23 verbs)** — prevents AI from suggesting invalid/dangerous verbs. Both `AIService` and `AgentTools` enforce the same list.

10. **DLL downloads only from KnownDLLRegistry** — currently only cnc-ddraw. Prevents arbitrary DLL downloads. The agent cannot download DLLs that aren't registered.

11. **Research cache is per-game with 7-day TTL** — web search results are cached in `~/.cellar/research/{game-id}.json` to avoid redundant network calls.

12. **Pipe handling: close write ends before drain** — Wine child processes (winedevice, services.exe) inherit pipe file descriptors and keep them open indefinitely. Closing write ends before `readDataToEndOfFile` prevents infinite hangs. `trace_launch` skips drain entirely and uses only the real-time capture buffer.

13. **Swift 6 Sendable compliance** — all closures captured by `readabilityHandler` and `DispatchQueue` use thread-safe wrapper classes (`OutputMonitor`, `StderrCapture`, `TraceStderrCapture`, `ResultBox`) marked `@unchecked Sendable` with internal NSLock.
