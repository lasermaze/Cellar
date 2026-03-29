# Agentic Architecture v2: Research-Diagnose-Adapt Loop

## Why v1 Failed

The v1 agent loop is a **configuration search** system: inspect → configure → launch → retry with different config. It has 10 tools, all focused on *acting* (set env, place DLL, launch). But the actual problem of getting a game running is a **diagnosis and adaptation** problem that requires *understanding*.

### The Real Session That Worked (2026-03-27)

Getting Cossacks: European Wars running required 6 non-linear pivots in ~10 minutes:

```
1. Launch → "Wine prefix not owned by you" → need to run as correct user
2. Launch as peter → "mdraw.dll not found" → dmln.exe is a 12KB stub, dmcr.exe is the real binary
3. Restore mdraw.dll, launch dmcr.exe → "Could not open Missions\Missions.txt"
   → game needs working directory set to game folder (WineProcess never sets it)
4. Launch with correct CWD → "Direct Draw Init Failed (80004001)"
   → same old error, but now we can debug further
5. Add +loaddll tracing → "DDRAW.DLL loaded as builtin"
   → cnc-ddraw in game_dir is being IGNORED — Wine loads syswow64/ddraw.dll instead
6. Copy cnc-ddraw to syswow64 → GAME LAUNCHES SUCCESSFULLY
```

The v1 agent could never have done this because:
- **Pivot 2** requires understanding that dmln.exe is a stub (not in any prompt or tool)
- **Pivot 3** requires knowing WineProcess doesn't set CWD (infrastructure bug, invisible to agent)
- **Pivot 5** requires interpreting `+loaddll` traces to realize the DLL override isn't working
- **Pivot 6** requires understanding wow64 DLL search order (not in domain knowledge)

### Root Cause Analysis

| v1 Architecture Assumption | Reality |
|---|---|
| The right config exists and just needs to be found | The infrastructure has bugs that prevent any config from working |
| Domain knowledge can be pre-baked into a system prompt | Each game surfaces novel problems requiring live research |
| Tools that act are sufficient | Tools that *investigate* are more important than tools that act |
| Linear retry with different variants converges | Non-linear pivots based on unexpected evidence are required |
| Agent errors are config errors | Many errors are environment/infrastructure/working-directory/DLL-path errors |

## v2 Architecture: Three Phases

```
┌─────────────────────────────────────────────────────────┐
│                    PHASE 1: RESEARCH                     │
│                                                          │
│  Before touching Wine, understand the problem space:     │
│  • What game is this? What engine, what graphics API?    │
│  • What do WineHQ/ProtonDB/forums say about it?         │
│  • What worked for others? What are the known pitfalls?  │
│  • What does the game actually need (files, DLLs, CWD)? │
│                                                          │
│  Output: A hypothesis about what configuration is needed │
│          AND what could go wrong                         │
└──────────────────────┬──────────────────────────────────┘
                       v
┌─────────────────────────────────────────────────────────┐
│                   PHASE 2: DIAGNOSE                      │
│                                                          │
│  Run targeted diagnostic launches (not to play, but to   │
│  understand). Short launches with debug tracing:         │
│  • +loaddll: which DLLs loaded, native vs builtin?       │
│  • +relay: what API calls is the game making?            │
│  • Check: is CWD correct? Are files findable?            │
│  • Check: did the DLL override actually take effect?     │
│  • Compare actual behavior vs expected from research     │
│                                                          │
│  Output: Root cause understanding, not just "it crashed" │
└──────────────────────┬──────────────────────────────────┘
                       v
┌─────────────────────────────────────────────────────────┐
│                    PHASE 3: ADAPT                         │
│                                                          │
│  Apply targeted fixes based on diagnosis, not guesses:   │
│  • Fix the specific thing that's broken                  │
│  • Verify the fix took effect before launching again     │
│  • If fix doesn't work, return to DIAGNOSE (not retry)   │
│                                                          │
│  Key: each iteration builds on previous understanding    │
│  NOT: independent retry attempts with different configs  │
└─────────────────────────────────────────────────────────┘
```

### Non-Linear Flow

Unlike v1's linear loop, v2 can jump between phases:

