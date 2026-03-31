@preconcurrency import Vapor
@preconcurrency import Leaf

enum MemoryController {
    /// Register collective memory routes.
    static func register(_ app: Application) throws {
        // GET /memory -- aggregate stats page
        app.get("memory") { req async throws -> View in
            let stats = MemoryStatsService.fetchStats()
            return try await req.view.render("memory", MemoryContext(
                title: "Community Memory",
                stats: stats
            ))
        }

        // GET /memory/:gameSlug -- per-game detail page
        app.get("memory", ":gameSlug") { req async throws -> View in
            let slug = req.parameters.get("gameSlug") ?? ""
            let detail = MemoryStatsService.fetchGameDetail(slug: slug)
            return try await req.view.render("memory-game", MemoryGameContext(
                title: detail?.gameName ?? slug,
                detail: detail,
                slug: slug
            ))
        }
    }

    // MARK: - View Models

    struct MemoryContext: Content {
        let title: String
        let stats: MemoryStats
    }

    struct MemoryGameContext: Content {
        let title: String
        let detail: GameDetail?
        let slug: String
    }
}
