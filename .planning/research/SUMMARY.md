# Project Research Summary

**Project:** Cellar v1.1 — Agentic Independence
**Domain:** macOS CLI Wine game launcher — agent autonomy layer additions
**Researched:** 2026-03-28
**Confidence:** HIGH

## Executive Summary

Cellar v1.1 extends an existing, proven agent loop (18 tools, Research-Diagnose-Adapt system prompt, success database) rather than building from scratch. The research confirms that all five technical questions for v1.1 — window detection, PE parsing, Wine trace parsing, HTML extraction, and max_tokens handling — have well-understood solutions using either standard Apple frameworks or a single new Swift dependency (SwiftSoup 2.8.7). The only genuinely new external dependency is SwiftSoup for structured HTML extraction from fetched web pages; everything else builds on CoreGraphics, Foundation, and the existing `objdump` toolchain. The recommended approach is to layer v1.1 features incrementally: fix the agent loop's correctness gaps first (max_tokens mid-tool-use truncation is a latent bug that will corrupt loop state under real usage), then add the engine detection and proactive pre-configuration layer that eliminates the most common class of first-run failures, then add dialog detection as a fallback.

The key architectural insight from research is that the three new capabilities — dialog detection, engine detection, and proactive pre-configuration — are not independent features. They form a causal chain: engine detection enables pre-configuration (which eliminates first-run dialogs before they appear), and dialog detection is the fallback when pre-configuration is incomplete or wrong. Building them in isolation and integrating them later creates rework. The recommended delivery sequence (engine detection → pre-configuration → dialog detection) mirrors the causal data flow at runtime. All three new modules (`GameEngineDetector`, `ProactiveConfigurator`, `WindowMonitor`) are self-contained and can be built without changes to the existing agent loop API surface.

The top risk for the entire v1.1 effort is a cluster of silent-failure modes: `CGWindowListCopyWindowInfo` silently omitting window titles without Screen Recording permission, Wine trace format varying across Gcenx CrossOver builds, and engine detection producing false-positive pre-configuration that breaks games. All three fail without errors, producing behavior that is hard to attribute to the new features. The mitigation is consistent across all three cases: build graceful degradation and fallback paths before assuming the happy path works, test against actual Gcenx-distributed Wine binaries (not upstream Wine documentation), and prefer trace:msgbox (no permissions required, fires synchronously) over `CGWindowListCopyWindowInfo` as the primary dialog detection signal.

---

## Key Findings

### Recommended Stack

The v1.1 stack requires only one new external dependency. All window detection, PE parsing, Wine trace parsing, and agent loop changes use existing Apple frameworks or toolchain utilities already present. SwiftSoup 2.8.7 (pure Swift, SPM-compatible, actively maintained as of March 2025) replaces the current raw-text HTML stripping in `fetch_page` with structured CSS-selector-based extraction capable of pulling tables, code blocks, and list items from WineHQ AppDB and PCGamingWiki pages.

**Core technologies:**
- `CoreGraphics` (built-in, macOS 14+): macOS window list enumeration via `CGWindowListCopyWindowInfo` — returns bounds, owner PID, layer, and window title (with Screen Recording permission) for all on-screen windows; not deprecated as of macOS 15 Sequoia
- `Foundation.Data` + `objdump -p` (built-in toolchain): PE header and import table extraction — use `objdump -p` first (already proven in the codebase); native Swift binary parsing (~80-100 lines) is available as fallback if `objdump` proves unreliable
- `SwiftSoup 2.8.7`: structured HTML extraction from fetched web pages — the only production-grade HTML parser in the Swift ecosystem; pure Swift, no C dependencies, Swift 6 compatible, SPM native
- `AgentLoop.swift` logic changes only: max_tokens + incomplete tool_use block handling, stuck-loop detection, budget ceiling — no new framework needed

**Critical version note:** When `stop_reason == "max_tokens"` and the last content block is a `tool_use` block, the correct recovery is to retry with higher `max_tokens` without appending the truncated response. The current AgentLoop handles text truncation correctly but will corrupt state on tool_use truncation. This is a correctness fix with documented Anthropic guidance.

### Expected Features

**Must have (table stakes — P1):**
- Agent loop resilience: max_tokens mid-tool-use truncation handled correctly; 3-attempt exponential backoff on HTTP 5xx; budget ceiling with session cost summary printed at session end
- Game engine detection from file patterns and PE imports — enables proactive pre-configuration and richer research queries
- Engine-aware proactive pre-configuration — write `ddraw.ini`, renderer INI, or known-working registry values before first launch for recognized engines; eliminates the "stuck on renderer dialog" class of first-run failures
- Wine trace:msgbox dialog detection — add `+msgbox` to WINEDEBUG in `trace_launch`, parse structured dialog title and text from stderr; no new macOS permissions required
- Actionable fix extraction from `fetch_page` — SwiftSoup post-processing returns `extracted_fixes` (env vars, winetricks verbs, registry keys) alongside existing `text_content`