```
RESEARCH → DIAGNOSE → "DLL not loading as native"
    → RESEARCH (why does wow64 DLL search work this way?)
    → ADAPT (place DLL in syswow64 instead)
    → DIAGNOSE (verify DLL now loads as native)
    → ADAPT (launch for real)
    → user confirms success
```

## What Changes

### New Tools Needed

#### Research Tools (v1 has NONE of these)

**`search_web`** — Search for game-specific Wine compatibility info
```
Input:  { query: "Cossacks European Wars Wine macOS DirectDraw" }
Output: { results: [{ title, url, snippet }] }
```
The single biggest gap. The agent currently operates from a ~500-word static system prompt. A human would Google "Cossacks Wine macOS" before doing anything.

**`fetch_page`** — Read a specific URL (WineHQ AppDB, PCGamingWiki, forum thread)
```
Input:  { url: "https://appdb.winehq.org/objectManager.php?sClass=version&iId=34378" }
Output: { text_content: "..." }
```
Follow-up to search_web. Forums and wikis contain specific configs, env vars, registry keys that the agent can extract and try.

**`check_protondb`** — Structured query for ProtonDB/WineHQ AppDB ratings and reports
```
Input:  { game_name: "Cossacks European Wars", steam_appid?: 4880 }
Output: { rating, reports: [{ wine_version, distro, notes, tweaks }] }
```
Optional convenience wrapper. Could be implemented as search_web + fetch_page.

#### Diagnostic Tools (v1 has basic versions, need enhancement)

**`trace_launch`** — Launch game briefly with targeted Wine debug channels, kill after N seconds
```
Input:  { debug_channels: ["+loaddll", "+ddraw"], timeout_seconds: 5 }
Output: {
    loaded_dlls: [{ name, path, type: "native"|"builtin" }],
    errors: [...],
    raw_stderr: "..."
}
```
This is NOT `launch_game`. This is a *diagnostic probe* — it launches with tracing, captures output for a few seconds, kills the process, and returns *structured analysis* of what happened. The game doesn't need to work; we need to see what Wine is doing.

Key difference from v1's `launch_game`: the output is **parsed into structured findings**, not raw stderr. The agent shouldn't have to parse `00cc:trace:loaddll:build_module Loaded L"C:\\windows\\system32\\DDRAW.DLL" at 69EC0000: builtin` — the tool should return `{ name: "ddraw.dll", type: "builtin", expected: "native" }`.

**`verify_dll_override`** — Check if a DLL override is actually taking effect
```
Input:  { dll_name: "ddraw" }
Output: {
    override_configured: "n,b",
    actually_loaded: "builtin",
    loaded_from: "C:\\windows\\syswow64\\ddraw.dll",
    native_candidates: ["C:\\GOG Games\\...\\ddraw.dll"],
    diagnosis: "Native DLL exists in game_dir but Wine loaded builtin from syswow64. In wow64 bottles, system DLLs are searched in syswow64 first. Place the native DLL in syswow64 or windows/system32."
}
```
This is the tool that would have caught the cnc-ddraw placement bug. It combines: (1) read the registry/env override config, (2) do a trace_launch with +loaddll, (3) compare expected vs actual, (4) explain the discrepancy.

**`check_file_access`** — Verify the game can find files it needs
```
Input:  { relative_paths: ["Missions\\Missions.txt", "mode.dat"] }
Output: {
    working_directory: "C:\\users\\peter",
    game_directory: "C:\\GOG Games\\Cossacks - European Wars",
    results: [
        { path: "Missions\\Missions.txt", exists_in_gamedir: true, exists_from_cwd: false },
        { path: "mode.dat", exists_in_gamedir: true, exists_from_cwd: false }
    ],
    diagnosis: "Game uses relative paths but working directory is not the game directory. Files exist in game dir but won't be found at runtime."
}
```
This would have caught the CWD bug before even launching.

