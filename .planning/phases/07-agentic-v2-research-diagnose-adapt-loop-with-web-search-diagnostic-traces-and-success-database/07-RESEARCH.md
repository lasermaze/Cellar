# Phase 7: Agentic v2 — Research-Diagnose-Adapt Loop - Research

**Researched:** 2026-03-27
**Domain:** Swift CLI tool extension — Wine compatibility agent with web research, diagnostic tracing, and structured success storage
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Research Tools**
- `search_web` tool: search for game-specific Wine compatibility info (WineHQ, ProtonDB, PCGamingWiki, forums)
- `fetch_page` tool: read a specific URL and extract text content for the agent
- Cache research results per game in `~/.cellar/research/{gameId}.json` — skip if <7 days old
- Research is optional: skip if success DB has a known-working record

**Diagnostic Tools**
- `trace_launch` tool: launch game briefly with targeted Wine debug channels (+loaddll, +ddraw, +relay), kill after N seconds, return **structured analysis** (not raw stderr) — parsed DLL load info, errors, etc.
- `verify_dll_override` tool: combine registry/env override config + trace_launch + comparison to explain discrepancies (e.g., "native DLL exists in game_dir but Wine loaded builtin from syswow64")
- `check_file_access` tool: verify game can find files it needs by comparing working directory vs game directory for relative paths
- `inspect_game` enhancement: add PE imports via `objdump -p`, bottle type detection (wow64), data file reading, known shim flagging

**Action Tool Enhancements**
- `place_dll` enhancement: add syswow64 target, auto-detect based on bottle type (wow64 + 32-bit system DLL → syswow64), write companion config files (ddraw.ini), verify after placement
- `launch_game` enhancement: ALWAYS set working directory to game EXE's parent directory, return structured DLL load analysis, distinguish diagnostic vs real launch, include pre-flight checks
- `write_game_file` new tool: write config/data files the game needs (mode.dat, ddraw.ini, etc.) into the game directory

**Infrastructure Fixes (P0)**
- WineProcess.run() must set `process.currentDirectoryURL` to the binary's parent directory
- DLLPlacementTarget must include `.syswow64` case for 32-bit system DLLs in wow64 bottles
- place_dll must write companion configs (ddraw.ini for cnc-ddraw) based on KnownDLLRegistry metadata

