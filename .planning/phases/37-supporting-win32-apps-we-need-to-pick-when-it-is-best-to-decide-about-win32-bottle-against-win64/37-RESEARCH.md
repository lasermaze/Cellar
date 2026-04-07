# Phase 37: Win32 Bottle Support - Research

**Researched:** 2026-04-06
**Domain:** Wine prefix architecture, PE header parsing, macOS Wine constraints
**Confidence:** HIGH (with one critical finding that affects phase scope)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Bottle arch is decided at `cellar add` time, before bottle creation
- PE type of the installer exe is inspected to determine arch: PE32 → win32, PE32+ → win64
- For disc images / multi-file installers, inspect the installer exe itself
- Fallback when PE detection fails: default to win64 (current behavior)
- Store `bottleArch: String?` ("win32" or "win64") in GameEntry in games.json
- Pure PE type detection: PE32 → win32 bottle, PE32+ → win64 bottle (no era/size heuristics)
- Extract PE header reading into a shared utility used by both `cellar add` and `inspect_game` — DRY
- Update agent system prompt with bottle arch awareness
- CLI: `--arch win32` / `--arch win64` flag on `cellar add` to override PE detection
- Web UI: show detected arch after file analysis, with dropdown to override
- No bottle re-creation in this phase

### Claude's Discretion
- Exact PE header parsing approach for the shared utility (reuse existing 64KB scan or targeted read)
- How to pass WINEARCH to WineProcess.initPrefix() (env var injection)
- Exact wording of agent system prompt additions for bottle arch awareness

### Deferred Ideas (OUT OF SCOPE)
- Bottle re-creation command (`cellar recreate <game> --arch win32`)
- Agent tool to recreate bottle mid-session
</user_constraints>

---

## CRITICAL FINDING: macOS Wine Does Not Support win32 Prefixes

**This is the most important research finding and affects the phase design.**

Cellar installs Wine via `brew install gcenx/wine/wine-crossover`. The Gcenx macOS Wine builds:
- Are compiled with `--enable-archs=i386,x86_64` (dual architecture)
- Use WoW64 mode (wine32on64): a single 64-bit prefix handles both 32-bit AND 64-bit apps
- Do NOT support `WINEARCH=win32` — setting it produces the error: `wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode`

**macOS Catalina (10.15) dropped native 32-bit support in 2019.** Wine on macOS adapted by using WoW64 mode — 32-bit Windows API calls thunk to 64-bit Unix calls. This is the ONLY architecture that works on modern macOS.

**Consequence for Phase 37:** A "win32 bottle" is not creatable on macOS. The `WINEARCH=win32` approach the locked decisions reference **will not work** with Cellar's Wine installation. All bottles are effectively WoW64 (64-bit prefix that runs 32-bit apps via thunking).

**What this means for the phase goal:** The actual compatibility improvement for 32-bit games on macOS Wine is NOT about bottle architecture — it's about how the agent approaches 32-bit games. Specifically:
- In a WoW64 bottle, 32-bit game DLLs go in `drive_c/windows/syswow64`, NOT `system32`
- The agent's existing wow64 logic in DLLPlacementTarget.autoDetect() is ALREADY correct for this
- PE detection still has value: knowing a game is PE32 tells the agent to expect syswow64 placement and avoid system32 DLL overrides for system DLLs

**Recommended re-scoping:** Rather than creating separate win32 bottles (not possible on macOS), Phase 37 should:
1. Extract PE detection into a shared utility (still valuable)
2. Store detected arch in GameEntry (still valuable for agent context)
3. Skip the `WINEARCH` injection to `WineProcess.initPrefix()` — it won't work
4. Focus on agent system prompt improvements: "if bottle_arch=PE32, the game is 32-bit; system DLLs go in syswow64"
5. Add `inspect_game` output field `bottle_arch` for agent awareness

---

## Summary

Phase 37 intends to create win32 Wine bottles for 32-bit games. Research reveals this is not possible on macOS: Cellar uses `gcenx/wine/wine-crossover` which runs exclusively in WoW64 mode. `WINEARCH=win32` is unsupported and produces an error.