**`inspect_game` (ENHANCED)** — Add deeper analysis
```
Additions to current output:
- pe_imports: ["mdraw.dll", "MINMM.dll", "DSOUND.dll", "DPLAYX.dll", ...]
    (use `objdump` or PE header parsing, not just `file` command)
- working_directory_set: false  (flag if WineProcess doesn't set CWD)
- bottle_type: "wow64"  (32-bit, 64-bit, or wow64 — affects DLL search paths)
- data_files: { "mode.dat": "1024 768 46 0 0 28 8 6 1 2", ... }
    (read small config files the game uses)
- known_shims: ["mdraw.dll (GSC DirectDraw wrapper)", ...]
    (flag DLLs that are game-specific wrappers, not standard Windows DLLs)
```

The current `inspect_game` tells the agent what files exist. The enhanced version tells the agent what the game *needs* and what might go wrong.

#### Modified Action Tools

**`place_dll` (ENHANCED)**
```
Changes:
- New target: "syswow64" (required for 32-bit system DLLs in wow64 bottles)
- Auto-detect: if bottle is wow64 and DLL is a system DLL override, default to syswow64
- Write companion config files (ddraw.ini for cnc-ddraw) based on KnownDLLRegistry metadata
- Verify after placement: run verify_dll_override to confirm it will load
```

**`launch_game` (ENHANCED)**
```
Changes:
- ALWAYS set working directory to game EXE's parent directory
- Return structured DLL load analysis (not just raw stderr)
- Distinguish "diagnostic launch" (short, traced) from "real launch" (user plays)
- Include a "pre-flight check" that verifies CWD, DLL overrides, file access before launching
```

**`write_game_file`** — Write config/data files the game needs
```
Input:  { relative_path: "mode.dat", content: "1024 768 46 0 0 99 8 6 1 2" }
Output: { written_to: "C:\\GOG Games\\...\\mode.dat" }

Input:  { relative_path: "ddraw.ini", content: "[ddraw]\nrenderer=opengl\n..." }
Output: { written_to: "C:\\GOG Games\\...\\ddraw.ini" }
```
Many games need config files written before first launch (mode.dat, .ini files, etc.). Currently the agent has no way to create files in the game directory. Only env vars and registry.

### Enhanced System Prompt — Domain Knowledge Updates

Remove from prompt (wrong or misleading):
```diff
- Games that crash immediately: try virtual desktop mode via set_registry
  (virtual desktop does NOT work on macOS winemac.drv — confirmed by WineHQ)
- NtUserChangeDisplaySettings returning -2 = try virtual desktop (WINE_VD)
  (same — WINE_VD is non-functional on macOS)
```

Add to prompt:
```
## macOS-Specific Knowledge

- Virtual desktop (explorer /desktop=, WINE_VD) does NOT work on macOS winemac.drv.
  It only works with X11 driver (XQuartz). Do not suggest it.

- wow64 bottles (default in wine-crossover): 32-bit system DLLs load from
  C:\windows\syswow64\, NOT from the application directory. If overriding a system
  DLL (ddraw, d3d9, etc.) with a native replacement, it must go in syswow64.

- cnc-ddraw on macOS Wine requires ddraw.ini with renderer=opengl. The default
  renderer=auto tries direct3d9 first, which fails under Wine. Always write ddraw.ini.

- Many games use relative file paths. WineProcess MUST set working directory to the
  game executable's parent directory. If the game fails with "could not open" errors
  for files that exist in the game directory, this is a CWD issue.

- The game's PE imports show which DLLs are ACTUALLY loaded. If ddraw.dll is not in
  the import table but mdraw.dll is, then cnc-ddraw won't be loaded via ddraw=n,b
  override alone — the game uses a custom rendering layer.

## Diagnostic Methodology

- Before configuring anything: run a trace_launch to see what's actually happening.
- After placing a DLL override: verify it loaded correctly before doing a real launch.
- When a launch fails: determine if the failure is in configuration (wrong env vars),
  infrastructure (wrong DLL path, wrong CWD), or game-specific (missing data files).
- Don't retry with different configs if the previous config wasn't even applied correctly.

## Research Methodology

- Before first launch attempt: search for the game on WineHQ AppDB, PCGamingWiki,
  and ProtonDB to see what others have done.
- Pay attention to: specific Wine version recommendations, required winetricks verbs,
  DLL overrides, registry tweaks, and known bugs.
- Cross-reference forum advice with actual game binary analysis (PE imports, data files).
```

### KnownDLLRegistry Enhancement

