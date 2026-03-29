import Foundation

/// Launch orchestration extracted from LaunchCommand for web reuse.
/// Determines whether a game can be directly launched (has recipe/success)
/// or needs the AI agent.
enum LaunchService {
    /// Check if a game has a working config for direct launch.
    static func canDirectLaunch(gameId: String) -> Bool {
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

    /// Resolve the Wine binary URL, or nil if Wine is not installed.
    static func resolveWine() -> URL? {
        let status = DependencyChecker().checkAll()
        guard status.allRequired else { return nil }
        return status.wine
    }
}
