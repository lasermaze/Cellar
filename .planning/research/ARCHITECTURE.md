# Architecture Research: Cellar v1.1 Agentic Independence

**Domain:** macOS CLI+TUI Wine game launcher — v1.1 feature integration
**Researched:** 2026-03-28
**Confidence:** HIGH (based on direct codebase inspection)

---

## Standard Architecture

### System Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        CLI Commands Layer                         │
│  AddCommand  LaunchCommand  StatusCommand  LogCommand             │
└──────────────────────────┬───────────────────────────────────────┘
                           │
┌──────────────────────────┴───────────────────────────────────────┐
│                     AIService (static entry point)               │
│  runAgentLoop() ─── detects provider ─── builds system prompt    │
└──────────────────────────┬───────────────────────────────────────┘
                           │
         ┌─────────────────┴──────────────────┐
         │                                    │
┌────────┴────────┐               ┌───────────┴──────────┐
│   AgentLoop     │               │     AgentTools       │
│  state machine  │  toolExecutor │  18 tool impls       │
│  HTTP↔Anthropic │◄─────────────│  accumulates state   │
│  max_tokens     │               │  per session         │
└─────────────────┘               └───────────┬──────────┘
                                              │
          ┌───────────────────────────────────┼───────────────┐
          │                                   │               │
┌─────────┴──────┐  ┌──────────────┐  ┌──────┴──────┐  ┌────┴──────┐
│  WineProcess   │  │ RecipeEngine │  │SuccessDB    │  │CellarPaths│
│  synchronous   │  │ bundled+user │  │ JSON CRUD   │  │ path mgmt │
│  Wine launch   │  │ recipes      │  │ query/save  │  │           │
└────────────────┘  └──────────────┘  └─────────────┘  └───────────┘
          │
┌─────────┴───────────────────────────────────────┐
│              Supporting subsystems               │
│  BottleManager  DLLDownloader  WineActionExecutor│
│  KnownDLLRegistry  WinetricksRunner              │
└─────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | v1.1 Change |
|-----------|----------------|-------------|
| `AgentLoop` | Anthropic API send/execute/return cycle, max_tokens handling | Modify: budget-aware escalation, iteration counting changes |
| `AgentTools` | All 18 tool implementations, mutable session state | Modify: add engine detection, add dialog-state queries, modify search tools |
| `AIService.runAgentLoop()` | System prompt construction, AgentTools wiring, session entry | Modify: pre-configuration phase before loop, smarter system prompt |
| `WineProcess` | Synchronous Wine process execution, stderr capture, timeout | Already correct for v1.1 — WD fix already shipped |
| `SuccessDatabase` | JSON CRUD for success records, query methods | Already correct for v1.1 — schema and queries ship in v1.0 |
| `KnownDLLRegistry` | Static DLL metadata + companion file specs | Modify: add engine classification hints |
| `CGWindowListCopyWindowInfo` | macOS window list (new) | New: `WindowMonitor` module |
| Engine detection | Detect game engine from EXE metadata, files, registry | New: `GameEngineDetector` module or extend `inspect_game` |
| Proactive config | Pre-set renderer/settings before agent starts | New: pre-configuration phase in `AIService.runAgentLoop()` |

---

## Integration Points — Each v1.1 Feature

### 1. Dialog Detection via CGWindowListCopyWindowInfo

**Question:** New tool? Background monitor during launch?

**Answer:** Background monitor spawned by `launch_game` tool, not a standalone tool.

The reason: `CGWindowListCopyWindowInfo` must be called during an active Wine process run. The `launch_game` tool in `AgentTools` already wraps the `WineProcess.run()` call synchronously. The window list monitor fits as a background observation pass that runs concurrently with the Wine process and writes its findings to the `WineResult`.

**Integration:**

`WineProcess.run()` already has a polling loop:
```
while process.isRunning {
    Thread.sleep(forTimeInterval: 2.0)
    // stale output timeout check
}
```