```swift
struct KnownDLL {
    let name: String
    let dllFileName: String
    let githubOwner: String
    let githubRepo: String
    let assetPattern: String
    let description: String
    let requiredOverrides: [String: String]

    // NEW: companion config files to write alongside the DLL
    let companionFiles: [CompanionFile]

    // NEW: placement hints for different bottle types
    let preferredTarget: DLLPlacementTarget  // .syswow64 for system DLLs in wow64

    // NEW: game-specific variants
    let variants: [String: String]  // e.g., ["cossacks": "cnc-ddraw_cossacks.zip"]
}

struct CompanionFile {
    let filename: String       // "ddraw.ini"
    let content: String        // default content for macOS Wine
    let placement: Placement   // .sameAsParentDLL
}
```

### WineProcess.run() Fix (Critical)

```swift
func run(
    binary: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    logFile: URL? = nil
) throws -> WineResult {
    let process = Process()
    process.executableURL = wineBinary
    process.arguments = [binary] + arguments

    // FIX: Set working directory to the game executable's parent directory
    let binaryURL = URL(fileURLWithPath: binary)
    process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

    // ... rest unchanged
}
```

### DLLPlacementTarget Enhancement

```swift
enum DLLPlacementTarget {
    case gameDir     // next to the game EXE
    case system32    // Wine's virtual System32 (64-bit DLLs in wow64)
    case syswow64    // Wine's SysWOW64 (32-bit DLLs in wow64 bottles) ← NEW

    /// Auto-detect correct target based on bottle type and DLL bitness
    static func autoDetect(
        bottleURL: URL,
        dllBitness: Int,  // 32 or 64
        isSystemDLL: Bool // true for ddraw, d3d9, etc.
    ) -> DLLPlacementTarget {
        let isWow64 = FileManager.default.fileExists(
            atPath: bottleURL.appendingPathComponent("drive_c/windows/syswow64").path
        )
        if isSystemDLL && isWow64 && dllBitness == 32 {
            return .syswow64
        }
        return .gameDir
    }
}
```

## Infrastructure Bugs to Fix (Pre-Phase)

These are not agent improvements — they are bugs that block ANY approach:

| Bug | File | Fix | Priority |
|-----|------|-----|----------|
| WineProcess doesn't set working directory | WineProcess.swift:32 | Set `process.currentDirectoryURL` to binary's parent dir | P0 |
| place_dll has no syswow64 target | AgentTools.swift:666, WineActionExecutor.swift:74 | Add syswow64 case to DLLPlacementTarget | P0 |
| place_dll doesn't write companion configs | AgentTools.swift:675-700 | Add CompanionFile support to KnownDLLRegistry + placement | P0 |
| System prompt suggests virtual desktop on macOS | AIService.swift:524 | Remove; add note that it doesn't work on macOS | P1 |
| inspect_game doesn't parse PE imports | AgentTools.swift:290-350 | Use `objdump -p` or PE header parsing | P1 |
| inspect_game doesn't detect bottle type (wow64) | AgentTools.swift:290-350 | Check for syswow64 directory existence | P1 |
| No write_game_file tool | AgentTools.swift | Add tool for writing mode.dat, ddraw.ini, etc. | P1 |

## Cost and Performance Considerations

### Research Phase Cost

Web search + page fetch adds API calls and latency. Mitigations:
- **Cache research results per game**: store in `~/.cellar/research/{gameId}.json`. If research was done <7 days ago, skip.
- **Parallel research**: search WineHQ, ProtonDB, PCGamingWiki concurrently (3 fetches, not sequential).
- **Research is optional**: if a saved recipe already exists and worked before, skip research entirely. Only research on first launch or after repeated failures.

### Diagnostic Launch Cost

Each trace_launch is a Wine process start+kill (~3-5 seconds). This is much cheaper than a full launch attempt that the user has to evaluate. Budget: 3 diagnostic launches before the first real launch, 2 between each failed real launch.

### Token Budget

Research phase may produce 5-10KB of text from web results. Pre-summarize before injecting into agent context:
- Extract only: env vars, registry keys, DLL overrides, winetricks verbs, known bugs
- Discard: general descriptions, unrelated game versions, Linux-only advice

