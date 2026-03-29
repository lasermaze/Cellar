import Foundation

/// Thread-safe game store access for the web server.
/// CellarStore uses static methods with no synchronization -- fine for CLI
/// but unsafe for concurrent web requests. This actor serializes access.
actor GameService {
    static let shared = GameService()

    func loadGames() throws -> [GameEntry] {
        try CellarStore.loadGames()
    }

    func findGame(id: String) throws -> GameEntry? {
        try CellarStore.findGame(id: id)
    }

    func addGame(_ entry: GameEntry) throws {
        try CellarStore.addGame(entry)
    }

    func deleteGame(id: String, cleanBottle: Bool) throws {
        var games = try CellarStore.loadGames()
        games.removeAll { $0.id == id }
        try CellarStore.saveGames(games)
        if cleanBottle {
            let bottleDir = CellarPaths.bottleDir(for: id)
            try? FileManager.default.removeItem(at: bottleDir)
        }
    }

    func updateGame(_ entry: GameEntry) throws {
        try CellarStore.updateGame(entry)
    }
}
