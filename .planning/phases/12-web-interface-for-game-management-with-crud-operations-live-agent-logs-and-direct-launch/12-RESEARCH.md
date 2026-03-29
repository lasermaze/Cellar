# Phase 12: Web Interface for Game Management - Research

**Researched:** 2026-03-29
**Domain:** Server-side Swift web UI (Vapor + Leaf + HTMX + SSE)
**Confidence:** MEDIUM

## Summary

This phase adds a `cellar serve` subcommand that starts a Vapor HTTP server on localhost:8080, serving a web UI for managing the game library. The UI uses server-rendered Leaf templates enhanced with HTMX for dynamic interactions and Server-Sent Events for live agent log streaming. All existing business logic (CellarStore, RecipeEngine, AIService, WineProcess) is reused directly -- the web layer is purely routing + presentation.

The main architectural challenge is integrating Vapor into the existing swift-argument-parser binary without conflicts. Vapor historically hijacks `CommandLine.arguments`, but this is solved by constructing `Environment(name:arguments:)` with a static array. The second challenge is adapting the synchronous, print()-based AgentLoop to stream events over SSE -- this requires injecting a callback closure into the agent loop that writes SSE events instead of printing to stdout.

**Primary recommendation:** Add Vapor + Leaf as SPM dependencies, create a `ServeCommand` ParsableCommand subcommand, extract launch/add workflows into service types, and wire SSE streaming through an injected callback on AgentLoop.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Backend: Vapor (Swift web framework) -- adds WebSocket/SSE support, routing, middleware
- Frontend: HTMX + server-side Leaf templates -- minimal JS, server renders HTML, HTMX handles dynamic updates
- Architecture: New `cellar serve` subcommand in existing binary -- shares all models and business logic
- Access: localhost:8080, no authentication (personal tool)
- Live agent logs via Server-Sent Events (SSE), not WebSockets
- AgentLoop needs streaming callback injected (currently uses print())
- Show: iteration count, tool calls, agent reasoning text, cost/token tracking
- WineProcess readabilityHandler already streams -- wire to SSE endpoint
- Card-based game library -- each card shows game name, status, last played date
- Add game: upload/select installer path, triggers existing AddCommand workflow
- Delete game: remove from games.json, option to clean up bottle
- Launch button per game card
- Games with saved recipe/success record get "Launch" button (skips agent)
- Games without working config show "Launch with AI" (starts agent loop)
- Both launch modes stream output to browser via SSE

### Claude's Discretion
- Visual styling and CSS framework choice
- Card layout details (grid columns, responsive breakpoints)
- Log formatting and color coding in browser
- Error state presentation
- Loading indicators during launch

### Deferred Ideas (OUT OF SCOPE)
- Game cover art / thumbnails
- Multi-user support / remote access
- TUI mode (REQUIREMENTS.md TUI-01) -- separate from web interface
</user_constraints>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Vapor | from: "4.115.0" | HTTP server, routing, middleware | Standard Swift server framework; latest stable 4.121.3 |
| Leaf | from: "4.4.0" | Server-side HTML templates | Official Vapor templating; .leaf files in Resources/Views |
| HTMX | 2.0.8 (CDN) | Dynamic HTML without JS framework | Locked decision; SSE extension built-in |
| htmx-ext-sse | 2.2.4 (CDN) | SSE event handling + DOM swapping | Official HTMX SSE extension |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Pico CSS | 2.x (CDN) | Classless CSS framework | Styling recommendation -- minimal markup, good defaults, responsive |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Pico CSS | Water.css, Tailwind | Pico has best card/grid support with zero class names; Tailwind is heavy for server-rendered |
| CDN for HTMX | Bundled JS | CDN simpler for localhost tool; no build step needed |

**Installation (Package.swift additions):**
```swift
.package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
.package(url: "https://github.com/vapor/leaf.git", from: "4.4.0"),
```

**Target dependency additions:**
```swift
.product(name: "Vapor", package: "vapor"),
.product(name: "Leaf", package: "leaf"),
```

**Frontend (no install -- CDN links in base template):**
```html
<script src="https://cdn.jsdelivr.net/npm/htmx.org@2.0.8/dist/htmx.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/htmx-ext-sse@2.2.4"></script>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@2/css/pico.min.css">
```

## Architecture Patterns

### Recommended Project Structure
```
Sources/cellar/
  Commands/
    ServeCommand.swift          # ParsableCommand that boots Vapor
  Web/
    WebApp.swift                # configure(app:) -- routes, middleware, Leaf
    Controllers/
      GameController.swift      # CRUD routes for games
      LaunchController.swift    # Launch + SSE streaming routes
    Services/
      LaunchService.swift       # Extracted from LaunchCommand -- reusable launch logic
      GameService.swift         # Wraps CellarStore with web-friendly API
  Resources/
    Views/
      base.leaf                 # HTML shell with HTMX + CSS CDN links
      index.leaf                # Game library card grid
      game-card.leaf            # Individual game card partial
      launch-log.leaf           # SSE log viewer page
      add-game.leaf             # Add game form
    Public/
      css/custom.css            # Minimal overrides if needed
```

