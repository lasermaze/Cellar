@preconcurrency import Vapor
import Foundation
import NIOCore

/// Actor-based single launch guard -- Wine on macOS doesn't handle parallel processes well
private actor LaunchGuard {
    static let shared = LaunchGuard()
    private var activeLaunch: String? = nil
    private var acquiredAt: Date? = nil

    func tryAcquire(gameId: String) throws -> Bool {
        // Auto-release stale guards (>10 min — handles stuck agents)
        if activeLaunch != nil, let acquired = acquiredAt,
           Date().timeIntervalSince(acquired) > 600 {
            activeLaunch = nil
            acquiredAt = nil
        }
        if let active = activeLaunch {
            throw Abort(.conflict, reason: "Game '\(active)' is currently launching")
        }
        activeLaunch = gameId
        acquiredAt = Date()
        return true
    }

    func release() {
        activeLaunch = nil
        acquiredAt = nil
    }
}

/// Thread-safe pending user response store for web-based agent prompts.
/// Agent blocks on DispatchSemaphore; browser POSTs answer which signals the semaphore.
private final class PendingUserResponse: @unchecked Sendable {
    static let shared = PendingUserResponse()
    private let lock = NSLock()
    private var responses: [String: String] = [:]       // gameId -> answer
    private var semaphores: [String: DispatchSemaphore] = [:]  // gameId -> semaphore

    /// Called from agent thread (blocks until browser responds)
    func waitForResponse(gameId: String) -> String {
        let sem = DispatchSemaphore(value: 0)
        lock.lock()
        semaphores[gameId] = sem
        lock.unlock()

        sem.wait()

        lock.lock()
        let answer = responses.removeValue(forKey: gameId) ?? ""
        semaphores.removeValue(forKey: gameId)
        lock.unlock()
        return answer
    }

    /// Called from web route when user submits answer
    func submitResponse(gameId: String, answer: String) {
        lock.lock()
        responses[gameId] = answer
        let sem = semaphores[gameId]
        lock.unlock()
        sem?.signal()
    }
}

/// Thread-safe store for active AgentTools instances, allowing web routes to control them.
private final class ActiveAgents: @unchecked Sendable {
    static let shared = ActiveAgents()
    private let lock = NSLock()
    private var agents: [String: AgentTools] = [:]
    private var controls: [String: AgentControl] = [:]

    func register(gameId: String, tools: AgentTools, control: AgentControl) {
        lock.lock()
        agents[gameId] = tools
        controls[gameId] = control
        lock.unlock()
    }

    func getTools(gameId: String) -> AgentTools? {
        lock.lock()
        defer { lock.unlock() }
        return agents[gameId]
    }

    func getControl(gameId: String) -> AgentControl? {
        lock.lock()
        defer { lock.unlock() }
        return controls[gameId]
    }

    func remove(gameId: String) {
        lock.lock()
        agents.removeValue(forKey: gameId)
        controls.removeValue(forKey: gameId)
        lock.unlock()
    }
}

enum LaunchController {

