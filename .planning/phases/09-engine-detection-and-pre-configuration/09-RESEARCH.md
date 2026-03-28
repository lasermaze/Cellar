# Phase 9: Engine Detection and Pre-configuration - Research

**Researched:** 2026-03-28
**Domain:** Game engine fingerprinting, PE binary analysis, Wine pre-configuration
**Confidence:** HIGH

## Summary

This phase extends the existing `inspect_game` tool to detect game engine families and graphics APIs from file patterns, PE import tables, and binary string signatures. The codebase already parses PE imports via `objdump -p` and lists game directory files -- engine detection layers analysis on top of these existing data sources. A new data-driven `EngineRegistry` (modeled after `KnownDLLRegistry`) maps engine fingerprints to families. The system prompt gains engine-aware guidance for pre-configuration and search query enrichment.

The 8 target engine families (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard) are all well-documented with distinct file signatures. Detection confidence comes from weighted signal agreement: file patterns carry high weight (unique filenames like `fsgame.ltx` or `*.mpq`), PE imports carry medium weight (graphics API identification), and binary string matches provide supporting evidence.

**Primary recommendation:** Build a static `EngineRegistry` array of engine definitions with file glob patterns, PE import associations, and `strings`-based signatures. Run detection after `inspectGame()` collects its existing file list and PE imports, scoring each engine and returning the best match with confidence.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Extend inspect_game tool to add an `engine` field to its result -- no separate tool
- Detection uses all three signal types: file patterns, PE imports, and binary string heuristics for engine version strings
- Also scan Wine registry for engine-specific keys via read_registry patterns
- Weighted confidence scoring: file pattern match = high weight, PE import = medium, string scan = supporting. Multiple agreeing signals = "high" confidence, single weak signal = "low"
- Returns engine info only -- no config hints baked into detection results. Agent reasons about configuration itself.
- Separate `graphics_api` field alongside engine (ddraw.dll = DirectDraw, d3d9.dll = DX9, opengl32.dll = OpenGL, etc.) -- matches success database schema
- Re-detect every time, no caching -- detection is fast enough
- All 8 engine families per requirements: GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard
- Data-driven registry structure -- array/dictionary of engine definitions with name, file patterns, PE import patterns, string signatures, graphics API associations
- Easy to add new engines by adding data entries, not new code
- Full known-engine presets: renderer, resolution, sound, input settings -- not just renderer selection dialogs
- Agent decides whether to pre-configure -- system prompt suggests pre-configuring for known engines, agent chooses
- Uses existing tools: set_registry, write_game_file, set_environment -- no new pre_configure tool
- Agent diagnoses and adjusts if pre-config is wrong -- no snapshot/rollback mechanism
- Prompt-level guidance only for search enrichment -- system prompt tells agent to include engine name, graphics API, and current symptoms in search queries
- General guidance, not per-engine query templates
- System prompt tells agent to cross-reference success database by engine type and graphics API after detection

### Claude's Discretion
None specified -- all major decisions locked.

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| ENGN-01 | Agent detects game engine type from file patterns (GSC/DMCR, Unreal 1, Build, id Tech 2/3, Unity, UE4/5, Westwood, Blizzard) with confidence levels | EngineRegistry data structure with file glob patterns per engine family; weighted confidence scoring from signal agreement; detection runs inside inspectGame() |
| ENGN-02 | Agent uses PE import table as secondary engine signal (ddraw.dll = DirectDraw, d3d9.dll = DX9, etc.) | PE imports already parsed by inspectGame(); add graphics_api field derived from import presence; feed into engine confidence scoring as medium-weight signal |
| ENGN-03 | Agent pre-configures game settings before first launch based on detected engine -- writes INI files and registry entries to skip renderer selection dialogs | System prompt update with engine-aware pre-configuration guidance; agent uses existing write_game_file/set_registry/set_environment tools; no new tools needed |
| ENGN-04 | Agent constructs engine-aware web search queries using engine type, graphics API, and symptoms instead of just game name | System prompt update telling agent to include detected engine and graphics_api in search_web queries and query_successdb calls |
</phase_requirements>

## Standard Stack

### Core
| Component | Purpose | Why Standard |
|-----------|---------|--------------|
| `EngineRegistry` (new) | Static array of `EngineDefinition` structs | Mirrors `KnownDLLRegistry` pattern already in codebase |
| `/usr/bin/strings` | Extract printable strings from PE binaries | Available on macOS via Xcode CLI tools; already-proven pattern with `/usr/bin/objdump` and `/usr/bin/file` |
| `/usr/bin/objdump -p` | Parse PE import tables | Already used in `inspectGame()` at AgentTools.swift:595 |