**Should have (competitive — P2):**
- Engine-aware search queries — include engine name and graphics API in DuckDuckGo queries constructed after engine detection runs
- Cross-game pattern matching via success DB — query by engine/graphics_api tags; use similarity matches as hypotheses requiring trace_launch verification, not direct configuration application
- Hybrid window detection (CGWindowListCopyWindowInfo) — size/layer heuristics as optional complement to trace:msgbox; degrades gracefully without Screen Recording permission

**Defer (v2+):**
- Proton compatibility database integration — high value but high maintenance; web search sufficient for now
- Multi-session agent memory — defer until context window limits become an actual bottleneck
- Vision-based dialog detection — expensive (vision model API), fragile, requires additional permissions

**Anti-features (confirmed, do not build):**
- Virtual desktop mode — confirmed broken on macOS winemac.drv (XQuartz-only feature)
- Automatic Wine version switching — Gcenx tap provides one active build; version gambling is not a viable repair strategy
- Winetricks mass-installation — breaks bottle cleanliness, masks actual dependency gaps
- AI-generated dialog button clicking — requires Accessibility API permission, dangerous if wrong button is clicked

### Architecture Approach

The architecture is an incremental modification of the existing `AgentLoop` / `AgentTools` / `AIService` triad, adding three new modules (`GameEngineDetector`, `ProactiveConfigurator`, `WindowMonitor`) and making targeted changes to `WineProcess`, `AgentTools.inspectGame()`, `AgentTools.fetchPage()`, and `AgentLoop.run()`. The key structural decision is that proactive pre-configuration runs as a synchronous phase in `AIService.runAgentLoop()` before the first API call — it is not an agent tool. This eliminates 4-6 agent iterations for known-working games and is the right use of deterministic pattern matching (no LLM needed for engine detection). Window monitoring runs inside `WineProcess.run()`'s existing 2-second polling loop, not as a separate agent tool (the agent cannot call tools while a synchronous launch is blocking the executor).

**Major components:**
1. `GameEngineDetector` (new, `Core/GameEngineDetector.swift`) — pure Swift pattern matching on PE imports and file signatures; called from both `ProactiveConfigurator` and `AgentTools.inspectGame()`; returns confidence-scored engine hypothesis, not an assertion
2. `ProactiveConfigurator` (new, `Core/ProactiveConfigurator.swift`) — runs before first API call in `AIService.runAgentLoop()`; detects engine, checks success DB for exact match, applies mechanical Wine-compatibility defaults (INI fields, minimal registry); reports all applied actions in initial message
3. `WindowMonitor` (new, `Core/WindowMonitor.swift`) — CoreGraphics wrapper, called every 2s inside `WineProcess.run()` polling loop; returns `WindowSnapshot` (owner name, bounds, layer, optional title); requires Screen Recording permission only for window title
4. `AgentLoop.run()` modifications — adds `consecutiveMaxTokens` counter, `lastToolCall` dedup tracking (inject reminder after 2 identical tool+arg calls), budget warning at `remainingIterations <= 3`, and correct mid-tool-use truncation retry
5. `AgentTools.fetchPage()` modification — adds `ExtractedFix` SwiftSoup post-processing alongside existing `text_content`; extraction may be empty (always include raw text as fallback)

**Build order (dependency-driven):**
- Level 1 (no dependencies): `GameEngineDetector`, `WindowMonitor`
- Level 2: `WineProcess` + `WineResult` field additions, `inspectGame` embedding of `GameEngineDetector`, `ProactiveConfigurator`
- Level 3: `AIService` pre-config phase, `AgentLoop` resilience changes, `fetch_page` SwiftSoup extraction
- Level 4: System prompt search strategy refinements

### Critical Pitfalls

1. **CGWindowListCopyWindowInfo silently omits window titles without Screen Recording permission** — `kCGWindowName` key is absent (not nil) without permission; code treating nil title as "no window found" will always report no dialog. Mitigation: check permission before using title; fall back to bounds+layer heuristics (no permission required) and trace:msgbox as the primary signal.

2. **Wine windows are owned by `wine64`/`wine-preloader`, not by the game process name or root PID** — filtering by the root Wine PID passed to `WineProcess.run()` will miss windows owned by Wine child processes. Mitigation: filter by owner name (`wine64`, `wine-preloader`, `wine`); use bounds heuristic (game windows ≥640×480, dialog windows ≤600×300) as the primary classifier.

