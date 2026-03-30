---
phase: 12-web-interface-for-game-management
verified: 2026-03-29T22:00:00Z
status: human_needed
score: 5/5 must-haves verified
must_haves:
  truths:
    - "`cellar serve` starts a Vapor HTTP server on localhost:8080"
    - "Users see a card-based game library showing game name, status, and last played date"
    - "Users can add games (by installer path) and delete games (with optional bottle cleanup) from the browser"
    - "Users can directly launch games with working recipes -- Wine output streams to browser via SSE"
    - "Users can launch games with AI agent -- iteration count, tool calls, reasoning, and cost stream in real-time via SSE"
  artifacts:
    - path: "Package.swift"
      status: verified
    - path: "Sources/cellar/Commands/ServeCommand.swift"
      status: verified
    - path: "Sources/cellar/Web/WebApp.swift"
      status: verified
    - path: "Sources/cellar/Web/Services/GameService.swift"
      status: verified
    - path: "Sources/cellar/Web/Services/LaunchService.swift"
      status: verified
    - path: "Sources/cellar/Web/Controllers/GameController.swift"
      status: verified
    - path: "Sources/cellar/Web/Controllers/LaunchController.swift"
      status: verified
    - path: "Sources/cellar/Resources/Views/base.leaf"
      status: verified
    - path: "Sources/cellar/Resources/Views/index.leaf"
      status: verified
    - path: "Sources/cellar/Resources/Views/game-card.leaf"
      status: verified
    - path: "Sources/cellar/Resources/Views/add-game.leaf"
      status: verified
    - path: "Sources/cellar/Resources/Views/launch-log.leaf"
      status: verified
    - path: "Sources/cellar/Resources/Views/game-list.leaf"
      status: verified
    - path: "Sources/cellar/Core/AgentLoop.swift"
      status: verified
  key_links:
    - from: "Cellar.swift"
      to: "ServeCommand"
      status: verified
    - from: "ServeCommand"
      to: "WebApp.configure"
      status: verified
    - from: "WebApp"
      to: "GameController.register"
      status: verified
    - from: "WebApp"
      to: "LaunchController.register"
      status: verified
    - from: "GameController"
      to: "GameService.shared"
      status: verified
    - from: "LaunchController"
      to: "AgentLoop.onOutput"
      status: verified
    - from: "LaunchController"
      to: "LaunchService.canDirectLaunch"
      status: verified
    - from: "launch-log.leaf"
      to: "SSE stream"
      status: verified
    - from: "AIService.runAgentLoop"
      to: "AgentLoop onOutput"
      status: verified
human_verification:
  - test: "Start server and verify game library page renders"
    expected: "Dark-themed card grid at http://127.0.0.1:8080 with Pico CSS styling"
    why_human: "Visual rendering and CSS layout cannot be verified programmatically"
  - test: "Add a game via the web form and verify it appears"
    expected: "Game card appears in grid after form submission"
    why_human: "HTMX redirect behavior and template rendering need browser"
  - test: "Delete a game and verify in-place removal"
    expected: "Card removed without page reload via HTMX swap"
    why_human: "HTMX partial swap behavior needs browser"
  - test: "Launch a game and verify SSE streaming"
    expected: "Live log output streams to browser in real-time"
    why_human: "SSE connection and real-time streaming need browser + Wine installed"
---

# Phase 12: Web Interface for Game Management Verification Report