    static func register(_ app: Application) throws {
        // GET /games/:gameId/launch -- launch log page
        app.get("games", ":gameId", "launch") { req async throws -> View in
            guard let gameId = req.parameters.get("gameId") else {
                throw Abort(.badRequest)
            }
            guard let game = try await GameService.shared.findGame(id: gameId) else {
                throw Abort(.notFound)
            }
            let useAgent = (req.query[String.self, at: "agent"] ?? "false") == "true"
            return try await req.view.render("launch-log", LaunchLogContext(
                gameId: game.id,
                gameName: game.name,
                useAgent: useAgent,
                streamURL: "/games/\(game.id)/launch/stream?agent=\(useAgent)"
            ))
        }

        // GET /games/:gameId/launch/stream -- SSE stream
        app.get("games", ":gameId", "launch", "stream") { req async throws -> Response in
            guard let gameId = req.parameters.get("gameId") else {
                throw Abort(.badRequest)
            }

            // Enforce single active launch — return SSE error instead of 409 to prevent reconnect storm
            do {
                _ = try await LaunchGuard.shared.tryAcquire(gameId: gameId)
            } catch {
                let body = Response.Body(stream: { writer in
                    Task.detached {
                        sendSSE(writer: writer, event: "error",
                                data: "<div class='error'>Another launch is already in progress. Go back and try again.</div>")
                        sendSSE(writer: writer, event: "complete", data: "<div></div>")
                        _ = writer.write(.end)
                    }
                })
                let response = Response(status: .ok, body: body)
                response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
                response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
                return response
            }

            let useAgent = (req.query[String.self, at: "agent"] ?? "false") == "true"

            let body = Response.Body(stream: { writer in
                Task.detached {
                    defer {
                        Task { await LaunchGuard.shared.release() }
                    }

                    do {
                        try await runLaunch(
                            gameId: gameId,
                            useAgent: useAgent,
                            writer: writer
                        )
                    } catch {
                        sendSSE(writer: writer, event: "error",
                                data: "<div class='error'>Error: \(error.localizedDescription)</div>")
                    }

                    // Signal completion
                    sendSSE(writer: writer, event: "complete",
                            data: "<div>Launch finished.</div>")
                    _ = writer.write(.end)
                }
            })

            let response = Response(status: .ok, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
            response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
            return response
        }

        // POST /games/:gameId/launch/stop -- force stop agent
        app.post("games", ":gameId", "launch", "stop") { req async throws -> Response in
            guard let gameId = req.parameters.get("gameId") else { throw Abort(.badRequest) }
            ActiveAgents.shared.getControl(gameId: gameId)?.abort()
            await LaunchGuard.shared.release()
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "text/html")
            return Response(status: .ok, headers: headers,
                            body: .init(string: "<span style='color: var(--error);'>Agent stopped</span>"))
        }

        // POST /games/:gameId/launch/confirm -- user confirms game is working
        app.post("games", ":gameId", "launch", "confirm") { req async throws -> Response in
            guard let gameId = req.parameters.get("gameId") else { throw Abort(.badRequest) }
            ActiveAgents.shared.getControl(gameId: gameId)?.confirm()
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "text/html")
            return Response(status: .ok, headers: headers,
                            body: .init(string: "<span style='color: var(--success);'>Confirmed! Saving config...</span>"))
        }

