# Cellar

## What This Is

An open-source macOS CLI+TUI tool that turns old Windows game files into working, repeatable launchers. Cellar sits above Wine as a recipe and repair layer — it manages per-game Wine bottles, applies known or AI-generated configuration recipes, and helps users get old PC games running on Apple silicon Macs without needing to understand Wine internals.

## Core Value

Any user can go from "I have these old game files" to "the game launches and works" without manually configuring Wine.

## Requirements

### Validated

<!-- Shipped in v1.0 — 7 phases, 22 plans -->

- ✓ Import game files and identify the game — v1.0
- ✓ Create isolated per-game Wine bottles — v1.0
- ✓ Apply configuration recipes (known or AI-generated) — v1.0
- ✓ Launch games from terminal (`cellar launch <game>`) — v1.0
- ✓ Detect and guide installation of dependencies (Homebrew, Wine via Gcenx tap) — v1.0
- ✓ AI-powered log interpretation and recipe generation (API-first) — v1.0
- ✓ User-confirmed launch validation ("Did the game reach the menu?") — v1.0
- ✓ Save working recipes for reuse and community sharing — v1.0
- ✓ Agentic launch with 18-tool Research-Diagnose-Adapt loop — v1.0
- ✓ Web search and page fetching for compatibility research — v1.0
- ✓ Diagnostic traces, DLL verification, success database — v1.0

<!-- Shipped in v1.1 — 5 phases, 14 plans -->

- ✓ Agent persists through failures, handles max_tokens, budget-aware escalation — v1.1
- ✓ Dialog detection via Wine trace parsing + macOS window list — v1.1
- ✓ Game engine detection and pre-configuration — v1.1
- ✓ Smart web research with actionable fix extraction — v1.1
- ✓ Web interface for game management with CRUD and live agent logs — v1.1

<!-- Shipped in v1.2 — 17 phases, ~35 plans -->

- ✓ Agent queries collective memory (Git-backed) before starting diagnosis — v1.2
- ✓ Agent reasons about environment fit before applying stored configs — v1.2
- ✓ Agent pushes successful configs to collective memory via Cloudflare Worker proxy — v1.2
- ✓ Collective memory with rich entries: working config, environment context, confidence — v1.2
- ✓ Web interface shows collective memory state — v1.2
- ✓ Community ready: public repo, anonymous reads, validated writes — v1.2
- ✓ Kimi (Moonshot AI) provider support — v1.2
- ✓ ISO/BIN/CUE disc image support in cellar add — v1.2
- ✓ Single-command install via curl|bash — v1.2
- ✓ Prompt injection hardening: sanitizeEntry, CSRF, .env permissions — v1.2
- ✓ Async/await migration, AgentTools decomposition — v1.2
- ✓ Secure collective memory: Cloudflare Worker proxy, private key removed from binary — v1.2

### Active

<!-- v1.3: Agent Loop Rewrite -->

- [ ] Fix memory not saving on web UI confirm (race condition in fire-and-forget save)
- [ ] Fix stop button unresponsive during API calls (no cancellation)
- [ ] Fix agent exiting without saving (endTurn tug-of-war)
- [ ] Fix data races on AgentTools shared state (bare vars, no synchronization)
- [ ] Typed ToolResult enum replacing string matching for control flow
- [ ] Thread-safe AgentControl channel between web routes and agent loop
- [ ] Middleware system: BudgetTracker, SpinDetector, EventLogger extracted from loop body
- [ ] JSONL event log for debugging and richer session resume
- [ ] Post-loop save (one save path with await, no fire-and-forget)
- [ ] Clean endTurn handling (stop means stop, no tug-of-war)

### Out of Scope

- Storefront or game purchasing — Cellar launches games you already own
- Cloud streaming — everything runs locally
- Large compatibility database on day one — start with one game family
- Custom graphics translation layer — rely on Wine and existing translation
- Wine fork — use upstream Wine via Homebrew
- Steam/Epic integration — not a store launcher
- Mobile or non-Mac platforms — macOS only

## Context

**The problem:** Old Windows games on Mac fail not because the EXE can't run, but because every game needs a slightly different combination of bottle settings, graphics behavior, installer handling, config edits, and launch quirks. The setup work is repetitive, manual, and frustrating.