However, the phase's underlying value — better compatibility for 32-bit games — is achievable through a different mechanism. WoW64 bottles already support 32-bit apps; what matters is that the agent knows a game is 32-bit so it places DLLs in `syswow64` (not `system32`), avoids certain wow64-specific pitfalls, and doesn't waste time trying win64-only tricks. PE detection and arch storage in GameEntry remain fully valuable.

The PE header reading logic in `DiagnosticTools.swift` (lines 14-35) is the right starting point. It reads 512 bytes, finds the MZ header, follows e_lfanew to the PE header, and reads the machine type. This logic needs to be extracted into a shared utility. One latent bug: it reads e_lfanew as 2 bytes instead of 4 bytes (it is a DWORD at offset 0x3C). In practice this is fine since typical peOffset values fit in 2 bytes (0x40-0xFF), but the shared utility should read all 4 bytes correctly.

**Primary recommendation:** Implement PE detection + GameEntry arch storage + agent prompt awareness. Skip `WINEARCH` injection since it is not supported on macOS. The planner should note the re-scoping and confirm with user if needed, or implement the working subset.

## Standard Stack

### Core (No New Dependencies)

| Component | Source | Purpose | Notes |
|-----------|--------|---------|-------|
| Foundation `FileHandle` | Swift stdlib | Read PE header bytes | Already used in DiagnosticTools |
| `@Option` in ArgumentParser | Already dep | `--arch` CLI flag | Already used in AddCommand |
| Vapor `Content` | Already dep | Web form arch field | Pattern already in AddGameInput |

No new SPM dependencies needed. This phase is pure Swift logic on existing types.

### Key Existing Types to Modify

| Type | File | Change |
|------|------|--------|
| `GameEntry` | Models/GameEntry.swift | Add `bottleArch: String?` Codable field |
| `BottleManager.createBottle()` | Core/BottleManager.swift | Accept `arch: String?` param (for storage only, NOT for WINEARCH) |
| `WineProcess.initPrefix()` | Core/WineProcess.swift | No change needed (WINEARCH=win32 not supported) |
| `AddCommand` | Commands/AddCommand.swift | Add `--arch` flag, call PE detection, pass arch to createBottle |
| `GameController.AddGameInput` | Web/Controllers/GameController.swift | Add optional `arch` field |
| `AIService` system prompt | Core/AIService.swift | Add arch-aware guidance (~line 876) |
| `DiagnosticTools.inspectGame` | Core/Tools/DiagnosticTools.swift | Add `bottle_arch` to output JSON |

## Architecture Patterns

### Recommended Project Structure for PE Utility

```
Sources/cellar/Core/
├── PEReader.swift         # NEW: shared PE header utility (static struct)
├── BottleManager.swift    # MODIFY: accept arch param, store in GameEntry
├── AIService.swift        # MODIFY: arch-aware system prompt
├── Tools/
│   └── DiagnosticTools.swift  # MODIFY: use PEReader, add bottle_arch output
└── Commands/
    └── AddCommand.swift   # MODIFY: --arch flag, PE detection
```

### Pattern 1: PE Header Detection — Shared Utility

**What:** A static struct `PEReader` with a single method `detectArch(fileURL:) -> String?` returning `"win32"`, `"win64"`, or `nil` (detection failed).

**When to use:** At `cellar add` time (before bottle creation) and in `inspect_game` tool output.

**Design:**
```swift
// Source: PE Format spec + existing DiagnosticTools.swift lines 14-35
struct PEReader {
    enum Arch: String {
        case win32 = "win32"
        case win64 = "win64"
    }

    /// Detect PE architecture from file header. Returns nil if not a PE file
    /// or header is unreadable. Reads only first 512 bytes (sufficient for
    /// typical e_lfanew values of 0x40-0xFF).
    static func detectArch(fileURL: URL) -> Arch? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        let header = handle.readData(ofLength: 512)
        try? handle.close()

        // MZ magic
        guard header.count >= 2,
              header[0] == 0x4D, header[1] == 0x5A else { return nil }

        // e_lfanew: 4-byte LE DWORD at offset 0x3C
        guard header.count >= 0x40 else { return nil }
        let peOffset = Int(header[0x3C])
            | (Int(header[0x3D]) << 8)
            | (Int(header[0x3E]) << 16)
            | (Int(header[0x3F]) << 24)

        // PE signature: "PE\0\0" + Machine field (2 bytes)
        guard peOffset + 6 <= header.count,
              header[peOffset] == 0x50, header[peOffset+1] == 0x45,
              header[peOffset+2] == 0x00, header[peOffset+3] == 0x00 else { return nil }

        let machine = UInt16(header[peOffset+4]) | (UInt16(header[peOffset+5]) << 8)
        switch machine {
        case 0x8664: return .win64   // IMAGE_FILE_MACHINE_AMD64
        case 0x014C: return .win32   // IMAGE_FILE_MACHINE_I386
        default:     return nil      // ARM, MIPS, etc. — rare, treat as unknown
        }
    }
}
```

