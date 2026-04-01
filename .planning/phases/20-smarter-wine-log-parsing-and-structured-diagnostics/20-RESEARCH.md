# Phase 20: Smarter Wine Log Parsing and Structured Diagnostics - Research

**Researched:** 2026-03-31
**Domain:** Wine log parsing, Swift regex, diagnostic data modeling, disk persistence
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Error Pattern Coverage**
- Add 4 new subsystems: audio (dsound/alsa/pulse), input (dinput/xinput), font/text (freetype/gdi), memory/addressing
- Top 2-3 patterns per new subsystem — cover the most common failures old games hit, not comprehensive
- Every recognized pattern maps to an auto-fix suggestion (WineFix) when a known fix exists
- Version-agnostic patterns — no Wine version-specific databases
- For ambiguous patterns, suggest the most common fix; agent escalates to research if it doesn't help
- Detect causal chains: group related sequential errors into root cause + downstream effects
- No confidence levels on pattern matches — if it matches, report it
- Extract positive success signals alongside errors (e.g., "DirectDraw initialized", "audio device opened")
- Hardcoded patterns only — no recipe-extensible or plugin patterns

**Signal vs Noise Filtering**
- Selective fixme: filtering — strip fixme: lines EXCEPT from subsystems that have a matching detected error
- Keep all repeated lines — no deduplication of identical error lines
- Include a diagnostic summary header with counts: errors, warnings, successes, filtered noise lines
- Build a small allowlist of known-harmless warn: lines on macOS Wine (e.g., macdrv screen saver messages) and filter those
- Filtering applied everywhere — launch_game, trace_launch, and read_log all return filtered/structured output

**Structured Diagnostic Output**
- Grouped by subsystem: `graphics{errors, successes}`, `audio{errors, successes}`, `input{...}`, `memory{...}`, etc.
- Causal chains as a separate top-level section linking root causes to downstream effects
- Summary header: "2 errors (graphics, audio), 1 success (input), 847 fixme lines filtered"
- Replaces `detected_errors` field in launch_game results — full replacement, not additive
- Unified format for both launch_game and trace_launch
- Diagnostics only in launch/trace/read_log results — not injected into initial message before first launch

**Cross-Launch Trend Detection**
- launch_game and trace_launch results include `changes_since_last` section
- Diff annotated with `last_actions` showing what the agent applied before this launch
- Diagnostics persisted to disk at `~/.cellar/diagnostics/{gameId}/`
- trace_launch and launch_game share the same tracking baseline
- On new agent session: if previous diagnostic data exists, inject a summary into agent initial message

### Claude's Discretion
- Exact regex patterns for each new subsystem's error/success detection
- Which specific warn: patterns go on the macOS known-harmless allowlist
- Internal data structures for the diagnostic model (Swift structs/enums)
- How to track "last_actions" within AgentTools (session state management)
- Diagnostic file format on disk (~/.cellar/diagnostics/)
- How to integrate positive signals with existing DLL load and dialog parsing in trace_launch

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope
</user_constraints>

---

## Summary

Phase 20 upgrades the Wine stderr parser from a flat 5-pattern array to a structured, subsystem-grouped diagnostic engine. The core challenge is entirely within the Cellar Swift codebase — there are no third-party libraries to install. The work splits into three areas: (1) expanding `WineErrorParser` with ~20 new patterns across 4 subsystems plus positive success signals and causal chain detection; (2) adding noise filtering (selective fixme: suppression + macOS harmless warn: allowlist); and (3) wiring cross-launch trend tracking via a new `DiagnosticRecord` persisted to `~/.cellar/diagnostics/{gameId}/`.

The existing code is clean and well-suited for this expansion. `WineErrorParser` already uses the right pattern: a struct with a static `parse()` method returning typed results. The output format change (replacing `detected_errors` with `diagnostics`) touches exactly three integration points: `launchGame()`, `traceLaunch()`, and `readLog()`. The `contextParts` assembly in `AIService.runAgentLoop()` needs one new injection point for previous-session diagnostic state.

