@preconcurrency import Vapor
@preconcurrency import Leaf

enum GameController {
    /// Register all game-related routes.
    static func register(_ app: Application) throws {
        // GET / -- render full game library page
        app.get { req async throws -> View in
            let gameData = try await loadGameViewData()
            return try await req.view.render("index", IndexContext(
                title: "Library",
                games: gameData
            ))
        }

        // GET /games -- partial game list for HTMX refresh
        app.get("games") { req async throws -> View in
            let gameData = try await loadGameViewData()
            // If HTMX request, return just the game grid partial
            if req.headers.first(name: "HX-Request") == "true" {
                return try await req.view.render("game-list", GameListContext(games: gameData))
            }
            return try await req.view.render("index", IndexContext(
                title: "Library",
                games: gameData
            ))
        }

        // GET /games/add -- add game form
        app.get("games", "add") { req async throws -> View in
            try await req.view.render("add-game", ["title": "Add Game"])
        }

        // POST /games -- validate input, redirect to install page with SSE
        app.post("games") { req async throws -> Response in
            let input = try req.content.decode(AddGameInput.self)
            let installerURL = URL(fileURLWithPath: input.installPath)

            guard FileManager.default.fileExists(atPath: installerURL.path) else {
                throw Abort(.badRequest, reason: "Installer not found at \(input.installPath)")
            }
            guard LaunchService.resolveWine() != nil else {
                throw Abort(.serviceUnavailable, reason: "Wine is not installed")
            }

            let installerName = installerURL.deletingPathExtension().lastPathComponent
            let gameId = slugify(installerName)
            let gameName = installerName.replacingOccurrences(of: "_", with: " ")
            let encodedPath = input.installPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input.installPath

            return req.redirect(to: "/games/install?gameId=\(gameId)&gameName=\(gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gameName)&installPath=\(encodedPath)")
        }

        // GET /games/install -- install progress page
        app.get("games", "install") { req async throws -> View in
            guard let gameId = req.query[String.self, at: "gameId"],
                  let gameName = req.query[String.self, at: "gameName"],
                  let installPath = req.query[String.self, at: "installPath"] else {
                throw Abort(.badRequest)
            }
            let encodedPath = installPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? installPath
            return try await req.view.render("install-log", InstallLogContext(
                gameId: gameId,
                gameName: gameName,
                streamURL: "/games/install/stream?gameId=\(gameId)&gameName=\(gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? gameName)&installPath=\(encodedPath)"
            ))
        }

        // GET /games/install/stream -- SSE stream for installation
        app.get("games", "install", "stream") { req async throws -> Response in
            guard let gameId = req.query[String.self, at: "gameId"],
                  let gameName = req.query[String.self, at: "gameName"],
                  let installPath = req.query[String.self, at: "installPath"] else {
                throw Abort(.badRequest)
            }

            let body = Response.Body(stream: { writer in
                Task.detached {
                    do {
                        try await runInstall(
                            gameId: gameId,
                            gameName: gameName,
                            installPath: installPath,
                            writer: writer
                        )
                    } catch {
                        sendSSE(writer: writer, event: "error",
                                data: "<div class='error'>Error: \(escapeHTML(error.localizedDescription))</div>")
                    }
                    sendSSE(writer: writer, event: "complete",
                            data: "<div><a href='/' role='button'>Back to Library</a></div>")
                    _ = writer.write(.end)
                }
            })

            let response = Response(status: .ok, body: body)
            response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
            response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
            response.headers.replaceOrAdd(name: .connection, value: "keep-alive")
            return response
        }

        // DELETE /games/:gameId -- delete a game
        app.delete("games", ":gameId") { req async throws -> View in
            guard let gameId = req.parameters.get("gameId") else {
                throw Abort(.badRequest)
            }
            let cleanBottle = (req.query[String.self, at: "cleanBottle"] ?? "false") == "true"
            try await GameService.shared.deleteGame(id: gameId, cleanBottle: cleanBottle)

            // Return updated game list partial
            let gameData = try await loadGameViewData()
            return try await req.view.render("game-list", GameListContext(games: gameData))
        }
    }

    // MARK: - Helpers

