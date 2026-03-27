import ArgumentParser
import Foundation

struct LogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "log",
        abstract: "View launch logs for a game"
    )

    @Argument(help: "Game name (as shown in cellar status)")
    var game: String

    @Flag(name: .shortAndLong, help: "List all log files instead of showing the latest")
    var list: Bool = false

    mutating func run() throws {
        let logDir = CellarPaths.logDir(for: game)

        // Gather log files
        guard FileManager.default.fileExists(atPath: logDir.path) else {
            print("No logs found for \(game).")
            return
        }

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: logDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let logFiles = entries
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let lDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let rDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return lDate < rDate
            }

        guard !logFiles.isEmpty else {
            print("No logs found for \(game).")
            return
        }

        if list {
            // List all log file paths, newest last
            for file in logFiles {
                print(file.path)
            }
        } else {
            // Show contents of the most recent log file
            let latest = logFiles.last!
            print("--- \(latest.lastPathComponent) ---")
            if let contents = try? String(contentsOf: latest, encoding: .utf8) {
                print(contents)
            } else {
                print("(could not read log file)")
            }
        }
    }
}
