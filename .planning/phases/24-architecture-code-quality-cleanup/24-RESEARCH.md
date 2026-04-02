# Phase 24: Architecture & Code Quality Cleanup - Research

**Researched:** 2026-04-02
**Domain:** Swift async/await migration, monolith decomposition, DLL registry, error observability
**Confidence:** HIGH — all findings based on direct codebase inspection; no external library research required (pure Swift refactor)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **Async migration targets:** AIService, AgentLoopProvider, DLLDownloader, CollectiveMemoryWriteService, CollectiveMemoryService, GitHubAuthService — all 5+ files using DispatchSemaphore+ResultBox replaced with native async URLSession APIs
- **AgentLoop.run()** becomes `async func run(...)` — callers (LaunchCommand, LaunchController) updated accordingly
- **ArgumentParser commands** adopt `AsyncParsableCommand` where they call async code (LaunchCommand is the primary candidate)
- **Thread.sleep** replaced with `Task.sleep(nanoseconds:)` in all retry logic
- **WineProcess.run()** stays synchronous — Process is inherently sync and callers must block
- **AgentTools decomposition** into `Core/Tools/` extensions: ResearchTools, DiagnosticTools, ConfigTools, LaunchTools, SaveTools — each is an `extension AgentTools` file; coordinator class stays in AgentTools.swift
- **KnownDLLRegistry** gets new entries: dgVoodoo2 (D3D1–7 wrapper), dxwrapper (DirectDraw/Direct3D), DXVK (Vulkan-based D3D9–11) — hardcoded Swift, no external config
- **Vapor stays** — load-bearing (~1,450 lines, 8 files). No alternative evaluation needed.
- **Error reporting:** CollectiveMemoryService, CollectiveMemoryWriteService, GitHubAuthService replace silent nil returns with `fputs(...)` to stderr — no user-facing UI changes

### Claude's Discretion

- Exact file naming within Core/Tools/ subdirectory
- Whether to create a shared `HTTPClient` utility to deduplicate async URL fetch code
- Order of migration (which file to convert first)
- Specific dgVoodoo2/dxwrapper/DXVK GitHub release asset patterns and companion file contents

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

Phase 24 has no formal REQ-ID entries in REQUIREMENTS.md (it is an internal quality phase). The deliverables are defined by CONTEXT.md decisions and the phase description.

| Deliverable | Description | Research Support |
|-------------|-------------|-----------------|
| Async/await migration | Replace DispatchSemaphore+ResultBox in 5 files; remove @unchecked Sendable hacks | §Architecture Patterns: Async Migration |
| AgentTools decomposition | Split 2,513-line file into 5 extension files in Core/Tools/ | §Architecture Patterns: Extension Decomposition |
| KnownDLLRegistry expansion | Add dgVoodoo2, dxwrapper, DXVK entries | §Architecture Patterns: Registry Entries |
| GitHub API error reporting | fputs() to stderr instead of silent nil returns | §Architecture Patterns: Error Reporting |
| Vapor dependency audit | Confirmed keep — justified by load-bearing usage | §Standard Stack |
</phase_requirements>

---

## Summary

Phase 24 is a pure internal refactor — no new user-facing behavior, no new external dependencies, no new frameworks to learn. The entire phase works on existing Swift 6.2.3 language features and the existing codebase. All research is therefore codebase-inspection based rather than ecosystem-discovery based.

The async/await migration is the most structurally significant change. The current DispatchSemaphore+ResultBox pattern was a pragmatic workaround for Swift 6 Sendable requirements when the codebase was structured around synchronous ArgumentParser commands. Now that the web layer (Vapor) already uses async/await throughout, and Swift 6 has strong support for `AsyncParsableCommand`, the full async migration removes ~60 lines of boilerplate across 5 files and eliminates the `@unchecked Sendable` escape hatches that suppress compiler safety checks.

The AgentTools decomposition is straightforward: the MARK sections already define natural boundaries within the existing 2,513-line file. Using `extension AgentTools` in separate files preserves all access to shared mutable state without architectural changes. The KnownDLLRegistry expansion is additive data entry. Error reporting is a find-replace from `return nil` to `fputs(message, stderr); return nil`.

