@preconcurrency import Vapor
@preconcurrency import Leaf
import Foundation

/// Blocks cross-origin POST/PUT/DELETE/PATCH requests (CSRF protection).
/// Requests with no Origin header pass through — non-browser clients (curl, URLSession) are allowed.
struct OriginCheckMiddleware: AsyncMiddleware {
    let allowedPort: Int

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let mutatingMethods: [HTTPMethod] = [.POST, .PUT, .DELETE, .PATCH]
        guard mutatingMethods.contains(request.method) else {
            return try await next.respond(to: request)
        }
        guard let origin = request.headers.first(name: .origin) else {
            // No Origin header — non-browser client, allow through
            return try await next.respond(to: request)
        }
        let allowed = ["http://localhost:\(allowedPort)", "http://127.0.0.1:\(allowedPort)"]
        guard allowed.contains(origin) else {
            throw Abort(.forbidden, reason: "CSRF: Origin '\(origin)' not allowed")
        }
        return try await next.respond(to: request)
    }
}

enum WebApp {
    static func configure(_ app: Application, port: Int) throws {
        // Template engine
        app.views.use(.leaf)

        // Resolve views directory — prefer source tree (avoids LeafKit .build sandbox rejection),
        // fall back to bundle resources for deployed binaries
        let sourceViews = FileManager.default.currentDirectoryPath + "/Sources/cellar/Resources/Views"
        let viewsPath: String
        if FileManager.default.fileExists(atPath: sourceViews + "/base.leaf") {
            viewsPath = sourceViews + "/"
        } else if let resourcePath = Bundle.module.resourcePath {
            viewsPath = resourcePath + "/Views/"
        } else {
            fatalError("Cannot find Leaf template directory")
        }

        app.leaf.configuration.rootDirectory = viewsPath
        app.directory.viewsDirectory = viewsPath

        // CSRF protection — block cross-origin mutating requests before any route handler runs
        app.middleware.use(OriginCheckMiddleware(allowedPort: port))

        // Static files
        app.middleware.use(
            FileMiddleware(publicDirectory: app.directory.publicDirectory)
        )

        // Server config — localhost only, no auth needed
        app.http.server.configuration.port = port
        app.http.server.configuration.hostname = "127.0.0.1"

        // Game management routes
        try GameController.register(app)

        // Launch routes (SSE streaming)
        try LaunchController.register(app)

        // Settings routes (API keys)
        try SettingsController.register(app)

        // Memory routes (collective memory stats)
        try MemoryController.register(app)
    }
}
