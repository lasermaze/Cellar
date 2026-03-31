import Foundation

// MARK: - Lutris API Models

private struct LutrisSearchResponse: Codable {
    let count: Int
    let results: [LutrisGame]
}

struct LutrisGame: Codable {
    let id: Int
    let name: String
    let slug: String
    let year: Int?
    let providerGames: [LutrisProviderGame]

    enum CodingKeys: String, CodingKey {
        case id, name, slug, year
        case providerGames = "provider_games"
    }
}

struct LutrisProviderGame: Codable {
    let name: String
    let slug: String
    let service: String
}

private struct LutrisInstallerResponse: Codable {
    let count: Int
    let results: [LutrisInstaller]
}

struct LutrisInstaller: Codable {
    let id: Int
    let gameSlug: String
    let name: String
    let runner: String
    let script: LutrisScript?

    enum CodingKeys: String, CodingKey {
        case id, name, runner, script
        case gameSlug = "game_slug"
    }
}

struct LutrisScript: Codable {
    let system: LutrisSystem?
    let wine: LutrisWineConfig?
    let installer: [LutrisTask]?
    let game: LutrisGameConfig?
}

struct LutrisSystem: Codable {
    let env: [String: String]?
}

struct LutrisWineConfig: Codable {
    let overrides: [String: String]?
}

struct LutrisTask: Codable {
    let name: String?
    let app: String?
    let path: String?
    let key: String?
    let type: String?
    let value: String?
}

struct LutrisGameConfig: Codable {
    // Catch-all for the `game` key in Lutris scripts
}

// MARK: - ProtonDB Model

struct ProtonDBSummary: Codable {
    let tier: String
    let bestReportedTier: String
    let trendingTier: String
    let confidence: String
    let score: Double
    let total: Int
}

// MARK: - CompatibilityReport

struct CompatibilityReport {
    // Identity
    let gameName: String
    let lutrisSlug: String?
    let steamAppId: String?

    // Lutris extracted data
    let lutrisEnvVars: [ExtractedEnvVar]
    let lutrisDlls: [ExtractedDLL]
    let lutrisWinetricks: [ExtractedVerb]
    let lutrisRegistry: [ExtractedRegistry]
    let installerCount: Int

    // ProtonDB data
    let protonTier: String?
    let protonConfidence: String?
    let protonTotal: Int?
    let protonTrendingTier: String?

    var isEmpty: Bool {
        lutrisEnvVars.isEmpty &&
        lutrisDlls.isEmpty &&
        lutrisWinetricks.isEmpty &&
        lutrisRegistry.isEmpty &&
        protonTier == nil
    }

    func formatForAgent() -> String {
        var lines: [String] = []
        lines.append("--- COMPATIBILITY DATA ---")
        lines.append("Community compatibility data for '\(gameName)':")

        // ProtonDB section (omit if no tier)
        if let tier = protonTier {
            lines.append("")
            lines.append("## ProtonDB Rating")
            let confidence = protonConfidence ?? "unknown"
            let total = protonTotal.map { "\($0)" } ?? "unknown"
            lines.append("Tier: \(tier) (confidence: \(confidence), \(total) reports)")
            if let trending = protonTrendingTier {
                lines.append("Trending: \(trending)")
            }
        }

        // Lutris section (omit if no installers)
        if installerCount > 0 {
            lines.append("")
            lines.append("## Lutris Configuration (from \(installerCount) installer scripts)")

            lines.append("Environment variables:")
            if lutrisEnvVars.isEmpty {
                lines.append("  (none found)")
            } else {
                for v in lutrisEnvVars {
                    lines.append("  \(v.name)=\(v.value)")
                }
            }

            lines.append("DLL overrides:")
            if lutrisDlls.isEmpty {
                lines.append("  (none found)")
            } else {
                for dll in lutrisDlls {
                    lines.append("  \(dll.name) = \(dll.mode)")
                }
            }

            lines.append("Winetricks:")
            if lutrisWinetricks.isEmpty {
                lines.append("  (none found)")
            } else {
                let verbList = lutrisWinetricks.map { $0.verb }.joined(separator: ", ")
                lines.append("  \(verbList)")
            }

            lines.append("Registry edits:")
            if lutrisRegistry.isEmpty {
                lines.append("  (none found)")
            } else {
                for reg in lutrisRegistry {
                    let valStr = reg.value ?? "(no value)"
                    lines.append("  \(reg.path)  = \(valStr)")
                }
            }
        }

        lines.append("")
        lines.append("Note: ProtonDB reports are from Linux+Proton users. Config hints above are filtered for Wine/macOS compatibility.")
        lines.append("--- END COMPATIBILITY DATA ---")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Cache

private struct CompatibilityCache<T: Codable>: Codable {
    let fetchedAt: String
    let data: T

    func isStale(ttlDays: Int = 30) -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: fetchedAt) else { return true }
        let age = Date().timeIntervalSince(date)
        return age > Double(ttlDays) * 86400
    }
}