3. **Wine trace:msgbox output format varies between Gcenx CrossOver builds and upstream Wine** — strict prefix matching on `trace:msgbox:MessageBoxW` will silently miss dialogs on different Wine sub-versions. Mitigation: write a permissive regex; log raw lines that look like msgbox entries but don't parse; test against actual Gcenx `wine-crossover` binary output before shipping.

4. **Proactive INI writes break games that generate their INI on first run** — pre-writing a full INI skips the setup wizard but may embed wrong resolution or audio values for the user's system. Mitigation: write only Wine-compatibility-required fields (e.g., `renderer=opengl` in `ddraw.ini`); check if INI exists before writing; patch specific keys rather than replacing the file.

5. **max_tokens truncation mid-tool-use block corrupts agent loop state** — the current code attempts to continue with truncated tool_use JSON, which either fails to decode or produces inconsistent loop state. Mitigation: detect `stop_reason == "max_tokens"` with last block type `toolUse`, retry with doubled `max_tokens` (capped at 32768), do NOT append the truncated response to message history.

---

## Implications for Roadmap

Based on the dependency graph in FEATURES.md and the build order in ARCHITECTURE.md, the natural phase structure for v1.1 is:

### Phase 1: Agent Loop Resilience
**Rationale:** All v1.1 features are fragile if the loop can abort on max_tokens mid-tool-use truncation or silent HTTP errors. The max_tokens + tool_use truncation issue is a correctness defect — it must be fixed before any new feature is tested against it. Budget tracking and loop deduplication are changes to the same `AgentLoop.run()` state machine and belong together.
**Delivers:** A correct, resilient agent loop with session cost visibility. No feature additions, just correctness and observability.
**Addresses:** Agent loop resilience (max_tokens retry, HTTP retry), budget tracking + ceiling, stuck-loop detection (all P1)
**Avoids:** Pitfall 7 (max_tokens truncation corrupts state), Pitfall 6 (loop repetition without progress)
**Research flag:** Standard patterns — Anthropic docs are authoritative and specific. No additional research needed.

### Phase 2: Game Engine Detection
**Rationale:** Engine detection is the prerequisite for proactive pre-configuration (Phase 3) and smarter search queries (Phase 5). It is a self-contained pure-Swift module with no UI or agent changes. Adding it to `inspect_game` output gives immediate agent benefit (richer LLM context for the Research phase) even before Phase 3 ships.
**Delivers:** `GameEngineDetector` struct; `inspect_game` tool result gains `engine` field with confidence score, detected signals, and known-config hint.
**Uses:** `objdump -p` (existing), Foundation file system APIs, PE import DLL name patterns from research
**Avoids:** Pitfall 4 (engine detection false positives) — output must be confidence-scored hypotheses (`"likely DirectDraw"`) not assertions (`"DirectDraw"`)
**Research flag:** Standard patterns — file signatures and PE import patterns are a published standard. No additional research needed.

### Phase 3: Proactive Pre-configuration
**Rationale:** With engine detection available, proactive pre-configuration is deterministic logic calling existing subsystems. This is the highest-leverage feature in v1.1 — for known-working games, it eliminates the entire Research-Diagnose-Adapt cycle and replaces it with a sub-second mechanical config application, directly unblocking the v1.1 UAT milestone (American Conquest as the target game).
**Delivers:** `ProactiveConfigurator` struct; pre-config phase inserted into `AIService.runAgentLoop()` before the first API call; fast path for exact success DB matches; initial message injection reporting all applied actions.
**Implements:** Pre-Launch Phase Runner pattern; SuccessDatabase exact-match fast path
**Avoids:** Pitfall 5 (INI pre-write breaks games), Pitfall 10 (proactive registry edits breaking bottle)
**Research flag:** Implementation risk in INI partial-write behavior (existing-file patch vs full replace). Validate this specifically during implementation.