### Supporting
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| `FileManager.contentsOfDirectory` | List game files for pattern matching | Already used in inspectGame(); extend to subdirectory scanning for deeper signatures |
| System prompt (AIService.swift) | Engine-aware agent guidance | Updated with pre-configuration methodology and search enrichment instructions |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `/usr/bin/strings` for binary scanning | Swift `Data` + manual ASCII extraction | `strings` is simpler, already-proven CLI pattern; Swift Data would avoid Process spawn but adds complexity |
| Static `EngineRegistry` array | JSON config file loaded at runtime | Static array is simpler, type-safe, matches KnownDLLRegistry; JSON adds IO and parsing overhead for no gain |
| Registry scanning via `read_registry` tool | Direct file read of `user.reg`/`system.reg` | read_registry already exists as agent tool; but engine detection runs in inspectGame() which is Swift code, so direct file read is more appropriate for detection-time checks |

## Architecture Patterns

### Recommended Structure
```
Sources/cellar/Models/
    EngineRegistry.swift      # EngineDefinition struct + static registry array
Sources/cellar/Core/
    AgentTools.swift           # inspectGame() extended with engine detection
    AIService.swift            # System prompt updated with engine guidance
```

### Pattern 1: Data-Driven Engine Registry
**What:** A static array of `EngineDefinition` structs, each declaring an engine family's fingerprint signals.
**When to use:** For all 8 engine families and any future additions.
**Example:**
```swift
struct EngineDefinition {
    let name: String                    // "GSC/DMCR"
    let family: String                  // "gsc" (for successdb queries)
    let filePatterns: [String]          // ["fsgame.ltx", "*.db0", "*.db1", "dmcr.exe", "xr_3da.exe"]
    let peImportSignals: [String]       // DLL names that support this engine
    let stringSignatures: [String]      // ["X-Ray Engine", "GSC Game World"]
    let typicalGraphicsApi: String?     // "directdraw"
    let weight: Double                  // Base confidence weight (0.0-1.0)
}

struct EngineRegistry {
    static let engines: [EngineDefinition] = [
        // ... 8 engine definitions
    ]

    static func detect(
        gameFiles: [String],
        peImports: [String],
        binaryStrings: [String]
    ) -> EngineDetectionResult? { ... }
}
```

### Pattern 2: Weighted Confidence Scoring
**What:** Each signal type contributes a weight; combined score maps to confidence level.
**When to use:** When scoring engine detection results.
**Logic:**
- File pattern match (unique file like `fsgame.ltx`): +0.5 (HIGH weight)
- File pattern match (common extension like `.grp`): +0.3
- PE import signal agreement: +0.25 (MEDIUM weight)
- Binary string match: +0.15 (SUPPORTING weight)
- Multiple signals agreeing: multiply total by 1.2
- Confidence thresholds: >= 0.6 = "high", >= 0.35 = "medium", >= 0.15 = "low"

### Pattern 3: Graphics API Detection from PE Imports
**What:** Map PE import DLLs to graphics API names, matching the success database schema.
**When to use:** Always, as a separate field from engine detection.
**Mapping:**
```swift
static func detectGraphicsApi(peImports: [String]) -> String? {
    let lower = peImports.map { $0.lowercased() }
    if lower.contains("ddraw.dll") { return "directdraw" }
    if lower.contains("d3d8.dll") { return "direct3d8" }
    if lower.contains("d3d9.dll") { return "direct3d9" }
    if lower.contains("d3d11.dll") { return "direct3d11" }
    if lower.contains("opengl32.dll") { return "opengl" }
    return nil
}
```

### Pattern 4: Binary String Extraction via /usr/bin/strings
**What:** Run `strings` on the game executable to find engine version strings.
**When to use:** As a supporting signal after file patterns and PE imports.
**Example:**
```swift
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
process.arguments = [executablePath]
// Parse output, search for engine-specific signatures
```
**Limit:** Cap output to first 500KB or use `strings -n 8` (minimum 8-char strings) to reduce noise.

