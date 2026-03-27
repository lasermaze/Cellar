import Foundation

struct CellarPaths {
    static let base: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cellar")

    static let gamesJSON: URL = base.appendingPathComponent("games.json")

    static let bottlesDir: URL = base.appendingPathComponent("bottles")

    static let logsDir: URL = base.appendingPathComponent("logs")

    static let userRecipesDir: URL = base.appendingPathComponent("recipes")

    static func userRecipeFile(for gameId: String) -> URL {
        userRecipesDir.appendingPathComponent("\(gameId).json")
    }

    static let aiTipSentinel: URL = base.appendingPathComponent(".ai-tip-shown")

    static func bottleDir(for gameId: String) -> URL {
        bottlesDir.appendingPathComponent(gameId)
    }

    static func logDir(for gameId: String) -> URL {
        logsDir.appendingPathComponent(gameId)
    }

    static func logFile(for gameId: String, timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestampString = formatter.string(from: timestamp)
        return logDir(for: gameId).appendingPathComponent("\(timestampString).log")
    }

    static func repairReportFile(for gameId: String, timestamp: Date) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return logDir(for: gameId).appendingPathComponent("repair-report-\(formatter.string(from: timestamp)).txt")
    }
}