Wine's log line format is well-understood: `{threadId}:{severity}:{channel}:{function} message`. The severity levels are `err`, `warn`, `fixme`, `trace`. Relevant channels map cleanly to subsystems: `dsound`/`alsa`/`mmdevapi`/`winmm` for audio, `dinput`/`xinput` for input, `freetype`/`gdi`/`font` for text, `virtual`/`heap`/`seh` for memory. The project targets macOS 14+ with Swift 6.0 (tools version), so Swift Regex (`Regex<>`) is available but the existing codebase uses NSRegularExpression — stay consistent with NSRegularExpression to avoid mixing regex styles.

**Primary recommendation:** Implement the new `WineDiagnostics` struct as the single output type, expand `WineErrorParser` to produce it, update the three integration points, and add `DiagnosticRecord` for cross-launch persistence — in that order, in separate plans.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (NSRegularExpression) | macOS 14+ | Pattern matching across Wine log lines | Already used in WineErrorParser; consistent with codebase |
| Foundation (JSONEncoder/JSONDecoder) | macOS 14+ | Diagnostic persistence to disk | Already used for all Cellar JSON persistence (SessionHandoff, SuccessDatabase) |
| FileManager | macOS 14+ | Create `~/.cellar/diagnostics/{gameId}/` directory | Already used in CellarPaths for all disk I/O |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Regex (`Regex<>`) | macOS 13+ / Swift 5.7+ | Type-safe pattern matching | Available but NOT used in current codebase — skip for consistency |
| CryptoKit (SHA-256) | macOS 10.15+ | Hashing diagnostic content for change detection | Already pulled in for EnvironmentFingerprint; use if content-hash comparison needed |

### No New Dependencies

This phase requires zero new SPM dependencies. Everything is Foundation + existing project patterns.

---

## Architecture Patterns

### Recommended File Structure Changes

```
Sources/cellar/Core/
├── WineErrorParser.swift          # EXPAND: new subsystems, noise filtering, causal chains
├── WineDiagnostics.swift          # NEW: WineDiagnostics struct, SubsystemDiagnostic, CausalChain
├── DiagnosticRecord.swift         # NEW: persistence model for cross-launch tracking
├── AgentTools.swift               # MODIFY: replace detected_errors, add last_actions tracking
└── AIService.swift                # MODIFY: inject previous-session diagnostic summary

Sources/cellar/Persistence/
└── CellarPaths.swift              # MODIFY: add diagnosticsDir(for:) and diagnosticFile(for:)
```

### Pattern 1: WineDiagnostics Output Type

Replace the flat `[WineError]` with a structured type grouping errors and successes by subsystem.

```swift
// WineDiagnostics.swift

struct SubsystemDiagnostic {
    let errors: [WineError]
    let successes: [WineSuccess]
}

struct WineSuccess {
    let subsystem: WineErrorCategory
    let detail: String
}

struct CausalChain {
    let rootCause: WineError
    let downstreamEffects: [WineError]
    let summary: String   // e.g. "missing d3d9.dll caused DirectX init failure"
}

struct WineDiagnostics {
    // Per-subsystem groups
    var graphics: SubsystemDiagnostic
    var audio: SubsystemDiagnostic
    var input: SubsystemDiagnostic
    var font: SubsystemDiagnostic
    var memory: SubsystemDiagnostic
    var configuration: SubsystemDiagnostic
    var unknown: SubsystemDiagnostic

    // Causal chains detected across subsystems
    var causalChains: [CausalChain]

    // Noise filtering summary
    var filteredFixmeCount: Int
    var filteredHarmlessWarnCount: Int

    // Computed summary string for agent consumption
    var summaryLine: String {
        // "2 errors (graphics, audio), 1 success (input), 847 fixme lines filtered"
    }
}
```

**Source:** Project's existing WineError/WineErrorCategory/WineFix types as the reference pattern.

### Pattern 2: Expanded WineErrorParser.parse()

Return `WineDiagnostics` instead of `[WineError]`. Parse line-by-line for performance (Wine logs can be 50K+ lines). Compile all NSRegularExpression patterns once as static constants.