## Success Criteria

The v2 architecture succeeds if the agent can:

1. **Discover that cnc-ddraw needs to go in syswow64** (not game_dir) by running a diagnostic trace and seeing the DLL loaded as builtin
2. **Discover that mode.dat controls resolution** (not registry) by researching the game on PCGamingWiki/forums
3. **Discover that the game needs CWD set correctly** by checking file access before launching
4. **Discover that mdraw.dll is a custom shim** by inspecting PE imports and finding ddraw.dll is NOT imported directly
5. **Avoid suggesting virtual desktop on macOS** by having correct domain knowledge

All 5 of these were required to launch Cossacks. The v1 agent could do zero of them.

## Comparison: v1 vs v2

| Dimension | v1 | v2 |
|-----------|-----|-----|
| **Knowledge source** | Static 500-word system prompt | Live web research + cached results |
| **Pre-launch** | inspect_game (file listing) | Research + deep inspection (PE imports, bottle type, data files) + file access check |
| **DLL placement** | game_dir or system32 | Auto-detect based on bottle type (wow64 → syswow64) |
| **Failure response** | Try next config variant | Diagnose WHY it failed (trace_launch, verify_dll_override) |
| **Iteration model** | Linear: config A → B → C | Non-linear: diagnose → research → targeted fix → verify → launch |
| **Config file support** | Env vars + registry only | + write_game_file (mode.dat, ddraw.ini, etc.) |
| **Working directory** | Not set (inherits CLI CWD) | Always set to game EXE's parent directory |
| **Launch types** | One type (full launch) | Diagnostic trace (short, kill after N sec) + full launch (user evaluates) |
| **Verification** | None (launch and hope) | verify_dll_override, check_file_access before real launch |
| **Cost per game** | Low (no research) | Higher first time, cached for subsequent launches |

## Success Database

### Purpose

Every successful game launch produces hard-won knowledge: which DLLs go where, what config files are needed, what the actual executable is, what pitfalls were encountered. This knowledge is currently lost — the v1 recipe format only stores env vars and registry keys. The success database captures the **full resolution path** so that:

1. **Same game, next launch**: skip research and diagnosis entirely, replay the known-working setup
2. **Similar games**: when encountering another DirectDraw game, or another GSC engine game, the agent can query the database for analogous solutions
3. **Community sharing**: the database is the unit of contribution — users share success records, not just recipes
4. **Agent learning**: the agent's research phase starts by querying the database before hitting the web

### Schema