    private static func loadGameViewData() async throws -> [GameViewData] {
        let games = try await GameService.shared.loadGames()
        return games.map { game in
            GameViewData(
                id: game.id,
                name: game.name,
                status: game.lastResult.map { $0.reachedMenu ? "Working" : "Needs Attention" } ?? "Ready",
                lastPlayed: game.lastLaunched.map { formatDate($0) } ?? "Never",
                canDirectLaunch: LaunchService.canDirectLaunch(gameId: game.id)
            )
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    // MARK: - View Models

    struct IndexContext: Content {
        let title: String
        let games: [GameViewData]
    }

    struct GameListContext: Content {
        let games: [GameViewData]
    }

    struct GameViewData: Content {
        let id: String
        let name: String
        let status: String
        let lastPlayed: String
        let canDirectLaunch: Bool
    }

    struct AddGameInput: Content {
        let installPath: String
    }

    struct InstallLogContext: Content {
        let gameId: String
        let gameName: String
        let streamURL: String
    }

    // MARK: - Install Logic

    private static func runInstall(
        gameId: String, gameName: String, installPath: String, writer: BodyStreamWriter
    ) async throws {
        let installerURL = URL(fileURLWithPath: installPath)
        guard let wineURL = LaunchService.resolveWine() else {
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>Wine is not installed</div>")
            return
        }

        // Create bottle
        sendSSE(writer: writer, event: "status",
                data: "<div>Creating Wine bottle for \(escapeHTML(gameName))...</div>")
        let bottleManager = BottleManager(wineBinary: wineURL)
        _ = try bottleManager.createBottle(gameId: gameId)

        sendSSE(writer: writer, event: "log",
                data: "<div class='log-line'>Bottle created at ~/.cellar/bottles/\(escapeHTML(gameId))</div>")

        // Run installer
        sendSSE(writer: writer, event: "status",
                data: "<div>Running installer inside Wine bottle...</div>")
        sendSSE(writer: writer, event: "log",
                data: "<div class='log-line'>Installer: \(escapeHTML(installerURL.lastPathComponent))</div>")

        let bottleURL = CellarPaths.bottleDir(for: gameId)
        let wineProcess = WineProcess(wineBinary: wineURL, winePrefix: bottleURL)

        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<WineResult, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let r = try wineProcess.run(
                        binary: installerURL.path,
                        arguments: ["/VERYSILENT", "/SP-", "/SUPPRESSMSGBOXES"],
                        environment: [:]
                    )
                    continuation.resume(returning: r)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        if result.exitCode == 0 {
            sendSSE(writer: writer, event: "log",
                    data: "<div class='log-line success'>Installer exited normally</div>")
        } else {
            sendSSE(writer: writer, event: "log",
                    data: "<div class='log-line error'>Installer exited with code \(result.exitCode)</div>")
        }

        if !result.stderr.isEmpty {
            let lines = result.stderr.components(separatedBy: "\n").suffix(20)
            for line in lines where !line.isEmpty {
                sendSSE(writer: writer, event: "log",
                        data: "<div class='log-line'>\(escapeHTML(line))</div>")
            }
        }

        // Scan for executables
        sendSSE(writer: writer, event: "status",
                data: "<div>Scanning for game executables...</div>")

        let discovered = BottleScanner.scanForExecutables(bottlePath: bottleURL)
        var executablePath: String? = nil

        if let recipe = try? RecipeEngine.findBundledRecipe(for: gameId) {
            if let found = BottleScanner.findExecutable(named: recipe.executable, in: discovered) {
                executablePath = found.path
            }
        }
        if executablePath == nil, let first = discovered.first {
            executablePath = first.path
        }

        if discovered.isEmpty {
            sendSSE(writer: writer, event: "error",
                    data: "<div class='error'>No game executables found in bottle</div>")
        } else {
            sendSSE(writer: writer, event: "log",
                    data: "<div class='log-line'>Found \(discovered.count) executable(s)</div>")
            for exe in discovered.prefix(5) {
                sendSSE(writer: writer, event: "log",
                        data: "<div class='log-line'>  \(escapeHTML(exe.lastPathComponent))</div>")
            }
        }

        // Save game entry
        let entry = GameEntry(
            id: gameId,
            name: gameName,
            installPath: installPath,
            executablePath: executablePath,
            recipeId: nil,
            addedAt: Date()
        )
        try await GameService.shared.addGame(entry)

        if let exePath = executablePath {
            sendSSE(writer: writer, event: "status",
                    data: "<div class='success'>Game added! Executable: \(escapeHTML(URL(fileURLWithPath: exePath).lastPathComponent))</div>")
        } else {
            sendSSE(writer: writer, event: "status",
                    data: "<div class='success'>Game added (no executable found — agent will search on launch)</div>")
        }
    }

    // MARK: - SSE Helper

    @discardableResult
    private static func sendSSE(writer: BodyStreamWriter, event: String, data: String) -> EventLoopFuture<Void> {
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

    private static func slugify(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .components(separatedBy: "-")
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}