```swift
// WineErrorParser.swift (expanded)

struct WineErrorParser {
    // Pre-compiled patterns (static lets — compiled once, reused every call)
    private static let missingDLLPattern = try! NSRegularExpression(
        pattern: #"err:module:import_dll.*Library\s+(\S+)"#
    )
    private static let audioInitFailPattern = try! NSRegularExpression(
        pattern: #"err:dsound:.*(?:no driver|failed to open|CoCreateInstance)"#
    )
    // ... etc

    static func parse(_ stderr: String) -> WineDiagnostics {
        var diagnostics = WineDiagnostics.empty()
        let lines = stderr.components(separatedBy: "\n")

        for line in lines {
            // Route each line to subsystem detector
            // Track matched subsystems for selective fixme: filtering
        }

        // Post-pass: causal chain detection
        diagnostics.causalChains = detectCausalChains(diagnostics)

        // Post-pass: noise filtering counts
        diagnostics.filteredFixmeCount = filterFixmes(lines, matchedSubsystems: ...)
        return diagnostics
    }
}
```

**Key insight:** Static pre-compiled patterns avoid the performance cost documented in Swift forums — NSRegularExpression compilation is expensive, reuse is free.

### Pattern 3: Wine Log Line Format

Wine stderr lines have this structure (confirmed from WineHQ debug documentation and real log examples):

```
{threadId}:{severity}:{channel}:{function} {message}
```

Examples:
```
0009:err:module:import_dll Library d3d9.dll not found
0023:fixme:dsound:IDirectSound8_CreateSoundBuffer unimplemented flags
0009:warn:ntdll:RtlSetHeapInformation 0x7ffffe000 1 0x0 0
002c:err:alsa:ALSA_CheckSetVolume Could not find 'PCM Playback Volume' element
```

The `{threadId}` is a hex thread ID (e.g. `0009`, `002c`). For pattern matching, ignore the thread prefix — use `contains()` or patterns that don't anchor to line start (or use `.*` prefix). The severity and channel together form the routing key: `err:dsound`, `fixme:d3d`, `warn:freetype`, etc.

### Pattern 4: Selective fixme: Filtering

The context says: strip fixme: lines EXCEPT from subsystems that have a matching detected error.

```swift
// During parsing, track which subsystems have errors
var subsystemsWithErrors: Set<String> = []

// For filtering:
func isNoisyFixme(_ line: String, subsystemsWithErrors: Set<String>) -> Bool {
    guard line.contains("fixme:") else { return false }
    // Extract channel from fixme:channel: pattern
    // If channel is in subsystemsWithErrors, keep it
    // Otherwise, it's noise
    return !subsystemsWithErrors.contains(extractChannel(line))
}
```

### Pattern 5: DiagnosticRecord Persistence

Follow the `SessionHandoff` pattern exactly — Codable struct, JSONEncoder with .prettyPrinted + .sortedKeys, atomic write, silent failure.

```swift
// DiagnosticRecord.swift

struct DiagnosticRecord: Codable {
    let gameId: String
    let timestamp: String           // ISO8601
    let diagnostics: [String: Any]  // or a Codable mirror of WineDiagnostics
    let lastActions: [String]       // tool names + params applied before this launch
                                    // e.g. ["set_environment(WINEDEBUG=+d3d)", "install_winetricks(d3dx9)"]

    // Persistence follows SessionHandoff pattern
    static func write(_ record: DiagnosticRecord, gameId: String) { ... }
    static func readLatest(gameId: String) -> DiagnosticRecord? { ... }
}
```

**Storage path:** `~/.cellar/diagnostics/{gameId}/latest.json` — overwrite on each launch; no per-timestamp history needed (cross-session comparison is latest vs current).

**For cross-session comparison:** `readLatest()` on new session — if exists, diff new diagnostics against it and inject summary into `contextParts` in `AIService`.

### Pattern 6: last_actions Tracking in AgentTools

The context says to annotate `changes_since_last` with `last_actions` — what the agent applied between the previous launch and this one. Track using a mutable array that records action tool calls since the last launch.

