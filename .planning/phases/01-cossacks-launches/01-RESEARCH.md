# Phase 1: Cossacks Launches - Research

**Researched:** 2026-03-25
**Domain:** Swift 6 CLI tool, Wine/Gcenx subprocess management, GOG installer automation, recipe-driven bottle configuration
**Confidence:** HIGH (stack), MEDIUM (Cossacks-specific Wine config), HIGH (architecture patterns)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**CLI Flow Design**
- `cellar` with no arguments on a fresh Mac: immediately detect missing deps and walk user through interactive setup
- Two-step game flow: `cellar add /path/to/game` first, then `cellar launch cossacks` by name
- Game name auto-derived from directory name (no `--name` flag needed)
- Output style: informative — a few lines per action explaining what's happening ("Creating bottle... Applying recipe... Launching Wine..."), not minimal and not verbose
- After setup is complete and deps are present, `cellar` shows status + next step: "All dependencies found. Run `cellar add /path/to/game` to get started."

**Guided Install UX**
- Auto-run installs: Cellar runs `brew install` etc. directly — user watches progress
- Stream Homebrew's own output in real-time during installation (no spinner/summary)
- Let Homebrew handle Xcode CLT detection and prompts — don't duplicate
- On install failure: show error and offer retry, with manual steps as fallback
- No pre-check for Xcode CLT separately

**Recipe Contents**
- Target: GOG original edition of Cossacks: European Wars specifically (one version only)
- Recipe specifies the exact EXE to launch (no scanning/asking)
- Full experience recipe: launch config + display settings (resolution, windowed mode) + audio + performance tweaks + known crash workarounds
- Recipe lives in `recipes/cossacks-european-wars.json` in the project repo root
- Wine settings in recipe use Wine-native formats: registry edits as .reg file content, DLL overrides as Wine env var format
- Full transparency when applying: show each registry key being set, like a diff
- Cellar runs the GOG installer (setup.exe) inside the Wine bottle — user points `cellar add` at the installer, not pre-installed files

**Validation + Logging**
- Wine stdout/stderr streams to terminal in real-time while game runs
- Also captured to log file simultaneously: `~/.cellar/logs/{game}/{timestamp}.log`
- Immediate validation prompt when Wine process exits: "Did the game reach the menu? [y/n]"
- Quick-exit detection: if Wine exits in < 2 seconds, flag as likely crash, skip validation prompt, suggest checking logs
- Record just success/failure flag in game metadata (no detailed failure description in v1)
- `cellar log` design: Claude's discretion
- After game exits: ask user "Shut down Wine services? [y/n]"
- Ctrl+C during game: kill Wine process but still ask validation question
- Wineserver cleanup on Ctrl+C: terminate game process only, leave wineserver decision to post-exit prompt

