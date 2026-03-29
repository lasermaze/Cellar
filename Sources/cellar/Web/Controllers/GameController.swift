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

        // POST /games -- add a new game
        app.post("games") { req async throws -> Response in
            let input = try req.content.decode(AddGameInput.self)
            let url = URL(fileURLWithPath: input.installPath)
            let gameId = url.deletingLastPathComponent().lastPathComponent
                .lowercased()
                .replacingOccurrences(of: " ", with: "-")
            let entry = GameEntry(
                id: gameId,
                name: gameId.replacingOccurrences(of: "-", with: " ").capitalized,
                installPath: input.installPath,
                recipeId: nil,
                addedAt: Date()
            )
            try await GameService.shared.addGame(entry)
            return req.redirect(to: "/")
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
}