```swift
// In AgentTools mutable state:
var lastAppliedActions: [String] = []   // cleared on each launch_game/trace_launch call
var pendingActions: [String] = []       // accumulated since last launch

// In execute():
// After set_environment, install_winetricks, place_dll, set_registry — append to pendingActions
// At top of launchGame() / traceLaunch(): swap pendingActions into lastAppliedActions, clear pendingActions
```

This gives a clean "what changed before this launch" list without requiring persistent state between sessions.

### Pattern 7: Changes Diff Computation

```swift
func computeChanges(
    current: WineDiagnostics,
    previous: DiagnosticRecord?
) -> [String: Any] {
    guard let previous = previous else {
        return ["note": "No previous launch data available"]
    }
    // Compare error lists:
    // new_errors = current.allErrors - previous.allErrors
    // resolved_errors = previous.allErrors - current.allErrors
    // persistent_errors = current.allErrors ∩ previous.allErrors
    // new_successes = current.allSuccesses - previous.allSuccesses
    return [
        "last_actions": previous.lastActions,
        "new_errors": ...,
        "resolved_errors": ...,
        "persistent_errors": ...,
        "new_successes": ...
    ]
}
```

Identity of errors for comparison: use `(category, detail)` tuple or a stable string key. Do NOT rely on object identity — these come from different parse runs.

### Anti-Patterns to Avoid

- **Recompiling NSRegularExpression on every parse call:** Compilation is expensive (~0.25s for complex patterns). Make all patterns static constants.
- **Using new Swift `Regex<>` type in this file:** The existing codebase uses NSRegularExpression everywhere. Mixing styles increases maintenance cost with no benefit.
- **Storing full raw stderr in DiagnosticRecord:** Too large. Store only the structured WineDiagnostics summary — error categories, detail strings, counts.
- **Creating a separate diagnostic file per launch:** Latest-only (`latest.json`) is sufficient for cross-session comparison and keeps storage bounded.
- **Trying to make WineDiagnostics directly Codable:** The `WineFix` enum has associated values (`.compound([WineFix])`) that require custom Codable. Use a separate `CodableDiagnosticsSnapshot` struct for disk persistence with string-ified fix descriptions.
- **Passing raw WineDiagnostics to jsonResult():** `jsonResult()` takes `[String: Any]` — build a serialization method on WineDiagnostics that produces the JSON dict, don't try to JSON-encode the Swift struct directly.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Regex compilation | Pattern factory/cache class | Static `let` constants | Swift static lets are initialized once; simpler and correct |
| Diff between error sets | Custom graph/tree comparison | Simple Set operations (subtract, intersection) | Error lists are small (<50 items); Set<String> diff is O(n) |
| JSON disk persistence | Custom serializer | JSONEncoder + Codable | Already the project pattern (SessionHandoff, CollectiveMemoryEntry) |
| Directory creation | Manual FileManager boilerplate | Follow CellarPaths pattern | CellarPaths.refuseRoot() + createDirectory already used everywhere |

**Key insight:** The hard problem in this phase is _identifying the right patterns_, not building infrastructure. The infrastructure (regex, JSON, file I/O) is all solved by Foundation and existing project patterns.

---

## Concrete Wine Error Patterns by Subsystem

This section documents the actual Wine log patterns for each new subsystem. Confidence: MEDIUM (from WineHQ forum evidence and Wine source code, cross-verified where possible).

### Audio Subsystem (dsound / alsa / mmdevapi)

**Common error lines:**
```
err:dsound:DSOUND_ReopenDevice Failed to open device
err:dsound:IDirectSound8_Initialize no driver (80004001)
err:alsa:ALSA_CheckSetVolume Could not find 'PCM Playback Volume' element
err:mmdevapi:AudioClient_Initialize Unable to get audio endpoint
fixme:dsound:IDirectSoundCaptureImpl_CreateCaptureBuffer (0x...) {
```

**Success signals to detect:**
```
trace:dsound:DSOUND_OpenDevice opened successfully   (rare; usually silent on success)
```

**Recommended patterns (2-3):**
1. `err:dsound:.*` — catch-all dsound errors; extract function name
2. `err:alsa:.*` / `err:mmdevapi:.*` — audio backend errors
3. `err:dsound.*no driver\|80004001` — DirectSound "no audio device" (suggests `winealsa` or `winemac` audio driver issue)