### Claude's Discretion
- `cellar log` command design (list vs show last vs both)
- Exact JSON schema for recipe files (following Wine-native format decision)
- Loading/progress indicators during bottle creation
- Error message wording
- `cellar status` output format
- ~/.cellar/ directory structure details

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SETUP-01 | Cellar detects whether Homebrew is installed (ARM and Intel paths) | Check `/opt/homebrew/bin/brew` (ARM) and `/usr/local/bin/brew` (Intel); use `FileManager.fileExists` or `Process` to check |
| SETUP-02 | Cellar detects whether Wine is installed via Gcenx Homebrew tap | Check for `wine` or `wine64` binary in Homebrew bin path; verify Gcenx tap via `brew tap list` or formula name |
| SETUP-03 | Cellar guides user through installing Homebrew if missing | Run official Homebrew install script via `Process`; stream output in real-time via `Pipe` + `readabilityHandler`; let Homebrew handle CLT |
| SETUP-04 | Cellar guides user through installing Wine (Gcenx tap) if missing | `brew tap gcenx/wine` then `brew install --no-quarantine gcenx/wine/wine-crossover`; `--no-quarantine` required to prevent Gatekeeper damage error |
| SETUP-05 | Cellar detects whether GPTK is installed on the system | Check for GPTK presence at known install paths; detect-only, no installation |
| BOTTLE-01 | Cellar creates an isolated WINEPREFIX per game automatically on first launch | Path: `~/.cellar/bottles/{game-id}/`; create with `wineboot --init`; set `WINEPREFIX` env var on every Wine invocation |
| RECIPE-01 | Cellar ships with a bundled recipe for Cossacks: European Wars | JSON file at `recipes/cossacks-european-wars.json` in repo; bundled with binary at install time |
| RECIPE-02 | Recipes auto-apply on launch (registry edits, DLL overrides, env vars, launch args) | Apply .reg content via `wine regedit`; DLL overrides via `WINEDLLOVERRIDES` env var; env vars set on `Process.environment` |
| LAUNCH-01 | User can launch a game via Wine with correct WINEPREFIX and recipe flags | `Process` with `WINEPREFIX` + recipe env vars; `wine` binary path from detected Homebrew install |
| LAUNCH-02 | Cellar captures Wine stdout/stderr to per-launch log files | `Pipe` on both stdout and stderr; `readabilityHandler` for real-time terminal streaming + simultaneous file write |
| LAUNCH-03 | After launch, Cellar asks user if the game reached the menu (validation prompt) | Prompt on `Process.terminationHandler`; skip if exit time < 2s (crash); record flag in game metadata JSON |
</phase_requirements>

---

## Summary

Phase 1 builds the complete end-to-end pipeline for a single game: from detecting missing dependencies on a fresh Mac, through installing them automatically, to creating a Wine bottle, applying a configuration recipe, running the GOG installer, launching the game, and capturing validation. Every component is new (greenfield project), so Phase 1 simultaneously establishes the project scaffold and delivers working functionality.

The technical core is two-layered. The outer layer is a Swift 6 CLI using Swift Argument Parser with two subcommands for this phase (`cellar` with no args for setup/status, `cellar add` for adding a game, `cellar launch` for launch). The inner layer is Wine subprocess management using `Foundation.Process` with real-time output streaming via `Pipe` and `FileHandle.readabilityHandler`. The Cossacks-specific configuration is captured in a bundled JSON recipe that drives registry edits, DLL overrides, and launch arguments.

Key research discovery: the GOG installer for Cossacks requires special handling. The default argument list from GOG includes Windows-style backslash paths (video file intros) that must be escaped when passed through a shell, and the game requires `WINE_CPU_TOPOLOGY` (single CPU affinity) on modern Wine versions to prevent crashes. The `wine-crossover` package from the Gcenx tap requires `--no-quarantine` during installation to prevent macOS Gatekeeper from treating the bundle as damaged.

**Primary recommendation:** Build in this order: (1) Swift Package scaffold + CLI entry point, (2) dependency detection + guided install, (3) bottle creation, (4) recipe loading and application, (5) Wine process launch with streaming, (6) validation prompt. Each step is independently testable.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.x | Language | Native Foundation.Process, Codable, compiles to single binary |
| Swift Argument Parser | 1.7.1 | CLI subcommand parsing | Official Apple library, type-safe, zero boilerplate |
| Foundation.Process | (stdlib) | Wine subprocess management | Native macOS, full process lifecycle + Pipe support |
| Foundation.JSONDecoder | (stdlib) | Recipe file parsing | Built-in Codable, no extra dependencies |
| Foundation.FileManager | (stdlib) | Directory/file creation | Standard macOS file ops |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Package Manager | (stdlib) | Build system | `swift build` from command line — no Xcode needed |
| macOS Foundation Pipe | (stdlib) | stdout/stderr capture + streaming | Attach to Process for real-time output |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Foundation.Process | swift-subprocess (swiftlang) | swift-subprocess is in 1.0 review (2026) but not yet stable; Foundation.Process is battle-tested and sufficient |
| readabilityHandler | Dispatch I/O | DispatchIO is preferred for large-volume pipes per Apple but readabilityHandler is simpler for Wine output volumes |