**System Prompt Updates**
- Remove: virtual desktop suggestions (doesn't work on macOS winemac.drv)
- Add: wow64 DLL search order (syswow64 for 32-bit system DLLs)
- Add: cnc-ddraw requires ddraw.ini with renderer=opengl on macOS
- Add: CWD must be game EXE's parent directory
- Add: PE imports show actual DLL dependencies
- Add: diagnostic methodology (trace before configuring, verify after placing)
- Add: research methodology (search before first launch)

**KnownDLLRegistry Enhancement**
- Add `companionFiles: [CompanionFile]` — files to write alongside the DLL (e.g., ddraw.ini)
- Add `preferredTarget: DLLPlacementTarget` — .syswow64 for system DLLs in wow64
- Add `variants: [String: String]` — game-specific variants

**Success Database**
- Storage: `~/.cellar/successdb/{game-id}.json`
- Schema captures: executable info, working directory requirements, environment, DLL overrides with placement details, game config files, registry settings, game-specific DLLs, pitfalls (symptom + cause + fix + wrong_fix), resolution narrative, tags
- `query_successdb` tool: query by game_id (exact), tags (overlap), engine (substring), graphics_api (substring), symptom (fuzzy match against pitfalls)
- `save_success` tool: replaces/extends save_recipe — agent constructs full record from session context
- Agent queries success DB before web research; similar-game queries by engine/graphics_api/tags

**Agent Loop Changes**
- Three-phase flow: Research → Diagnose → Adapt (non-linear, can jump between phases)
- Diagnostic launches are NOT full launches — short, traced, killed after N seconds
- Budget: 3 diagnostic launches before first real launch, 2 between each failed real launch
- Research phase pre-summarizes web results to extract only actionable info (env vars, registry keys, DLL overrides, known bugs)

**Cost/Performance**
- Research results cached per game (7-day TTL)
- Parallel research: WineHQ + ProtonDB + PCGamingWiki concurrently
- Trace launches ~3-5 seconds each (cheaper than full launch attempts)
- Token budget: pre-summarize web results before injecting into agent context

### Claude's Discretion
- Internal implementation details of tool handlers
- Error handling and edge cases within each tool
- Exact structured output format for trace_launch parsing
- How to organize new tools within AgentTools.swift
- Test strategy and test file organization
- Order of implementation across plans

### Deferred Ideas (OUT OF SCOPE)
- `check_protondb` convenience wrapper (can be implemented as search_web + fetch_page)
- Community sharing of success database records (Phase 5 scope)
- Game-specific DLL variants in KnownDLLRegistry (e.g., cnc-ddraw_cossacks.zip)
- Local inference alternative to API-first AI
</user_constraints>

---

## Summary

Phase 7 replaces the v1 agent's linear config-search loop with a three-phase Research-Diagnose-Adapt architecture. The codebase is a Swift CLI tool (`Cellar`) that wraps Wine process management with an Anthropic tool-use agent loop. All infrastructure already exists: `AgentLoop.swift` drives the Anthropic API tool-use cycle, `AgentTools.swift` provides the 10 v1 tools, `WineProcess.swift` manages Wine subprocesses, and `KnownDLLRegistry.swift`/`DLLDownloader.swift` handle DLL placement. Phase 7 adds new tools to these files and fixes identified infrastructure bugs.

The architecture is entirely native Swift with no external package dependencies. HTTP is done via `URLSession.shared` with `DispatchSemaphore` + `ResultBox` for synchronous bridging (the established pattern across AIService.swift and AgentLoop.swift). JSON persistence uses Swift `Codable` with `JSONEncoder`/`JSONDecoder` written to `~/.cellar/`. PE import parsing uses `objdump -p` spawned via `Process()` — the same pattern used by `inspectGame()` which already spawns `/usr/bin/file`. All new tools follow the existing `AgentTools.execute()` dispatch pattern: receive `JSONValue` input, return JSON string, never throw.

The highest-risk implementation work is `trace_launch` — it requires launching Wine with a hard timeout and then parsing structured DLL load information from `+loaddll` debug output. The `+loaddll` channel emits lines like `00cc:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\DDRAW.DLL" at 69EC0000: builtin`. Regex parsing of this format is the critical path. The success database is straightforward Codable JSON — the complexity is the fuzzy symptom matching for `query_successdb`, which should use simple substring/keyword matching rather than complex fuzzy logic.

**Primary recommendation:** Implement in three waves: (1) P0 infrastructure fixes + `write_game_file` + enhanced `place_dll`/`launch_game`, (2) diagnostic tools (`trace_launch`, `verify_dll_override`, `check_file_access`, enhanced `inspect_game`), (3) research tools (`search_web`, `fetch_page`) + success database (`query_successdb`, `save_success`) + system prompt update.

---

## Standard Stack

### Core (all already in project — no new dependencies)

| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| Swift | 5.9+ (Swift 6 concurrency) | Primary language | Project baseline; Package.swift already configured |
| Foundation | macOS system | URLSession, Process, JSONEncoder/Decoder, FileManager | Native; no external deps needed |
| URLSession.shared | — | HTTP fetches for web search/page fetch | Established pattern in AIService.swift and AgentLoop.swift |
| DispatchSemaphore + ResultBox | — | Synchronous bridge for URLSession | Already used in AgentLoop.callAPI() and AIService.callAPI() |
| Process() | — | Spawn subprocesses (wine, objdump) | Already used in WineProcess.swift, AgentTools.inspectGame() |
| Codable + JSONEncoder/Decoder | — | Persist success DB and research cache as JSON | Already used for Recipe, GameEntry, all model types |

### Supporting Tools (system utilities, no Swift packages)

| Tool | Path | Purpose | Notes |
|------|------|---------|-------|
| objdump | `/usr/bin/objdump` | Parse PE imports from game EXE | macOS ships LLVM objdump; `-p` flag dumps PE header including import table |
| wine | Gcenx tap path | Diagnostic trace launches | WineProcess.run() already wraps this |
| wineserver | Same dir as wine | Kill after trace | WineProcess.killWineserver() already exists |

### No New External Dependencies

This phase adds no Swift package dependencies. All networking, file I/O, process management, and JSON work uses existing Foundation primitives already proven in the codebase.

---

## Architecture Patterns

### Existing File Structure (what exists now)

```
Sources/cellar/
├── Core/
│   ├── AgentLoop.swift          # Anthropic tool-use loop driver (unchanged)
│   ├── AgentTools.swift         # 10 tool implementations — EXTEND here
│   ├── AIService.swift          # System prompt lives here — UPDATE prompt
│   ├── WineProcess.swift        # Wine subprocess — FIX CWD bug here
│   ├── WineErrorParser.swift    # DLLPlacementTarget enum — ADD .syswow64
│   ├── DLLDownloader.swift      # DLL download/cache — unchanged
│   ├── WineActionExecutor.swift # Recipe-based actions — ADD syswow64 support
│   └── ...
├── Models/
│   ├── KnownDLLRegistry.swift   # DLL metadata — EXTEND with companionFiles, preferredTarget
│   └── ...
└── Persistence/
    ├── CellarPaths.swift        # File paths — ADD successdb, research paths
    └── CellarStore.swift        # Game store — unchanged
```

### New Files to Create

```
Sources/cellar/
├── Core/
│   └── SuccessDatabase.swift    # SuccessRecord Codable struct + SuccessDatabase CRUD
└── Persistence/
    └── (CellarPaths extensions) # successdbDir, researchCacheDir paths added to CellarPaths.swift
```

### Pattern 1: Tool Handler Pattern (established, must follow)

Every tool in `AgentTools.swift` follows this contract:

```swift
// Source: AgentTools.swift — all 10 existing tools
private func toolName(input: JSONValue) -> String {
    // 1. Extract and validate params from JSONValue
    guard let param = input["param_name"]?.asString, !param.isEmpty else {
        return jsonResult(["error": "param_name is required"])
    }
    // 2. Do work — may throw internally but NEVER propagate
    do {
        let result = try doSomething()
        return jsonResult(["status": "ok", "result": result])
    } catch {
        return jsonResult(["error": "Failed: \(error.localizedDescription)"])
    }
}
```

New tools (`trace_launch`, `verify_dll_override`, `check_file_access`, `search_web`, `fetch_page`, `write_game_file`, `query_successdb`, `save_success`) all follow this exact pattern. Register in `execute()` switch.

### Pattern 2: DispatchSemaphore + ResultBox HTTP (established, must follow)

Web fetch for `search_web` and `fetch_page` must use the same pattern as `AgentLoop.callAPI()`:

```swift
// Source: AgentLoop.swift lines 180-201 — established pattern for synchronous URLSession
private func callAPI(request: URLRequest) throws -> Data {
    final class ResultBox: @unchecked Sendable {
        var value: Result<Data, Error> = .failure(AgentLoopError.noResponse)
    }
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            box.value = .failure(error)
        } else if let data = data {
            box.value = .success(data)
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return try box.value.get()
}
```

`search_web` and `fetch_page` implement their own version of this inside the tool handler. Never use `async`/`await` — the agent loop runs synchronously.

### Pattern 3: Process() Subprocess (established, must follow)

`trace_launch` and enhanced `inspect_game` (objdump) spawn subprocesses via `Process()`:

```swift
// Source: AgentTools.swift inspectGame() lines 283-310 — established pattern
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/objdump")
process.arguments = ["-p", executablePath]
let pipe = Pipe()
process.standardOutput = pipe
process.standardError = Pipe()  // discard stderr
do {
    try process.run()
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    // parse output...
} catch {
    // return error JSON
}
```

For `trace_launch`: use the same pattern as `WineProcess.run()` with `readabilityHandler` but add a `DispatchWorkItem` timer to kill after N seconds.

### Pattern 4: Codable JSON Persistence (established, must follow)

The success database and research cache use the same Codable pattern as `Recipe` and `GameEntry`:

```swift
// Pattern: encode to JSON file, decode from JSON file
struct SuccessRecord: Codable {
    let schemaVersion: Int
    let gameId: String
    let gameName: String
    // ... all fields from architecture doc schema
}

// Write:
let data = try JSONEncoder().encode(record)
try data.write(to: fileURL, options: .atomic)

// Read:
let data = try Data(contentsOf: fileURL)
let record = try JSONDecoder().decode(SuccessRecord.self, from: data)
```

Use `JSONEncoder()` with default settings. No custom date encoding needed (use ISO8601 string for `verifiedAt`).

### Pattern 5: WineProcess.run() with Hard Timeout (new pattern for trace_launch)

`trace_launch` needs to kill Wine after N seconds regardless of output activity. The existing `WineProcess.run()` uses a stale-output timeout (5 minutes). For `trace_launch`, implement an **absolute timeout** using `DispatchQueue.global().asyncAfter`:

```swift
// Pattern for trace_launch — absolute kill timer
let killTimer = DispatchWorkItem {
    process.terminate()
    try? wineProcess.killWineserver()
}
DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeoutSeconds), execute: killTimer)
// Start process...
process.waitUntilExit()
killTimer.cancel()  // if process exited before timeout
```

### Pattern 6: objdump -p PE Import Parsing

`objdump -p <exe>` on macOS outputs PE header sections. The import table appears as:

```
DLL Name: KERNEL32.dll
DLL Name: USER32.dll
DLL Name: ddraw.dll
```

Parse with regex or simple line scanning for `DLL Name:` prefix. The macOS system `objdump` is LLVM-based and supports PE files natively — verified via `llvm-objdump` D113356 review which confirms PE import table support.

```swift
// Pattern: scan objdump -p output for DLL imports
var imports: [String] = []
for line in output.components(separatedBy: "\n") {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("DLL Name: ") {
        let dllName = String(trimmed.dropFirst("DLL Name: ".count))
        imports.append(dllName)
    }
}
```

### Pattern 7: +loaddll Debug Output Parsing

When Wine runs with `WINEDEBUG=+loaddll`, stderr contains lines like:
```
00cc:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\DDRAW.DLL" at 69EC0000: builtin
00cc:trace:loaddll:build_module Loaded L"C:\\windows\\syswow64\\DDRAW.DLL" at 6A4C0000: native
```

Parse to extract: DLL name, load path, and type (native/builtin):

```swift
// Regex pattern for loaddll output
// Match: Loaded L"<path>" at <addr>: <type>
let pattern = #"trace:loaddll.*Loaded L"([^"]+)" at [0-9A-Fa-f]+: (native|builtin)"#
```

The path component gives the full Windows path. Extract the last component as the DLL filename. Type is the last word after the colon.

### Anti-Patterns to Avoid

- **Never make AgentTools functions async or throwing** — agent loop contract is synchronous String return
- **Never use Thread.sleep in tool handlers** — only in the Wine process wait loop
- **Never share URLSession state** — use `URLSession.shared` exclusively (prevents delegate queue deadlock, per Phase 02 decision)
- **Never parse +loaddll output as line-by-line sequential** — Wine may emit multiple load events per DLL (load, unload, reload); collect all, then deduplicate
- **Never use UserDefaults for persistence** — all Cellar data goes in `~/.cellar/` as JSON files
- **Do not async/await** — the entire codebase runs synchronously; swift CLI tools don't have a RunLoop

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTML text extraction for fetch_page | Custom HTML parser | Strip tags with regex: remove `<[^>]+>` patterns | fetch_page only needs readable text; SwiftSoup would add a package dependency; simple regex strip is sufficient for forum/wiki content |
| Web search API | Custom search infrastructure | Direct HTTP to a search API (DuckDuckGo HTML, SerpAPI, or Brave API) | Agents in this codebase make direct HTTP calls |
| Fuzzy string matching for query_successdb symptom | Levenshtein distance, ML embeddings | Lowercased keyword overlap: check if significant words from symptom query appear in stored pitfall symptoms | The corpus is tiny (tens of records); simple overlap is correct complexity |
| Kill-after-N-seconds | Thread polling with sleep | DispatchQueue.global().asyncAfter + DispatchWorkItem.cancel() | Clean cancellable timer, no spinning |
| PE parsing | Custom PE header reader | objdump -p via Process() | Already on macOS, handles 32/64-bit PE |
| JSON index for successdb | SQLite, CoreData | in-memory array scan of small JSON files + optional index.json | The success DB will have tens of records for years; file scan is correct |

**Key insight:** This codebase deliberately avoids external dependencies (no SPM packages beyond Foundation). Every "could use library X" answer is "use Foundation + spawn a system binary." Keep that discipline.

---

## Common Pitfalls

### Pitfall 1: trace_launch Leaves Zombie wineserver
**What goes wrong:** Killing Wine process after N seconds doesn't kill wineserver. Subsequent launches fail with "prefix locked" or "wineserver already running" errors.
**Why it happens:** Wine spawns a persistent `wineserver` daemon per prefix. Killing the main process doesn't kill it.
**How to avoid:** Always call `wineProcess.killWineserver()` after the kill timer fires. This already exists in `WineProcess.killWineserver()`.
**Warning signs:** Next launch hangs indefinitely; `ps aux | grep wineserver` shows orphan process.

### Pitfall 2: objdump Output Format Varies by macOS Version
**What goes wrong:** `objdump -p` output format differs between LLVM versions shipped with different Xcode/Command Line Tools versions. "DLL Name:" prefix may not appear on all versions.
**Why it happens:** macOS ships LLVM objdump, not binutils objdump. The PE support was added in LLVM D113356 but output format is not guaranteed stable.
**How to avoid:** Implement `inspect_game` PE import parsing defensively — return empty array on parse failure, not an error. Also accept "library: " or scan for any line containing ".dll" as a fallback.
**Warning signs:** `pe_imports` returns empty for known PE32 executables.

### Pitfall 3: +loaddll Trace Produces Enormous Output
**What goes wrong:** `WINEDEBUG=+loaddll` is verbose. A 3-second trace can produce 50KB+ of stderr, overwhelming the agent context if returned raw.
**Why it happens:** Wine traces every DLL event including system DLLs (ntdll, kernel32, etc.).
**How to avoid:** The `trace_launch` tool must return **structured output only** (parsed DLL list), not raw stderr. Filter to game-relevant DLLs: those in the game directory or those matching the configured overrides.
**Warning signs:** Agent context gets flooded; token limit hit early in session.

### Pitfall 4: HTTP Redirect Handling in fetch_page
**What goes wrong:** Many URLs (WineHQ AppDB, PCGamingWiki) redirect (301/302). A simple URLSession request to the original URL may return the redirect response body, not the actual page.
**Why it happens:** URLSession.shared follows redirects by default, but redirect following requires delegate configuration in some cases.
**How to avoid:** Use `URLSession.shared` which follows redirects automatically by default (verified: Apple docs state shared session follows redirects). No special handling needed.
**Warning signs:** fetch_page returns HTML of redirect page ("You are being redirected...") instead of content.

### Pitfall 5: Race Condition in Parallel Research
**What goes wrong:** Parallel research (WineHQ + ProtonDB + PCGamingWiki concurrently) has a race when writing results to the same cache file.
**Why it happens:** Three concurrent `URLSession.dataTask` completions may try to write `~/.cellar/research/{gameId}.json` simultaneously.
**How to avoid:** Research phase collects all three results first (separate variables), then writes a single combined JSON after all fetches complete. Use a `DispatchGroup` to wait for all fetches.
**Warning signs:** Cache file is truncated or corrupted on second launch.

### Pitfall 6: syswow64 Path Must Exist Before Placement
**What goes wrong:** `place_dll` with `.syswow64` target tries to write to `drive_c/windows/syswow64/` but the directory doesn't exist (non-wow64 bottle).
**Why it happens:** Not all bottles are wow64. The directory only exists in crossover-style wow64 bottles.
**How to avoid:** `DLLPlacementTarget.autoDetect()` checks directory existence first (per CONTEXT.md spec). Fallback to `.gameDir` if syswow64 doesn't exist.
**Warning signs:** File write error "no such directory" during place_dll.

### Pitfall 7: Swift 6 Sendable Violations in New Concurrent Code
**What goes wrong:** Parallel research using `DispatchGroup` + concurrent `dataTask` completions triggers Swift 6 Sendable warnings or errors.
**Why it happens:** Captured variables mutated in concurrent closures violate Swift 6's actor isolation model.
**How to avoid:** Use the established `ResultBox: @unchecked Sendable` pattern from `AgentLoop.callAPI()` for any result captured across concurrent boundaries. Use `NSLock` for any shared mutable state (established in `OutputMonitor`, `StderrCapture`).
**Warning signs:** Swift compiler error "mutation of captured var in concurrently-executing code."

---

## Code Examples

### Infrastructure Fix 1: WineProcess CWD

```swift
// Source: .planning/agentic-architecture-v2.md — WineProcess.run() fix
// File: Sources/cellar/Core/WineProcess.swift, around line 40

func run(binary: String, arguments: [String] = [], ...) throws -> WineResult {
    let process = Process()
    process.executableURL = wineBinary
    process.arguments = [binary] + arguments

    // FIX: Set CWD to game binary's parent directory
    // Many games use relative paths (Missions\Missions.txt, mode.dat)
    let binaryURL = URL(fileURLWithPath: binary)
    process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

    // ... rest unchanged
}
```

### Infrastructure Fix 2: DLLPlacementTarget.syswow64

```swift
// Source: Sources/cellar/Core/WineErrorParser.swift — extend enum
enum DLLPlacementTarget {
    case gameDir    // next to EXE
    case system32   // Wine's virtual System32
    case syswow64   // Wine's SysWOW64 — 32-bit system DLLs in wow64 bottles  // NEW

    static func autoDetect(bottleURL: URL, dllBitness: Int, isSystemDLL: Bool) -> DLLPlacementTarget {
        let syswow64Path = bottleURL
            .appendingPathComponent("drive_c/windows/syswow64").path
        let isWow64 = FileManager.default.fileExists(atPath: syswow64Path)
        if isSystemDLL && isWow64 && dllBitness == 32 { return .syswow64 }
        return .gameDir
    }
}
```

### Infrastructure Fix 3: KnownDLL with CompanionFiles

```swift
// Source: Sources/cellar/Models/KnownDLLRegistry.swift — extend struct

struct CompanionFile {
    let filename: String   // "ddraw.ini"
    let content: String    // default content string
}

struct KnownDLL {
    let name: String
    let dllFileName: String
    let githubOwner: String
    let githubRepo: String
    let assetPattern: String
    let description: String
    let requiredOverrides: [String: String]
    let companionFiles: [CompanionFile]      // NEW
    let preferredTarget: DLLPlacementTarget  // NEW
    let isSystemDLL: Bool                    // NEW — for autoDetect
}

// Updated registry entry:
KnownDLL(
    name: "cnc-ddraw",
    dllFileName: "ddraw.dll",
    githubOwner: "FunkyFr3sh",
    githubRepo: "cnc-ddraw",
    assetPattern: "cnc-ddraw.zip",
    description: "DirectDraw replacement for classic 2D games via OpenGL/D3D9",
    requiredOverrides: ["ddraw": "n,b"],
    companionFiles: [
        CompanionFile(
            filename: "ddraw.ini",
            content: "[ddraw]\nrenderer=opengl\nfullscreen=true\nhandlemouse=true\nadjmouse=true\ndevmode=0\nmaxgameticks=0\nnonexclusive=false\nsinglecpu=true"
        )
    ],
    preferredTarget: .syswow64,
    isSystemDLL: true
)
```

### New Tool: trace_launch

```swift
// Source: .planning/agentic-architecture-v2.md — trace_launch tool design
// Add to AgentTools.swift

private func traceLaunch(input: JSONValue) -> String {
    let channels = input["debug_channels"]?.asArray?.compactMap { $0.asString } ?? ["+loaddll"]
    let timeoutSeconds = input["timeout_seconds"]?.asInt ?? 5

    var env = accumulatedEnv
    let debugStr = channels.joined(separator: ",")
    let existing = env["WINEDEBUG"] ?? ""
    env["WINEDEBUG"] = existing.isEmpty ? debugStr : "\(existing),\(debugStr)"

    let process = Process()
    process.executableURL = wineProcess.wineBinary
    process.arguments = [executablePath]
    let binaryURL = URL(fileURLWithPath: executablePath)
    process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

    var fullEnv = ProcessInfo.processInfo.environment
    fullEnv["WINEPREFIX"] = wineProcess.winePrefix.path
    for (k, v) in env { fullEnv[k] = v }
    process.environment = fullEnv

    let stderrPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = stderrPipe

    let stderrCapture = StderrCapture()
    stderrPipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        guard !data.isEmpty else { return }
        if let str = String(data: data, encoding: .utf8) { stderrCapture.append(str) }
    }

    let killWorkItem = DispatchWorkItem { [weak process] in
        process?.terminate()
        try? self.wineProcess.killWineserver()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeoutSeconds), execute: killWorkItem)

    do { try process.run() } catch {
        killWorkItem.cancel()
        return jsonResult(["error": "Failed to start trace: \(error.localizedDescription)"])
    }

    process.waitUntilExit()
    killWorkItem.cancel()

    let rawStderr = stderrCapture.value
    let loadedDLLs = parseLoaddllOutput(rawStderr)
    let errors = parseWineErrors(rawStderr)

    return jsonResult([
        "loaded_dlls": loadedDLLs.map { ["name": $0.name, "path": $0.path, "type": $0.type] },
        "errors": errors,
        "timeout_applied": process.terminationReason == .uncaughtSignal
    ])
}
```

### New Tool: write_game_file

```swift
// Source: .planning/agentic-architecture-v2.md — write_game_file tool design
private func writeGameFile(input: JSONValue) -> String {
    guard let relativePath = input["relative_path"]?.asString, !relativePath.isEmpty else {
        return jsonResult(["error": "relative_path is required"])
    }
    guard let content = input["content"]?.asString else {
        return jsonResult(["error": "content is required"])
    }

    let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
    // Convert Windows backslash paths to forward slash
    let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
    let targetURL = gameDir.appendingPathComponent(normalizedPath)

    do {
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: targetURL, atomically: true, encoding: .utf8)
        return jsonResult(["status": "ok", "written_to": targetURL.path])
    } catch {
        return jsonResult(["error": "Failed to write file: \(error.localizedDescription)"])
    }
}
```

### New Tool: search_web (using URLSession)

```swift
// Pattern: direct HTTP to a search endpoint
// The CONTEXT.md decides to use WineHQ, ProtonDB, PCGamingWiki as targets
// search_web queries these via their search pages using URLSession.shared
private func searchWeb(input: JSONValue) -> String {
    guard let query = input["query"]?.asString, !query.isEmpty else {
        return jsonResult(["error": "query is required"])
    }

    // Check research cache first
    let cacheURL = CellarPaths.researchCacheFile(for: gameId)
    if let cached = loadResearchCache(at: cacheURL), !cached.isStale() {
        return jsonResult(["results": cached.results, "from_cache": true])
    }

    // Use DuckDuckGo HTML search (no API key required)
    let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
    guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
        return jsonResult(["error": "Invalid query URL"])
    }

    var request = URLRequest(url: url)
    request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

    // Synchronous fetch using established ResultBox pattern
    final class ResultBox: @unchecked Sendable {
        var value: Result<Data, Error> = .failure(URLError(.badURL))
    }
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: request) { data, _, error in
        box.value = error.map { .failure($0) } ?? data.map { .success($0) } ?? .failure(URLError(.badURL))
        semaphore.signal()
    }.resume()
    semaphore.wait()

    // Extract results from HTML (strip tags, extract snippets)
    guard let data = try? box.value.get(),
          let html = String(data: data, encoding: .utf8) else {
        return jsonResult(["error": "Failed to fetch search results"])
    }

    let results = parseSearchResults(html)
    // Cache results
    saveResearchCache(results: results, at: cacheURL)

    return jsonResult(["results": results, "from_cache": false])
}
```

### SuccessRecord Codable Schema

```swift
// Source: .planning/agentic-architecture-v2.md — success DB schema
// File: Sources/cellar/Core/SuccessDatabase.swift (new file)

struct SuccessRecord: Codable {
    let schemaVersion: Int              // 1
    let gameId: String
    let gameName: String
    let gameVersion: String?
    let source: String?                 // "gog", "steam"
    let engine: String?
    let graphicsApi: String?
    let verifiedAt: String              // ISO8601 date string
    let wineVersion: String?
    let bottleType: String?             // "wow64"
    let os: String?
    let executable: ExecutableInfo
    let workingDirectory: WorkingDirectoryInfo?
    let environment: [String: String]
    let dllOverrides: [DLLOverrideRecord]
    let gameConfigFiles: [GameConfigFile]
    let registry: [RegistryRecord]
    let gameSpecificDlls: [GameSpecificDLL]
    let pitfalls: [PitfallRecord]
    let resolutionNarrative: String?
    let tags: [String]
}

struct PitfallRecord: Codable {
    let symptom: String
    let cause: String
    let fix: String
    let wrongFix: String?
}

// ... nested types follow same pattern
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Linear config-search (v1 agent loop) | Three-phase Research-Diagnose-Adapt | Phase 7 | Non-linear pivots based on evidence, not blind retry |
| save_recipe (env vars + registry only) | save_success (full record with pitfalls, narrative, DLL chain) | Phase 7 | Captures WHY, not just WHAT |
| Single DLL placement target (game_dir, system32) | Three targets (game_dir, system32, syswow64) | Phase 7 | Fixes wow64 DLL search order bug |
| Static 500-word system prompt | Live web research + success DB + updated domain knowledge | Phase 7 | Agent can discover game-specific requirements |
| launch_game only (full launches) | trace_launch (diagnostic) + launch_game (real) | Phase 7 | Cheaper investigation before committing to full launch |
| WineProcess without CWD setting | WineProcess always sets CWD to binary's parent | Phase 7 | Fixes relative-path file access failures |

**Deprecated/outdated after Phase 7:**
- `save_recipe` tool: replaced by `save_success` (save_recipe can remain for backward compat but save_success is the preferred path after a successful session)
- Virtual desktop suggestion in system prompt: removed (non-functional on macOS winemac.drv)

---

## Open Questions

1. **Web search API selection for `search_web`**
   - What we know: The CONTEXT.md says "search for game-specific Wine compatibility info (WineHQ, ProtonDB, PCGamingWiki, forums)" but doesn't specify which search API to use
   - What's unclear: DuckDuckGo HTML search is no-key but may be rate-limited or change structure; Brave Search API costs money; a direct fetch to WineHQ AppDB search is more reliable for Wine-specific queries
   - Recommendation: Implement `search_web` as a direct fetch to WineHQ AppDB (`https://appdb.winehq.org/objectManager.php?sClass=application&sTitle=<query>`), PCGamingWiki (`https://www.pcgamingwiki.com/w/index.php?search=<query>`), and ProtonDB search (`https://www.protondb.com/search?q=<query>`) — three targeted URLs rather than general web search. This matches the CONTEXT.md's explicit list of target sites and avoids API key requirements.

2. **HTML-to-text extraction depth for `fetch_page`**
   - What we know: Agent needs readable text from game compatibility pages; SwiftSoup is not an option (no dependencies)
   - What's unclear: Simple regex tag stripping may mangle tables (WineHQ AppDB has config tables); structured extraction would help the agent find env vars in table format
   - Recommendation: Strip HTML tags with regex, then apply lightweight cleanup (collapse whitespace, decode basic entities `&amp; &lt; &gt;`). Return up to 8000 chars. The agent (Claude) is good at extracting info from messy text.

3. **Fuzzy symptom matching in `query_successdb`**
   - What we know: The CONTEXT.md specifies "fuzzy match against pitfalls" for symptom queries
   - What's unclear: "Fuzzy" is ambiguous — Levenshtein, keyword overlap, or something else?
   - Recommendation: Use keyword overlap: lowercase both query and stored symptom, split into words, count overlap. Score = overlapping words / max(query words, symptom words). Return records where score > 0.3. This is sufficient for the small corpus (tens of records) and avoids complexity.

4. **Parallel research implementation with DispatchGroup**
   - What we know: CONTEXT.md says "Parallel research: WineHQ + ProtonDB + PCGamingWiki concurrently"; codebase is synchronous (no async/await)
   - What's unclear: Parallel URLSession calls from a synchronous context require careful semaphore management
   - Recommendation: Use `DispatchGroup` with three `URLSession.dataTask` calls, each signaling the group on completion. Wait on the group with `dispatchGroup.wait()`. This is the correct concurrent pattern for the synchronous codebase without introducing async.

---

## Implementation Order (Recommended)

The planner should sequence work in three waves based on dependency order and risk:

**Wave 1 — P0 Infrastructure Fixes (no new tools, just fixes)**
1. `WineProcess.run()` CWD fix — one line change, unblocks everything
2. `DLLPlacementTarget.syswow64` + `KnownDLL` companion files — enables correct DLL placement
3. `place_dll` syswow64 support + companion file writing
4. `write_game_file` new tool — simple file write, low risk
5. System prompt update — remove virtual desktop, add domain knowledge

**Wave 2 — Diagnostic Tools (medium complexity)**
6. Enhanced `inspect_game` — objdump PE imports, bottle type detection, data files
7. `trace_launch` — timed Wine launch with debug channels, parsed output
8. `check_file_access` — file existence comparison, low complexity
9. `verify_dll_override` — combines trace_launch result with config state

**Wave 3 — Research Tools + Success DB (new subsystem)**
10. `SuccessDatabase.swift` + `CellarPaths` extensions
11. `query_successdb` + `save_success` tools
12. `search_web` + `fetch_page` tools + research cache
13. `launch_game` enhancement (pre-flight check, structured DLL analysis)

---

## Sources

### Primary (HIGH confidence)
- Direct codebase reading — `AgentTools.swift`, `AgentLoop.swift`, `AIService.swift`, `WineProcess.swift`, `KnownDLLRegistry.swift`, `WineErrorParser.swift`, `CellarPaths.swift` — all implementation patterns verified against actual code
- `.planning/agentic-architecture-v2.md` — PRD with full schema, code examples, infrastructure bug list
- `.planning/phases/07-agentic-v2-.../07-CONTEXT.md` — locked decisions and discretion areas

### Secondary (MEDIUM confidence)
- LLVM D113356 review — confirms `objdump -p` PE import support on macOS LLVM objdump
- Wine GitLab Debug Channels wiki — confirms `+loaddll` trace format (channel prefix, function name, log line format)

### Tertiary (LOW confidence, single source)
- DuckDuckGo HTML search as `search_web` backend — unverified rate limits/stability for programmatic use; recommend using targeted site fetches instead (see Open Questions #1)

---

## Metadata

**Confidence breakdown:**
- Infrastructure fixes (CWD, syswow64, companionFiles): HIGH — all changes are surgical and well-specified in architecture doc with exact code
- New tool implementations (write_game_file, check_file_access, write_game_file): HIGH — follow established tool handler pattern exactly
- trace_launch + loaddll parsing: MEDIUM — format is documented but macOS-specific output variations are possible
- search_web / fetch_page HTML extraction: MEDIUM — URLSession pattern is HIGH confidence; HTML extraction from arbitrary sites is inherently fragile
- SuccessDatabase schema and persistence: HIGH — straightforward Codable JSON following existing patterns

**Research date:** 2026-03-27
**Valid until:** 2026-04-27 (30 days — stable domain, Swift Foundation APIs don't change)