**Fix mapping:** No driver → `set_environment(WINEDLLOVERRIDES=dsound=n,b)` or suggest checking audio backend config.

### Input Subsystem (dinput / xinput)

**Common error lines:**
```
err:dinput:DirectInputCreateEx 0x... returned error: c00000bb
fixme:xinput1_3:WINAPI_XInputGetCapabilities
warn:dinput:IDirectInputDevice2WImpl_GetDeviceState
```

**Recommended patterns (2-3):**
1. `err:dinput:.*` — DirectInput initialization or device errors
2. `err:xinput.*\|fixme:xinput.*GetCapabilities` — XInput device detection failure

**Fix mapping:** dinput init fail → `install_winetricks(dinput)` or `set_environment(SDL_JOYSTICK_DISABLED=1)`.

### Font/Text Subsystem (freetype / gdi / font)

**Common error lines:**
```
err:font:freetype_load_font error: FreeType error 2 - 0x2
warn:font:freetype_load_font Unable to find face index 0 in
err:font:WineEngGetGlyphOutline Could not load font
wine: cannot find 'FreeType'
```

**Recommended patterns (2-3):**
1. `err:font:.*freetype\|cannot find.*FreeType` — FreeType library not found or font load error
2. `err:gdi:.*\|err:font:.*` — general GDI/font rendering failures

**Fix mapping:** FreeType not found → macOS-specific; Gcenx Wine bundles FreeType; if this appears, Wine install is broken.

### Memory/Addressing Subsystem (virtual / heap / seh)

**Common error lines:**
```
err:virtual:virtual_setup_exception bad exception c0000005 at...
err:seh:raise_exception Unhandled exception: page fault on read access to 0x...
err:seh:NtRaiseException signal at 0x... not handled
0009:err:ntdll:RtlpWaitForCriticalSection waited 10 sec for...
```

**Recommended patterns (2-3):**
1. `err:seh:.*Unhandled exception.*page fault` — access violation / null pointer crash
2. `err:virtual:virtual_setup_exception\|virtual_handle_signal` — memory protection / Wine exception handling failure
3. `err:ntdll:RtlpWaitForCriticalSection` — deadlock indicator (waited N sec for critical section)

**Fix mapping:** Page fault / access violation → often indicates wrong architecture (32-bit game on 64-bit prefix) or missing DLL. Suggest `install_winetricks(vcrun2019)` or check bottle architecture.

### Existing Graphics Patterns (extend, not replace)

Current: `err:x11`, `err:winediag+display`, `DirectDraw Init Failed`, `ddraw+80004001`.

**Add success signals:**
```
// DirectDraw init success — appears in normal DX8/DX9 game launches
trace:ddraw:ddraw_init initialized
fixme:d3d:wined3d_check_device_format   (actually harmless — d3d device WAS created)
```
Pattern: `trace:ddraw:.*init\|ddraw.*initialized` — positive signal that ddraw setup worked.

### macOS Known-Harmless warn: Allowlist

From `macdrv_main.c` source inspection:

```
warn:macdrv:*Could not determine screen saver state*   — IOKit query; harmless
warn:ntdll:*RtlSetHeapInformation*                    — heap info; harmless on macOS
fixme:ver:*GetSystemFirmwareTable*                     — BIOS query; always harmless
fixme:winspool:*DrvDocumentEvent*                      — printer subsystem; harmless
fixme:actctx:*parse_*                                  — activation context; harmless for most games
```

Build as a `[String]` allowlist of partial match strings applied via `line.contains()` checks.

---

## Common Pitfalls

### Pitfall 1: WineFix Codable Incompatibility

**What goes wrong:** `WineFix` has `case compound([WineFix])` — a recursive enum with associated values. Attempting to make it `Codable` hits a compiler error; attempting custom `Codable` conformance is complex.

**Why it happens:** The diagnostic persistence needs to serialize `suggestedFix` to disk.