**Installation (Package.swift):**
```swift
dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
],
targets: [
    .executableTarget(name: "cellar", dependencies: [
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
    ]),
]
```

**Swift build command:**
```bash
swift build -c release
```

---

## Architecture Patterns

### Recommended Project Structure
```
Sources/
├── cellar/              # Main executable target
│   ├── main.swift       # @main entry point — CellarCLI root command
│   ├── Commands/
│   │   ├── StatusCommand.swift    # `cellar` (no args) / `cellar status`
│   │   ├── AddCommand.swift       # `cellar add /path/to/setup.exe`
│   │   └── LaunchCommand.swift    # `cellar launch <game>`
│   ├── Core/
│   │   ├── DependencyChecker.swift  # Homebrew + Wine + GPTK detection
│   │   ├── BottleManager.swift      # WINEPREFIX creation + management
│   │   ├── RecipeEngine.swift       # Load + apply recipe to bottle
│   │   ├── WineProcess.swift        # Process spawn + pipe management
│   │   └── ValidationPrompt.swift   # Post-launch prompt + metadata write
│   ├── Models/
│   │   ├── Recipe.swift             # Codable recipe struct
│   │   ├── GameEntry.swift          # Codable game library entry
│   │   └── LaunchResult.swift       # Validation result struct
│   └── Persistence/
│       └── CellarStore.swift        # ~/.cellar/ read/write
recipes/
└── cossacks-european-wars.json      # Bundled recipe (shipped with binary)
Package.swift
```

**`~/.cellar/` runtime directory structure:**
```
~/.cellar/
├── games.json                       # Game library (array of GameEntry)
├── bottles/
│   └── cossacks-european-wars/      # WINEPREFIX root
│       └── (Wine prefix contents)
└── logs/
    └── cossacks-european-wars/
        └── 2026-03-25T14-30-00.log  # Per-launch log
```

### Pattern 1: Swift Argument Parser Subcommand Structure
**What:** Root `ParsableCommand` with subcommands registered via `subcommands` property. `cellar` with no args becomes the default behavior.
**When to use:** All CLI entry points in this phase.
**Example:**
```swift
// Source: https://apple.github.io/swift-argument-parser/documentation/argumentparser/
import ArgumentParser

@main
struct Cellar: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cellar",
        abstract: "Wine game launcher for old PC games",
        subcommands: [AddCommand.self, LaunchCommand.self, StatusCommand.self],
        defaultSubcommand: StatusCommand.self
    )
}
```

### Pattern 2: Real-Time Process Output Streaming
**What:** Attach `Pipe` to both stdout and stderr; use `readabilityHandler` to forward data to terminal AND append to log file simultaneously.
**When to use:** All Wine subprocess launches (installer, wineboot, game launch).
```swift
// Source: Apple Developer Documentation — FileHandle.readabilityHandler
let process = Process()
let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

let logFileHandle = /* open log file for writing */

stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else { return }
    // Write to terminal
    FileHandle.standardOutput.write(data)
    // Capture to log file
    logFileHandle.write(data)
}
stderrPipe.fileHandleForReading.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty else { return }
    FileHandle.standardError.write(data)
    logFileHandle.write(data)
}
```

### Pattern 3: WINEPREFIX-Scoped Wine Process
**What:** Every Wine invocation (`wine`, `wineboot`, `regedit`) MUST set `WINEPREFIX` in `process.environment`. Never rely on the default `~/.wine`.
**When to use:** Every single Wine subprocess in the entire project.
```swift
// Canonical Wine subprocess launch pattern
func makeWineProcess(winePrefix: URL, binary: String, arguments: [String] = []) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: wineBinaryPath)
    process.arguments = [binary] + arguments
    var env = ProcessInfo.processInfo.environment
    env["WINEPREFIX"] = winePrefix.path
    process.environment = env
    return process
}
```