**Key fix vs existing code:** Reads `e_lfanew` as 4 bytes (not 2) and also checks machine type `0x014C` (i386) explicitly instead of treating all non-0x8664 as 32-bit.

### Pattern 2: GameEntry Arch Storage

**What:** Add `bottleArch: String?` to GameEntry following the existing `executablePath: String?` optional pattern.

```swift
// Source: Models/GameEntry.swift — follows existing Codable pattern
struct GameEntry: Codable {
    let id: String
    let name: String
    let installPath: String
    var executablePath: String?
    var bottleArch: String?      // "win32" or "win64", nil if unknown
    let recipeId: String?
    let addedAt: Date
    var lastLaunched: Date?
    var lastResult: LaunchResult?
}
```

`bottleArch` uses `String?` (not an enum) consistent with other fields like `bottleType` in `SuccessRecord`.

### Pattern 3: AddCommand Integration

**What:** Run PE detection before bottle creation, use result to set `bottleArch` in GameEntry. The `--arch` flag overrides detection.

```swift
// In AddCommand.run(), after effectiveInstallerURL is determined,
// before bottleManager.createBottle():

@Option(help: "Force bottle architecture (win32 or win64)")
var arch: String? = nil

// Detect arch from installer PE header
let detectedArch = PEReader.detectArch(fileURL: effectiveInstallerURL)?.rawValue
let bottleArch = arch ?? detectedArch ?? "win64"  // fallback: win64

if let detected = detectedArch {
    print("Detected installer architecture: \(detected)")
}
if let override = arch {
    print("Architecture override: \(override)")
}

// NOTE: Do NOT pass WINEARCH to createBottle — not supported on macOS Wine
// bottleArch is stored in GameEntry for agent awareness only
```

### Pattern 4: Web UI Arch Override

**What:** The `add-game.leaf` form currently has only `installPath`. The web flow uses a redirect pattern: POST /games → redirect to /games/install → SSE stream. Arch detection should happen in the SSE stream (where the file is read), with arch stored in GameEntry.

For the override UI: the add-game form can include an optional `arch` select field (defaults to "auto"), passed through the redirect query parameters alongside `installPath`.

**Flow:**
1. `add-game.leaf`: Add optional `<select name="arch">` with options: auto (default), win32, win64
2. `POST /games`: Read `arch` from `AddGameInput`, include in redirect URL as `&arch=win32`
3. `GET /games/install/stream`: Read `arch` query param, pass to `runInstall()`
4. `runInstall()`: Call `PEReader.detectArch()`, use override if provided, store in GameEntry

### Pattern 5: Agent System Prompt Update

**What:** Add bottle_arch awareness to the system prompt section around line 876 in AIService.swift.

```
## Win32 vs Win64 Game Awareness
- bottle_arch in inspect_game output shows the game's PE architecture
- PE32 (win32) games: 32-bit system DLLs (ddraw.dll, dsound.dll, etc.) must go in syswow64
  (WoW64 prefix: syswow64 holds the 32-bit variants; system32 holds 64-bit stubs only)
- PE32+ (win64) games: system DLLs go in system32 as normal
- win32 games do NOT need different winetricks verbs — wine installs both architectures
- win32 games: DLLPlacementTarget.autoDetect() will correctly choose syswow64 when isSystemDLL=true
```

### Pattern 6: inspect_game Output Update

Add `bottle_arch` to the `jsonResult()` call in DiagnosticTools, derived from `PEReader.detectArch()` rather than the inline string comparison:

```swift
let bottleArch = PEReader.detectArch(fileURL: URL(fileURLWithPath: executablePath))?.rawValue ?? "unknown"

return jsonResult([
    "game_id": gameId,
    "executable_path": executablePath,
    "exe_type": exeType,           // keep for backward compat: "PE32 (32-bit)" string
    "bottle_arch": bottleArch,     // NEW: "win32", "win64", or "unknown"
    ...
])
```

