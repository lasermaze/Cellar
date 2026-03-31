@preconcurrency import Vapor
@preconcurrency import Leaf
import Foundation

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