### Pattern 4: Homebrew Path Detection
**What:** Check both ARM and Intel Homebrew paths explicitly. Do not use `which brew` (can be wrong in a restricted PATH).
**When to use:** Dependency checker, any code that resolves Wine binary path.
```swift
// Source: Homebrew official docs — brew.sh/Installation
func detectHomebrew() -> URL? {
    let armPath = "/opt/homebrew/bin/brew"   // Apple Silicon
    let intelPath = "/usr/local/bin/brew"     // Intel
    for path in [armPath, intelPath] {
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
    }
    return nil
}
```

### Pattern 5: Recipe Application — Registry via regedit
**What:** Write .reg file content to a temp file, run `wine regedit /path/to/file.reg` inside the bottle's WINEPREFIX.
**When to use:** Applying recipe registry settings.
```swift
// Apply .reg content string from recipe
func applyRegistryFile(content: String, winePrefix: URL) throws {
    let tempReg = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".reg")
    try content.write(to: tempReg, atomically: true, encoding: .utf8)
    let process = makeWineProcess(winePrefix: winePrefix, binary: "regedit")
    process.arguments = [tempReg.path]
    try process.run()
    process.waitUntilExit()
    try? FileManager.default.removeItem(at: tempReg)
}
```

### Pattern 6: SIGINT / Ctrl+C Handling
**What:** Trap SIGINT with `DispatchSourceSignal` to cleanly terminate the Wine game process and still show the validation prompt.
**When to use:** Game launch command only.
```swift
// Source: Multiple verified sources — signal handling in Swift CLI
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
signal(SIGINT, SIG_IGN)  // prevent default termination
sigintSource.setEventHandler {
    wineGameProcess.terminate()
    // validation prompt will fire from terminationHandler
}
sigintSource.resume()
```

### Anti-Patterns to Avoid
- **Default WINEPREFIX:** Never invoke `wine` without setting `WINEPREFIX` explicitly. Cross-contamination between games is a critical failure mode.
- **Process.launch() (deprecated):** Use `Process.run()` (throws on failure) instead of the deprecated `launch()`.
- **Blocking main thread on process output:** Use `readabilityHandler` or background threads; never `process.standardOutput.fileHandleForReading.readDataToEndOfFile()` for long-running processes — it blocks and prevents Ctrl+C handling.
- **Shell-interpolating Windows paths:** Never pass `.\videos\cdv.avi` style paths through a shell — backslashes get eaten. Pass arguments as an array to `Process.arguments`, not as a shell command string.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| CLI argument parsing | Custom argv parser | Swift Argument Parser | Type-safe, handles help, errors, completion |
| JSON encode/decode | Manual string building | Foundation Codable | Schema migration, safety, less code |
| File path expansion | Manual `~` replacement | `URL(fileURLWithPath:).standardized` + `NSString.expandingTildeInPath` | Edge cases in path expansion |
| Process stdout capture | `system()` or shell redirect | `Foundation.Process` + `Pipe` | `system()` gives no stdout access; shell redirect loses real-time streaming |
| Wine prefix per game | Shared ~/.wine prefix | Isolated `~/.cellar/bottles/{id}/` | Game configs leak into each other permanently |
| Registry edits | Direct file manipulation of `system.reg` | `wine regedit file.reg` | Wine manages registry format internally; direct edits corrupt state |

**Key insight:** Wine's registry files (`system.reg`, `user.reg`) are managed internally by Wine and must only be modified through `wine regedit`. Direct file editing causes unpredictable corruption.

---

## Common Pitfalls