**Phase Goal:** Users can manage their game library, add/delete games, launch games (directly or with AI agent), and watch real-time agent logs -- all from a browser-based web UI served on localhost:8080 via Vapor + HTMX
**Verified:** 2026-03-29T22:00:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `cellar serve` starts a Vapor HTTP server on localhost:8080 | VERIFIED | ServeCommand.swift creates Vapor Application on port 8080 via WebApp.configure(); registered in Cellar.swift subcommands array |
| 2 | Users see a card-based game library showing game name, status, and last played date | VERIFIED | index.leaf renders game-grid with game-card.leaf partials showing `#(game.name)`, `#(game.status)`, `#(game.lastPlayed)`; GameController loads data via GameService |
| 3 | Users can add games (by installer path) and delete games (with optional bottle cleanup) from the browser | VERIFIED | POST /games decodes AddGameInput, creates GameEntry, calls GameService.shared.addGame(); DELETE /games/:gameId calls deleteGame(cleanBottle:); add-game.leaf has hx-post form, game-card.leaf has hx-delete button |
| 4 | Users can directly launch games with working recipes -- Wine output streams to browser via SSE | VERIFIED | LaunchController.runDirectLaunch() applies bundled/user recipes via RecipeEngine, runs WineProcess on DispatchQueue.global, streams result via sendSSE; response has Content-Type: text/event-stream |
| 5 | Users can launch games with AI agent -- iteration count, tool calls, reasoning, and cost stream in real-time via SSE | VERIFIED | LaunchController.runAgentLaunch() calls AIService.runAgentLoop with onOutput callback; callback maps AgentEvent cases to SSE events (iteration, tool, log, cost, status, error); launch-log.leaf has sse-swap targets for each event type |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `Package.swift` | Vapor + Leaf SPM deps | VERIFIED | vapor 4.115+, leaf 4.4+ in dependencies and target |
| `Sources/cellar/Commands/ServeCommand.swift` | cellar serve subcommand | VERIFIED | 60 lines, ParsableCommand with --port option, async Vapor bootstrap via thread+semaphore bridge |
| `Sources/cellar/Web/WebApp.swift` | Vapor config with Leaf, routes, middleware | VERIFIED | 43 lines, configures Leaf views, FileMiddleware, registers GameController + LaunchController + SettingsController |
| `Sources/cellar/Web/Services/GameService.swift` | Thread-safe game store access | VERIFIED | 34 lines, actor with loadGames, findGame, addGame, deleteGame, updateGame wrapping CellarStore |
| `Sources/cellar/Web/Services/LaunchService.swift` | Launch detection for web context | VERIFIED | 26 lines, canDirectLaunch checks user recipe, bundled recipe, success DB; resolveWine via DependencyChecker |
| `Sources/cellar/Web/Controllers/GameController.swift` | CRUD routes for game library | VERIFIED | 109 lines, GET /, GET /games, GET /games/add, POST /games, DELETE /games/:gameId with view models |
| `Sources/cellar/Web/Controllers/LaunchController.swift` | Launch routes with SSE streaming | VERIFIED | 313 lines, SSE stream route, direct+agent launch, LaunchGuard actor, escapeHTML, sendSSE helper |
| `Sources/cellar/Resources/Views/base.leaf` | HTML layout with HTMX + Pico CSS | VERIFIED | 67 lines, dark theme, HTMX 2.0.8, htmx-ext-sse 2.2.4, Pico CSS 2, nav with Games + Settings |
| `Sources/cellar/Resources/Views/index.leaf` | Game library page with card grid | VERIFIED | 24 lines, extends base, game-grid with game-card partials, empty state message |
| `Sources/cellar/Resources/Views/game-card.leaf` | Individual game card | VERIFIED | 20 lines, name/status/lastPlayed, conditional Launch/Launch with AI buttons, hx-delete with confirm |
| `Sources/cellar/Resources/Views/add-game.leaf` | Add game form | VERIFIED | 19 lines, hx-post to /games, installPath input, cancel link |
| `Sources/cellar/Resources/Views/launch-log.leaf` | Live log viewer with SSE consumer | VERIFIED | 70 lines, sse-connect to streamURL, sse-swap targets for status/iteration/cost/tool/log/error/complete |
| `Sources/cellar/Resources/Views/game-list.leaf` | HTMX partial for delete swap | VERIFIED | 11 lines, game-grid or empty state |
| `Sources/cellar/Core/AgentLoop.swift` | AgentEvent enum + onOutput callback | VERIFIED | AgentEvent with 9 cases (iteration, text, toolCall, toolResult, cost, budgetWarning, status, error, completed); onOutput property with nil default; emit() calls both print and callback; 21 emit() calls, 0 raw print() calls |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Cellar.swift | ServeCommand | subcommands array | VERIFIED | `ServeCommand.self` in subcommands list |
| ServeCommand | WebApp | WebApp.configure(app, port:) | VERIFIED | Line 24: `try WebApp.configure(app, port: portValue)` |
| WebApp | GameController | register(app) | VERIFIED | Line 35: `try GameController.register(app)` |
| WebApp | LaunchController | register(app) | VERIFIED | Line 38: `try LaunchController.register(app)` |
| GameController | GameService | actor method calls | VERIFIED | `GameService.shared.loadGames()`, `.findGame()`, `.addGame()`, `.deleteGame()` throughout |
| LaunchController | AgentLoop onOutput | callback writing SSE events | VERIFIED | onOutput closure in runAgentLaunch maps all AgentEvent cases to sendSSE calls |
| LaunchController | LaunchService | canDirectLaunch check | VERIFIED | Used indirectly via GameController.loadGameViewData() for card button state |
| LaunchController | AIService | runAgentLoop with onOutput | VERIFIED | Line 258: `AIService.runAgentLoop(..., onOutput: onOutput)` |
| AIService | AgentLoop | onOutput parameter | VERIFIED | AIService.runAgentLoop accepts onOutput, passes to AgentLoop constructor |
| launch-log.leaf | SSE stream | sse-connect attribute | VERIFIED | `sse-connect="#(streamURL)"` with swap targets for all event types |
| index.leaf | base.leaf | Leaf template extension | VERIFIED | `#extend("base"):` / `#export("content"):` pattern |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| WEB-01 | 12-03 | User can view game library as card grid showing name, status, last played | SATISFIED | GameController GET / renders index.leaf with game-card.leaf partials; GameViewData has id, name, status, lastPlayed, canDirectLaunch |
| WEB-02 | 12-03 | User can add/delete games through web interface | SATISFIED | POST /games adds via GameService; DELETE /games/:gameId removes with optional cleanBottle; hx-post and hx-delete in templates |
| WEB-03 | 12-04 | User can directly launch with Wine output streamed via SSE | SATISFIED | LaunchController.runDirectLaunch applies recipes, runs WineProcess, streams exit status and stderr via SSE |
| WEB-04 | 12-02, 12-04 | User can launch with AI agent, real-time SSE streaming of iterations/tools/reasoning/cost | SATISFIED | AgentEvent enum, onOutput callback, LaunchController.runAgentLaunch maps all events to SSE; launch-log.leaf has sse-swap targets |
| WEB-05 | 12-01 | `cellar serve` starts Vapor on localhost:8080, sharing business logic | SATISFIED | ServeCommand registered, WebApp configures Vapor, services wrap existing CellarStore/RecipeEngine/AIService |

