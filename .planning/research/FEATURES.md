# Feature Research: Cellar v1.1 — Agentic Independence

**Domain:** macOS CLI+TUI Wine game launcher — agent autonomy layer
**Researched:** 2026-03-28
**Confidence:** HIGH (existing codebase examined, Anthropic API docs verified)

---

## Context: What v1.0 Already Ships

These features exist and are NOT scope for v1.1:

- 18-tool agent loop (inspect_game, launch_game, place_dll, set_environment, set_registry, install_winetricks, read_log, read_registry, ask_user, save_recipe, write_game_file, trace_launch, check_file_access, verify_dll_override, query_successdb, save_success, search_web, fetch_page)
- Research-Diagnose-Adapt three-phase system prompt
- DuckDuckGo web search with 7-day research cache
- Success database with symptom fuzzy matching
- DLL placement with companion files and syswow64 auto-detection
- Working directory fix (CWD set to game exe parent)

The v1.1 features build on this foundation. The agent loop exists — it needs to be *smarter*, more *resilient*, and more *aware* of what the game is doing.

---

## Feature Landscape

### Table Stakes (Users Expect These)

For a tool that claims "agentic independence," the following are minimum credibility requirements. Missing any of these means the agent will silently give up, waste money on repeated failures, or get stuck on trivially detectable problems.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Agent persists through max_tokens truncation | API responses are sometimes cut mid-tool-call; agent must not abort | LOW | Pattern is documented by Anthropic: detect incomplete tool_use block when stop_reason == max_tokens, retry with higher max_tokens. AgentLoop.swift already handles stop_reason: max_tokens with a continuation prompt — this needs hardening for the incomplete tool_use block case specifically. |
| Agent persists through API errors with retry | Network blips should not abort a 20-minute session | LOW | Current code returns immediately on any HTTP error. Needs 3-attempt retry with exponential backoff for 5xx and network errors; 4xx (except 429) are fatal. |
| Agent persists through tool execution errors | A tool returning an error JSON should not halt the loop | LOW | Tool executor already returns strings, not throws. The loop continues. Needs explicit "error" framing in tool result so agent understands it must handle it, not give up. |
| Budget tracking — total token cost visible | Users need to know if they spent $0.10 or $5.00 on a session | LOW | AnthropicToolResponse already includes usage.input_tokens and usage.output_tokens. Sum across iterations. Print at end of session. |
| Agent stops when budget ceiling is hit | Open-ended loops can run up unexpected bills | MEDIUM | Configurable budget ceiling (default $1.00). Track cumulative cost using model pricing constants. Warn at 80%, halt at 100%. Current loop has no cost awareness. |
| Wine trace parsing delivers structured output | trace_launch already exists; output must be structured, not raw stderr | MEDIUM | Already implemented per agentic-architecture-v2.md. Verify actual test results (UAT test 7). The key capability is parsing `+loaddll` output to `{ name, path, type: "native/builtin" }`. |
| Dialog stuck detection via Wine traces | Agent must know if game is blocked on a dialog vs crashed | HIGH | WINEDEBUG=+msgbox emits `trace:msgbox:MessageBoxW` with dialog title and text. Format: `yyy:xxx:FunctionName message`. Parsing this stream identifies stuck-on-dialog state. No competitor does this automatically. |

### Differentiators (Competitive Advantage)