### Pitfall 1: Gcenx wine-crossover Requires `--no-quarantine`
**What goes wrong:** `brew install gcenx/wine/wine-crossover` succeeds but macOS Gatekeeper marks the bundle as "damaged" and refuses to run it. Users see: "wine-crossover is damaged and can't be opened."
**Why it happens:** Homebrew adds the quarantine extended attribute to downloaded casks by default. Wine bundles are not notarized in the standard way, so Gatekeeper rejects them.
**How to avoid:** Always install with `--no-quarantine` flag:
```bash
brew install --no-quarantine gcenx/wine/wine-crossover
```
**Warning signs:** Gatekeeper damage error on first `wine` invocation after install.

### Pitfall 2: GOG Installer Argument Escaping
**What goes wrong:** The GOG Cossacks installer's post-install launch arguments contain Windows-style backslash paths (`.\videos\cdv.avi`). When these are passed through a shell, backslashes get eaten and the launched game process fails immediately.
**Why it happens:** The GOG installer setup registers a post-install launch command that includes video intro paths as arguments. These are Windows paths, not POSIX paths.
**How to avoid:** Pass installer arguments as a Swift array to `Process.arguments` (not as a shell string). Do NOT use `/bin/sh -c "wine setup.exe .\videos\..."`. Use `process.arguments = ["setup.exe"]` without the post-install video arguments, or escape backslashes explicitly.
**Warning signs:** Game exits in < 2s immediately after `cellar add` runs the installer — likely the post-install launch step failing.

### Pitfall 3: Wine Crashes Without CPU Affinity Fix
**What goes wrong:** Cossacks exits immediately or crashes on launch on modern Wine versions (Wine 8+). This is a known Lutris-documented issue.
**Why it happens:** The game has threading behavior that breaks on multi-core Wine. Setting CPU topology to single-core fixes it.
**How to avoid:** Include in recipe's env vars:
```
WINE_CPU_TOPOLOGY=1:0
```
Or use `taskset`-equivalent. The Lutris configuration confirms `single_cpu: true` is required.
**Warning signs:** Quick-exit (< 2s) on launch with no DirectX error in logs; or crash in game logic shortly after menu appears.

