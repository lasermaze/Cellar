import ArgumentParser
import Foundation

// MARK: - WikiCommand

struct WikiCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wiki",
        abstract: "Wiki management commands",
        subcommands: [IngestCommand.self]
    )
}

// MARK: - IngestCommand

extension WikiCommand {
    struct IngestCommand: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ingest",
            abstract: "Pre-compile game wiki pages from external sources"
        )

        @Argument(help: "Game name to ingest")
        var gameName: String?

        @Flag(name: .long, help: "Ingest top games from Lutris catalog")
        var popular: Bool = false

        @Flag(name: .customLong("all-local"), help: "Ingest all games in local success database")
        var allLocal: Bool = false

        mutating func validate() throws {
            let modeCount = [gameName != nil, popular, allLocal].filter { $0 }.count
            if modeCount == 0 {
                throw ValidationError("Provide a game name, --popular, or --all-local")
            }
            if modeCount > 1 {
                throw ValidationError("Provide only one of: game name, --popular, --all-local")
            }
        }

        mutating func run() async throws {
            var ingested = 0
            var skipped = 0

            if let name = gameName {
                // Single game mode
                let success = await WikiIngestService.ingest(gameName: name)
                if success {
                    print("Ingested: \(name)")
                    ingested += 1
                } else {
                    print("Skipped: \(name) (no data or already up to date)")
                    skipped += 1
                }

            } else if popular {
                // Popular mode — top games from Lutris catalog
                let games = await CompatibilityService.fetchPopularGames(limit: 50)
                if games.isEmpty {
                    print("Error: could not fetch popular games from Lutris")
                    return
                }
                let total = games.count
                for (index, game) in games.enumerated() {
                    print("[\(index + 1)/\(total)] \(game)...")
                    let success = await WikiIngestService.ingest(gameName: game)
                    if success {
                        ingested += 1
                    } else {
                        skipped += 1
                    }
                    if index < total - 1 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }

            } else if allLocal {
                // All-local mode — all games in the success database
                let records = SuccessDatabase.loadAll()
                if records.isEmpty {
                    print("No games found in local success database")
                    return
                }
                let total = records.count
                for (index, record) in records.enumerated() {
                    print("[\(index + 1)/\(total)] \(record.gameName)...")
                    let success = await WikiIngestService.ingest(gameName: record.gameName)
                    if success {
                        ingested += 1
                    } else {
                        skipped += 1
                    }
                    if index < total - 1 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                    }
                }
            }

            print("Ingested \(ingested) game(s) (\(skipped) skipped)")
        }
    }
}