These are what makes Cellar genuinely autonomous rather than a fancy script runner.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Game engine detection from files | Engine type predicts the entire fix strategy (DirectDraw game = cnc-ddraw path; Unreal 1 = OpenGL renderer flags; Build engine = different DLL set) | MEDIUM | File patterns are reliable: `UnrealI.u` / `*.u` + `*.ini` = Unreal 1; `*.GRP` + `DUKE3D.EXE` = Build engine; `dmcr.exe` + `mdraw.dll` = GSC/DMCR engine; `*.pak` + `Binaries/Win64` = UE4+. PE imports are a secondary signal. No existing macOS tool detects engine for Wine compatibility purposes. |
| Engine-aware pre-configuration | Skip renderer selection dialogs before first launch by writing correct INI/registry values | HIGH | For Unreal 1 games: write `[WinDrv.WindowsClient] WindowedViewportX=1024` to `[game].ini` before launch. For DirectDraw games: write `ddraw.ini`. For Build engine games: write `setup.cfg`. Agent can do this proactively based on engine detection, eliminating the "stuck on renderer dialog" class of failure. This is unique — no competitor handles old-game first-run configuration automatically. |
| Hybrid dialog detection (Wine + window list) | Combine `trace:msgbox` parsing with CGWindowListCopyWindowInfo window size/title to confirm dialog vs game | HIGH | CGWindowListCopyWindowInfo (Screen Recording permission) returns kCGWindowBounds, kCGWindowName, kCGWindowOwnerPID. A dialog: small window (< 600x400), title contains "Error"/"Warning"/"Setup"/"Renderer". A game: large window or titled with game name. Wine msgbox trace fires synchronously before the dialog appears. Hybrid signal gives high confidence. Competitors (Bottles, Heroic, Lutris) do none of this — they rely entirely on user reporting. |
| Cross-game success pattern matching | When encountering a new game, query success DB by engine/graphics API/symptoms to seed the diagnosis | MEDIUM | Already designed in agentic-architecture-v2.md. `query_successdb({ engine: "GSC", tags: ["directdraw"] })` returns Cossacks fix strategy for American Conquest. The differentiator is the tag schema and the agent's willingness to use analogical reasoning. Competitors have static script databases with no dynamic cross-game reasoning. |
| Engine-aware web search queries | Search "Cossacks Wine macOS" not just "game name Wine" — include engine name, graphics API, specific error | MEDIUM | search_web already exists. Enhancement: agent constructs richer queries from engine detection output. `"[engine] [graphics_api] Wine macOS [symptom]"` returns far more relevant results than `"[game_name] Wine"`. |
| Actionable fix extraction from web pages | fetch_page already exists — agent needs structured extraction, not free-text summarization | MEDIUM | Agent system prompt needs explicit extraction instruction: "Extract: exact env var names and values, exact registry paths, exact DLL names, exact winetricks verbs, exact INI file changes. Discard: general descriptions, unrelated OS advice, version-specific notes for Windows only." No tooling change needed — prompt engineering. |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Automated screenshot-based success detection | Users want zero-touch launches | Requires screen recording permission, vision model API calls ($$$), high false positive rate on loading screens vs game windows | User-confirmed validation (already shipped). For v1.1, add hybrid window size + title heuristic as a soft signal, but keep user confirmation as authoritative. |
| Virtual desktop mode for stuck dialogs | "Wine virtual desktop fixes display issues" | Does NOT work on macOS winemac.drv — only works with XQuartz X11. Confirmed broken. Already removed from system prompt. | cnc-ddraw via syswow64 for DirectDraw games. OpenGL renderer INI pre-set for 3D engines. |
| Automatic Wine version switching | Users expect "try different Wine version" as a fix | Gcenx tap only provides one active Wine build. Version switching is not a viable repair strategy in this setup. Would require downloading multiple Wine builds. | Focus on correct configuration, not version gambling. |
| Winetricks mass-installation | "Install all common Windows components preemptively" | Breaks bottle cleanliness, installs unneeded components, masks actual missing dependency. Winetricks verbs take 5-30 minutes. | Install only what PE imports or runtime errors specifically require. |
| AI-generated dialog button clicking | "Agent should click OK on dialogs automatically" | Requires Accessibility API (separate permission), fragile to window layout changes, dangerous if it clicks wrong button in a game-critical dialog | Proactive pre-configuration eliminates most first-run dialogs. Remaining ones handled by asking user. |
| Parallel multi-config testing | "Try 5 configs simultaneously and pick what works" | Wine processes share X11/winemac resources; parallel Wine processes cause display corruption and race conditions on macOS | Sequential Research-Diagnose-Adapt with a budget ceiling is faster and more reliable. |