### Anti-Patterns to Avoid
- **Scanning entire binary in Swift:** Use `/usr/bin/strings` instead of reading the full EXE into memory. Game executables can be 50MB+.
- **Over-coupling detection to configuration:** Detection returns engine info only. The agent decides what to configure. This keeps the code simpler and lets the agent adapt.
- **Per-engine code paths in detection:** Use the data-driven registry. Adding a new engine should mean adding an array entry, not a new if-branch.
- **Deep recursive directory scanning:** Only scan top-level and one level deep. Games have thousands of files in subdirectories.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| PE import parsing | Custom PE parser | `/usr/bin/objdump -p` (already used) | PE format is complex; objdump handles all variants |
| Binary string extraction | Swift Data scanning | `/usr/bin/strings` | Handles encoding edge cases, memory efficient |
| File glob matching | Custom glob engine | `String` prefix/suffix checks on filename list | Game files are already listed; simple contains/hasSuffix checks suffice |
| Graphics API mapping | Heuristic guessing | Direct PE import DLL name mapping | ddraw.dll/d3d9.dll/opengl32.dll are definitive signals |

**Key insight:** The existing `inspectGame()` already does the heavy lifting (file listing, PE imports, data files). Engine detection is pattern matching on data we already have, plus one additional `strings` call.

## Common Pitfalls

### Pitfall 1: Case Sensitivity in File Matching
**What goes wrong:** Engine file patterns miss matches because Windows filenames are case-insensitive but macOS file listing preserves case.
**Why it happens:** A game might have `FSGAME.LTX` or `FsGame.ltx` depending on the installer.
**How to avoid:** Always lowercase both the pattern and the filename before comparison.
**Warning signs:** Engine detected on one game install but not another of the same game.

### Pitfall 2: False Positives from Common Extensions
**What goes wrong:** `.pak` files trigger id Tech detection for non-id-Tech games (many engines use `.pak`).
**Why it happens:** `.pak` is a generic archive extension used by multiple engines.
**How to avoid:** Use `.pak` only as a supporting signal, never as a sole identifier. Combine with folder names (`baseq2/`, `baseq3/`) or other unique files.
**Warning signs:** High false-positive rate on detection tests.

### Pitfall 3: strings Output Volume
**What goes wrong:** `strings` on a large executable produces megabytes of output, slowing detection.
**Why it happens:** Modern executables contain many string literals.
**How to avoid:** Use `strings -n 10` (minimum 10-char strings) and pipe through `head -5000` or cap Swift-side. Only search for specific signatures, don't store all strings.
**Warning signs:** Detection takes > 1 second on larger executables.

### Pitfall 4: Pre-configuration Breaking Games
**What goes wrong:** Agent writes INI/registry settings that conflict with a specific game version.
**Why it happens:** Engine families span many games with varying config needs.
**How to avoid:** System prompt tells agent to pre-configure conservatively and verify with trace_launch. The Research-Diagnose-Adapt loop handles failures.
**Warning signs:** Game crashes immediately after pre-configuration that worked for a different game on the same engine.

### Pitfall 5: Confusing Engine Family with Graphics API
**What goes wrong:** Treating engine detection and graphics API as the same thing.
**Why it happens:** Many old games use DirectDraw regardless of engine. A GSC game and a Westwood game both import ddraw.dll.
**How to avoid:** Keep `engine` and `graphics_api` as separate fields. Engine comes from file patterns + strings. Graphics API comes from PE imports.
**Warning signs:** All DirectDraw games classified as the same engine.

## Code Examples

### Engine Definition Data (verified patterns from SteamDB FileDetectionRuleSets and community tools)