// MARK: - CompatibilityService

struct CompatibilityService {

    // MARK: - Public API

    /// Fetch a unified compatibility report for the given game name.
    /// Returns nil if the report is empty or if both APIs are unreachable.
    /// Never throws — all errors are swallowed.
    static func fetchReport(for gameName: String) -> CompatibilityReport? {
        // Step 1: Search Lutris for best game match
        guard let lutrisGame = fetchLutrisGame(name: gameName) else {
            return nil
        }

        // Step 2: Extract Steam AppID from providerGames
        let steamAppId = lutrisGame.providerGames
            .first(where: { $0.service == "steam" })
            .map { $0.slug }

        // Step 3: Parallel fetch of installers + ProtonDB summary
        final class ResultBox<T>: @unchecked Sendable { var value: T? }
        let installersBox = ResultBox<[LutrisInstaller]>()
        let protonBox = ResultBox<ProtonDBSummary>()

        let installerSemaphore = DispatchSemaphore(value: 0)
        let protonSemaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            installersBox.value = fetchLutrisInstallers(slug: lutrisGame.slug)
            installerSemaphore.signal()
        }

        DispatchQueue.global().async {
            if let appId = steamAppId {
                protonBox.value = fetchProtonDBSummary(appId: appId)
            }
            protonSemaphore.signal()
        }

        installerSemaphore.wait()
        protonSemaphore.wait()

        let installers = installersBox.value ?? []
        let protonSummary = protonBox.value

        // Step 4 & 5: Extract and filter config from installers
        let extracted = extractFromInstallers(installers)
        let filteredEnvVars = filterPortableEnvVars(extracted.envVars)

        // Step 6: Build report
        let report = CompatibilityReport(
            gameName: gameName,
            lutrisSlug: lutrisGame.slug,
            steamAppId: steamAppId,
            lutrisEnvVars: filteredEnvVars,
            lutrisDlls: extracted.dlls,
            lutrisWinetricks: extracted.verbs,
            lutrisRegistry: extracted.registry,
            installerCount: installers.count,
            protonTier: protonSummary?.tier,
            protonConfidence: protonSummary?.confidence,
            protonTotal: protonSummary?.total,
            protonTrendingTier: protonSummary?.trendingTier
        )

