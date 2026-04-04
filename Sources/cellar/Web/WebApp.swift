@preconcurrency import Vapor
@preconcurrency import Leaf
import Foundation

/// Blocks cross-origin POST/PUT/DELETE/PATCH requests (CSRF protection).
/// Requests with no Origin header pass through — non-browser clients (curl, URLSession) are allowed.
struct OriginCheckMiddleware: AsyncMiddleware {
    let allowedPort: Int

    /// Pure logic: should this request be allowed through?
    /// Returns true if allowed, false if should be blocked.
    static func isOriginAllowed(_ origin: String?, method: String, allowedPort: Int) -> Bool {
        let mutatingMethods = ["POST", "PUT", "DELETE", "PATCH"]
        guard mutatingMethods.contains(method) else { return true }
        guard let origin = origin else { return true }  // no Origin = non-browser client
        let allowed = ["http://localhost:\(allowedPort)", "http://127.0.0.1:\(allowedPort)"]
        return allowed.contains(origin)
    }

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let method = request.method.string
        let origin = request.headers.first(name: .origin)
        guard Self.isOriginAllowed(origin, method: method, allowedPort: allowedPort) else {
            throw Abort(.forbidden, reason: "CSRF: Origin '\(origin ?? "")' not allowed")
        }
        return try await next.respond(to: request)
    }
}

enum WebApp {
    static func configure(_ app: Application, port: Int) throws {
        // Template engine
        app.views.use(.leaf)

        // Resolve resource directories — prefer source tree for development,
        // fall back to bundle resources for deployed binaries.
        // Leaf's security check blocks paths with dotfile components (like ~/.cellar/),
        // so when running from a dotfile path, copy resources to a safe temp location.
        let sourceViews = FileManager.default.currentDirectoryPath + "/Sources/cellar/Resources/Views"
        let sourcePublic = FileManager.default.currentDirectoryPath + "/Sources/cellar/Resources/Public"
        let viewsPath: String
        let publicPath: String
        if FileManager.default.fileExists(atPath: sourceViews + "/base.leaf") {
            // Development: source tree
            viewsPath = sourceViews + "/"
            publicPath = sourcePublic + "/"
        } else if let resourcePath = Bundle.module.resourcePath {
            // SPM flat bundles (.copy("Resources")) put files under bundle/Resources/,
            // but Bundle.resourcePath returns the bundle root — not bundle/Resources/.
            // Check both layouts so this works regardless of bundle structure.
            let resolvedBase: String
            if FileManager.default.fileExists(atPath: resourcePath + "/Resources/Views/base.leaf") {
                resolvedBase = resourcePath + "/Resources"
            } else {
                resolvedBase = resourcePath
            }
            let bundleViews = resolvedBase + "/Views/"
            let bundlePublic = resolvedBase + "/Public/"
            // Check if the bundle path contains a dotfile component (e.g. ~/.cellar/)
            // Leaf blocks these for security, so copy to a safe temp location
            let hasDotfileInPath = resolvedBase.split(separator: "/").contains { $0.hasPrefix(".") }
            if hasDotfileInPath {
                let safeDir = NSTemporaryDirectory() + "cellar-resources"
                let safeViews = safeDir + "/Views/"
                let safePublic = safeDir + "/Public/"
                try? FileManager.default.removeItem(atPath: safeDir)
                try? FileManager.default.copyItem(atPath: resolvedBase + "/Views", toPath: String(safeViews.dropLast()))
                try? FileManager.default.copyItem(atPath: resolvedBase + "/Public", toPath: String(safePublic.dropLast()))
                viewsPath = safeViews
                publicPath = safePublic
            } else {
                viewsPath = bundleViews
                publicPath = bundlePublic
            }
        } else {
            fatalError("Cannot find Leaf template directory")
        }

        app.leaf.configuration.rootDirectory = viewsPath
        app.directory.viewsDirectory = viewsPath
        app.directory.publicDirectory = publicPath

        // CSRF protection — block cross-origin mutating requests before any route handler runs
        app.middleware.use(OriginCheckMiddleware(allowedPort: port))

        // Static files — use resolved publicPath (not default working directory,
        // which may be inside ~/.cellar/ and get rejected as a dotfile path)
        app.middleware.use(
            FileMiddleware(publicDirectory: publicPath)
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