**How to avoid:** Do not persist `WineFix` directly. In `DiagnosticRecord`, store `fix_description: String` (using the existing `describeFix()` method from `AgentTools`). This is consistent with how fixes are already presented to the agent.

**Warning signs:** "Type 'WineFix' does not conform to protocol 'Encodable'" compiler error.

### Pitfall 2: jsonResult() Type Mismatch

**What goes wrong:** `jsonResult()` in AgentTools takes `[String: Any]`. Passing a `WineDiagnostics` struct directly won't compile. Nested dictionaries with mixed types (`[WineError]`) also fail `JSONSerialization`.

**Why it happens:** `JSONSerialization.data(withJSONObject:)` (what `jsonResult()` uses internally) only handles `[String: Any]` with primitive-compatible values.

**How to avoid:** Add a `func asDictionary() -> [String: Any]` method on `WineDiagnostics` that produces the exact JSON dict shape. Test this method independently before wiring to tool results.

### Pitfall 3: Causal Chain False Positives

**What goes wrong:** Detecting `err:module:import_dll` for `d3d9.dll` and then flagging all subsequent d3d errors as "caused by missing d3d9.dll" — but sometimes d3d9.dll loads fine and the d3d error is independent.

**Why it happens:** Causal chains are inferred from sequence, not causality.

**How to avoid:** Restrict causal chain detection to the specific pattern: `import_dll` error for DLL X, followed by an error in a channel that is known to depend on X. Use a hardcoded dependency map (e.g., `d3d9.dll` → `d3d`, `d3dx9_*.dll` → `d3d`). Keep the map small (5-10 known pairs) rather than trying to be comprehensive.

**Warning signs:** Every launch showing the same causal chain regardless of what's actually broken.

### Pitfall 4: Thread-ID Prefix Breaking Pattern Matches

**What goes wrong:** Pattern `#"err:dsound:"#` fails to match `"002c:err:dsound:"` because the thread ID prefix is not accounted for.

**Why it happens:** Wine prepends `{threadId}:` to every message by default. When the `tid` debug channel is enabled, all lines have this prefix.

**How to avoid:** All patterns should either use `contains()` for substring matching, or prefix patterns with `.*` to skip the thread ID. The existing codebase uses `stderr.contains("err:x11")` — follow this approach. For regex captures (like extracting DLL names), use `#".*err:module:import_dll.*Library\s+(\S+)"#`.

### Pitfall 5: Previous-Session Diagnostic Injection Doubling

**What goes wrong:** When a previous `DiagnosticRecord` exists on disk AND `SessionHandoff` also exists, the initial message gets two blocks of diagnostic history — `SessionHandoff.formatForAgent()` (which mentions what was tried) and the new diagnostic summary (which repeats the errors).

**Why it happens:** `contextParts` in `AIService` already injects `SessionHandoff`. The new diagnostic injection is additive.

**How to avoid:** Only inject the diagnostic summary from `DiagnosticRecord` when there is NO `SessionHandoff` for this game (i.e., fresh session start). If a `SessionHandoff` exists, skip the diagnostic summary — the handoff already has the last session's context.

---

## Code Examples

### NSRegularExpression Static Pattern (verified project pattern)

```swift
// Source: WineErrorParser.swift (existing matchPattern helper)
// Pre-compile once as static let — never inside parse()
private static let missingDLLPattern: NSRegularExpression = {
    // Force-unwrap is safe: patterns are compile-time constants
    try! NSRegularExpression(pattern: #"err:module:import_dll.*Library\s+(\S+)"#)
}()

// Usage inside parse() — no allocation, just matching
let range = NSRange(stderr.startIndex..., in: stderr)
let matches = Self.missingDLLPattern.matches(in: stderr, range: range)
```

### Diagnostic JSON Shape (target output format)