---

## Feature Dependencies

```
Agent Loop Resilience (max_tokens + retry + budget)
  └── required by: all other features (foundational)

Wine Trace Parsing (already in trace_launch)
  └── enhances──> Dialog Detection via trace:msgbox
                      └── requires──> WINEDEBUG=+msgbox in trace_launch call
                      └── enhances──> Hybrid Dialog Detection (window list)

CGWindowListCopyWindowInfo Window Detection
  └── requires──> Screen Recording permission (macOS entitlement)
  └── enhances──> Dialog Detection
  └── optional complement to trace:msgbox (not a replacement)

Game Engine Detection
  └── enhances──> Engine-Aware Pre-Configuration (INI/registry before launch)
  └── enhances──> Engine-Aware Web Search (better query construction)
  └── enhances──> Cross-Game Pattern Matching (engine tag in success DB)

Cross-Game Pattern Matching (query_successdb by engine/tags)
  └── requires──> Success database with engine+tags fields (already in schema)
  └── enhances──> Research phase (query DB before web search)

Actionable Fix Extraction
  └── requires──> fetch_page (already exists)
  └── requires──> system prompt extraction instructions (prompt change only)
  └── enhances──> Engine-Aware Web Search (better inputs → better extraction)
```

### Dependency Notes

- **Agent Loop Resilience must come first:** every other feature fails ungracefully if the loop aborts on max_tokens or a network error. This is Phase 1.
- **Engine Detection enables Pre-Configuration:** you cannot pre-set INI files for an unknown engine. Engine detection unlocks the entire pre-configuration category.
- **Window Detection requires Screen Recording entitlement:** this is a macOS permission the user must grant. Add late — don't block core features on this optional enhancement.
- **Dialog Detection via trace:msgbox is independent of window detection:** the Wine trace approach works without any new macOS permissions. Prefer it.
- **Cross-Game Matching requires populated success DB:** one entry (Cossacks) is enough to demo the concept. The value compounds over time.

---

## MVP Definition for v1.1

### Launch With (v1.1 core — must ship)

- [ ] **Agent loop resilience** — max_tokens recovery, API retry, budget ceiling, empty response handling. Foundational. Without this, all other improvements are fragile.
- [ ] **Budget tracking with session summary** — print total tokens + cost at end of every agent session. Immediate user trust improvement.
- [ ] **Game engine detection** — detect engine from file patterns and PE imports. Required for pre-configuration and smarter research. Low-to-medium complexity, high leverage.
- [ ] **Engine-aware pre-configuration** — write INI / registry before first launch for known engines (Unreal 1, DirectDraw/cnc-ddraw, Build engine). Eliminates "stuck on renderer dialog" class of first-run failure.
- [ ] **Wine trace:msgbox dialog detection** — add `+msgbox` to WINEDEBUG in trace_launch, parse `trace:msgbox:MessageBoxW` lines, return structured dialog info. No new permissions required.
- [ ] **Actionable fix extraction** — system prompt instruction update only. No code change. Immediate improvement to research quality.

### Add After Validation (v1.1 stretch)

- [ ] **Engine-aware search queries** — extend search_web to accept engine/graphics-api hints and construct richer queries. Add when engine detection is validated.
- [ ] **Cross-game pattern matching** — extend query_successdb to query by engine and graphics_api tags, not just game_id. Add after Cossacks success record is confirmed.
- [ ] **Hybrid window detection (CGWindowListCopyWindowInfo)** — add as a complement to trace:msgbox. Requires Screen Recording permission. Add after trace-based detection is proven. Keep optional (graceful degradation if permission denied).

### Future Consideration (v2+)