The window monitor runs inside this loop: every 2-second tick, call `CGWindowListCopyWindowInfo` to snapshot visible windows. Classify windows by title/size heuristics:
- Title contains "Error", "Warning", "Missing", known dialog phrases → dialog window
- Size is < 400x200 → likely a dialog, not gameplay
- Size matches game resolution (e.g., 1024x768) → gameplay window

The `WineResult` struct gains optional fields:
```swift
var dialogsDetected: [WindowSnapshot]   // title + size at detection time
var gameWindowDetected: Bool            // large window == game reached menu
```

The `launch_game` tool result JSON already returned to the agent gains `dialog_detected: true/false` and `dialog_title: "..."` fields.

**New type needed:** `WindowMonitor` — a simple struct with one `poll() -> WindowSnapshot?` method. Lives in `Core/WindowMonitor.swift`. No state between calls. Uses `CoreGraphics` import.

**Why not a standalone `check_windows` tool:** The agent cannot call a tool while a game is running — `launch_game` is synchronous and blocks the tool executor until the process exits. The window state must be captured during the launch.

**Hybrid signal:** Wine `+msgbox` trace is already enabled in `WineProcess.run()` (`WINEDEBUG` override). The `launch_game` tool already parses `trace:msgbox` from stderr (in `WineErrorParser` or inline). Combine: if `+msgbox` fires AND a small window appears → high-confidence dialog stuck state.

**Confidence:** HIGH — `CGWindowListCopyWindowInfo` is a stable CoreGraphics API (part of macOS since 10.5). Requires no special entitlements for CLI tools (unlike screenshot capture).

---

### 2. Engine Detection

**Question:** New module? Extension of `inspect_game` tool?

**Answer:** New `GameEngineDetector` struct called from `inspect_game` tool implementation.

**Rationale:** `inspect_game` is already the "understand the game before acting" tool. Adding engine detection there is the right place — the agent calls `inspect_game` first in every session and uses the result to plan its approach. Creating a separate `detect_engine` tool would add an agent tool invocation with no benefit.

**Integration:**

`AgentTools.inspectGame()` currently returns `pe_imports`, `bottle_type`, `data_files`, `notable_imports`. Add:
```swift
"engine": engineDetector.detect(
    exePath: executablePath,
    gameDir: gameDir,
    peImports: peImports,
    bottleURL: bottleURL
)
```

Where `engine` is a structured result:
```json
{
  "name": "GSC DMCR",
  "confidence": "high",
  "signals": ["mdraw.dll in pe_imports", "MINMM.dll in pe_imports"],
  "known_config": "Use cnc-ddraw in syswow64. mdraw.dll is a custom ddraw wrapper."
}
```

**New type needed:** `GameEngineDetector` in `Core/GameEngineDetector.swift`. Implements pattern matching against:
- PE imports (presence of engine-specific DLLs: `mdraw.dll`, `binkw32.dll`, `Miles Sound System`, `Unreal`, `id Software`)
- File patterns in game directory (`.pak`, `.upk`, `.vpk`, `.gob`, `engine.ini`)
- Registry keys in the bottle (app registration paths)
- EXE name patterns (`UT2004.exe`, `quake.exe`, `doom.exe`)

**Known engine signatures to ship in v1.1:**
- GSC DMCR (Cossacks) — `mdraw.dll`, `MINMM.dll`
- id Software (Quake/Doom) — `opengl32.dll` import, `.wad` files
- Unreal Engine 2 — `Engine.dll`, `.upk` files, `UnrealEngine2.exe` pattern
- Valve Source — `.vpk` files, `tier0.dll` import
- Sierra SCI — `RESOURCE.MAP`, `RESOURCE.000`

The engine detection result feeds into the system prompt enrichment for the session (see "Proactive Pre-configuration" below).

**Confidence:** HIGH — PE import parsing already exists in `inspectGame()` via `objdump -p`. Engine detection is an extension of existing pattern matching.

---

### 3. Proactive Pre-configuration

**Question:** Before agent loop starts? As an agent tool?

**Answer:** Before the agent loop starts, in `AIService.runAgentLoop()`, as a pre-configuration phase.