```json
{
  "diagnostics": {
    "summary": "2 errors (graphics, audio), 1 success (input), 847 fixme lines filtered",
    "graphics": {
      "errors": [
        { "detail": "DirectDraw initialization failed", "suggested_fix": "place_dll(cnc-ddraw, gameDir) + set_environment(WINEDLLOVERRIDES=ddraw=n,b)" }
      ],
      "successes": []
    },
    "audio": {
      "errors": [
        { "detail": "dsound: no audio driver (80004001)", "suggested_fix": "set_environment(WINEDLLOVERRIDES=dsound=n,b)" }
      ],
      "successes": []
    },
    "input": {
      "errors": [],
      "successes": [{ "detail": "DirectInput initialized successfully" }]
    },
    "causal_chains": [
      {
        "root_cause": "missing d3d9.dll",
        "downstream_effects": ["Direct3D device creation failed"],
        "summary": "missing d3d9.dll caused DirectX init failure"
      }
    ]
  },
  "changes_since_last": {
    "last_actions": ["install_winetricks(d3dx9)", "set_environment(WINEDEBUG=+d3d)"],
    "new_errors": [],
    "resolved_errors": [{ "detail": "d3dx9_43.dll not found" }],
    "persistent_errors": [{ "detail": "DirectDraw initialization failed" }],
    "new_successes": []
  }
}
```

### DiagnosticRecord Persistence (SessionHandoff pattern)

```swift
// DiagnosticRecord.swift
struct DiagnosticRecord: Codable {
    let gameId: String
    let timestamp: String
    let errorSummary: [String]      // ["graphics: DirectDraw initialization failed", ...]
    let successSummary: [String]    // ["input: DirectInput initialized successfully"]
    let lastActions: [String]       // ["install_winetricks(d3dx9)", ...]
    let errorCount: Int
    let successCount: Int

    static func write(_ record: DiagnosticRecord) {
        let dir = CellarPaths.diagnosticsDir(for: record.gameId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: CellarPaths.diagnosticFile(for: record.gameId), options: .atomic)
    }

    static func readLatest(gameId: String) -> DiagnosticRecord? {
        guard let data = try? Data(contentsOf: CellarPaths.diagnosticFile(for: gameId)) else { return nil }
        return try? JSONDecoder().decode(DiagnosticRecord.self, from: data)
    }
}
```

### CellarPaths Extension

```swift
// In CellarPaths.swift
static let diagnosticsDir: URL = base.appendingPathComponent("diagnostics")

static func diagnosticsDir(for gameId: String) -> URL {
    diagnosticsDir.appendingPathComponent(gameId)
}

static func diagnosticFile(for gameId: String) -> URL {
    diagnosticsDir(for: gameId).appendingPathComponent("latest.json")
}
```

### Previous-Session Diagnostic Injection (AIService pattern)

```swift
// In AIService.runAgentLoop() — after existing contextParts assembly
// Only inject when there is no SessionHandoff (avoid doubling context)
if previousSession == nil,
   let diagRecord = DiagnosticRecord.readLatest(gameId: gameId) {
    let summary = diagRecord.formatForAgent()
    contextParts.insert(summary, at: contextParts.startIndex)
}
```

```swift
// DiagnosticRecord.formatForAgent()
func formatForAgent() -> String {
    var lines = ["--- PREVIOUS SESSION DIAGNOSTICS ---"]
    lines.append("Last run: \(errorCount) errors, \(successCount) successes")
    if !errorSummary.isEmpty {
        lines.append("Errors: \(errorSummary.joined(separator: "; "))")
    }
    if !lastActions.isEmpty {
        lines.append("Last actions applied: \(lastActions.joined(separator: ", "))")
    }
    lines.append("--- END PREVIOUS SESSION DIAGNOSTICS ---")
    return lines.joined(separator: "\n")
}
```

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Flat `[WineError]` from `WineErrorParser.parse()` | `WineDiagnostics` struct with subsystem grouping | Agent sees organized signal, not a flat list |
| `detected_errors` key in launch_game JSON | `diagnostics` key with grouped structure | Full replacement — agent system prompt docs must update |
| Raw 8000-char stderr tail in `read_log` | Filtered/structured diagnostic output | Dramatic noise reduction for agent |
| No cross-launch comparison | `changes_since_last` in every launch result | Agent sees what changed, why |
| Session handoff for previous session context | + DiagnosticRecord for diagnostic-specific history | Diagnostic history survives even on successful launches |

---

## Implementation Plan Breakdown (suggested phases)

