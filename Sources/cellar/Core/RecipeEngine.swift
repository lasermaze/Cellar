import Foundation

struct RecipeEngine {
    /// Load a recipe from a JSON file path.
    static func loadRecipe(from path: URL) throws -> Recipe {
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(Recipe.self, from: data)
    }

    /// Find a bundled recipe by game ID.
    ///
    /// Looks for `{gameId}.json` in a `recipes/` directory.
    /// Tries Bundle.main first (for release builds), then falls back to
    /// the current working directory (for `swift run` during development).
    static func findBundledRecipe(for gameId: String) throws -> Recipe? {
        // Strategy 1: Bundle.main (release build with bundled resources)
        if let bundledURL = Bundle.main.url(
            forResource: gameId,
            withExtension: "json",
            subdirectory: "recipes"
        ) {
            return try loadRecipe(from: bundledURL)
        }

        // Strategy 2: recipes/ relative to current working directory (development / swift run)
        let cwdRecipePath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("recipes")
            .appendingPathComponent("\(gameId).json")

        if FileManager.default.fileExists(atPath: cwdRecipePath.path) {
            return try loadRecipe(from: cwdRecipePath)
        }

        // Strategy 3: Scan all recipes for one whose ID is a substring of the game ID
        // e.g., recipe "cossacks-european-wars" matches game ID "gog-galaxy-cossacks-european-wars"
        let recipesDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("recipes")
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: recipesDir,
            includingPropertiesForKeys: nil
        ) {
            for file in contents where file.pathExtension == "json" {
                let recipeId = file.deletingPathExtension().lastPathComponent
                if gameId.contains(recipeId) {
                    return try loadRecipe(from: file)
                }
            }
        }

        // No recipe found for this game ID
        return nil
    }

    /// Apply a recipe to a bottle: registry edits + env vars.
    ///
    /// Returns the merged environment dictionary to be set on the game launch process.
    func apply(recipe: Recipe, wineProcess: WineProcess) throws -> [String: String] {
        print("Applying recipe: \(recipe.name)")

        // Apply registry entries with full transparency
        for entry in recipe.registry {
            print("  Registry: \(entry.description)")
            // Print each line of the reg content indented (diff-like transparency)
            let lines = entry.regContent.components(separatedBy: "\n")
            for line in lines {
                print("    \(line)")
            }

            // Write reg content to a temp file
            let tempRegFile = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString + ".reg")
            try entry.regContent.write(to: tempRegFile, atomically: true, encoding: .utf8)

            // Apply via wine regedit
            try wineProcess.applyRegistryFile(at: tempRegFile)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempRegFile)
        }

        // Print each environment variable being set (transparency)
        for (key, value) in recipe.environment.sorted(by: { $0.key < $1.key }) {
            print("  Setting \(key)=\(value)")
        }

        print("Recipe applied.")

        // Return the environment dict — to be merged into the game launch process environment
        return recipe.environment
    }
}
