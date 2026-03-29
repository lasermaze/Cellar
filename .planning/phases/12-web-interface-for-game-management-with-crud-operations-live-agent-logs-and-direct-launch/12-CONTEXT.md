# Phase 12: Web Interface for Game Management - Context

**Gathered:** 2026-03-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Browser-based web UI to manage the Cellar game library. Users can add games, delete games, launch games (with or without AI agent), and view real-time agent logs during launch. Serves from localhost as a companion to the CLI.

</domain>

<decisions>
## Implementation Decisions

### Tech Stack
- Backend: Vapor (Swift web framework) — adds WebSocket/SSE support, routing, middleware
- Frontend: HTMX + server-side Leaf templates — minimal JS, server renders HTML, HTMX handles dynamic updates
- Architecture: New `cellar serve` subcommand in existing binary — shares all models and business logic
- Access: localhost:8080, no authentication (personal tool)

### Live Agent Logs
- Server-Sent Events (SSE) to stream agent loop iterations to browser in real-time
- AgentLoop needs a streaming callback injected (currently uses print() statements)
- Show: iteration count, tool calls, agent reasoning text, cost/token tracking
- WineProcess readabilityHandler already streams — wire to SSE endpoint

### Game Management UX
- Card-based game library — each card shows game name, status, last played date
- Add game: upload/select installer path, triggers existing AddCommand workflow
- Delete game: remove from games.json, option to clean up bottle
- Launch button per game card

### Direct Launch Mode
- Games with a saved recipe/success record get a "Launch" button that skips the agent entirely
- Uses existing recipeFallbackLaunch path — apply recipe, run Wine, done
- Games without a working config show "Launch with AI" which starts the agent loop
- Both modes stream output to the browser via SSE

### Claude's Discretion
- Visual styling and CSS framework choice
- Card layout details (grid columns, responsive breakpoints)
- Log formatting and color coding in browser
- Error state presentation
- Loading indicators during launch

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- CellarStore: full CRUD for games.json (loadGames, addGame, updateGame, findGame)
- All models Codable: GameEntry, LaunchResult, Recipe, CellarConfig — ready as JSON API responses
- DependencyChecker: system status checks (Homebrew, Wine, winetricks)
- WineProcess.readabilityHandler: already streams stderr/stdout in real-time
- RecipeEngine: findBundledRecipe, saveUserRecipe, apply recipe
- CellarPaths: all file path resolution (~/.cellar/logs, bottles, recipes, etc.)

### Established Patterns
- JSON encoder: .prettyPrinted + .iso8601 date strategy (CellarStore)
- Synchronous API calls via DispatchSemaphore (AgentLoop) — needs async adaptation for Vapor
- CLI commands as ParsableCommand structs — extract business logic into shared services

### Integration Points
- LaunchCommand.run() contains the full launch workflow — extract into a LaunchService
- AIService.runAgentLoop() is the agent entry point — needs streaming callback parameter
- AgentLoop.run() uses print() for output — inject callback for SSE streaming
- WineProcess.run() uses readabilityHandler — wire to SSE instead of terminal

</code_context>

<specifics>
## Specific Ideas

- Agent log stream should feel live — show each tool call as it happens, not batch at the end
- Direct launch for working games should be instant — no AI overhead, just apply recipe and go

</specifics>

<deferred>
## Deferred Ideas

- Game cover art / thumbnails — nice to have, not in scope
- Multi-user support / remote access — personal tool for now
- TUI mode (REQUIREMENTS.md TUI-01) — separate from web interface

</deferred>

---

*Phase: 12-web-interface-for-game-management-with-crud-operations-live-agent-logs-and-direct-launch*
*Context gathered: 2026-03-29*