This phase splits naturally into 2 plans:

**Plan 1 — Parser Expansion + Noise Filtering:**
- New `WineDiagnostics` and `DiagnosticRecord` types
- Expand `WineErrorParser` with 4 new subsystems + success signals + causal chains
- Noise filtering (fixme: + macOS harmless allowlist)
- `WineDiagnostics.asDictionary()` for JSON serialization
- Unit-testable in isolation (no need to touch AgentTools)

**Plan 2 — Integration + Cross-Launch Tracking:**
- `CellarPaths` diagnostics paths
- Replace `detected_errors` with `diagnostics` in `launchGame()` and `traceLaunch()`
- Switch `readLog()` to return filtered/structured output
- Add `pendingActions` / `lastAppliedActions` tracking in AgentTools
- Wire `changes_since_last` into launch results
- Previous-session diagnostic injection in `AIService.contextParts`
- Update agent system prompt docs for new tool output format

---

## Open Questions

1. **WineDiagnostics JSON serialization for read_log**
   - What we know: `readLog()` currently returns `{ "log_content": tail, "log_file": path }`. Switching to structured output removes the raw log from the result.
   - What's unclear: The agent may legitimately want raw log context for patterns the parser doesn't know. Does structured-only leave gaps?
   - Recommendation: Return BOTH `diagnostics` (structured) AND a `filtered_log` (raw stderr with noise lines removed but err:/warn: lines kept). This preserves agent access to unparsed signals without sending full noise.

2. **last_actions string format**
   - What we know: The CONTEXT.md examples show `["set_environment(WINEDEBUG=+d3d)", "install_winetricks(d3dx9)"]`.
   - What's unclear: Should tool name + params be the format, or something richer?
   - Recommendation: Use `"\(toolName)(\(key params))"` — readable, consistent with how `describeFix()` works.

3. **Diagnostic record on successful launch**
   - What we know: Successful launches (user confirmed ok) trigger `SessionHandoff.delete()`. Should `DiagnosticRecord` also be deleted on success?
   - What's unclear: Keeping the last-success diagnostic could help on regression (game breaks after an update).
   - Recommendation: Keep `DiagnosticRecord` even after success — it records what a working state looks like. Inject it on next session with "PREVIOUS SUCCESSFUL SESSION" label.

---

## Sources

### Primary (HIGH confidence)
- WineErrorParser.swift (project source) — existing patterns, types, integration points
- AgentTools.swift (project source) — launchGame(), traceLaunch(), readLog() integration points at lines ~1308, ~1610, ~889
- SessionHandoff.swift (project source) — persistence pattern to follow exactly
- CellarPaths.swift (project source) — directory/path pattern to extend
- AIService.swift (project source) — contextParts assembly at lines ~845-856
- Package.swift (project source) — macOS 14+, Swift 6.0 tools version confirmed

### Secondary (MEDIUM confidence)
- WineHQ Debug Channels wiki (https://wiki.winehq.org/Debug_Channels) — Wine log format `{tid}:{severity}:{channel}` confirmed
- wine-mirror/wine macdrv_main.c (GitHub) — macOS harmless warn: messages identified from source
- WineHQ forums — err:dsound, err:alsa, err:module:import_dll, err:seh causal chain patterns confirmed via community examples

### Tertiary (LOW confidence)
- Swift Forums (NSRegularExpression performance thread) — static pre-compilation recommendation for performance
- WineHQ forum examples — specific audio/input/font error string patterns (from user-posted logs, not Wine source)

---

## Metadata

**Confidence breakdown:**
- Wine log format and existing integration points: HIGH — verified from project source code
- New subsystem error patterns: MEDIUM — confirmed from WineHQ forum examples and Wine source, but exact strings vary by Wine version
- Swift architecture patterns: HIGH — directly mirrors existing SessionHandoff/CollectiveMemoryEntry patterns in project
- macOS harmless warn: allowlist: MEDIUM — identified from macdrv_main.c source, but completeness unknown

**Research date:** 2026-03-31
**Valid until:** 2026-05-31 (stable domain — Wine log format changes slowly; Swift patterns are project-internal)