### Phase 4: Dialog Detection (trace:msgbox primary, window monitor optional)
**Rationale:** Dialog detection is the diagnostic complement to proactive pre-configuration — when pre-config doesn't fully work, the agent needs to detect dialog stuck-state from a `launch_game` result. Wine trace:msgbox is the primary signal (no permissions, faster, tolerant of format variation when written defensively). `CGWindowListCopyWindowInfo` is an optional complementary signal added only after trace-based detection is validated.
**Delivers:** `+msgbox` added to WINEDEBUG in `trace_launch`; structured `dialog_detected`, `dialog_title`, `dialog_message` fields in `launch_game` tool result; `WindowMonitor` struct (optional, graceful degradation without Screen Recording permission); `WineResult` gains `dialogsDetected` and `gameWindowDetected` fields.
**Uses:** CoreGraphics `CGWindowListCopyWindowInfo`, Wine debug channels (`+msgbox`, `+dialog`)
**Avoids:** Pitfall 1 (Screen Recording permission silent failure), Pitfall 2 (Wine window owner PID filtering), Pitfall 3 (trace format variation)
**Research flag:** NEEDS VALIDATION — must test against actual Gcenx `wine-crossover` build trace output before shipping the parser. Screen Recording permission behavior on macOS 15 Sequoia for CLI tools should be verified on target hardware.

### Phase 5: Smarter Research Tools
**Rationale:** With the loop corrected, engine detection feeding richer context to the agent, and dialog detection providing structured failure signals, the research phase becomes significantly more precise. Actionable fix extraction (SwiftSoup post-processing in `fetch_page`) and engine-aware search query construction are lower-risk changes that make the LLM's research output more token-efficient. Success DB similarity match tightening belongs here as well.
**Delivers:** SwiftSoup 2.8.7 added as SPM dependency; `fetch_page` returns `extracted_fixes` (structured env vars, winetricks verbs, registry keys) alongside `text_content`; system prompt gains explicit search strategy section with engine-name and symptom query construction; success DB similarity match relevance threshold raised from 0.3 to 0.6.
**Uses:** SwiftSoup 2.8.7, DuckDuckGo HTML scrape (existing), system prompt engineering
**Avoids:** Pitfall 8 (DuckDuckGo rate limiting — cache-first behavior, 403 graceful fallback), Pitfall 9 (success DB wrong match applied directly)
**Research flag:** SwiftSoup integration is standard. DuckDuckGo rate limiting is a known limitation — document it explicitly, implement cache-first behavior, and add User-Agent header + 403 graceful fallback before shipping.

### Phase 6: Integration and End-to-End Validation
**Rationale:** With all five capability layers in place, end-to-end testing verifies the combined system: engine detection feeds proactive config, pre-config summary is reported in the initial message, and the agent builds on it using trace:msgbox dialog detection and smarter search queries when needed. Target UAT scenario (American Conquest launch to gameplay) exercises the full v1.1 system.
**Delivers:** All v1.1 features working cohesively; v1.1 UAT passing; milestone complete.
**Research flag:** Standard integration testing. No new research needed.

### Phase Ordering Rationale

- Loop resilience must come first because all other phases add test surface area — testing them on a loop with a latent correctness bug produces misleading failures.
- Engine detection must precede pre-configuration because `ProactiveConfigurator` directly calls `GameEngineDetector`; there is a code dependency.
- Pre-configuration before dialog detection because pre-configuration is the proactive path that makes dialog detection less frequently exercised; validating pre-config establishes what dialog detection needs to handle as its fallback scope.
- Research tools last because they require SwiftSoup (a new SPM dependency) and involve system prompt changes that are best tuned after the structural features are stable and validated.

### Research Flags

Phases needing deeper research or real-device validation before shipping:
- **Phase 4 (Dialog Detection):** Must capture and examine actual Gcenx `wine-crossover` stderr trace output from a Wine program that produces a MessageBox. Do not ship the parser based on Wine source code or documentation alone. Screen Recording permission degradation on macOS 15 Sequoia for a CLI binary launched from Terminal.app requires device verification.
- **Phase 5 (Research Tools):** DuckDuckGo anti-bot behavior under multiple-queries-per-session needs validation in the actual usage environment before assuming the 1-second inter-query delay is sufficient.

Phases with well-documented, low-risk patterns (no additional research needed):
- **Phase 1 (Loop Resilience):** Anthropic stop_reason docs are authoritative and specific. Pattern is unambiguous.
- **Phase 2 (Engine Detection):** PE format is a published Microsoft standard. File signature patterns are from established community tools.
- **Phase 3 (Proactive Config):** Pure Swift calling existing subsystems (`GameEngineDetector`, `SuccessDatabase`, `write_game_file` logic). Implementation risk is limited to INI partial-write behavior.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | One new dependency (SwiftSoup); all others are built-in Apple frameworks or existing toolchain. SwiftSoup verified against GitHub source and package metadata. max_tokens recovery pattern verified against official Anthropic stop_reason docs. |
| Features | HIGH | Based on direct codebase inspection plus Anthropic API docs. Feature dependency graph is well-established from code analysis. Anti-feature list is grounded in concrete macOS Wine behavior (virtual desktop broken on winemac.drv is empirically confirmed in prior phases). |
| Architecture | HIGH | Based on direct source code inspection of `AgentLoop.swift`, `AgentTools.swift`, `AIService.swift`, `WineProcess.swift`. Integration points are concrete, not speculative. Build order derived from actual code dependencies, not estimated. |
| Pitfalls | HIGH (most) / MEDIUM (Wine trace format) | Critical pitfalls verified against Apple developer docs (Screen Recording permission gating), Anthropic official docs (max_tokens truncation), and Wine source code (debug channel declarations). Wine trace:msgbox format variation is MEDIUM confidence because the exact CrossOver build output format was not verified against a running Gcenx Wine instance. |

