@preconcurrency import Vapor
@preconcurrency import Leaf

enum WebApp {
    static func configure(_ app: Application, port: Int) throws {
        // Template engine
        app.views.use(.leaf)

        // Resolve views directory from SPM bundle resource path
        if let resourcePath = Bundle.module.resourcePath {
            app.leaf.configuration.rootDirectory = resourcePath
            app.directory.viewsDirectory = resourcePath + "/Views/"
            app.directory.publicDirectory = resourcePath + "/Public/"
        }

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
    }
}