        // Step 7: Return nil if empty
        return report.isEmpty ? nil : report
    }

    // MARK: - Private Fetchers

    private static func fetchLutrisGame(name: String) -> LutrisGame? {
        let normalized = name.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let cacheFile = CellarPaths.lutrisCompatCacheDir.appendingPathComponent("\(normalized).json")

        if let cached: LutrisGame = readCache(LutrisGame.self, from: cacheFile, ttlDays: 30) {
            return cached
        }

        var urlComponents = URLComponents(string: "https://lutris.net/api/games")!
        urlComponents.queryItems = [URLQueryItem(name: "search", value: name)]
        guard let url = urlComponents.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, statusCode) = performFetch(request: request), statusCode == 200 else {
            return nil
        }

        guard let response = try? JSONDecoder().decode(LutrisSearchResponse.self, from: data) else {
            return nil
        }

        let queryTokens = normalizeGameName(name)
        var bestGame: LutrisGame?
        var bestScore = 0.3 // minimum threshold

        for game in response.results {
            let gameTokens = normalizeGameName(game.name)
            let score = jaccardSimilarity(queryTokens, gameTokens)
            if score > bestScore {
                bestScore = score
                bestGame = game
            }
        }

        if let best = bestGame {
            writeCache(best, to: cacheFile)
        }

        return bestGame
    }

    private static func fetchLutrisInstallers(slug: String) -> [LutrisInstaller] {
        let cacheFile = CellarPaths.lutrisCompatCacheDir.appendingPathComponent("installers-\(slug).json")

        if let cached: [LutrisInstaller] = readCache([LutrisInstaller].self, from: cacheFile, ttlDays: 30) {
            return cached
        }

        var urlComponents = URLComponents(string: "https://lutris.net/api/installers")!
        urlComponents.queryItems = [URLQueryItem(name: "game", value: slug)]
        guard let url = urlComponents.url else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let (data, statusCode) = performFetch(request: request), statusCode == 200 else {
            return []
        }

        guard let response = try? JSONDecoder().decode(LutrisInstallerResponse.self, from: data) else {
            return []
        }

        let installers = response.results
        writeCache(installers, to: cacheFile)
        return installers
    }

    private static func fetchProtonDBSummary(appId: String) -> ProtonDBSummary? {
        let cacheFile = CellarPaths.protondbCompatCacheDir.appendingPathComponent("\(appId).json")

        if let cached: ProtonDBSummary = readCache(ProtonDBSummary.self, from: cacheFile, ttlDays: 30) {
            return cached
        }

        guard let url = URL(string: "https://www.protondb.com/api/v1/reports/summaries/\(appId).json") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        guard let (data, statusCode) = performFetch(request: request), statusCode == 200 else {
            return nil
        }

        guard let summary = try? JSONDecoder().decode(ProtonDBSummary.self, from: data) else {
            return nil
        }

        writeCache(summary, to: cacheFile)
        return summary
    }

    // MARK: - Installer Extraction

    private static func extractFromInstallers(
        _ installers: [LutrisInstaller]
    ) -> (envVars: [ExtractedEnvVar], dlls: [ExtractedDLL], verbs: [ExtractedVerb], registry: [ExtractedRegistry]) {
        var seenEnvVarNames = Set<String>()
        var seenDllNames = Set<String>()
        var seenVerbs = Set<String>()
        var seenRegKeys = Set<String>()

        var envVars: [ExtractedEnvVar] = []
        var dlls: [ExtractedDLL] = []
        var verbs: [ExtractedVerb] = []
        var registry: [ExtractedRegistry] = []

        let wineInstallers = installers.filter { $0.runner == "wine" }

        for installer in wineInstallers {
            guard let script = installer.script else { continue }

            // Env vars from system.env
            if let env = script.system?.env {
                for (key, value) in env {
                    if !seenEnvVarNames.contains(key) {
                        seenEnvVarNames.insert(key)
                        envVars.append(ExtractedEnvVar(name: key, value: value, context: "lutris"))
                    }
                }
            }

            // DLL overrides from wine.overrides
            if let overrides = script.wine?.overrides {
                for (dllName, mode) in overrides {
                    if !seenDllNames.contains(dllName) {
                        seenDllNames.insert(dllName)
                        dlls.append(ExtractedDLL(name: dllName, mode: mode, context: "lutris"))
                    }
                }
            }

            // Winetricks verbs and registry from installer tasks
            if let tasks = script.installer {
                for task in tasks {
                    // Winetricks tasks
                    if task.name == "winetricks", let app = task.app {
                        let taskVerbs = app.split(separator: " ").map(String.init)
                        for verb in taskVerbs {
                            if !seenVerbs.contains(verb) {
                                seenVerbs.insert(verb)
                                verbs.append(ExtractedVerb(verb: verb, context: "lutris"))
                            }
                        }
                    }

                    // Registry edits
                    if task.name == "set_regedit", let key = task.key {
                        let regKey = "\(key)/\(task.value ?? "")"
                        if !seenRegKeys.contains(regKey) {
                            seenRegKeys.insert(regKey)
                            registry.append(ExtractedRegistry(path: key, value: task.value, context: "lutris"))
                        }
                    }
                }
            }
        }

        return (envVars: envVars, dlls: dlls, verbs: verbs, registry: registry)
    }

    // MARK: - Fuzzy Matching

    private static let stopWords: Set<String> = ["the", "a", "an", "of", "and"]

    private static func normalizeGameName(_ name: String) -> Set<String> {
        let lowercased = name.lowercased()
        // Strip punctuation by keeping only letters, digits, and spaces
        let cleaned = lowercased.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber || c == " " { return c }
            return " "
        }
        let cleanedString = String(cleaned)
        let tokens = cleanedString
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
        return Set(tokens)
    }

    private static func jaccardSimilarity(_ a: Set<String>, _ b: Set<String>) -> Double {
        if a.isEmpty && b.isEmpty { return 0.0 }
        let intersection = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0.0 }
        return Double(intersection) / Double(union)
    }

    // MARK: - Proton Flag Filtering

    private static let protonOnlyPrefixes = [
        "PROTON_",
        "STEAM_",
        "SteamAppId",
        "SteamGameId",
        "LD_PRELOAD",
        "WINEDLLPATH",
        "WINELOADERNOEXEC",
        "DXVK_FILTER_DEVICE_NAME"
    ]

    private static func filterPortableEnvVars(_ vars: [ExtractedEnvVar]) -> [ExtractedEnvVar] {
        vars.filter { envVar in
            !protonOnlyPrefixes.contains(where: { envVar.name.hasPrefix($0) })
        }
    }

    // MARK: - Cache Helpers

    private static func readCache<T: Codable>(_ type: T.Type, from file: URL, ttlDays: Int) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        guard let cache = try? JSONDecoder().decode(CompatibilityCache<T>.self, from: data) else { return nil }
        guard !cache.isStale(ttlDays: ttlDays) else { return nil }
        return cache.data
    }

    private static func writeCache<T: Codable>(_ data: T, to file: URL) {
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let cache = CompatibilityCache(fetchedAt: formatter.string(from: Date()), data: data)
        guard let encoded = try? JSONEncoder().encode(cache) else { return }
        try? encoded.write(to: file)
    }

    // MARK: - HTTP Helper

    private static func performFetch(request: URLRequest) -> (data: Data, statusCode: Int)? {
        final class ResultBox: @unchecked Sendable {
            var value: (Data, Int)?
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if error == nil,
               let data = data,
               let httpResponse = response as? HTTPURLResponse {
                box.value = (data, httpResponse.statusCode)
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return box.value
    }
}