### Pattern 1: Vapor Integration with swift-argument-parser
**What:** Boot Vapor from a ParsableCommand without argument parsing conflicts
**When to use:** The `cellar serve` subcommand
**Example:**
```swift
// Source: https://github.com/vapor/vapor/issues/2385
struct ServeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the web interface"
    )

    @Option(name: .long, help: "Port to listen on")
    var port: Int = 8080

    mutating func run() throws {
        // Prevent Vapor from hijacking CommandLine.arguments
        var env = Environment(name: "development", arguments: ["vapor"])
        let app = Application(env)
        defer { app.shutdown() }

        try WebApp.configure(app, port: port)
        try app.run()
    }
}
```

### Pattern 2: SSE Streaming from Vapor Routes
**What:** Long-lived HTTP response with text/event-stream content type
**When to use:** Agent log streaming, Wine process output streaming
**Example:**
```swift
// Source: https://aldo10012.medium.com/setting-up-server-sent-events-sse-in-vapor-a-practical-guide
app.get("games", ":gameId", "launch", "stream") { req async throws -> Response in
    guard let gameId = req.parameters.get("gameId") else {
        throw Abort(.badRequest)
    }

    let body = Response.Body(stream: { writer in
        Task {
            // SSE format: "event: <name>\ndata: <html>\n\n"
            func sendEvent(name: String, html: String) {
                let message = "event: \(name)\ndata: \(html)\n\n"
                let buffer = ByteBuffer(string: message)
                _ = try? await writer.write(.buffer(buffer)).get()
            }

            await sendEvent(name: "status", html: "<div>Starting launch...</div>")

            // Run agent with streaming callback...
            // On completion:
            _ = try? await writer.write(.end).get()
        }
    })

    let response = Response(status: .ok, body: body)
    response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
    response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
    response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
    return response
}
```

### Pattern 3: HTMX SSE Consumer
**What:** Browser-side SSE connection with automatic DOM swapping
**When to use:** Launch log viewer page
**Example:**
```html
<!-- Source: https://htmx.org/extensions/sse/ -->
<div hx-ext="sse" sse-connect="/games/cossacks/launch/stream">
    <div id="status" sse-swap="status"></div>
    <div id="log" sse-swap="log" hx-swap="beforeend"></div>
    <div id="iteration" sse-swap="iteration"></div>
    <div id="cost" sse-swap="cost"></div>
</div>
```

### Pattern 4: AgentLoop Streaming Callback
**What:** Inject an output callback into AgentLoop to replace print() statements
**When to use:** When running agent from web interface
**Example:**
```swift
// Add callback parameter to AgentLoop
struct AgentLoop {
    // ... existing properties ...
    let onOutput: ((AgentEvent) -> Void)?

    enum AgentEvent {
        case iteration(number: Int, total: Int)
        case text(String)
        case toolCall(name: String)
        case cost(inputTokens: Int, outputTokens: Int, usd: Double)
        case budgetWarning(percentage: Int)
        case completed(AgentLoopResult)
    }
}
```

### Pattern 5: HTMX Partial Responses for CRUD
**What:** Server returns HTML fragments, HTMX swaps them into the page
**When to use:** Add game, delete game, refresh game list
**Example:**
```swift
// Delete game -- returns updated game list partial
app.delete("games", ":gameId") { req -> View in
    guard let gameId = req.parameters.get("gameId") else {
        throw Abort(.badRequest)
    }
    var games = try CellarStore.loadGames()
    games.removeAll { $0.id == gameId }
    try CellarStore.saveGames(games)
    // Optionally clean up bottle...
    return try await req.view.render("game-list", ["games": games])
}
```

### Anti-Patterns to Avoid
- **Running Vapor on main thread with synchronous code:** Vapor is async (NIO event loop). The existing synchronous AgentLoop uses DispatchSemaphore which WILL deadlock on NIO threads. Must run agent loop on a separate dispatch queue, not on event loop threads.
- **Sharing mutable state without synchronization:** CellarStore is not thread-safe (reads/writes games.json). Web server handles concurrent requests. Wrap in actor or serial queue.
- **Rendering full pages for HTMX partials:** HTMX expects HTML fragments. Check for `HX-Request` header to decide full page vs. partial.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTML templating | String interpolation | Leaf templates | XSS prevention, partials, layouts |
| Real-time updates | Polling or WebSocket | SSE via Vapor stream + HTMX SSE extension | Simpler than WS; HTMX handles reconnection |
| CSS layout/styling | Custom CSS from scratch | Pico CSS classless framework | Responsive cards/grids with semantic HTML |
| HTTP routing | Manual URL parsing | Vapor's router | Type-safe parameters, middleware support |
| Static file serving | Manual file reading | Vapor FileMiddleware | Caching, MIME types, security |