- [ ] **Proton compatibility database integration** — ProtonDB API or scraper for community reports. High value but high maintenance. Defer until web search proves insufficient.
- [ ] **Multi-session agent memory** — persist agent reasoning across sessions (not just recipes). Requires conversation compaction design. Defer until context window limits become a real bottleneck.
- [ ] **Vision-based dialog detection** — screenshot analysis to identify stuck state without user confirmation. Expensive (vision model API), requires permissions, fragile. Defer until v2 maturity.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Agent loop resilience (max_tokens + retry) | HIGH | LOW | P1 |
| Budget tracking + session cost summary | HIGH | LOW | P1 |
| Game engine detection | HIGH | MEDIUM | P1 |
| Engine-aware pre-configuration | HIGH | MEDIUM | P1 |
| Wine trace:msgbox dialog detection | HIGH | MEDIUM | P1 |
| Actionable fix extraction (prompt only) | HIGH | LOW | P1 |
| Engine-aware search queries | MEDIUM | LOW | P2 |
| Cross-game pattern matching | MEDIUM | LOW | P2 |
| Hybrid window detection (CGWindowListCopyWindowInfo) | MEDIUM | HIGH | P2 |
| Vision-based dialog detection | LOW | HIGH | P3 |
| Multi-session agent memory | MEDIUM | HIGH | P3 |

**Priority key:**
- P1: Must have for v1.1 launch
- P2: Should have, add when P1 is validated
- P3: Nice to have, future consideration

---

## Competitor Feature Analysis

| Feature | Bottles (Linux) | Lutris (Linux) | Heroic (Linux/macOS) | Cellar v1.1 |
|---------|-----------------|---------------|----------------------|-------------|
| Dialog/msgbox detection | None — user reports stuck | None — user reports stuck | None — user reports stuck | trace:msgbox parsing + optional window heuristic |
| Engine detection | None — manual config | None — manual scripts | None — launcher scripts | File pattern + PE imports auto-detection |
| Pre-configuration (INI/renderer) | Manual — user edits files | Script-based per-game | Manual — per-game launch options | Automatic based on engine detection |
| AI repair loop | None | None | None | 18-tool Research-Diagnose-Adapt loop |
| Budget/cost tracking | N/A (no AI) | N/A (no AI) | N/A (no AI) | Per-session token + cost summary |
| Cross-game learning | Static community scripts | Static install scripts | None | Success DB with tag-based similarity queries |
| macOS-native | No (Linux) | No (Linux) | Partial (uses CrossOver) | Yes — wined3d/OpenGL, Apple silicon, Swift 6 |

**Key insight:** No competitor does dialog detection, engine detection, or proactive pre-configuration. These are genuinely novel capabilities in the macOS Wine compatibility space. The agent architecture is the moat.

---

## Technical Implementation Notes

### Agent Loop Resilience — What Already Exists vs What's Missing

**Already in AgentLoop.swift:**
- `stop_reason: max_tokens` → appends assistant turn + continuation prompt (line 125-129)
- Max iteration ceiling (`maxIterations: 20`)
- Error logging on API failure