### Anti-Patterns to Avoid

- **Setting WINEARCH=win32 in WineProcess.initPrefix():** Not supported on macOS Wine (Gcenx crossover). Will produce error: `wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode`. Do NOT add this.
- **Reading e_lfanew as 2 bytes:** Existing DiagnosticTools bug. The utility should read all 4 bytes. Typical values (0x40-0xFF) fit in 2 bytes but it's still wrong per spec.
- **Treating all non-0x8664 machine types as win32:** ARM, MIPS, IA-64, RISC-V all have their own machine codes. Return `nil` for unknown types.
- **Storing bottleArch as an enum in Codable:** Use `String?` to match existing SuccessRecord.bottleType pattern and avoid migration issues.
- **Adding architecture selection to the `install-log.leaf` SSE template:** The arch is determined before this page loads. Collect it in the add form, pass through redirect.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PE type detection | Custom file parser | Extract from existing DiagnosticTools.swift lines 14-35 | Already tested, already handles edge cases |
| CLI flag parsing | Manual argv parsing | swift-argument-parser `@Option` | Already used in AddCommand |
| JSON Codable fields | Custom encode/decode | Swift synthesized Codable | Existing pattern in GameEntry |
| WINEARCH 32-bit prefix | Any WINEARCH injection | Don't — not supported on macOS | Wine WoW64 mode handles 32-bit apps transparently |

**Key insight:** The hard part is NOT creating 32-bit bottles (impossible on macOS) — it's using the arch detection to give the agent better context. Don't over-engineer.

## Common Pitfalls

### Pitfall 1: WINEARCH=win32 Does Not Work on macOS
**What goes wrong:** Setting `WINEARCH=win32` when calling `wineboot --init` causes Wine to print `wine: WINEARCH is set to 'win32' but this is not supported in wow64 mode` and may create a corrupt or empty prefix.
**Why it happens:** macOS dropped 32-bit binary support in 10.15. Gcenx Wine builds use WoW64 mode exclusively. There is no `wine32` binary — only `wine64`.
**How to avoid:** Do not set `WINEARCH` during `initPrefix()`. All Cellar bottles are already WoW64 (64-bit prefix + 32-bit thunking). PE arch detection informs agent behavior only.
**Warning signs:** If you check `DependencyChecker.detectWine()`, it looks for `wine64` first — that's the only binary. `wine32` doesn't exist in the Gcenx build.

### Pitfall 2: e_lfanew Larger Than 512 Bytes
**What goes wrong:** A PE file with a large DOS stub may have `e_lfanew > 512`, making the PE header unreachable with the current 512-byte read limit.
**Why it happens:** Legitimate PE files can have very large DOS stubs (some commercial installers embed additional data before the PE header).
**How to avoid:** The shared utility reads 512 bytes initially. If `peOffset >= 512`, do a second seek+read. In practice this is rare — typical values are 0x40-0xF0. For the utility, a 1024-byte read provides additional safety at negligible cost.
**Warning signs:** Detection returns `nil` for a valid EXE. Log the peOffset value when detection fails.

### Pitfall 3: Disc Image Installer vs Game Executable Architecture Mismatch
**What goes wrong:** The disc image installer (setup.exe) might be a 32-bit installer wrapping a 64-bit game installation. PE32 installer → stored as win32 → but game runs as win64.
**Why it happens:** Old installer toolchains (NSIS, Inno Setup) shipped as 32-bit even for 64-bit games.
**How to avoid:** This is the known heuristic limitation in the CONTEXT.md decisions. The `--arch` override handles this case. The agent's `inspect_game` tool checks the actual game exe (not installer) and can re-confirm arch. If bottle_arch in GameEntry doesn't match exe_type in inspect_game output, the agent should note the discrepancy.
**Warning signs:** game exe_type is "PE32+ (64-bit)" but bottle_arch is "win32" in inspect_game output.