### Pitfall 4: readabilityHandler EOF Not Called Reliably
**What goes wrong:** After the Wine process exits, `readabilityHandler` may not be called for the final bytes of stdout/stderr. Some data is lost from the log.
**Why it happens:** Known Foundation bug (tracked in swift-corelibs-foundation issue #3275) — `readabilityHandler` on Pipe sometimes does not fire on EOF.
**How to avoid:** After `process.waitUntilExit()`, drain any remaining data:
```swift
process.terminationHandler = { proc in
    // Drain remaining bytes after exit
    let remaining = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    if !remaining.isEmpty {
        FileHandle.standardOutput.write(remaining)
        logFileHandle.write(remaining)
    }
}
```
**Warning signs:** Log file truncated at the end; last Wine error message not appearing.

### Pitfall 5: Wineboot Blocks Indefinitely on First Prefix Init
**What goes wrong:** `wineboot --init` on a fresh WINEPREFIX takes 30-60+ seconds on first run. If Cellar doesn't stream output, the terminal appears frozen. Users kill it mid-init, leaving a corrupt prefix.
**Why it happens:** Wine initializes its fake Windows registry, installs Mono/Gecko prompts (if not suppressed), and runs several Wine services on first boot.
**How to avoid:** Always stream wineboot output in real-time. Suppress Gecko/Mono dialogs with env vars:
```
WINEDLLOVERRIDES=mscoree,mshtml=  (empty = disable Mono/Gecko prompts)
```
Or: `WINEDEBUG=-all` to reduce noise. Show the user a message: "Initializing Wine bottle (first-time setup, ~30 seconds)..."
**Warning signs:** Silent hang for 30+ seconds during `cellar add`.

### Pitfall 6: Apple Silicon Wine Architecture Mismatch
**What goes wrong:** Wine binary is x86_64 (running under Rosetta) but is invoked from an arm64 Swift binary in an arm64 shell context. Path resolution, `DYLD_*` env vars, and some Foundation behaviors differ between architectures.
**Why it happens:** `wine-crossover` from Gcenx may be x86_64-only. Swift CLI compiles as arm64 native on Apple Silicon. These can coexist but PATH and env inheritance must be explicit.
**How to avoid:** Do not rely on `$PATH` to find `wine`. Resolve the full path to the wine binary from the detected Homebrew prefix:
- ARM Homebrew: `/opt/homebrew/bin/wine`
- Intel Homebrew: `/usr/local/bin/wine`

### Pitfall 7: Log File Directory Not Created Before Write
**What goes wrong:** Writing to `~/.cellar/logs/cossacks-european-wars/2026-03-25T14-30.log` fails because intermediate directories don't exist.
**Why it happens:** `FileHandle(forWritingAtPath:)` does not create directories. Fails silently if directory is absent.
**How to avoid:** Always call `FileManager.default.createDirectory(at:withIntermediateDirectories:true)` before opening the log file.

---

## Code Examples

### Verified Patterns from Official/Authoritative Sources

#### Dependency Detection — Homebrew
```swift
// Source: Homebrew official docs (brew.sh/Installation) + verified with multiple sources
func brewPath() -> URL? {
    let candidates = [
        "/opt/homebrew/bin/brew",  // Apple Silicon (M1/M2/M3)
        "/usr/local/bin/brew",     // Intel Mac
    ]
    return candidates.compactMap { path -> URL? in
        FileManager.default.fileExists(atPath: path)
            ? URL(fileURLWithPath: path)
            : nil
    }.first
}
```

#### Dependency Detection — Wine via Gcenx
```swift
// Wine binary is in the same Homebrew bin directory as brew
func wineBinaryPath(brewPrefix: URL) -> URL? {
    let brewBinDir = brewPrefix.deletingLastPathComponent()  // .../bin/
    let candidates = ["wine64", "wine"].map { brewBinDir.appendingPathComponent($0) }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}
```

#### Install Homebrew (streaming output)
```swift
// Source: Foundation.Process + Pipe pattern
func installHomebrew() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c",
        #"curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh | bash"#
    ]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    pipe.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if !data.isEmpty { FileHandle.standardOutput.write(data) }
    }
    try process.run()
    process.waitUntilExit()
}
```

#### Install wine-crossover via Gcenx tap
```bash
# Source: Gcenx/homebrew-wine README — --no-quarantine is required
brew tap gcenx/wine
brew install --no-quarantine gcenx/wine/wine-crossover
```

#### Create Wine Bottle
```swift
// Source: WineHQ docs + ARCHITECTURE.md
func createBottle(at prefixPath: URL) throws {
    try FileManager.default.createDirectory(
        at: prefixPath,
        withIntermediateDirectories: true
    )
    let wineboot = Process()
    wineboot.executableURL = wineBinaryURL.deletingLastPathComponent()
        .appendingPathComponent("wineboot")
    wineboot.arguments = ["--init"]
    var env = ProcessInfo.processInfo.environment
    env["WINEPREFIX"] = prefixPath.path
    env["WINEDLLOVERRIDES"] = "mscoree,mshtml="  // suppress Gecko/Mono popups
    wineboot.environment = env
    // stream output as per Pattern 2...
    try wineboot.run()
    wineboot.waitUntilExit()
}
```

#### Run GOG Installer (setup.exe) Inside Bottle
```swift
// Source: Lutris config research + GOG installer argument escaping findings
// IMPORTANT: Do NOT pass post-install video args; use process.arguments array, not shell string
func runGOGInstaller(setupExe: URL, winePrefix: URL) throws {
    let process = Process()
    process.executableURL = wineBinaryURL
    // Pass only the installer path — no shell, no backslash paths
    process.arguments = [setupExe.path, "/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"]
    var env = ProcessInfo.processInfo.environment
    env["WINEPREFIX"] = winePrefix.path
    process.environment = env
    // attach pipes for streaming...
    try process.run()
    process.waitUntilExit()
}
```

#### Validation Prompt with Quick-Exit Detection
```swift
// Source: CONTEXT.md decisions
func runLaunchAndValidate(process: Process, gameId: String) throws {
    let startTime = Date()
    // ... set up pipes, SIGINT handler ...
    try process.run()
    process.waitUntilExit()

    let elapsed = Date().timeIntervalSince(startTime)
    if elapsed < 2.0 {
        print("Wine exited in \(String(format: "%.1f", elapsed))s — likely a crash.")
        print("Check logs: ~/.cellar/logs/\(gameId)/")
        return
    }

    print("Shut down Wine services? [y/n] ", terminator: "")
    let shutdown = readLine()?.lowercased() == "y"
    if shutdown { /* WINEPREFIX wineserver -k */ }

    print("Did the game reach the menu? [y/n] ", terminator: "")
    let reached = readLine()?.lowercased() == "y"
    // record reached flag in game metadata JSON
}
```

---

## Recipe Schema (Claude's Discretion — Recommended Design)

```json
{
  "id": "cossacks-european-wars",
  "name": "Cossacks: European Wars",
  "version": "2.1.0.13",
  "source": "gog",
  "executable": "dmln.exe",
  "wine_tested_with": "wine-crossover-23.7.1",
  "environment": {
    "WINE_CPU_TOPOLOGY": "1:0",
    "WINEDLLOVERRIDES": "ddraw=n,b"
  },
  "registry": [
    {
      "description": "Set screen resolution to 1024x768 windowed",
      "reg_content": "Windows Registry Editor Version 5.00\n\n[HKEY_CURRENT_USER\\Software\\GSC Game World\\Cossacks - European Wars]\n\"ScreenWidth\"=dword:00000400\n\"ScreenHeight\"=dword:00000300\n\"Windowed\"=dword:00000001"
    }
  ],
  "launch_args": [],
  "notes": "Requires single CPU affinity (WINE_CPU_TOPOLOGY=1:0) on Wine 8+. GOG version 2.1.0.13."
}
```

**Schema decisions:**
- `reg_content`: Verbatim .reg file text — applied via `wine regedit`. Shown line-by-line to user for transparency.
- `environment`: Merged into process environment. Keys shown to user as "Setting WINE_CPU_TOPOLOGY=1:0".
- `executable`: Relative to game install dir inside bottle, not absolute path — bottle-portable.
- `wine_tested_with`: Informational; warn if user's version differs significantly.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `wine-stable` via official Homebrew tap | `gcenx/wine/wine-crossover` via Gcenx tap | 2023 (deprecated 2026-09-01) | Must use Gcenx tap or wine fails to install via Homebrew |
| `Process.launch()` | `Process.run()` (throws) | Swift 5.4 | `launch()` deprecated — use `run()` which throws on failure |
| `NSTask` | `Foundation.Process` | macOS 10.11 | Rename only; API is the same |
| Manual signal handling with `signal()` | `DispatchSource.makeSignalSource` | Swift 3+ | Thread-safe; works with async patterns |
| Piping via shell string (`/bin/sh -c "wine ..."`) | `Process.arguments` array | N/A | Avoids shell escaping issues with Windows paths |

**Deprecated/outdated:**
- `Process.launch()`: Deprecated in favor of `Process.run()` — throws instead of crashing on missing executable.
- `wine-stable` Homebrew cask: Disable date 2026-09-01. All new installs must use Gcenx tap.
- WINEARCH=win32 prefix creation: `wine-crossover` does NOT support 32-bit-only prefixes. Default 64-bit prefix supports both 32-bit and 64-bit apps — this is the correct behavior for Cossacks (32-bit game in 64-bit prefix).

---

## Open Questions

1. **Cossacks-specific registry keys for display configuration**
   - What we know: The game reads resolution/windowed settings from `HKCU\Software\GSC Game World\Cossacks - European Wars` (likely) and/or a .ini-style config file
   - What's unclear: Exact registry path and key names for GOG version 2.1.0.13. PCGamingWiki returned 403. Lutris script did not detail registry paths.
   - Recommendation: Test against actual GOG installer during Wave 0 (bottle + recipe task). Read the game's config file after first run to reverse-engineer settings.

2. **`--no-quarantine` flag propagation**
   - What we know: `--no-quarantine` must be passed to `brew install` for wine-crossover
   - What's unclear: Whether Cellar can programmatically remove quarantine after a standard install using `xattr -rd com.apple.quarantine /path/to/wine-crossover.app` as a fallback
   - Recommendation: Use `--no-quarantine` in install command; add `xattr` fallback if install-time flag fails.

3. **GOG installer post-install auto-launch behavior**
   - What we know: The GOG installer auto-launches the game after install, with backslash-path arguments for video intros
   - What's unclear: Whether `/VERYSILENT` suppresses the post-install auto-launch, or whether Cellar needs to kill the process after installer exits
   - Recommendation: Use `/VERYSILENT /SP- /SUPPRESSMSGBOXES` flags and monitor for unexpected child processes after installer exits.

4. **GPTK detection path on macOS**
   - What we know: GPTK is Apple's Game Porting Toolkit; it's detect-only for Phase 1; it's not redistributable
   - What's unclear: Where GPTK is installed on end-user machines (Apple provides GPTK via Xcode Auxiliary Tools or direct download — install paths vary)
   - Recommendation: SETUP-05 is detect-only. Research exact path in next phase when it becomes relevant. For Phase 1, a best-effort check at `/usr/local/bin/gameportingtoolkit` or `/opt/homebrew/bin/gameportingtoolkit` is sufficient.

---

## Sources

### Primary (HIGH confidence)
- https://github.com/apple/swift-argument-parser/releases — version 1.7.1 confirmed, March 2025
- https://apple.github.io/swift-argument-parser/documentation/argumentparser/ — API reference
- https://developer.apple.com/documentation/foundation/process — Foundation.Process API
- https://developer.apple.com/documentation/foundation/filehandle/1412413-readabilityhandler — readabilityHandler API
- https://docs.brew.sh/Installation — Homebrew ARM vs Intel paths
- https://github.com/Gcenx/homebrew-wine — Gcenx tap: wine-crossover + game-porting-toolkit
- https://github.com/Gcenx/wine-on-mac — `--no-quarantine` requirement confirmed

### Secondary (MEDIUM confidence)
- https://lutris.net/games/cossacks-european-wars/ — `single_cpu: true` requirement confirmed, backslash escaping documented
- https://forum.winehq.org/ — `WINEPREFIX wineserver -k` per-prefix shutdown pattern
- https://forums.swift.org/t/swift-6-concurrency-nspipe-readability-handlers/59834 — readabilityHandler Swift 6 concurrency notes
- https://github.com/swiftlang/swift-corelibs-foundation/issues/3275 — readabilityHandler EOF bug confirmed
- https://jrsoftware.org/ishelp/topic_setupcmdline.htm — InnoSetup silent install flags

### Tertiary (LOW confidence — needs validation)
- Cossacks registry key paths for display settings — inferred from game name, not directly verified; test against actual installer
- GOG installer post-install auto-launch suppression via `/VERYSILENT` — reported behavior, needs empirical testing

---

## Metadata

**Confidence breakdown:**
- Standard Stack: HIGH — Swift Argument Parser version confirmed, Foundation.Process is official Apple API
- Architecture: HIGH — patterns derived from official Apple documentation and established Wine practices
- Wine subprocess patterns: HIGH — verified against Foundation.Process docs and WineHQ documentation
- Cossacks-specific Wine config: MEDIUM — `single_cpu` fix confirmed via Lutris; exact registry keys need empirical validation
- Gcenx tap install: HIGH — `--no-quarantine` requirement confirmed from official Gcenx README

**Research date:** 2026-03-25
**Valid until:** 2026-04-25 (Gcenx tap formula names could change; 30-day estimate)