**Rationale:** The agent loop is designed for the LLM to drive decisions. But certain pre-configuration (renderer selection, resolution, disabling problematic intro videos) is mechanical: if engine X is detected, write file Y with content Z. Handing this to the LLM costs tokens and iterations for something we can deterministically apply before the first API call.

**Integration:**

`AIService.runAgentLoop()` currently:
1. Detects provider
2. Builds system prompt
3. Creates `AgentTools`
4. Creates `AgentLoop`
5. Calls `agentLoop.run()`

v1.1 inserts a new step between 3 and 4:

```swift
// Step 3.5: Pre-configuration phase
let preConfig = ProactiveConfigurator(
    gameId: gameId,
    entry: entry,
    executablePath: executablePath,
    bottleURL: bottleURL,
    wineProcess: wineProcess
)
let preConfigResult = preConfig.apply()
// preConfigResult.appliedActions: list of what was done (for system prompt injection)
// preConfigResult.engineDetected: "GSC DMCR" etc (for system prompt)
```

The pre-configuration result is injected into the initial user message (not the system prompt, to avoid polluting all sessions):
```
"Launch game 'Cossacks' (ID: cossacks-european-wars)...
Pre-configuration applied: engine=GSC DMCR, wrote ddraw.ini with renderer=opengl, placed cnc-ddraw in syswow64."
```

**New type needed:** `ProactiveConfigurator` in `Core/ProactiveConfigurator.swift`.

Responsibilities:
- Call `GameEngineDetector.detect()` to identify engine
- Check `SuccessDatabase` for existing success record (fast path: full replay)
- If success record exists: apply all known-working config mechanically, report to agent
- If no record: apply engine-class defaults (e.g., for GSC DMCR, write default `ddraw.ini`)

**What "apply" means:**
- Write INI/config files the game requires (via `write_game_file` equivalent logic)
- Set registry keys known to be required for the engine class
- Place DLLs from `KnownDLLRegistry` if engine signature implies them

**What it does NOT do:**
- Launch the game (that remains agent-driven)
- Make assumptions beyond engine-class known patterns
- Override the agent's subsequent decisions

**Confidence:** HIGH — this is pure Swift logic calling existing subsystems. No new external dependencies.

---

### 4. max_tokens Handling in AgentLoop

**Question:** How does this change the state machine?

**Current state:** `AgentLoop` already handles `max_tokens` stop reason (line 126-130 in `AgentLoop.swift`). It appends the truncated response and asks the model to continue. This is technically correct.

**What's missing for v1.1:**

The issue isn't the single-response truncation handler — that exists. The issue is **budget-aware escalation** and **loop resilience** when the agent fails to make progress:

