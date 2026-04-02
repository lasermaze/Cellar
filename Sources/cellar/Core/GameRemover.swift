import Foundation

struct GameRemover {
    /// Remove a game and all its associated artifacts.
    /// The games.json update is the critical step (throws on failure).
    /// Artifact deletion uses try? — missing artifacts are silently skipped.
    static func remove(gameId: String) throws {
        // Step 1: Remove from games.json (critical — throws on failure)
        var games = try CellarStore.loadGames()
        games.removeAll { $0.id == gameId }
        try CellarStore.saveGames(games)

        // Step 2: Remove all artifacts (non-fatal if any are missing)
        let artifacts: [URL] = [
            CellarPaths.bottleDir(for: gameId),
            CellarPaths.logDir(for: gameId),
            CellarPaths.userRecipeFile(for: gameId),
            CellarPaths.successdbFile(for: gameId),
            CellarPaths.sessionFile(for: gameId),
            CellarPaths.diagnosticsDir(for: gameId),
            CellarPaths.researchCacheFile(for: gameId),
            CellarPaths.lutrisCompatCacheDir.appendingPathComponent("\(gameId).json"),
            CellarPaths.protondbCompatCacheDir.appendingPathComponent("\(gameId).json"),
        ]
        for artifact in artifacts {
            try? FileManager.default.removeItem(at: artifact)
        }
    }
}