**The landscape:**
- Wine is active and releasing current builds in 2026 (LGPL v2.1)
- Whisky demonstrated demand for a clean macOS Wine wrapper but is no longer actively maintained
- Heroic is a broader launcher but its macOS path leans on CrossOver, not open Wine
- Apple's GPTK is positioned as evaluation/porting toolkit, not a consumer launcher

**The wedge:** Old strategy / management / turn-based PC games on Apple silicon Macs. Starting with Cossacks: European Wars as the flagship test case. These games matter to a dedicated audience, are less demanding than modern AAA titles, and typically fail for configuration reasons rather than anti-cheat or cutting-edge graphics.

**AI role:** AI is a compatibility operator, not marketing. Useful AI jobs: game identification (EXE metadata, hashes, directory structure), recipe generation (Wine build + bottle template + config flags), log interpretation (translate runtime errors into likely causes), and recipe refinement (save what works with confidence scores).

**Target user:** Wine-naive — people who just want to play an old game and don't know what Wine is. Cellar should guide them through the entire process including dependency installation.

## Constraints

- **Tech stack**: Swift 6 CLI+TUI — no GUI, terminal-based interface
- **Wine distribution**: Gcenx Homebrew tap (`gcenx/wine`) — official Homebrew wine-stable is deprecated
- **Wine engine**: wined3d → OpenGL for DX8/DX9 games. GPTK/D3DMetal optional for DX11+ (detect if installed, cannot redistribute)
- **AI inference**: API-first (Claude/OpenAI) — simpler to build, requires internet for AI features
- **Launch validation**: User-confirmed — ask the user if the game reached the menu, no automated screenshot analysis in v1
- **Recipe storage**: Local + Git repo — bundled recipes, community contributes via PRs
- **License**: Open source (GPL-3.0 aligns with Whisky/Heroic ecosystem)
- **Scope**: One game family first (old strategy games), expand from there

## Current Milestone: v1.3 Agent Loop Rewrite

**Goal:** Fix critical bugs in the agent loop (race conditions, unresponsive stop, lost saves) and modernize the architecture with typed results, thread-safe control, middleware system, and structured event logging.

**Target features:**
- Fix 4 critical bugs: memory not saving on confirm, stop button unresponsive, agent exits without saving, data races
- Typed ToolResult enum replacing fragile string matching
- Thread-safe AgentControl channel for web UI ↔ agent communication
- Middleware system extracting budget tracking, spin detection, event logging from the loop body
- JSONL event log for debugging and richer session resume
- Post-loop save with await (one save path, no fire-and-forget)
- Clean endTurn semantics (no tug-of-war)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Name: Cellar | Fits Wine/bottle metaphor, memorable, available | — Pending |
| Homebrew for Wine | Avoids bundling complexity, leverages existing package management | — Pending |
| API-first AI | Simpler to build than local inference, good enough for MVP | — Pending |
| User-confirmed validation | Avoids vision model complexity in v1, honest about what we can detect | — Pending |
| Cossacks: European Wars as flagship | 2001 RTS, DirectDraw/DX8, dedicated audience | — Pending |
| Recipes in Git repo | Community PRs, version-controlled, works offline with bundled set | — Pending |
| GPL-3.0 license | Aligns with Whisky/Heroic ecosystem, encourages contribution | — Pending |
| CLI+TUI instead of SwiftUI | Dramatically simpler, faster to build, no Xcode project needed | — Pending |
| Wine via Gcenx tap (not bundled) | Official wine-stable deprecated. Gcenx is the WineHQ macOS maintainer | — Pending |
| wined3d/OpenGL for DX8/DX9 | D3DMetal doesn't cover old DirectX. Only viable path for target wedge | — Pending |
| GPTK detect-only (not bundled) | Apple EULA prohibits redistribution of D3DMetal. Detect if installed. | — Pending |

| Collective memory via Git repo | Agent-first, open-source friendly, no infrastructure dependency, version-controlled | — Pending |
| GitHub App for agent auth | Agents push without human approval, scoped access, no PAT management | — Pending |
| Agents always reason before applying | Compare environments + adapt configs, not blind application | — Pending |

---
*Last updated: 2026-04-03 after v1.3 milestone start*