```json
{
  "schema_version": 1,
  "game_id": "cossacks-european-wars",
  "game_name": "Cossacks: European Wars",
  "game_version": "2.1.0.13",
  "source": "gog",
  "engine": "DMCR (GSC Game World)",
  "graphics_api": "DirectDraw 7 (via mdraw.dll shim)",
  "verified_at": "2026-03-27T16:45:00Z",
  "wine_version": "wine-crossover-23.7.1",
  "bottle_type": "wow64",
  "os": "macOS 25.2.0 (Apple M2)",

  "executable": {
    "binary": "dmcr.exe",
    "launcher_stub": "dmln.exe",
    "note": "dmln.exe is a 12KB stub that launches dmcr.exe. Always launch dmcr.exe directly.",
    "pe_type": "PE32",
    "pe_imports": ["KERNEL32.dll", "USER32.dll", "GDI32.dll", "ADVAPI32.dll",
                   "ole32.dll", "WS2_32.dll", "DPLAYX.dll", "DSOUND.dll",
                   "mdraw.dll", "MINMM.dll"],
    "note_imports": "Does NOT import ddraw.dll directly. Uses mdraw.dll (GSC custom DirectDraw wrapper) which internally loads ddraw.dll at runtime."
  },

  "working_directory": {
    "must_be_game_dir": true,
    "reason": "Game uses relative paths (Missions\\Missions.txt, mode.dat). Fails with assertion error if CWD is not the game directory."
  },

  "environment": {
    "WINE_CPU_TOPOLOGY": "1:0",
    "WINEDLLOVERRIDES": "ddraw=n,b;mscoree,mshtml="
  },

  "dll_overrides": [
    {
      "dll": "ddraw",
      "override": "native",
      "source": "cnc-ddraw",
      "source_version": "latest",
      "source_repo": "FunkyFr3sh/cnc-ddraw",
      "source_asset": "cnc-ddraw.zip",
      "placement": "syswow64",
      "placement_reason": "wow64 bottle loads 32-bit system DLLs from syswow64, not from application directory. Placing in game_dir has NO effect — Wine still loads builtin from syswow64.",
      "also_in_game_dir": true,
      "companion_config": {
        "filename": "ddraw.ini",
        "placement": "game_dir",
        "content": "[ddraw]\nrenderer=opengl\nfullscreen=true\nhandlemouse=true\nadjmouse=true\ndevmode=0\nmaxgameticks=0\nnonexclusive=false\nsinglecpu=true"
      },
      "registry_override": {
        "key": "HKCU\\Software\\Wine\\DllOverrides",
        "value_name": "ddraw",
        "data": "native"
      }
    }
  ],

  "game_config_files": [
    {
      "file": "mode.dat",
      "placement": "game_dir",
      "format": "space-separated: ResWidth ResHeight SoundVol 0 0 MusicVol GameSpeed ScrollSpeed GameMode MusicType",
      "default_content": "1024 768 46 0 0 99 8 6 1 2",
      "note": "Primary resolution config. Game reads this, NOT the registry ScreenWidth/ScreenHeight keys."
    }
  ],

  "registry": [
    {
      "key": "HKCU\\Software\\GSC Game World\\Cossacks - European Wars",
      "values": {
        "ScreenWidth": "dword:00000400",
        "ScreenHeight": "dword:00000300",
        "Windowed": "dword:00000001"
      },
      "note": "Best-effort. Game primarily uses mode.dat for resolution. These may only work with cnc-ddraw present."
    }
  ],

  "game_specific_dlls": [
    {
      "dll": "mdraw.dll",
      "type": "game_bundled",
      "description": "GSC's custom DirectDraw wrapper. Required by dmcr.exe (hard PE import). Internally loads ddraw.dll via LoadLibrary. Do NOT rename or remove.",
      "interaction_with_cnc_ddraw": "mdraw.dll calls DirectDrawCreate → Windows loads ddraw.dll → cnc-ddraw intercepts if placed in syswow64 with override=native"
    },
    {
      "dll": "MINMM.dll",
      "type": "game_bundled",
      "description": "GSC's custom multimedia wrapper. Required by dmcr.exe (hard PE import)."
    }
  ],

  "pitfalls": [
    {
      "symptom": "Direct Draw Init Failed (80004001)",
      "cause": "NtUserChangeDisplaySettings returns -2 on macOS. Wine cannot change display resolution via winemac.drv.",
      "fix": "cnc-ddraw in syswow64 intercepts DirectDraw calls and renders via OpenGL without requiring display mode change.",
      "wrong_fix": "Virtual desktop (WINE_VD, explorer /desktop=) — does NOT work on macOS winemac.drv, only works with X11."
    },
    {
      "symptom": "Could not open Missions\\Missions.txt → assertion failure",
      "cause": "Working directory not set to game directory. Game uses relative paths.",
      "fix": "Set process.currentDirectoryURL / launch via 'wine start /d <gamedir>'."
    },
    {
      "symptom": "err:module:import_dll Library mdraw.dll not found",
      "cause": "mdraw.dll was renamed/removed. It is a hard dependency of dmcr.exe.",
      "fix": "Keep mdraw.dll in the game directory. cnc-ddraw replaces ddraw.dll, not mdraw.dll."
    },
    {
      "symptom": "DDRAW.DLL loaded as builtin despite ddraw=n,b override",
      "cause": "wow64 bottle loads 32-bit system DLLs from syswow64. cnc-ddraw placed in game_dir is not found by Wine's DLL search for system DLLs.",
      "fix": "Copy cnc-ddraw's ddraw.dll to drive_c/windows/syswow64/ddraw.dll."
    },
    {
      "symptom": "Debug Assertion Failed dbgheap.c:1011 _CrtIsValidHeapPointer",
      "cause": "Heap corruption on exit. Non-fatal — game was running, crash happens during cleanup.",
      "fix": "Ignore. This is a known issue with old MSVC debug builds under Wine."
    }
  ],

  "resolution_narrative": "dmln.exe is a 12KB launcher stub → dmcr.exe is the real binary. dmcr.exe imports mdraw.dll (GSC's custom ddraw wrapper), NOT ddraw.dll directly. mdraw.dll internally calls DirectDrawCreate which loads ddraw.dll. In a wow64 bottle, Wine searches syswow64 for system DLLs, ignoring the game directory. cnc-ddraw must be placed in syswow64 AND ddraw.ini with renderer=opengl must be in the game directory. Working directory must be set to the game directory for relative file paths.",

  "tags": ["directdraw", "2d", "gsc-engine", "dmcr", "cnc-ddraw", "wow64-syswow64", "cwd-required", "gog", "rts", "2001"]
}
```