**Key insight:** The entire web layer should be thin -- routing + templates + SSE plumbing. All business logic already exists in CellarStore, RecipeEngine, AIService, etc. The risk is over-engineering the web layer when the real work is just wiring existing code to HTTP endpoints.

## Common Pitfalls

### Pitfall 1: NIO Event Loop Deadlock
**What goes wrong:** AgentLoop uses DispatchSemaphore for synchronous HTTP calls. Calling this on a NIO event loop thread causes permanent deadlock.
**Why it happens:** Vapor routes run on NIO event loop threads. DispatchSemaphore blocks the thread, but NIO needs that thread to complete the URL session callback.
**How to avoid:** Run the entire agent loop on a dedicated DispatchQueue (not the NIO event loop). Use `Task.detached` or `DispatchQueue.global().async` to move off the event loop before invoking any synchronous code.
**Warning signs:** Server hangs on first agent API call, no response ever returned.

### Pitfall 2: Vapor Hijacking CommandLine Arguments
**What goes wrong:** `Application(Environment.development)` parses CommandLine.arguments, conflicting with swift-argument-parser.
**Why it happens:** Vapor's Environment init reads process arguments by default.
**How to avoid:** Use `Environment(name: "development", arguments: ["vapor"])` with a static array.
**Warning signs:** Unrecognized argument errors when running `cellar serve --port 8080`.

### Pitfall 3: SSE Connection Lifecycle
**What goes wrong:** SSE connections stay open after browser tab closes, leaking resources. Agent keeps running with no consumer.
**Why it happens:** Server doesn't detect client disconnect promptly.
**How to avoid:** Check for write errors in the SSE stream loop -- when writer.write fails, the client disconnected. Break the loop and clean up. Also set reasonable timeouts.
**Warning signs:** Memory growth over time, orphaned agent processes.

### Pitfall 4: Leaf Template Discovery
**What goes wrong:** Templates not found at runtime, 500 errors on every page.
**Why it happens:** Leaf expects templates in `./Resources/Views/` relative to the working directory. When running via `swift run`, CWD may not match the project root.
**How to avoid:** Set `app.directory.viewsDirectory` explicitly in configure(), or ensure the binary is run from the project root. Consider `app.leaf.configuration.rootDirectory` for custom paths.
**Warning signs:** "No template named 'index' found" errors.

### Pitfall 5: Swift 6 Sendable + Vapor
**What goes wrong:** Vapor's route closures must be Sendable. Capturing mutable state triggers compiler errors.
**Why it happens:** The project uses swift-tools-version: 6.0 with strict concurrency.
**How to avoid:** Use actors for shared mutable state. Pass immutable snapshots to closures. The existing `@unchecked Sendable` wrapper pattern (used in WineProcess) works for cases where manual synchronization is acceptable.
**Warning signs:** "Capture of mutable variable in a @Sendable closure" compiler errors.

### Pitfall 6: CellarStore Thread Safety
**What goes wrong:** Concurrent web requests read/write games.json simultaneously, causing data corruption or lost writes.
**Why it happens:** CellarStore uses static methods with no synchronization -- fine for CLI (single thread) but unsafe for a web server.
**How to avoid:** Wrap CellarStore access in a serial DispatchQueue or an actor. Alternatively, create a GameService actor that serializes all store operations.
**Warning signs:** Intermittent "file not found" or corrupted JSON errors under concurrent requests.

## Code Examples

### Configuring Vapor with Leaf and FileMiddleware
```swift
// Source: https://docs.vapor.codes/leaf/getting-started/
import Vapor
import Leaf

func configure(_ app: Application, port: Int) throws {
    // Template engine
    app.views.use(.leaf)

    // Static files from Public/
    app.middleware.use(
        FileMiddleware(publicDirectory: app.directory.publicDirectory)
    )

    // Port configuration
    app.http.server.configuration.port = port
    app.http.server.configuration.hostname = "127.0.0.1"

    // Register routes
    try routes(app)
}
```

### SSE Event Formatting Helper
```swift
// Source: SSE specification (https://html.spec.whatwg.org/multipage/server-sent-events.html)
struct SSEEvent {
    let event: String
    let data: String

    /// Format as SSE wire protocol. Data lines with newlines must be split.
    func formatted() -> String {
        let dataLines = data.components(separatedBy: "\n")
            .map { "data: \($0)" }
            .joined(separator: "\n")
        return "event: \(event)\n\(dataLines)\n\n"
    }

    var buffer: ByteBuffer {
        ByteBuffer(string: formatted())
    }
}
```