**Overall confidence:** HIGH

### Gaps to Address

- **Wine trace format on actual Gcenx build:** The `trace:msgbox:MessageBoxW` format described in STACK.md comes from Wine source code and community documentation, not from a live Gcenx `wine-crossover` trace capture. Before shipping the dialog parser, run a minimal Wine program that triggers a MessageBox and capture raw stderr from the Gcenx build. Write the parser against that actual output.
- **Screen Recording permission on macOS 15 Sequoia for CLI tools:** Documented behavior is that the permission is granted to the terminal application (Terminal.app, iTerm2), not the CLI binary. This is MEDIUM confidence — verify on target hardware that `cellar` launched from Terminal.app can read `kCGWindowName` when Terminal.app holds Screen Recording permission, and confirm behavior from iTerm2 as well.
- **DuckDuckGo anti-bot behavior at scale:** One search per launch works; multiple searches within a single session may trigger rate limiting. Validate that the 1-second inter-query delay plus realistic User-Agent header is sufficient before shipping Phase 5.

---

## Sources

### Primary (HIGH confidence)
- [Anthropic: Handling Stop Reasons (official)](https://platform.claude.com/docs/en/build-with-claude/handling-stop-reasons) — max_tokens + tool_use truncation behavior, correct retry pattern
- [Anthropic: Tool Use with Claude (official)](https://platform.claude.com/docs/en/build-with-claude/tool-use) — tool_use block structure, incomplete JSON on truncation
- [Apple Developer Docs: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) — kCGWindowName requires Screen Recording permission; key is absent, not nil
- [Apple Developer Forums: window name not available in macOS 10.15](https://developer.apple.com/forums/thread/126860) — Screen Recording permission requirement confirmed officially
- [Wine source: dlls/user32/msgbox.c](https://github.com/wine-mirror/wine/blob/master/dlls/user32/msgbox.c) — confirmed WINEDEBUG=+msgbox channel and MessageBoxW trace output
- [Microsoft PE Format spec](https://learn.microsoft.com/en-us/windows/win32/debug/pe-format) — PE header structure, import table offsets
- [SwiftSoup GitHub](https://github.com/scinfu/SwiftSoup) — version 2.8.7, March 2025, Swift 6 compatible, macOS 14+
- Cellar codebase: `AgentLoop.swift`, `AgentTools.swift`, `AIService.swift`, `WineProcess.swift` — direct inspection 2026-03-28
- `.planning/agentic-architecture-v2.md` — v1.1 architecture design document with empirical Wine/macOS findings

### Secondary (MEDIUM confidence)
- [Nonstrict.eu: ScreenCaptureKit on macOS Sonoma](https://nonstrict.eu/blog/2023/a-look-at-screencapturekit-on-macos-sonoma/) — CGWindowListCopyWindowInfo not deprecated; CGWindowListCreateImage/CGDisplayStream are the migrating APIs
- [Wine Developer's Guide: Debug Channels](https://fossies.org/linux/misc/old/winedev-guide.html) — trace output format documentation (version-dated; exact CrossOver output may differ)
- [CodeWeavers: Working on Wine Part 4 - Debugging Wine](https://www.codeweavers.com/blog/aeikum/2019/1/15/working-on-wine-part-4-debugging-wine) — CrossOver Wine debug output perspective
- [game-engine-finder](https://github.com/vetleledaal/game-engine-finder), [enginedetect](https://github.com/YellowberryHN/enginedetect) — game engine file pattern references
- [SteamDatabase FileDetectionRuleSets](https://github.com/SteamDatabase/FileDetectionRuleSets) — engine detection patterns used by Steam
- [DuckDuckGo rate limiting (duckduckgo-search PyPI)](https://pypi.org/project/duckduckgo-search/) — RatelimitException behavior documented by scraping community

### Tertiary (LOW confidence)
- None identified — all findings have at least MEDIUM-confidence corroboration from multiple sources.

---
*Research completed: 2026-03-28*
*Ready for roadmap: yes*