No orphaned requirements found. REQUIREMENTS.md maps WEB-01 through WEB-05 to Phase 12, and all five are claimed by plans 12-01 through 12-04.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (none found) | - | - | - | - |

No TODO/FIXME/placeholder comments in web source files. No empty implementations. No stub returns. All print() calls in AgentLoop replaced with emit().

### Human Verification Required

### 1. Game Library Page Rendering

**Test:** Run `swift run cellar serve` and open http://127.0.0.1:8080/ in a browser
**Expected:** Dark-themed page with "Cellar" nav, "Game Library" heading, card grid (or empty state message), "Add Game" button
**Why human:** Visual layout, CSS styling, and dark theme rendering need visual inspection

### 2. Add Game Flow

**Test:** Click "Add Game", enter an installer path (e.g., `/path/to/setup.exe`), submit
**Expected:** Redirects to library, new game card appears with derived name and "Ready" status
**Why human:** HTMX form submission, redirect behavior, and game ID derivation need browser

### 3. Delete Game Flow

**Test:** Click "Delete" on a game card, confirm the dialog
**Expected:** Card removed from grid without full page reload (HTMX partial swap)
**Why human:** HTMX hx-delete with hx-target swap needs browser to verify no-reload behavior

### 4. Direct Launch SSE Streaming

**Test:** Click "Launch" on a game with a working recipe (requires Wine installed + game configured)
**Expected:** Launch log page opens, SSE connection established, recipe application logged, Wine output streams line-by-line
**Why human:** Requires Wine installation, actual game files, and real-time SSE observation

### 5. Agent Launch SSE Streaming

**Test:** Click "Launch with AI" on a game (requires ANTHROPIC_API_KEY set)
**Expected:** Iteration count, tool calls, reasoning text, and cost update in real-time via SSE; agent-mode sections (tools, iteration, cost) visible
**Why human:** Requires API key, real agent execution, and real-time SSE observation

### Gaps Summary

No automated gaps found. All 5 success criteria truths verified through code inspection:

1. **Infrastructure:** Vapor + Leaf configured, ServeCommand wired, views directory resolved, all controllers registered.
2. **Data layer:** GameService actor provides thread-safe CRUD, LaunchService detects direct-launch eligibility.
3. **Agent streaming:** AgentEvent enum with 9 cases, onOutput callback on AgentLoop, emit() replaces all print() calls, AIService overload passes callback through.
4. **Web CRUD:** GameController handles full lifecycle (list, add, delete) with HTMX partial swaps.
5. **Launch SSE:** LaunchController streams both direct launch (recipe + Wine output) and agent launch (all AgentEvent types) via SSE with proper Content-Type headers.
6. **Templates:** All 7 Leaf templates exist, extend base.leaf correctly, use HTMX SSE attributes for real-time updates.
7. **Build:** Project compiles cleanly under Swift 6 strict concurrency.

The only remaining verification is human testing of visual rendering, HTMX interactions, and real-time SSE streaming in a browser with actual Wine/AI dependencies available.

---

_Verified: 2026-03-29T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