### Pitfall 4: bottleArch Field Breaks GameEntry Deserialization for Existing Records
**What goes wrong:** Existing games.json records without `bottleArch` fail to decode.
**Why it happens:** Adding a non-optional field to a Codable struct breaks backwards compatibility.
**How to avoid:** Declare `bottleArch: String?` (optional). Swift synthesized Codable will default to `nil` when the field is absent in existing JSON. No migration needed.
**Warning signs:** App crashes or throws on `CellarStore.loadGames()` after adding the field.

### Pitfall 5: Web UI Arch Override Lost in Redirect Chain
**What goes wrong:** User selects win32 override in the add form, but the arch value is dropped when redirecting through the install flow.
**Why it happens:** The current redirect chain passes `gameId`, `gameName`, and `installPath` as query params. If `arch` isn't threaded through every step, it gets lost.
**How to avoid:** Add `arch` to ALL three steps: `AddGameInput`, redirect URL params, `runInstall()` signature. Thread it to `GameEntry` construction.

## Code Examples

### PE Reader Utility (complete)

```swift
// Source: PE Format spec (https://learn.microsoft.com/en-us/windows/win32/debug/pe-format)
// Replaces inline detection in DiagnosticTools.swift lines 14-35
struct PEReader {
    enum Arch: String {
        case win32 = "win32"
        case win64 = "win64"
    }

    static func detectArch(fileURL: URL) -> Arch? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        // Read first 1024 bytes — covers typical e_lfanew range (0x40-0xFF) with safety margin
        let header = handle.readData(ofLength: 1024)
        try? handle.close()

        // MZ magic ("MZ" = 0x4D 0x5A)
        guard header.count >= 0x40,
              header[0] == 0x4D, header[1] == 0x5A else { return nil }

        // e_lfanew: 4-byte LE DWORD at offset 0x3C
        let peOffset = Int(header[0x3C])
            | (Int(header[0x3D]) << 8)
            | (Int(header[0x3E]) << 16)
            | (Int(header[0x3F]) << 24)

        // Need at least peOffset + 6 bytes (4 sig + 2 machine)
        guard peOffset >= 0, peOffset + 6 <= header.count else { return nil }

        // PE signature: "PE\0\0"
        guard header[peOffset]   == 0x50,
              header[peOffset+1] == 0x45,
              header[peOffset+2] == 0x00,
              header[peOffset+3] == 0x00 else { return nil }

        let machine = UInt16(header[peOffset+4]) | (UInt16(header[peOffset+5]) << 8)
        switch machine {
        case 0x8664: return .win64   // IMAGE_FILE_MACHINE_AMD64
        case 0x014C: return .win32   // IMAGE_FILE_MACHINE_I386
        default:     return nil      // Unknown architecture
        }
    }
}
```

### AddCommand --arch Flag Integration

```swift
// Source: existing AddCommand.swift pattern with @Option
@Option(name: .long, help: "Force bottle architecture: win32 or win64 (default: auto-detect)")
var arch: String? = nil

// Validation in run():
if let a = arch, a != "win32" && a != "win64" {
    print("Error: --arch must be 'win32' or 'win64'")
    throw ExitCode.failure
}

// Detection (after effectiveInstallerURL is resolved):
let detectedArch = PEReader.detectArch(fileURL: effectiveInstallerURL)?.rawValue
let bottleArch: String? = arch ?? detectedArch
if let arch = bottleArch {
    print("Bottle architecture: \(arch)\(detectedArch == nil ? " (fallback: detection failed)" : "")")
}
```

### GameEntry with bottleArch

```swift
// Source: Models/GameEntry.swift — follows existing optional field pattern
struct GameEntry: Codable {
    let id: String
    let name: String
    let installPath: String
    var executablePath: String?
    var bottleArch: String?      // "win32" or "win64"; nil = unknown (legacy records)
    let recipeId: String?
    let addedAt: Date
    var lastLaunched: Date?
    var lastResult: LaunchResult?
}
```

### System Prompt Addition (AIService.swift ~line 876)

```swift
// Add after the existing wow64 bullet point:
"""
- bottle_arch in inspect_game output: "win32" = 32-bit game, "win64" = 64-bit game
- For win32 games: system DLLs (ddraw, dsound, d3d8, etc.) belong in syswow64, NOT system32
- For win32 games: DLLPlacementTarget auto-detect handles syswow64 routing — trust it
- All Cellar bottles are WoW64 (wine32on64 mode on macOS) — both 32-bit and 64-bit games work in the same bottle type
- Do NOT attempt to recreate a bottle with different architecture — not supported
"""
```

