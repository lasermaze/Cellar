# Phase 24: Architecture & Code Quality Cleanup - Context

**Gathered:** 2026-04-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Modernize codebase internals — async/await migration, monolith decomposition, registry expansion, error reporting, dependency audit. No user-facing behavior changes. All existing functionality must continue working identically.

</domain>

<decisions>
## Implementation Decisions

### Async/await migration
- Migrate all 5 files using DispatchSemaphore+ResultBox pattern to native Swift async/await: AIService, AgentLoopProvider, DLLDownloader, CollectiveMemoryWriteService, WineProcess (screenshot helper)
- Remove all `@unchecked Sendable` ResultBox hacks — use proper async URLSession APIs
- AgentLoop itself becomes async (mutating func run → async func run)
- ArgumentParser commands adopt `AsyncParsableCommand` where they call async code
- Thread.sleep calls replaced with Task.sleep
- Keep WineProcess.run() synchronous — Process is inherently sync and the caller needs to block

### AgentTools decomposition
- Split by tool category into separate files under Core/Tools/:
  - ResearchTools.swift — search_web, fetch_page, check_success_db, check_collective_memory
  - DiagnosticTools.swift — trace_launch, analyze_dll_trace, inspect_pe_imports, read_log
  - ConfigTools.swift — set_environment, set_registry, install_winetricks, place_dll, write_game_file
  - LaunchTools.swift — launch_game, ask_user, changes_since_last
  - SaveTools.swift — save_success, save_recipe
- AgentTools.swift remains as the coordinator class holding shared mutable state (accumulatedEnv, launchCount, installedDeps, taskState) and the execute() dispatch method
- Each category file is an extension on AgentTools — keeps access to shared state simple

### KnownDLLRegistry expansion
- Add entries for commonly needed DLLs: dgVoodoo2 (D3D1-7 to D3D11 wrapper), dxwrapper (DirectDraw/Direct3D compatibility), DXVK (Vulkan-based D3D9-11)
- Keep entries hardcoded in Swift — no external config file. The registry is small and changes infrequently.
- Each entry follows the existing KnownDLL struct pattern (GitHub release source, asset pattern, required overrides, companion files)

### Vapor dependency weight
- Keep Vapor — it's load-bearing (game CRUD, live agent SSE, memory stats, settings). ~1,450 lines across 8 files is reasonable for what it does.
- No action needed beyond acknowledging this is justified. The web UI was a Phase 12 deliverable and has been extended in Phases 17 and beyond.

### Error reporting in GitHub services
- CollectiveMemoryService and CollectiveMemoryWriteService: replace silent nil returns with structured error logging via print() to stderr
- GitHubAuthService: same — log auth failures to stderr instead of swallowing silently
- No user-facing error UI changes — just make failures debuggable via `cellar log` or terminal output

### Claude's Discretion
- Exact file naming within Core/Tools/ subdirectory
- Whether to create a shared HTTPClient utility to deduplicate async URL fetch code
- Order of migration (which file to convert first)
- Specific dgVoodoo2/dxwrapper/DXVK GitHub release asset patterns and companion file contents

</decisions>

<code_context>
## Existing Code Insights

### Files requiring async migration
- `AIService.swift:63-86` — callAPI() with DispatchSemaphore+ResultBox
- `AgentLoopProvider.swift:51-76` — syncHTTPCall() same pattern
- `DLLDownloader.swift:109-131` — httpGet() same pattern
- `CollectiveMemoryWriteService.swift:279-297` — httpRequest() same pattern
- `WineProcess.swift:273` — DispatchSemaphore for screenshot timing (keep sync)

### AgentTools shared state
- `accumulatedEnv: [String: String]` — used across set_environment and launch_game
- `launchCount: Int` / `maxLaunches: Int` — used by launch_game
- `installedDeps: Set<String>` — used by install_winetricks
- `taskState: TaskState` — used by save_success and isTaskComplete
- `pendingActions` / `lastAppliedActions` / `previousDiagnostics` — used by changes_since_last

### Established patterns
- All commands use synchronous `ArgumentParser` ParsableCommand today
- Web controllers already use async/await (Vapor requires it)
- `@preconcurrency import Vapor` used to suppress Sendable warnings in web layer

### Integration points
- `AgentLoop.run()` is called from `LaunchCommand` (CLI) and `LaunchController` (web)
- Both callers will need updating when AgentLoop goes async

</code_context>

<specifics>
## Specific Ideas

User directive: "Make the industry standards" — apply conventional Swift patterns without discussion. No novel approaches, just modern Swift best practices.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 24-architecture-code-quality-cleanup*
*Context gathered: 2026-04-02*