**Primary recommendation:** Migrate async first (enables the `AgentLoop.run() async` signature change that affects callers), then decompose AgentTools, then add registry entries, then add error logging. The async migration must be first because LaunchCommand's `AsyncParsableCommand` adoption cascades into how AgentLoop is called.

---

## Standard Stack

### Core (already present — no new installs needed)

| Component | Version | Purpose | Status |
|-----------|---------|---------|--------|
| Swift | 6.2.3 | Language — async/await, actors, Sendable | Active on system |
| swift-argument-parser | ≥1.7.0 | `AsyncParsableCommand` protocol | Already in Package.swift |
| Foundation URLSession | macOS 14+ | `data(for:)` async API | Available via macOS 14 target |
| Vapor | 4.115.0 | Web server — stays unchanged | Already in Package.swift |

### No New Dependencies

This phase adds zero new SPM dependencies. All required APIs are:
- `URLSession.data(for: URLRequest)` — async API available since macOS 12, required macOS 14
- `Task.sleep(nanoseconds:)` — Swift concurrency standard library
- `AsyncParsableCommand` — swift-argument-parser ≥1.2

---

## Architecture Patterns

### Recommended File Structure After Phase 24

```
Sources/cellar/Core/
├── AgentLoop.swift              — async func run() (was mutating func run())
├── AgentLoopProvider.swift      — async callAPI(), async callWithRetry()
├── AgentTools.swift             — class AgentTools: coordinator + shared state + execute() dispatch + tool definitions
├── AIService.swift              — async callAPI() private static func
├── CollectiveMemoryService.swift — async fetchBestEntry() with fputs() error logging
├── CollectiveMemoryWriteService.swift — async pushEntry() with fputs() error logging
├── DLLDownloader.swift          — async syncRequest() renamed to fetch()
├── GitHubAuthService.swift      — async performHTTPRequest() with fputs() error logging
└── Tools/                       — NEW subdirectory
    ├── ResearchTools.swift      — extension AgentTools: search_web, fetch_page, query_compatibility, query_successdb, check_collective_memory
    ├── DiagnosticTools.swift    — extension AgentTools: inspect_game, trace_launch, analyze_dll_trace, read_log, check_file_access, verify_dll_override
    ├── ConfigTools.swift        — extension AgentTools: set_environment, set_registry, install_winetricks, place_dll, write_game_file, read_game_file
    ├── LaunchTools.swift        — extension AgentTools: launch_game, ask_user, list_windows, changes_since_last
    └── SaveTools.swift          — extension AgentTools: save_success, save_recipe

Models/
└── KnownDLLRegistry.swift       — expanded with dgVoodoo2, dxwrapper, DXVK entries

Commands/
└── LaunchCommand.swift          — struct LaunchCommand: AsyncParsableCommand
```

---

### Pattern 1: Async URLSession Migration

**What:** Replace the 5-instance DispatchSemaphore+ResultBox pattern with native `URLSession.data(for:)`.

**Current pattern (5 occurrences across codebase):**
```swift
// BAD — current pattern in AIService, AgentLoopProvider, DLLDownloader, CollectiveMemoryService, GitHubAuthService
private static func callAPI(request: URLRequest) throws -> Data {
    final class ResultBox: @unchecked Sendable {
        var value: Result<Data, Error> = .failure(...)
    }
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        // ... set box.value
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return try box.value.get()
}
```

**Replacement pattern:**
```swift
// GOOD — native async/await
private static func callAPI(request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    if httpResponse.statusCode >= 400 {
        throw AIServiceError.httpError(statusCode: httpResponse.statusCode)
    }
    return data
}
```