## State of the Art

| Old Approach | Current Approach | Impact for Phase 37 |
|--------------|------------------|---------------------|
| Separate win32/win64 Wine prefixes (Linux) | WoW64 single prefix (macOS, Wine 9+) | WINEARCH=win32 not needed — one bottle type for all |
| manual arch selection | PE header detection + override | Deterministic, no guesswork |
| Agent unaware of game bitness | inspect_game outputs bottle_arch | Agent can make better DLL placement decisions |

**Deprecated/outdated for macOS:**
- `WINEARCH=win32` wineboot: Error in Gcenx Wine builds. Do not use.
- `wine32` binary: Not present in Gcenx crossover builds. Only `wine64` exists.
- syswow64 check via `DLLPlacementTarget.autoDetect()`: Already works correctly for detecting WoW64 layout — no changes needed.

## Open Questions

1. **Does the user want to be informed that true win32 bottles are not possible on macOS?**
   - What we know: WINEARCH=win32 fails on Gcenx Wine builds (macOS WoW64 only)
   - What's unclear: Whether the user realized this when writing the CONTEXT.md decisions
   - Recommendation: Planner should surface this finding. The phase can still deliver value (PE detection + arch storage + agent prompt) but WINEARCH injection should be skipped.

2. **Should bottleArch=win32 affect DLL placement auto-detection in the agent?**
   - What we know: `DLLPlacementTarget.autoDetect()` already checks for syswow64 presence (file existence test). This always returns `.syswow64` for 32-bit system DLLs in WoW64 bottles.
   - What's unclear: Whether the agent currently uses autoDetect correctly, or whether explicit arch awareness in the prompt is sufficient
   - Recommendation: Prompt addition is sufficient. autoDetect() is already correct — it checks the actual filesystem, not a stored arch value.

3. **Should the web UI arch detection happen at POST /games time or during the SSE stream?**
   - What we know: PE detection is fast (reads 1024 bytes). The POST /games handler already reads the file to validate it exists.
   - Recommendation: Detect at POST /games time, store detected arch in the redirect URL. This allows showing "Detected: 32-bit" in the form before the install begins. The `--arch` select can default to "auto" and show the detected value as a hint.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `DiagnosticTools.swift` lines 14-35 — PE detection logic to extract
- Existing codebase: `GuidedInstaller.swift` — confirms Cellar uses `gcenx/wine/wine-crossover`
- Existing codebase: `DependencyChecker.swift` — detects `wine64`, not `wine32` (confirms WoW64-only)
- Microsoft PE Format spec: https://learn.microsoft.com/en-us/windows/win32/debug/pe-format — machine type codes (0x8664=AMD64, 0x014C=i386)
- Gcenx macOS Wine builds: https://github.com/Gcenx/macOS_Wine_builds — `--enable-archs=i386,x86_64` confirms WoW64 mode

### Secondary (MEDIUM confidence)
- Wine Arch Linux Forum: WoW64 transition; `WINEARCH=win32` error message in wow64 mode
- WineHQ forum: https://forum.winehq.org/viewtopic.php?t=38627 — "WINEARCH is set to 'win32' but this is not supported in wow64 mode"
- Wine 9.0 announcement: https://www.theregister.com/2024/01/18/wine_90_is_out — WoW64 as the modern approach

### Tertiary (LOW confidence)
- Various Arch Linux forum posts about WoW64 transition breaking win32 prefixes (Linux-specific, may not transfer exactly to macOS but consistent with macOS findings)

## Metadata

**Confidence breakdown:**
- macOS WINEARCH=win32 not supported: HIGH — verified via Gcenx build flags, DependencyChecker detecting wine64 only, multiple sources confirming macOS WoW64-only
- PE header parsing approach: HIGH — existing working code in codebase, PE spec is stable
- GameEntry Codable extension pattern: HIGH — directly verified from existing codebase patterns
- Web UI arch threading: MEDIUM — pattern is straightforward but the redirect chain has multiple steps to thread through
- Agent prompt improvements: MEDIUM — content verified, exact wording is Claude's discretion

**Research date:** 2026-04-06
**Valid until:** 2026-05-06 (stable domain — Wine macOS architecture is unlikely to change)