**Missing (needs adding):**
- Incomplete `tool_use` block detection when `max_tokens` fires mid-tool-call. Current code sends a continuation text prompt, but if the last content block is a partial `tool_use` block (no complete `input` JSON), Claude may confuse itself. The documented fix: detect `response.content.last?.type == .toolUse` when `stop_reason == max_tokens`, then retry with higher `maxTokens` (not a continuation message).
- 3-attempt exponential backoff retry on HTTP 5xx and network errors (currently returns immediately)
- Token accumulation across iterations (`usage.input_tokens + usage.output_tokens` per call)
- Budget ceiling check (configurable, default $1.00) with 80% warning
- Empty `end_turn` response guard (Anthropic docs: empty response after tool results means Claude thinks it's done — send "Please continue" user message)

### Game Engine Detection — Reliable File Patterns

Patterns ordered by specificity (check specific before general):

| Engine | File Indicators | Confidence |
|--------|----------------|------------|
| GSC/DMCR (Cossacks, American Conquest) | `dmcr.exe` + `mdraw.dll` | HIGH |
| Unreal 1 (1998-2000) | `*.u` files + `System/` dir + `[game].ini` | HIGH |
| Build Engine (Duke Nukem 3D, Blood) | `*.GRP` file in root | HIGH |
| id Tech 2 (Quake II) | `baseq2/pak0.pak` | HIGH |
| id Tech 3 (Quake III) | `baseq3/pak0.pk3` | HIGH |
| Unity (2010+) | `[GameName]_Data/` directory | HIGH |
| Unreal Engine 4/5 | `[Game]/Binaries/Win64/` | HIGH |
| Westwood/C&C | `*.mix` files | MEDIUM |
| Blizzard (StarCraft 1) | `Storm.dll` + `*.mpq` | MEDIUM |
| Custom/Unknown | PE imports analysis, no pattern match | LOW |

PE imports are a secondary signal: `ddraw.dll` import = DirectDraw game; `d3d9.dll` = DX9; `opengl32.dll` = OpenGL; custom shim DLL (like `mdraw.dll`) = game-specific wrapper.

### Wine trace:msgbox Output Format

When WINEDEBUG includes `+msgbox`, Wine emits to stderr:

```
trace:msgbox:MessageBoxW hwnd=0x0 text=L"Direct Draw Init Failed (80004001)" caption=L"Error" type=0x10
```

Parse fields: `text=L"[message]"` and `caption=L"[title]"` to extract dialog content. This fires synchronously as the dialog appears, before user interaction. The agent can read this from the trace_launch stderr output and return a structured result like:
```json
{ "dialog_detected": true, "title": "Error", "message": "Direct Draw Init Failed (80004001)" }
```

This is enough to skip the "launch failed — read the log" cycle and go straight to a targeted fix.

### CGWindowListCopyWindowInfo — Dialog Heuristic

Requires Screen Recording entitlement (`com.apple.security.screen-recording` or runtime prompt via `CGRequestScreenCaptureAccess()`). Returns window list with `kCGWindowBounds`, `kCGWindowName`, `kCGWindowOwnerPID`, `kCGWindowLayer`.

Dialog heuristic for Wine windows:
- Owner process is `wine64`, `wine`, or `wineserver`
- Window size is small: width < 600 OR height < 200
- Window title contains "Error", "Warning", "Setup", "Select", "Renderer", "DirectX", or is exactly the game name followed by nothing

Game window heuristic:
- Owner is wine process family
- Window size is large: width >= 640 AND height >= 480
- Window title matches game name or is empty (fullscreen)

This is supplementary to trace:msgbox, not a replacement. The trace fires faster and requires no permissions.

---

## Sources

- Anthropic API documentation — stop_reason handling, max_tokens recovery: [Handling stop reasons](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons) — HIGH confidence
- Anthropic API documentation — context windows and token awareness: [Context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows) — HIGH confidence
- Wine debug channel format — WineHQ community documentation: [Debug Channels (WineHQ staging wiki)](https://github.com/wine-compholio/wine-staging/wiki/Debug) — HIGH confidence
- Wine msgbox.c source — confirms WINEDEBUG=+msgbox output format: [wine-mirror/wine msgbox.c](https://github.com/wine-mirror/wine/blob/master/dlls/user32/msgbox.c) — HIGH confidence
- CGWindowListCopyWindowInfo — Apple developer documentation: [Apple Developer Docs](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo) — HIGH confidence
- Game engine file patterns — community tools and PCGamingWiki: [game-engine-finder (vetleledaal)](https://github.com/vetleledaal/game-engine-finder), [enginedetect (YellowberryHN)](https://github.com/YellowberryHN/enginedetect) — MEDIUM confidence (source code not fully inspected)
- Existing codebase analysis — AgentLoop.swift, AgentTools.swift, agentic-architecture-v2.md — HIGH confidence

---
*Feature research for: Cellar v1.1 Agentic Independence*
*Researched: 2026-03-28*