        // POST /games/:gameId/launch/respond -- user answers agent prompt
        app.post("games", ":gameId", "launch", "respond") { req async throws -> Response in
            guard let gameId = req.parameters.get("gameId") else {
                throw Abort(.badRequest)
            }
            struct UserAnswer: Content {
                let answer: String
            }
            let input = try req.content.decode(UserAnswer.self)
            PendingUserResponse.shared.submitResponse(gameId: gameId, answer: input.answer)
            return Response(status: .ok)
        }
    }

    // MARK: - Launch Logic

    private static func runLaunch(gameId: String, useAgent: Bool, writer: BodyStreamWriter) async throws {
        guard let game = try await GameService.shared.findGame(id: gameId) else {
            throw Abort(.notFound)
        }
        guard let wineURL = LaunchService.resolveWine() else {
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>Wine is not installed</div>")
            return
        }

        let bottleURL = CellarPaths.bottleDir(for: gameId)
        guard let executablePath = game.executablePath else {
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>No executable path configured for this game</div>")
            return
        }

        sendSSE(writer: writer, event: "status",
                data: "<div>Preparing to launch \(escapeHTML(game.name))...</div>")

        if useAgent {
            try await runAgentLaunch(
                gameId: gameId, game: game, executablePath: executablePath,
                wineURL: wineURL, bottleURL: bottleURL, writer: writer
            )
        } else {
            try await runDirectLaunch(
                gameId: gameId, game: game, executablePath: executablePath,
                wineURL: wineURL, bottleURL: bottleURL, writer: writer
            )
        }
    }

    private static func runDirectLaunch(
        gameId: String, game: GameEntry, executablePath: String,
        wineURL: URL, bottleURL: URL, writer: BodyStreamWriter
    ) async throws {
        sendSSE(writer: writer, event: "status",
                data: "<div>Direct launch -- applying config...</div>")

        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)
        let engine = RecipeEngine()
        var launchEnv: [String: String] = [:]

        // Load and apply bundled recipe
        if let recipe = try? RecipeEngine.findBundledRecipe(for: gameId) {
            do {
                let recipeEnv = try engine.apply(recipe: recipe, wineProcess: wineProcess)
                launchEnv.merge(recipeEnv) { _, new in new }
                sendSSE(writer: writer, event: "log",
                        data: "<div>Recipe applied: \(escapeHTML(recipe.name))</div>")
            } catch {
                sendSSE(writer: writer, event: "log",
                        data: "<div class='warning'>Recipe apply error: \(escapeHTML(error.localizedDescription))</div>")
            }
        }

        // Load and apply user recipe
        let userRecipeURL = CellarPaths.userRecipeFile(for: gameId)
        if FileManager.default.fileExists(atPath: userRecipeURL.path),
           let data = try? Data(contentsOf: userRecipeURL),
           let recipe = try? JSONDecoder().decode(Recipe.self, from: data) {
            do {
                let recipeEnv = try engine.apply(recipe: recipe, wineProcess: wineProcess)
                launchEnv.merge(recipeEnv) { _, new in new }
                sendSSE(writer: writer, event: "log",
                        data: "<div>User recipe applied</div>")
            } catch {
                sendSSE(writer: writer, event: "log",
                        data: "<div class='warning'>User recipe apply error: \(escapeHTML(error.localizedDescription))</div>")
            }
        }

        // Load success database — agent's proven working config takes priority
        if let record = SuccessDatabase.load(gameId: gameId) {
            launchEnv.merge(record.environment) { _, new in new }
            sendSSE(writer: writer, event: "log",
                    data: "<div>Success config applied: \(record.environment.count) env var(s)</div>")
        } else if let recipeId = game.recipeId, let record = SuccessDatabase.load(gameId: recipeId) {
            // Try recipe ID as fallback (game ID may differ from success DB key)
            launchEnv.merge(record.environment) { _, new in new }
            sendSSE(writer: writer, event: "log",
                    data: "<div>Success config applied (via recipe ID): \(record.environment.count) env var(s)</div>")
        }

        if !launchEnv.isEmpty {
            sendSSE(writer: writer, event: "log",
                    data: "<div>Environment: \(launchEnv.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))</div>")
        }

        sendSSE(writer: writer, event: "status",
                data: "<div>Launching game...</div>")

        // Run Wine process on a detached thread (WineProcess uses synchronous Process APIs)
        let capturedEnv = launchEnv
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<WineResult, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let logFile = CellarPaths.logFile(for: gameId, timestamp: Date())
                    try FileManager.default.createDirectory(
                        at: logFile.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let wineResult = try wineProcess.run(
                        binary: executablePath,
                        arguments: [],
                        environment: capturedEnv,
                        logFile: logFile
                    )
                    continuation.resume(returning: wineResult)
                } catch {
                    continuation.resume(returning: WineResult(
                        exitCode: -1,
                        stderr: "Launch error: \(error.localizedDescription)",
                        elapsed: 0,
                        logPath: nil,
                        timedOut: false
                    ))
                }
            }
        }

        // Stream the result
        let statusText: String
        if result.timedOut {
            statusText = "Game timed out (stale output)"
        } else if result.exitCode == 0 {
            statusText = "Game exited normally"
        } else {
            statusText = "Game exited with code \(result.exitCode)"
        }
        sendSSE(writer: writer, event: "status",
                data: "<div>\(statusText)</div>")

        if !result.stderr.isEmpty {
            let escaped = escapeHTML(result.stderr)
            for line in escaped.components(separatedBy: "\n").prefix(100) {
                sendSSE(writer: writer, event: "log",
                        data: "<div class='log-line'>\(line)</div>")
            }
        }
    }

    private static func runAgentLaunch(
        gameId: String, game: GameEntry, executablePath: String,
        wineURL: URL, bottleURL: URL, writer: BodyStreamWriter
    ) async throws {
        sendSSE(writer: writer, event: "status",
                data: "<div>Starting AI agent...</div>")

        // Capture writer for the callback closure
        let sseWriter = writer

        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)

        let onOutput: @Sendable (AgentEvent) -> Void = { event in
            switch event {
            case .iteration(let n, let total):
                sendSSE(writer: sseWriter, event: "iteration",
                        data: "<div class='iteration'>Iteration \(n)/\(total)</div>")
            case .text(let text):
                sendSSE(writer: sseWriter, event: "log",
                        data: "<div class='agent-text'>\(escapeHTML(text))</div>")
            case .toolCall(let name):
                sendSSE(writer: sseWriter, event: "tool",
                        data: "<div class='tool-call'>Tool: \(escapeHTML(name))</div>")
            case .toolResult(let name, let truncated):
                sendSSE(writer: sseWriter, event: "log",
                        data: "<div class='tool-result'>\(escapeHTML(name)): \(escapeHTML(truncated))</div>")
            case .cost(_, _, let usd):
                sendSSE(writer: sseWriter, event: "cost",
                        data: "<div class='cost'>Cost: $\(String(format: "%.4f", usd))</div>")
            case .budgetWarning(let pct):
                sendSSE(writer: sseWriter, event: "status",
                        data: "<div class='warning'>Budget warning: \(pct)% used</div>")
            case .status(let msg):
                sendSSE(writer: sseWriter, event: "status",
                        data: "<div>\(escapeHTML(msg))</div>")
            case .error(let msg):
                sendSSE(writer: sseWriter, event: "error",
                        data: "<div class='error'>\(escapeHTML(msg))</div>")
            case .completed(let loopResult):
                sendSSE(writer: sseWriter, event: "status",
                        data: "<div>Agent completed: \(loopResult.iterationsUsed) iterations, $\(String(format: "%.4f", loopResult.estimatedCostUSD))</div>")
            }
        }

        let capturedGameId = gameId
        let capturedWriter = sseWriter
        // PendingUserResponse.waitForResponse blocks on DispatchSemaphore — run on a global queue
        // to avoid blocking Swift's cooperative thread pool.
        let webAskUser: @Sendable (_ question: String, _ options: [String]?) -> String = { question, options in
            // Send prompt to browser via SSE — rendered inside a <dialog> modal
            var html = "<header><h3>Agent Question</h3></header>"
            html += "<p>\(escapeHTML(question))</p>"
            html += "<form hx-post='/games/\(capturedGameId)/launch/respond' hx-swap='none'>"
            if let opts = options, !opts.isEmpty {
                for opt in opts {
                    html += "<label style='display: block; margin-bottom: 0.5rem;'>"
                    html += "<input type='radio' name='answer' value='\(escapeHTML(opt))'> \(escapeHTML(opt))"
                    html += "</label>"
                }
                html += "<hr>"
            }
            html += "<input type='text' name='answer' placeholder='Type your answer...'>"
            html += "<footer style='display: flex; justify-content: flex-end; gap: 0.5rem; margin-top: 1rem;'>"
            html += "<button type='submit'>Submit</button>"
            html += "</footer></form>"
            sendSSE(writer: capturedWriter, event: "prompt", data: html)
            // Block on DispatchSemaphore (intentional — PendingUserResponse is a web bridge pattern)
            return PendingUserResponse.shared.waitForResponse(gameId: capturedGameId)
        }

        let result = await AIService.runAgentLoop(
            gameId: gameId,
            entry: game,
            executablePath: executablePath,
            wineURL: wineURL,
            bottleURL: bottleURL,
            wineProcess: wineProcess,
            onOutput: onOutput,
            askUserHandler: webAskUser,
            onToolsCreated: { tools, control in
                ActiveAgents.shared.register(gameId: gameId, tools: tools, control: control)
            }
        )
        ActiveAgents.shared.remove(gameId: gameId)

        switch result {
        case .success(let summary):
            sendSSE(writer: writer, event: "status",
                    data: "<div class='success'>Agent finished: \(escapeHTML(summary))</div>")
        case .failed(let message):
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>Agent failed: \(escapeHTML(message))</div>")
        case .unavailable:
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>AI provider unavailable</div>")
        }
    }

    // MARK: - SSE Helpers

    @discardableResult
    private static func sendSSE(writer: BodyStreamWriter, event: String, data: String) -> EventLoopFuture<Void> {
        // SSE format: event: <name>\ndata: <data>\n\n
        // Multi-line data must have each line prefixed with "data: "
        let dataLines = data.components(separatedBy: "\n")
            .map { "data: \($0)" }
            .joined(separator: "\n")
        let message = "event: \(event)\n\(dataLines)\n\n"
        var buffer = ByteBufferAllocator().buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        return writer.write(.buffer(buffer))
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    // MARK: - View Models

    struct LaunchLogContext: Content {
        let gameId: String
        let gameName: String
        let useAgent: Bool
        let streamURL: String
    }
}