1. **Stuck in max_tokens loop:** If the agent keeps getting truncated (e.g., it's trying to produce a very long response), the current code continues indefinitely until `maxIterations` is hit. Need: count consecutive max_tokens events; if >= 3, inject a directive: "Be more concise. Call one tool rather than explaining at length."

2. **Budget-aware escalation:** The agent currently has no visibility into how many iterations remain. Near the limit, it should be told to wrap up. Inject a countdown message when `remainingIterations <= 3`.

3. **Failure loop detection:** If the agent calls `launch_game` and it fails, then calls `launch_game` again with the same `accumulatedEnv` (no changes), it's stuck. Need: detect when the same tool is called twice in a row with identical inputs, and inject: "You already tried that. Diagnose the root cause before retrying."

**Integration:**

All changes live in `AgentLoop.run()` — the state machine method. No new types needed. Add:
- `consecutiveMaxTokens: Int` counter in the loop
- `lastToolCall: (name: String, inputHash: String)?` for stuck-loop detection
- Budget warning message injection when `maxIterations - iterationCount <= 3`

**Confidence:** HIGH — all changes are internal to `AgentLoop.run()`.

---

### 5. Smarter Search Strategies

**Question:** System prompt changes? New tools? Modified existing tools?

**Answer:** Both system prompt changes AND modifications to the existing `search_web` tool. No new tools needed.

**Current state:** `search_web` in `AgentTools` uses DuckDuckGo with a generic query and caches results per game. `fetch_page` retrieves and strips HTML.

**v1.1 changes:**

**A. Engine-aware search queries (system prompt change):**

The system prompt currently instructs the agent to call `search_web` with a game name query. v1.1 system prompt should add:
- After engine detection, include engine name in search queries
- Symptom-aware query construction: if `+msgbox` fires → search for "dialog" + game + wine
- Multi-target queries: WineHQ AppDB URL format, PCGamingWiki URL format for structured lookups

This is a system prompt change in `AIService.runAgentLoop()` — add a section:

```
## Search Strategy
When calling search_web:
- Include engine name if known: "[game] [engine] Wine macOS"
- Include symptom if known: "[game] [error] Wine fix"
- Try structured sources directly: "site:appdb.winehq.org [game]", "site:pcgamingwiki.com [game]"
- After failed launches: include specific error message in query
```

**B. Actionable fix extraction from fetch_page (modify fetch_page tool):**

Currently `fetch_page` returns up to 8000 chars of cleaned HTML text — the LLM must parse it. v1.1 should add a post-processing pass to `fetchPage()` in `AgentTools` that extracts structured fixes:

```swift
struct ExtractedFix {
    let envVars: [String: String]     // e.g., WINEDLLOVERRIDES=ddraw=n,b
    let winetricksVerbs: [String]     // e.g., ["d3dx9", "vcrun2015"]
    let registryKeys: [(key: String, value: String, data: String)]
    let notes: [String]               // free-text fix notes
}
```

The `fetchPage()` tool result gains an `extracted_fixes` key alongside `text_content`. Regex/string scanning for common patterns:
- `WINEDLLOVERRIDES=...` patterns
- `winetricks <verb>` mentions
- Registry key paths with dword values
- Gold/Platinum/Silver AppDB ratings

This reduces token usage (agent doesn't need to parse 8000 chars of prose) and makes fixes directly actionable.

**C. Success database cross-reference before web search (no new code):**

The system prompt already instructs: call `query_successdb` before `search_web`. v1.1 strengthens this: add symptom-based queries to the search strategy. If a `+msgbox` fires with text "cannot find file", search successdb with `symptom: "cannot find file"` before hitting the web.

**Confidence:** HIGH for A and C (system prompt changes). MEDIUM for B (regex extraction is imprecise — may miss edge cases in page formats).

---

## Recommended Project Structure

```
Sources/cellar/
├── Commands/           # CLI entry points (unchanged)
│   ├── AddCommand.swift
│   ├── LaunchCommand.swift
│   └── ...
├── Core/               # Business logic (primary change area)
│   ├── AgentLoop.swift         # MODIFY: budget awareness, stuck-loop detection
│   ├── AgentTools.swift        # MODIFY: fetch_page extraction, search hints, dialog results
│   ├── AIService.swift         # MODIFY: pre-config phase, smarter system prompt
│   ├── BottleManager.swift     # unchanged
│   ├── GameEngineDetector.swift     # NEW: engine signature detection
│   ├── ProactiveConfigurator.swift  # NEW: pre-config phase runner
│   ├── WindowMonitor.swift          # NEW: CGWindowListCopyWindowInfo wrapper
│   ├── WineProcess.swift       # MINOR MODIFY: pass WindowMonitor results to WineResult
│   ├── SuccessDatabase.swift   # unchanged
│   └── ...
├── Models/             # Data types (minor additions)
│   ├── GameEntry.swift         # unchanged
│   ├── WineResult.swift        # MODIFY: add dialogsDetected, gameWindowDetected
│   └── ...
└── Persistence/        # unchanged
```

### Structure Rationale

- `GameEngineDetector` is separate from `AgentTools` because engine detection is also used by `ProactiveConfigurator` (before the agent starts). Both need it without a circular dependency through `AgentTools`.
- `WindowMonitor` is separate from `WineProcess` because it uses CoreGraphics — isolating the import prevents CoreGraphics from touching every file that imports `WineProcess`.
- `ProactiveConfigurator` is separate from `AIService` because it may also be called by `AddCommand` in a future phase (detect engine during import, not just launch).

---

## Architectural Patterns

### Pattern 1: Pre-Launch Phase Runner

**What:** A synchronous "prepare" pass that runs before `AgentLoop.run()`. Detects engine, applies mechanical defaults, injects context into the initial message.

**When to use:** When there is deterministic config that can be applied without LLM judgment. Fast path for known-working games.

**Trade-offs:** Adds latency before the first API call (typically < 1 second). Risk: pre-config applies wrong defaults and confuses the agent. Mitigate by reporting all pre-config actions in the initial message so the agent can reason about them.

```swift
// In AIService.runAgentLoop():
let preConfig = ProactiveConfigurator(...)
let result = preConfig.apply()
let contextNote = result.appliedActions.isEmpty
    ? ""
    : "\nPre-configuration applied:\n" + result.appliedActions.joined(separator: "\n")
let initialMessage = "Launch the game...\(contextNote)"
```

### Pattern 2: In-Process Window Monitor

**What:** A lightweight background observer that runs inside the `WineProcess.run()` polling loop. Snapshots window state at each tick without spawning a new process.

**When to use:** When observing macOS window state during a blocking synchronous operation.

**Trade-offs:** `CGWindowListCopyWindowInfo` is a synchronous call on the main thread context. In a CLI tool (no runloop), this works fine — the call returns immediately. No async overhead. However, the call requires the process to have screen recording permission on macOS 10.15+ (Catalina) — this is a potential user friction point.

```swift
// In WineProcess.run() polling loop:
while process.isRunning {
    Thread.sleep(forTimeInterval: 2.0)
    if let snapshot = WindowMonitor.poll() {
        if snapshot.looksLikeDialog {
            dialogsDetected.append(snapshot)
        }
    }
    // stale timeout check...
}
```

### Pattern 3: Tool Result Enrichment

**What:** Post-processing tool results to extract structured data before returning to the agent. Applied in `fetch_page` and `launch_game`.

**When to use:** When raw tool output (page HTML, Wine stderr) contains information the agent would spend tokens parsing. Extract the signal, reduce noise.

**Trade-offs:** Regex extraction is imprecise. Always include the raw text alongside extracted data so the agent can fall back to reading the full content when extraction misses something.

```swift
// In fetchPage():
let rawText = extractVisibleText(from: htmlContent)
let fixes = ExtractedFix.extract(from: rawText)
return jsonResult([
    "text_content": rawText,
    "extracted_fixes": fixes.asDictionary  // structured, may be empty
])
```

---

## Data Flow

### v1.1 Launch Flow

```
cellar launch <game>
      │
      ▼
LaunchCommand.run()
      │
      ▼
AIService.runAgentLoop()
      │
      ├─► ProactiveConfigurator.apply()
      │       │
      │       ├─► GameEngineDetector.detect(peImports, files, registry)
      │       │       └─► returns: engine name, confidence, known_config
      │       │
      │       ├─► SuccessDatabase.queryByGameId()
      │       │       └─► if found: apply known config mechanically
      │       │
      │       └─► returns: appliedActions[], engineDetected
      │
      ├─► Build system prompt (enriched with engine context)
      │
      ├─► Build initial message (includes pre-config summary)
      │
      └─► AgentLoop.run()
              │
              │   [iteration loop]
              │
              ├─► callAnthropic(messages)
              │       └─► handles: end_turn / tool_use / max_tokens
              │
              ├─► tool_use → AgentTools.execute(name, input)
              │       │
              │       ├─► inspect_game → GameEngineDetector embedded
              │       │
              │       ├─► launch_game → WineProcess.run()
              │       │       │
              │       │       └─► WindowMonitor.poll() [inside polling loop]
              │       │               └─► CGWindowListCopyWindowInfo
              │       │
              │       ├─► search_web → DuckDuckGo + cache
              │       │
              │       └─► fetch_page → HTTP + ExtractedFix.extract()
              │
              └─► budget warning injection (when iterations ≤ 3 remaining)
```

### Key Data Flows

1. **Engine detection signal path:** `objdump -p` PE imports → `GameEngineDetector.detect()` → `inspectGame()` result → agent context → search query enrichment
2. **Dialog detection signal path:** `CGWindowListCopyWindowInfo` → `WindowMonitor.poll()` → `WineResult.dialogsDetected` → `launch_game` tool result JSON → agent reasoning
3. **Pre-config fast path:** `SuccessDatabase.queryByGameId()` → `ProactiveConfigurator.apply()` → mechanical config applied → agent skips research phase
4. **max_tokens budget path:** `consecutiveMaxTokens` counter in `AgentLoop` → directive injection → LLM produces concise response

---

## Scaling Considerations

This is a single-user CLI tool. Scaling is not a concern. The relevant performance considerations are:

| Concern | Current | v1.1 Impact | Mitigation |
|---------|---------|-------------|-----------|
| Pre-config latency | 0ms (no pre-config) | ~50-200ms (engine detect + successdb query) | Acceptable — before first API call |
| Window monitor overhead | 0 (none) | ~1ms per 2-second tick | Negligible |
| fetch_page extraction | Not implemented | ~5ms per page | Acceptable |
| AgentLoop iteration count | Unchanged | Stuck-loop detection adds <1ms per iteration | Negligible |

---

## Anti-Patterns

### Anti-Pattern 1: CGWindowListCopyWindowInfo as a Separate Agent Tool

**What people might do:** Add a `check_windows` tool to the 18-tool roster so the agent can call it on demand.

**Why it's wrong:** The agent cannot call tools while `launch_game` is executing — the tool executor is synchronous and blocks during the Wine process run. A `check_windows` tool would only work between launches (when no windows exist) or would require making `launch_game` async (major refactor). The signal is only useful during a launch.

**Do this instead:** Embed window monitoring inside `WineProcess.run()`'s polling loop and surface the results in `WineResult`. The `launch_game` tool reports dialog state after the process exits.

### Anti-Pattern 2: Proactive Config as Agent Tool Calls

**What people might do:** Let the agent call `inspect_game`, `detect_engine`, then decide to call `write_game_file` and `place_dll` before the first launch. This happens anyway in the Research phase.

**Why it's wrong:** This costs 4-6 agent iterations (inspect → search → verify → configure → re-inspect → launch). For known-working games, these iterations are pure overhead. Pre-configuration eliminates them for the common case.

**Do this instead:** `ProactiveConfigurator` runs the mechanical defaults before the first API call. Report what was applied in the initial message. The agent validates and builds on this rather than rediscovering it.

### Anti-Pattern 3: Engine Detection via LLM

**What people might do:** Ask the LLM to identify the engine from the file list and PE imports.

**Why it's wrong:** LLM-based engine detection costs tokens and an iteration. The engine detection is purely pattern matching on file names — no reasoning required. Pattern matching is deterministic, fast, and free.

**Do this instead:** `GameEngineDetector` is pure Swift — a switch statement on known import patterns and file signatures. LLM only sees the output (structured engine result), not the detection logic.

### Anti-Pattern 4: Replacing `search_web` with Brave/Bing API

**What people might do:** Replace the DuckDuckGo scrape with a paid search API for better results.

**Why it's wrong for v1.1:** The issue isn't search quality — it's search query quality and fix extraction. The same DuckDuckGo results become much more useful when (a) the query includes the engine name and symptom, and (b) the page content is parsed for actionable fixes. Fix the query and extraction first; worry about the search provider later.

**Do this instead:** Keep DuckDuckGo. Improve the system prompt search strategy instructions. Add `ExtractedFix` post-processing to `fetch_page`.

---

## Integration Points

### External Services

| Service | Integration Pattern | v1.1 Notes |
|---------|---------------------|------------|
| Anthropic API | Synchronous HTTP via DispatchSemaphore in `AgentLoop` | No change — existing pattern is correct |
| DuckDuckGo | HTML scrape in `AgentTools.searchWeb()` | No change to mechanism; improve queries via system prompt |
| GitHub (DLL downloads) | `DLLDownloader` in `WineActionExecutor` | No change |
| CGWindowListCopyWindowInfo | CoreGraphics framework call | NEW — requires `import CoreGraphics` in `WindowMonitor.swift` |

### Internal Boundaries

| Boundary | Communication | v1.1 Notes |
|----------|---------------|------------|
| `AIService` → `ProactiveConfigurator` | Direct call, returns `PreConfigResult` struct | NEW boundary |
| `ProactiveConfigurator` → `GameEngineDetector` | Direct call, returns `EngineDetectionResult` | NEW boundary |
| `ProactiveConfigurator` → `SuccessDatabase` | Direct static call | Reuses existing API |
| `AgentTools.inspectGame()` → `GameEngineDetector` | Direct call | NEW — replaces ad-hoc pattern matching in `inspectGame` |
| `WineProcess.run()` → `WindowMonitor` | Call inside polling loop | NEW — polling every 2s, returns optional `WindowSnapshot` |
| `AgentLoop` → budget warning injection | Internal to `AgentLoop.run()` state machine | NEW — no external boundary |

---

## Build Order

Dependencies determine order. Items at the same level can be built in parallel.

```
Level 1 (no dependencies):
  ├─ GameEngineDetector.swift — pure pattern matching, no dependencies
  └─ WindowMonitor.swift — CoreGraphics only, no Cellar dependencies

Level 2 (depends on Level 1):
  ├─ WineProcess.swift modification — add WindowMonitor call + WineResult fields
  ├─ AgentTools.inspectGame() modification — embed GameEngineDetector
  └─ ProactiveConfigurator.swift — depends on GameEngineDetector + SuccessDatabase (existing)

Level 3 (depends on Level 2):
  ├─ AIService.runAgentLoop() modification — add ProactiveConfigurator phase, richer system prompt
  ├─ AgentLoop.run() modification — budget awareness, stuck-loop detection, max_tokens counting
  └─ AgentTools.fetchPage() modification — add ExtractedFix post-processing

Level 4 (integration, depends on all):
  └─ System prompt refinements — engine-aware search strategy, dialog-awareness guidance
```

### Recommended Delivery Sequence

| Step | What | Why This Order |
|------|------|----------------|
| 1 | `WindowMonitor` + `WineResult` changes | Self-contained, no risk to existing flow. Dialog signal works even before agent changes. |
| 2 | `GameEngineDetector` + embed in `inspectGame` | Unblocks ProactiveConfigurator. `inspect_game` gains engine field with no behavior change. |
| 3 | `AgentLoop` resilience changes | Isolate loop fixes from feature changes. Easier to verify independently. |
| 4 | `ProactiveConfigurator` + `AIService` pre-config phase | Depends on GameEngineDetector and SuccessDatabase. High-value: known-game fast path. |
| 5 | `fetch_page` fix extraction + system prompt search strategy | Lower risk (adds data, doesn't change flow). Can ship without other v1.1 features. |
| 6 | End-to-end integration testing | Verify combined dialog + engine + pre-config + smarter search works cohesively. |

---

## Sources

- Direct inspection of `AgentLoop.swift`, `AgentTools.swift`, `AIService.swift`, `WineProcess.swift` (2026-03-28)
- Direct inspection of `SuccessDatabase.swift`, `GameEntry.swift`, `LaunchCommand.swift` (2026-03-28)
- `.planning/agentic-architecture-v2.md` — v2 architecture design document (2026-03-28)
- `.planning/PROJECT.md` — v1.1 requirements and constraints (2026-03-28)
- `CGWindowListCopyWindowInfo` — CoreGraphics API, macOS 10.5+, no entitlement required for CLI (MEDIUM confidence — based on training data, should verify screen recording permission behavior on macOS 15 Sequoia)

---
*Architecture research for: Cellar v1.1 Agentic Independence integration*
*Researched: 2026-03-28*