```swift
// Source: SteamDB FileDetectionRuleSets + PCGamingWiki + enginedetect.py
static let engines: [EngineDefinition] = [
    // 1. GSC/DMCR (X-Ray Engine) — S.T.A.L.K.E.R., Cossacks, American Conquest
    EngineDefinition(
        name: "GSC/DMCR",
        family: "gsc",
        filePatterns: ["fsgame.ltx", "xr_3da.exe", "dmcr.exe", "*.db0", "*.db1"],
        peImportSignals: ["ddraw.dll"],
        stringSignatures: ["X-Ray Engine", "GSC Game World", "DMCR"],
        typicalGraphicsApi: "directdraw"
    ),
    // 2. Unreal Engine 1 — Unreal, Unreal Tournament, Deus Ex, Rune
    EngineDefinition(
        name: "Unreal 1",
        family: "unreal1",
        filePatterns: ["*.u", "*.utx", "*.uax", "*.umx", "*.unr", "UnrealEd.*"],
        peImportSignals: ["d3d8.dll", "d3d9.dll"],
        stringSignatures: ["Unreal Engine", "Epic Games"],
        typicalGraphicsApi: "direct3d9"
    ),
    // 3. Build Engine — Duke Nukem 3D, Shadow Warrior, Blood
    EngineDefinition(
        name: "Build",
        family: "build",
        filePatterns: ["*.grp", "*.art", "GAME.CON", "DEFS.CON", "BUILD.EXE", "COMMIT.DAT"],
        peImportSignals: ["ddraw.dll"],
        stringSignatures: ["Build Engine", "Ken Silverman"],
        typicalGraphicsApi: "directdraw"
    ),
    // 4. id Tech 2/3 — Quake, Quake 2, Quake 3, RTCW, CoD
    EngineDefinition(
        name: "id Tech 2/3",
        family: "idtech",
        filePatterns: ["*.pak", "*.pk3", "baseq2/", "baseq3/", "id1/"],
        peImportSignals: ["opengl32.dll"],
        stringSignatures: ["id Tech", "id Software", "Quake"],
        typicalGraphicsApi: "opengl"
    ),
    // 5. Unity — broad modern engine
    EngineDefinition(
        name: "Unity",
        family: "unity",
        filePatterns: ["UnityPlayer.dll", "*_Data/", "globalgamemanagers*",
                       "Assembly-CSharp.dll", "Managed/"],
        peImportSignals: [],  // Unity games import UnityPlayer.dll, not standard graphics DLLs
        stringSignatures: ["Unity Engine", "UnityMain"],
        typicalGraphicsApi: "direct3d9"  // varies
    ),
    // 6. UE4/5 — Unreal Engine 4 and 5
    EngineDefinition(
        name: "UE4/5",
        family: "unreal4",
        filePatterns: ["*.uasset", "*.uexp", "*.utoc", "*.ucas",
                       "Engine/Binaries/", "Engine/Shaders/"],
        peImportSignals: ["d3d11.dll", "d3d9.dll"],
        stringSignatures: ["Unreal Engine 4", "Unreal Engine 5", "Epic Games"],
        typicalGraphicsApi: "direct3d11"
    ),
    // 7. Westwood — Command & Conquer, Red Alert, Tiberian Sun
    EngineDefinition(
        name: "Westwood",
        family: "westwood",
        filePatterns: ["*.mix", "CONQUER.MIX", "REDALERT.MIX", "TIBSUN.MIX",
                       "RA2.MIX", "SCORES.MIX", "LOCAL.MIX"],
        peImportSignals: ["ddraw.dll"],
        stringSignatures: ["Westwood Studios", "Command & Conquer"],
        typicalGraphicsApi: "directdraw"
    ),
    // 8. Blizzard — Diablo, StarCraft, Warcraft
    EngineDefinition(
        name: "Blizzard",
        family: "blizzard",
        filePatterns: ["*.mpq", "*.MPQ", "diabdat.mpq", "StarDat.mpq",
                       "install.exe", "war3.mpq", "d2data.mpq"],
        peImportSignals: ["ddraw.dll", "dsound.dll"],
        stringSignatures: ["Blizzard Entertainment", "Battle.net"],
        typicalGraphicsApi: "directdraw"
    ),
]
```

### Extending inspectGame() Return Value

```swift
// After existing PE import analysis, add:
let binaryStrings = extractBinaryStrings(executablePath)
let engineResult = EngineRegistry.detect(
    gameFiles: gameFiles,
    peImports: peImports,
    binaryStrings: binaryStrings
)
let graphicsApi = EngineRegistry.detectGraphicsApi(peImports: peImports)

// Add to result dictionary:
if let engine = engineResult {
    result["engine"] = engine.name
    result["engine_confidence"] = engine.confidence  // "high", "medium", "low"
    result["engine_family"] = engine.family
    result["detected_signals"] = engine.signals       // ["file:fsgame.ltx", "string:GSC Game World"]
}
if let api = graphicsApi {
    result["graphics_api"] = api
}
```

### System Prompt Engine Guidance (addition to AIService.swift)