**Shared helper candidate (Claude's discretion):** If a shared `HTTPClient` is created, it should be a standalone `enum` with a single `static func fetch(_ request: URLRequest) async throws -> Data` that handles status code checking. All 5 migration targets can then delegate to it, keeping each file's migration to a 3-line change.

**Thread.sleep → Task.sleep:**
```swift
// BAD
Thread.sleep(forTimeInterval: 1.0)

// GOOD
try await Task.sleep(nanoseconds: 1_000_000_000)
```

---

### Pattern 2: AsyncParsableCommand

**What:** `LaunchCommand` (and any other command that calls async code directly) adopts `AsyncParsableCommand` instead of `ParsableCommand`. The `run()` method becomes `async throws`.

**Current:**
```swift
struct LaunchCommand: ParsableCommand {
    mutating func run() throws {
        // calls AIService.runAgentLoop() which is synchronous
    }
}
```

**After migration:**
```swift
struct LaunchCommand: AsyncParsableCommand {
    mutating func run() async throws {
        // can now call async AIService.runAgentLoop()
    }
}
```

**Impact on Cellar.swift:** The root `CellarCLI` struct should also adopt `AsyncParsableCommand` if any subcommand is async — or ArgumentParser handles this automatically when a subcommand is `AsyncParsableCommand`. Verify this during implementation.

**Commands that call async code:** Only `LaunchCommand` directly calls into the agent loop. `AddCommand` runs the installer synchronously. `ServeCommand` blocks on `app.run()` which is already async-compatible via Vapor.

---

### Pattern 3: AgentLoop Async Propagation

**What:** `AgentLoop.run()` changes from `mutating func` to `async func`. This affects two call sites.

**Current signature:**
```swift
mutating func run(
    initialMessage: String,
    toolExecutor: (String, JSONValue) -> String,
    canStop: (() -> Bool)? = nil,
    shouldAbort: (() -> Bool)? = nil
) -> AgentLoopResult
```

**After:**
```swift
mutating func run(
    initialMessage: String,
    toolExecutor: (String, JSONValue) async -> String,  // executor can now be async too
    canStop: (() -> Bool)? = nil,
    shouldAbort: (() -> Bool)? = nil
) async -> AgentLoopResult
```

**Call site 1 — LaunchCommand (CLI):** `run()` is now awaited inside `async func run()` of the command.

**Call site 2 — LaunchController (web):** `runAgentLaunch()` is already `async throws`. `loop.run()` changes from synchronous to `await loop.run()`. The `Task.detached` wrapper in the SSE stream handler already provides an async context.

**PendingUserResponse in LaunchController:** The web UI's `askUserHandler` uses its own `DispatchSemaphore` to block the agent thread while waiting for browser input (POST /games/:gameId/launch/respond). This is an intentional bridge pattern and is not covered by this phase — it's an architectural concern that requires actor-based redesign of the web-to-agent channel, which is deferred per CONTEXT.md scope.

---

### Pattern 4: AgentTools Extension Decomposition

**What:** Move tool implementation methods from `AgentTools.swift` into 5 separate `extension AgentTools` files in `Core/Tools/`.

**Key insight:** Swift extension files in the same module have full access to `private` and `internal` members of the type they extend, **as long as `private` is changed to `fileprivate`** — or better, the helpers are marked `internal` (the default). For the decomposition to work cleanly, any `private` helper used by a moved method must become `fileprivate` or `internal`.

**What stays in AgentTools.swift:**
- All stored properties (shared state)
- `init(...)`
- `captureHandoff()`
- `static let toolDefinitions` (all 20+ ToolDefinition entries — 460 lines)
- `func execute(toolName:input:)` — the dispatch switch
- `private func jsonResult()` — shared by all extensions
- `ResearchCache` and `ResearchResult` private structs (used by ResearchTools)

**What moves to Core/Tools/ files:**
- ResearchTools.swift: `searchWeb`, `fetchPage`, `queryCompatibility`, `querySuccessdb`, `checkCollectiveMemory` (lines 2183–2513)
- DiagnosticTools.swift: `inspectGame`, `traceLaunch`, `checkFileAccess`, `verifyDllOverride`, `readLog`, `readRegistry`, `parseMsgboxDialogs` (lines 691–1081, 1551–1875)
- ConfigTools.swift: `setEnvironment`, `setRegistry`, `installWinetricks`, `placeDLL`, `writeGameFile`, `readGameFile` (lines 1097–1980)
- LaunchTools.swift: `launchGame`, `askUser`, `listWindows`, `computeChangesDiff`, `describeFix` (lines 1085–1503, 2409–2491)
- SaveTools.swift: `saveRecipe`, `saveSuccess`, `successRecordToDict` (lines 1505–2180)

**Access modifier note:** `jsonResult()` is currently `private`. It's used across multiple tool categories. Either:
1. Keep it in AgentTools.swift as `internal` (visible to all extensions in the module), or
2. Make it `fileprivate` — this will NOT work across files. Must be `internal`.

Recommendation: make `jsonResult()` `internal` (remove `private` keyword — internal is Swift's default).

---

### Pattern 5: KnownDLLRegistry Expansion

**What:** Add 3 new `KnownDLL` entries to the static registry array.

**Existing struct shape (verified from codebase):**
```swift
KnownDLL(
    name: String,              // matches place_dll argument
    dllFileName: String,       // actual .dll file to extract
    githubOwner: String,
    githubRepo: String,
    assetPattern: String,      // GitHub release asset filename to match
    description: String,
    requiredOverrides: [String: String],   // WINEDLLOVERRIDES entries
    companionFiles: [CompanionFile],        // config files placed alongside DLL
    preferredTarget: DLLPlacementTarget,
    isSystemDLL: Bool,
    variants: [String: String]
)
```

**New entries to add:**

**dgVoodoo2** — Translates DirectX 1–7 and Glide calls to Direct3D 11. Essential for early 3D games (1995–2002). GitHub: `dege-diorama/dgVoodoo2`. Releases are ZIP archives containing `D3D8.dll`, `D3DImm.dll`, `DDraw.dll`, `Glide.dll`, `Glide2x.dll`, `Glide3x.dll`. The key DLL for DirectDraw games is `DDraw.dll` with override `["ddraw": "n,b"]`. For D3D8 games: `D3D8.dll` with `["d3d8": "n,b"]`. Asset pattern: `dgVoodoo*.zip`. Note: dgVoodoo2 is complex — has multiple DLL files and an optional config file (dgVoodoo.conf). The `preferredTarget` is `.gameDir` (not system-wide).

**dxwrapper** — DirectX compatibility wrapper for DirectDraw and Direct3D 1–9. GitHub: `elishacloud/dxwrapper`. Asset: `dxwrapper.zip` containing `dxwrapper.dll` and `dxwrapper.ini`. Override: `["ddraw": "n,b"]` for DirectDraw games. `preferredTarget`: `.gameDir`.

**DXVK** — Vulkan-based Direct3D 9/10/11 implementation. GitHub: `doitsujin/dxvk`. Asset pattern: `dxvk-*.tar.gz`. Contains `x32/d3d9.dll`, `x32/d3d10core.dll`, `x32/d3d11.dll`, `x32/dxgi.dll`. For 32-bit games, override: `["d3d9": "n,b", "d3d11": "n,b", "dxgi": "n,b"]`. `preferredTarget`: `.syswow64`. DXVK on macOS via MoltenVK — note that on macOS, DXVK requires MoltenVK (Metal backend). This is relevant context for the description field but doesn't change the struct shape.

**Confidence on exact asset patterns:** MEDIUM — based on GitHub release naming conventions as of training data. The planner should verify current release asset names from the respective GitHub repos before hardcoding. The asset pattern is matched by `DLLDownloader` — if the pattern doesn't match, the download silently fails.

---

### Pattern 6: Error Reporting via fputs to stderr

**What:** Replace silent `return nil` in GitHub service failures with structured stderr logging.

**Current (silent):**
```swift
guard let (data, statusCode) = performFetch(request: request) else {
    return nil  // network error swallowed
}
```

**After:**
```swift
guard let (data, statusCode) = performFetch(request: request) else {
    fputs("[CollectiveMemoryService] Network error fetching entry for \(gameName)\n", stderr)
    return nil
}
```

**Why fputs, not print():** `print()` writes to stdout, which is the user-facing output channel. `fputs(..., stderr)` writes to the error stream, visible via `cellar log` or terminal redirect but not shown to the user in normal operation. This matches the intent: "make failures debuggable without surfacing to the user."

**Specific locations to instrument (verified from codebase):**

`CollectiveMemoryService.fetchBestEntry()`:
- Auth check failure (currently returns nil silently)
- Wine detection failure
- Network error from `performFetch()`
- Non-200 status codes (except 404, which is normal)
- JSON decode failure

`CollectiveMemoryWriteService.performRequest()`:
- Network error (currently returns nil silently, causing "Network error on PUT" to not log the specific network error)

`GitHubAuthService.getToken()`:
- Already logs the `unavailable(reason:)` case via the `.unavailable` return — callers see the reason string. The silent failure is in the `performHTTPRequest()` network error path which currently throws but the error message goes to `localizedDescription` which can be opaque. Adding `fputs` before rethrowing is the improvement.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Async HTTP | Custom async wrapper | `URLSession.shared.data(for:)` | Built into Foundation since macOS 12 |
| Sleep in retry | `Thread.sleep` | `Task.sleep(nanoseconds:)` | Thread.sleep blocks OS thread; Task.sleep suspends cooperative thread |
| Cross-file type access | Copy helpers into each file | `extension AgentTools` in same module | Swift module-level access to internal members |
| DLL asset format | Custom parser | Match existing `DLLDownloader.syncRequest` pattern | Asset download already handles ZIP/tar.gz extraction |

---

## Common Pitfalls

### Pitfall 1: DispatchSemaphore Inside an async Context

**What goes wrong:** Calling `semaphore.wait()` inside an `async` function blocks the cooperative thread pool. If all threads are blocked on semaphores, Swift's concurrency runtime deadlocks. This is already a theoretical concern with the current sync code — migration removes it.

**Why it happens:** async functions run on a shared thread pool. Blocking that pool starves other async work.

**How to avoid:** Never introduce `DispatchSemaphore.wait()` inside any `async` function. Use `await` instead.

### Pitfall 2: AgentLoop.run() Callers Must Await

**What goes wrong:** After `run()` becomes `async`, any non-async caller won't compile. LaunchController is already async. LaunchCommand becomes `AsyncParsableCommand`. But if there are other callers (e.g., test code), they will fail.

**How to find all callers:**
```bash
grep -rn "loop.run\|agentLoop.run\|\.run(initialMessage" Sources/
```

**How to avoid:** Convert all callers before marking `run()` as `async`. Use the compiler errors as a checklist.

### Pitfall 3: `private` vs `internal` in Extension Files

**What goes wrong:** Moving a method marked `private` to a separate file makes it inaccessible from the main file (and vice versa). `private` in Swift is file-scoped for extensions — a `private` method in `AgentTools.swift` cannot be called from `ResearchTools.swift` even though it's `extension AgentTools`.

**How to avoid:** Any helper method shared across extension files must be `internal` (the default — just remove the `private` keyword). `private` is only safe for helpers used exclusively within their own file.

**Specific impact:** `jsonResult()` is `private func jsonResult()` in AgentTools.swift and is called by every tool category. It must become `func jsonResult()` (internal).

### Pitfall 4: ResearchCache Struct Locality

**What goes wrong:** `ResearchCache` and `ResearchResult` are defined at file-scope in AgentTools.swift (lines 6–24) but are only used by the `searchWeb` method in what will become ResearchTools.swift.

**How to avoid:** Move `ResearchCache` and `ResearchResult` into ResearchTools.swift alongside the methods that use them. They are `private` — only used by the search methods.

### Pitfall 5: CellarCLI Root Command and AsyncParsableCommand

**What goes wrong:** If `LaunchCommand` adopts `AsyncParsableCommand` but `CellarCLI` (the root command in `Cellar.swift`) does not, ArgumentParser may not correctly dispatch async subcommands.

**How to avoid:** Check ArgumentParser docs — as of 1.2+, `AsyncParsableCommand` subcommands work under a synchronous root command via `ParsableCommand.main()`. However, the root `@main` entry point should call `CellarCLI.main()` which ArgumentParser handles. Verify this compiles without changes to `Cellar.swift`.

### Pitfall 6: PendingUserResponse in LaunchController Is Not Covered

**What goes wrong:** LaunchController.swift contains its own `DispatchSemaphore` in `PendingUserResponse` (the web UI's ask_user bridge). This is intentionally NOT migrated in Phase 24 — it's a cross-context blocking pattern that requires a different approach (actor + continuation) and is deferred.

**How to avoid:** Do not touch `PendingUserResponse` in LaunchController during Phase 24. The DispatchSemaphore there is at file scope, not inside an async function — it's safe for now.

---

## Code Examples

### Async URLSession Replacement (verified pattern — Foundation macOS 14+)

```swift
// Replaces DispatchSemaphore+ResultBox in all 5 migration targets
private static func callAPI(request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard http.statusCode < 400 else {
        throw AIServiceError.httpError(statusCode: http.statusCode)
    }
    return data
}
```

### Task.sleep Replacement (retry backoff)

```swift
// In AgentLoopProvider.callWithRetry() — replaces Thread.sleep
let backoffNanoseconds: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]
try await Task.sleep(nanoseconds: backoffNanoseconds[attempt - 1])
```

### AsyncParsableCommand

```swift
import ArgumentParser

// In LaunchCommand.swift
struct LaunchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch an installed game via Wine"
    )

    @Argument(help: "Game name or ID to launch")
    var game: String

    mutating func run() async throws {
        // Now can await async calls
        switch await AIService.runAgentLoop(...) {
        case .success(let summary): ...
        }
    }
}
```

### Extension AgentTools File Structure

```swift
// Core/Tools/ResearchTools.swift
import Foundation

// Private types used only by research tools
private struct ResearchCache: Codable { ... }
private struct ResearchResult: Codable { ... }

extension AgentTools {

    func searchWeb(input: JSONValue) -> String {
        // moved from AgentTools.swift
        // accesses self.gameId, self.entry, jsonResult() freely
    }

    func fetchPage(input: JSONValue) -> String { ... }

    func queryCompatibility(input: JSONValue) -> String { ... }
}
```

### KnownDLL Entry Template (new entries follow existing shape)

```swift
KnownDLL(
    name: "dxvk",
    dllFileName: "d3d9.dll",
    githubOwner: "doitsujin",
    githubRepo: "dxvk",
    assetPattern: "dxvk-",           // prefix match against release asset names
    description: "Vulkan-based D3D9/10/11 implementation via MoltenVK on macOS",
    requiredOverrides: ["d3d9": "n,b", "d3d11": "n,b", "dxgi": "n,b"],
    companionFiles: [],
    preferredTarget: .syswow64,
    isSystemDLL: true,
    variants: [:]
)
```

### fputs Error Logging Pattern

```swift
// CollectiveMemoryService — before a nil return that was previously silent
guard let (data, statusCode) = performFetch(request: request) else {
    fputs("[CollectiveMemoryService] Network error fetching collective memory for '\(gameName)'\n", stderr)
    return nil
}
guard statusCode == 200 else {
    if statusCode != 404 {
        fputs("[CollectiveMemoryService] Unexpected HTTP \(statusCode) for '\(gameName)'\n", stderr)
    }
    return nil
}
guard let entries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: data) else {
    fputs("[CollectiveMemoryService] Failed to decode collective memory JSON for '\(gameName)'\n", stderr)
    return nil
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact on This Phase |
|--------------|------------------|--------------|---------------------|
| Completion-handler URLSession | `async/await URLSession.data(for:)` | Swift 5.5 / macOS 12 | Replace 5 DispatchSemaphore patterns |
| Thread.sleep for retry | `Task.sleep(nanoseconds:)` | Swift 5.5 | Replace 4 Thread.sleep calls in retry loops |
| `@unchecked Sendable` escape | Native Sendable + async isolation | Swift 6.0 | Remove 5+ `@unchecked Sendable` class declarations |
| Monolithic tool file | Extension-based decomposition | N/A (design choice) | Split 2,513 lines into 5 files + coordinator |

---

## Migration Order (Recommended)

Phase 24 should proceed in this order to minimize integration risk:

1. **Async HTTP migration** (AIService, AgentLoopProvider, DLLDownloader, CollectiveMemoryWriteService, CollectiveMemoryService, GitHubAuthService) — can be done in parallel since they are independent files. Optionally extract shared HTTPClient utility first.

2. **AgentLoop.run() goes async** — depends on AgentLoopProvider being async first (provider.callWithRetry becomes `async throws`). After this, call sites must be updated immediately.

3. **LaunchCommand → AsyncParsableCommand** — depends on AgentLoop.run() being async.

4. **AgentTools decomposition** — independent of async migration. Can be done in parallel with steps 1–3 or after. No behavior changes, only file organization.

5. **KnownDLLRegistry expansion** — fully independent, additive only. Can be done at any time.

6. **Error reporting (fputs)** — fully independent, additive only. Can be done at any time.

---

## Open Questions

1. **Shared HTTPClient utility**
   - What we know: 5 files duplicate nearly identical DispatchSemaphore HTTP code
   - What's unclear: Is a shared utility worth the cross-file dependency?
   - Recommendation: Yes — create `enum HTTPClient { static func fetch(_ request: URLRequest) async throws -> Data }` in a new `Core/HTTPClient.swift`. The 5 files become 3-line delegations. Reduces future drift.

2. **dgVoodoo2 asset pattern verification**
   - What we know: GitHub releases exist at `dege-diorama/dgVoodoo2`; releases are ZIP files
   - What's unclear: Exact asset filename pattern in current releases (may be `dgVoodoo2_XX_X.zip` or similar)
   - Recommendation: Check the GitHub releases page during implementation to confirm the `assetPattern` string before hardcoding

3. **DXVK on macOS — MoltenVK dependency**
   - What we know: DXVK uses Vulkan; macOS only has Vulkan via MoltenVK (comes with Wine)
   - What's unclear: Whether Gcenx Wine tap bundles MoltenVK by default (it does for cross-over builds)
   - Recommendation: Add a note in the DXVK entry's `description` field: "Requires MoltenVK (included in Gcenx Wine builds)"

4. **CellarCLI + AsyncParsableCommand compatibility**
   - What we know: ArgumentParser 1.7.0 supports AsyncParsableCommand; async subcommands work under sync roots
   - What's unclear: Whether any other command (AddCommand, etc.) needs changes when LaunchCommand becomes async
   - Recommendation: Try it — the compiler will surface any issues immediately. No architectural risk.

---

## Sources

### Primary (HIGH confidence — direct codebase inspection)

- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentTools.swift` — 2,513 lines, MARK sections, function list
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AIService.swift` — DispatchSemaphore pattern at lines 63–87
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentLoopProvider.swift` — agentCallAPI() pattern at lines 53–78
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/DLLDownloader.swift` — syncRequest() pattern at lines 110–133
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/CollectiveMemoryService.swift` — performFetch() pattern, silent nil returns
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/CollectiveMemoryWriteService.swift` — performRequest() pattern at lines 281–299
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/GitHubAuthService.swift` — performHTTPRequest() pattern at lines 195–221
- `/Users/peter/Documents/Cellar/Sources/cellar/Models/KnownDLLRegistry.swift` — existing KnownDLL struct shape
- `/Users/peter/Documents/Cellar/Sources/cellar/Core/AgentLoop.swift` — current run() signature (mutating func)
- `/Users/peter/Documents/Cellar/Sources/cellar/Commands/LaunchCommand.swift` — current ParsableCommand usage
- `/Users/peter/Documents/Cellar/Sources/cellar/Web/Controllers/LaunchController.swift` — async runAgentLaunch(), PendingUserResponse
- `/Users/peter/Documents/Cellar/Package.swift` — swift-argument-parser 1.7.0, Vapor 4.115.0, macOS 14 target
- Swift 6.2.3 on system — async/await, Task.sleep, URLSession.data(for:) all available

### Secondary (MEDIUM confidence)

- Swift Evolution: SE-0296 (`async/await`), SE-0297 (`async let`), SE-0296 URLSession concurrency extensions — async URLSession API shape
- ArgumentParser documentation: `AsyncParsableCommand` protocol introduced in 1.2.0

### Tertiary (LOW confidence — verify during implementation)

- dgVoodoo2 GitHub release asset naming convention (releases page not fetched — verify before hardcoding assetPattern)
- DXVK GitHub release asset naming convention (same caveat)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new external dependencies; pure Swift 6.2 feature usage
- Architecture: HIGH — based on direct code inspection; decomposition boundaries match existing MARK sections
- Pitfalls: HIGH — all pitfalls derived from observed code patterns (private/internal scoping, async deadlock rules are Swift language spec)
- DLL registry entries: MEDIUM — struct shape is HIGH confidence; specific GitHub release asset patterns are MEDIUM (not verified against live releases)

**Research date:** 2026-04-02
**Valid until:** 2026-05-02 (stable domain — Swift async/await, ArgumentParser API — changes slowly)
