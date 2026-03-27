import Foundation

struct CellarStore {
    // MARK: - JSON encoder/decoder

    private static var encoder: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private static var decoder: JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    // MARK: - Persistence helpers

    /// Ensure ~/.cellar/ exists.
    private static func ensureBaseDir() throws {
        try FileManager.default.createDirectory(
            at: CellarPaths.base,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Public API

    /// Load all games from ~/.cellar/games.json. Returns an empty array if the file doesn't exist.
    static func loadGames() throws -> [GameEntry] {
        let url = CellarPaths.gamesJSON
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([GameEntry].self, from: data)
    }

    /// Save the games array to ~/.cellar/games.json.
    static func saveGames(_ games: [GameEntry]) throws {
        try ensureBaseDir()
        let data = try encoder.encode(games)
        try data.write(to: CellarPaths.gamesJSON, options: .atomic)
    }

    /// Find a game by its ID (slug). Returns nil if not found.
    static func findGame(id: String) throws -> GameEntry? {
        let games = try loadGames()
        return games.first { $0.id == id }
    }

    /// Add a new game entry. Does not check for duplicates — caller must check first.
    static func addGame(_ entry: GameEntry) throws {
        var games = try loadGames()
        games.append(entry)
        try saveGames(games)
    }

    /// Update an existing game entry (matched by id). If not found, does nothing.
    static func updateGame(_ entry: GameEntry) throws {
        var games = try loadGames()
        guard let index = games.firstIndex(where: { $0.id == entry.id }) else { return }
        games[index] = entry
        try saveGames(games)
    }
}