### Storage Location

```
~/.cellar/
├── successdb/
│   ├── index.json                          # game_id → file mapping + tags index
│   ├── cossacks-european-wars.json         # full success record
│   ├── american-conquest.json              # another GSC engine game (future)
│   └── ...
```

### How the Agent Uses It

#### Before Research Phase

```
Agent: "Let me check if we have a success record for this game..."
→ tool: query_successdb({ game_id: "cossacks-european-wars" })
→ Found! Full record with dll_overrides, pitfalls, config files.
→ Skip web research. Apply known-working configuration directly.
```

#### For Unknown Games — Query by Similarity

```
Agent: "No success record for 'american-conquest'. Let me check for similar games..."
→ tool: query_successdb({ tags: ["gsc-engine"] })
→ Found: cossacks-european-wars uses DMCR engine with mdraw.dll shim.
→ "American Conquest uses the same engine. Let me try the same approach..."
```

```
Agent: "No success record for 'age-of-empires-2'. Similar games?"
→ tool: query_successdb({ tags: ["directdraw", "2d", "rts"] })
→ Found: cossacks-european-wars needed cnc-ddraw in syswow64.
→ "This is also a DirectDraw 2D game in a wow64 bottle. cnc-ddraw in syswow64 likely needed."
```

#### Query Dimensions

| Query | Use Case |
|-------|----------|
| `game_id` exact match | Replay known-working config for same game |
| `engine` match | Same engine = same DLL shims, same quirks |
| `graphics_api` match | DirectDraw games share cnc-ddraw approach |
| `tags` overlap | Broad similarity: era, genre, bottle type |
| `pitfalls.symptom` match | Agent sees same error → look up known fix |
| `dll_overrides.source` match | "What other games needed cnc-ddraw?" |

### New Tool: `query_successdb`

```
Input:  {
    game_id?: string,           // exact match
    tags?: [string],            // any overlap
    engine?: string,            // substring match
    graphics_api?: string,      // substring match
    symptom?: string,           // fuzzy match against pitfalls[].symptom
    limit?: number              // max results (default 3)
}
Output: {
    matches: [{
        game_id, game_name, relevance_score,
        // For exact match: full record
        // For similarity match: summary with dll_overrides, pitfalls, key config
    }]
}
```

### New Tool: `save_success`

Replaces / extends the existing `save_recipe` tool. Called when the user confirms the game works.

```
Input: {
    game_id: string,
    game_name: string,
    // ... agent fills in everything it learned during the session:
    // executable info, DLL overrides, config files, pitfalls encountered, etc.
}
Output: { saved_to: "~/.cellar/successdb/cossacks-european-wars.json" }
```

The agent constructs the full success record from its session context: every diagnostic finding, every failed attempt (becomes a pitfall), every fix that worked.

### Why This Matters More Than Recipes

The current recipe format (`recipes/cossacks-european-wars.json`) stores:
- env vars, registry keys, retry variants

The success database stores:
- **Why** each setting is needed (not just what)
- **What doesn't work** (pitfalls with wrong_fix)
- **How DLLs interact** (mdraw.dll → ddraw.dll chain)
- **Infrastructure requirements** (CWD, bottle type, DLL placement path)
- **The narrative** of how the problem was solved
- **Tags** for cross-game similarity queries

A recipe tells the agent *what to do*. A success record teaches the agent *how to think* about similar problems.
