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
        // GameRemover handles games.json update + all artifact deletion
        try GameRemover.remove(gameId: id)
    }

    func updateGame(_ entry: GameEntry) throws {
        try CellarStore.updateGame(entry)
    }
}