### Detecting HTMX Requests for Partial vs Full Page
```swift
// Source: https://htmx.org/docs/#request-headers
func isHTMXRequest(_ req: Request) -> Bool {
    req.headers.first(name: "HX-Request") == "true"
}

// In a route handler:
app.get("games") { req async throws -> Response in
    let games = try CellarStore.loadGames()
    let template = isHTMXRequest(req) ? "game-list" : "index"
    let view = try await req.view.render(template, ["games": games])
    // Convert View to Response...
}
```

### Determining Direct Launch vs Agent Launch
```swift
// Source: existing codebase patterns (RecipeEngine, SuccessDatabase)
func canDirectLaunch(gameId: String) -> Bool {
    // Check for user recipe
    let userRecipe = CellarPaths.userRecipeFile(for: gameId)
    if FileManager.default.fileExists(atPath: userRecipe.path) { return true }
    // Check for bundled recipe
    if let _ = try? RecipeEngine.findBundledRecipe(for: gameId) { return true }
    // Check success database
    let successFile = CellarPaths.successdbFile(for: gameId)
    if FileManager.default.fileExists(atPath: successFile.path) { return true }
    return false
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Vapor ConsoleKit commands | swift-argument-parser | Vapor 4.x | Must use Environment(name:arguments:) workaround |
| WebSocket for real-time | SSE for unidirectional streaming | htmx 2.x | Simpler server, auto-reconnect, HTTP/2 multiplexing |
| htmx 1.x hx-sse attribute | htmx-ext-sse 2.x separate extension | htmx 2.0 | SSE moved to extension, new attribute names (sse-connect, sse-swap) |
| Leaf 4.2.x | Leaf 4.4.x | 2024 | Improved async rendering, Swift 6 compatibility |

**Deprecated/outdated:**
- `hx-sse` attribute (htmx 1.x) -- replaced by `sse-connect`/`sse-swap` in htmx-ext-sse 2.x
- Vapor ConsoleKit for CLI commands -- project already uses swift-argument-parser

## Open Questions

1. **Binary size increase from Vapor**
   - What we know: Vapor pulls in SwiftNIO, SwiftCrypto, and many dependencies. Current binary is lightweight (ArgumentParser + SwiftSoup only).
   - What's unclear: Exact size impact. Vapor is a substantial dependency tree.
   - Recommendation: Accept the increase -- it's a localhost tool, not deployed to constrained environments. Monitor compile time.

2. **Agent loop async adaptation depth**
   - What we know: AgentLoop.run() is fully synchronous with DispatchSemaphore bridges. Vapor is async/NIO.
   - What's unclear: Whether to make AgentLoop fully async or just wrap it in a Task.detached.
   - Recommendation: Wrap in Task.detached for Phase 12 (minimal change). A full async rewrite of AgentLoop is a separate concern.

3. **Concurrent launches**
   - What we know: Wine on macOS (winemac.drv) has issues with parallel processes. The CLI is single-launch by design.
   - What's unclear: Whether the web UI should enforce single-launch or allow queuing.
   - Recommendation: Enforce single active launch at a time. Show "launch in progress" status on other game cards. Use an actor to guard the launch gate.

## Sources

### Primary (HIGH confidence)
- [Vapor docs - Leaf Getting Started](https://docs.vapor.codes/leaf/getting-started/) - Package.swift setup, configuration
- [HTMX SSE Extension docs](https://htmx.org/extensions/sse/) - sse-connect, sse-swap attributes, event format
- [Vapor GitHub releases](https://github.com/vapor/vapor/releases) - Latest stable: 4.121.3 (Feb 2025)

### Secondary (MEDIUM confidence)
- [SSE in Vapor practical guide (Feb 2026)](https://aldo10012.medium.com/setting-up-server-sent-events-sse-in-vapor-a-practical-guide) - Response.Body(stream:) pattern, SSE event formatting
- [Vapor argument parsing issue #2385](https://github.com/vapor/vapor/issues/2385) - Environment(name:arguments:) workaround confirmed by maintainers
- [Vapor template Package.swift](https://github.com/vapor/template/blob/main/Package.swift) - Reference dependency versions

### Tertiary (LOW confidence)
- Pico CSS recommendation is based on training knowledge of classless CSS frameworks -- needs validation that v2 is current

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Vapor + Leaf versions verified via official docs and GitHub releases
- Architecture: MEDIUM - SSE streaming pattern verified from multiple sources; Vapor + ArgumentParser integration confirmed via GitHub issue; NIO deadlock risk is well-documented
- Pitfalls: HIGH - NIO deadlock, argument hijacking, and Sendable issues are well-known; CellarStore thread safety derived from codebase analysis

**Research date:** 2026-03-29
**Valid until:** 2026-04-28 (Vapor stable, HTMX stable -- 30-day window reasonable)