```
## Engine-Aware Methodology
After calling inspect_game, check the engine and graphics_api fields:
- If engine is detected with high confidence, query_successdb by engine type for similar-game solutions
- For known engines (GSC/DMCR, Build, Westwood, Blizzard): these are DirectDraw games. Pre-configure cnc-ddraw with ddraw.ini renderer=opengl BEFORE first launch to skip renderer dialogs.
- For id Tech 2/3 games: these use OpenGL natively, usually work well. Set MESA_GL_VERSION_OVERRIDE if needed.
- For Unity/UE4: modern engines, check d3d9/d3d11 paths. Usually need fewer Wine tweaks.
- Include engine name and graphics API in search_web queries: "GSC engine DirectDraw Wine macOS [symptom]" not just "[game name] Wine"
- After engine detection, always query_successdb with engine and graphics_api params for cross-game solutions
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual game identification | Data-driven file pattern detection (SteamDB, PCGamingWiki tools) | 2020-2024 | Automated engine identification from file listings |
| PE imports only | Multi-signal (files + imports + strings) | Community standard | Higher accuracy, fewer false positives |
| Game-specific configs | Engine-family configs | cnc-ddraw ecosystem | One config covers dozens of DirectDraw games |

**Key community tools that validate this approach:**
- [SteamDB FileDetectionRuleSets](https://github.com/SteamDatabase/FileDetectionRuleSets) -- regex-based engine detection from file lists (HIGH confidence, active project)
- [yellowberryHN/enginedetect](https://github.com/yellowberryHN/enginedetect) -- Python engine detector using file patterns (61 engines supported)
- [vetleledaal/game-engine-finder](https://github.com/vetleledaal/game-engine-finder) -- PCGamingWiki engine finder from exe + surrounding files

## Open Questions

1. **Binary string scan performance on large executables**
   - What we know: `/usr/bin/strings` is available on macOS, handles encoding well
   - What's unclear: Exact performance on 50MB+ executables when piped to Swift
   - Recommendation: Use `strings -n 10` with output cap (first 5000 lines). Benchmark during implementation. String scanning is the lowest-priority signal so can be skipped if too slow.

2. **Subdirectory scanning depth for engine detection**
   - What we know: `inspectGame()` currently lists top-level files only. Some signatures need one-level-deep scanning (e.g., Unity's `*_Data/` folder, id Tech's `baseq2/` folder).
   - What's unclear: Whether existing `gameFiles` array is sufficient or needs augmentation.
   - Recommendation: Add optional one-level subdirectory name listing (directory names only, not contents). This is cheap and catches folder-based signatures.

3. **Wine registry scanning at detection time**
   - What we know: CONTEXT.md says "scan Wine registry for engine-specific keys via read_registry patterns"
   - What's unclear: What engine-specific registry keys exist before first launch. Registry scanning is most useful after a game has run once.
   - Recommendation: Include registry scanning capability but don't weight it heavily for pre-first-launch detection. More useful for re-detection after failed launches.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `AgentTools.swift` inspectGame() implementation (lines 526-684)
- Existing codebase: `KnownDLLRegistry.swift` data-driven registry pattern
- Existing codebase: `SuccessDatabase.swift` engine/graphics_api schema (lines 65-66)
- [SteamDB FileDetectionRuleSets](https://github.com/SteamDatabase/FileDetectionRuleSets) -- community-standard file pattern rules for engine detection
- [cnc-ddraw](https://github.com/FunkyFr3sh/cnc-ddraw) -- DirectDraw replacement with ddraw.ini pre-configuration

### Secondary (MEDIUM confidence)
- [yellowberryHN/enginedetect](https://github.com/yellowberryHN/enginedetect) -- file pattern detection for 61 engines
- [MIX Format documentation](https://moddingwiki.shikadi.net/wiki/MIX_Format_(Westwood)) -- Westwood file format reference
- [MPQ format](https://github.com/mbroemme/mpq-tools) -- Blizzard archive format reference
- [OpenXRay](https://github.com/OpenXRay/xray-16) -- GSC X-Ray engine file structure (fsgame.ltx, .db archives)
- [PCGamingWiki](https://www.pcgamingwiki.com) -- per-game engine identification

### Tertiary (LOW confidence)
- Binary string signatures (e.g., "GSC Game World", "Westwood Studios") -- based on general knowledge of what strings appear in executables. Needs validation against actual game binaries during implementation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- extends existing patterns (KnownDLLRegistry, inspectGame PE parsing), no new dependencies
- Architecture: HIGH -- data-driven registry is a proven pattern in this codebase; weighted scoring is straightforward
- Engine fingerprints: MEDIUM -- file patterns confirmed via SteamDB/enginedetect projects; binary string signatures need validation against actual binaries
- Pitfalls: HIGH -- well-understood domain (case sensitivity, false positives from common extensions)

**Research date:** 2026-03-28
**Valid until:** 2026-04-28 (stable domain -- game engine file formats don't change)
