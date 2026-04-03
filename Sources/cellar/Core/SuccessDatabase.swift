import Foundation

// MARK: - Success Record Schema

/// Executable binary metadata captured at verification time.
struct ExecutableInfo: Codable {
    let path: String
    let type: String       // "PE32", "PE32+"
    let peImports: [String]?
}

/// Working directory requirement for the game.
struct WorkingDirectoryInfo: Codable {
    let requirement: String  // "must_be_exe_parent", "any"
    let notes: String?
}

/// A DLL override applied via WINEDLLOVERRIDES or registry.
struct DLLOverrideRecord: Codable {
    let dll: String
    let mode: String       // "n,b", "native", "builtin"
    let placement: String? // "game_dir", "system32", "syswow64"
    let source: String?    // "cnc-ddraw", "manual"
}

/// A game configuration file that was modified or is required.
struct GameConfigFile: Codable {
    let path: String       // relative to game dir
    let purpose: String
    let criticalSettings: [String: String]?
}

/// A Wine registry entry that was set for the game.
struct RegistryRecord: Codable {
    let key: String
    let valueName: String
    let data: String
    let purpose: String?
}

/// A game-specific DLL placed from an external source.
struct GameSpecificDLL: Codable {
    let filename: String
    let source: String     // "cnc-ddraw", "dgvoodoo2"
    let placement: String  // "game_dir", "syswow64"
    let version: String?
}

/// A pitfall encountered during setup and how it was resolved.
struct PitfallRecord: Codable {
    let symptom: String
    let cause: String
    let fix: String
    let wrongFix: String?
}

/// Comprehensive record of a working game configuration.
/// Stored as JSON in ~/.cellar/successdb/<gameId>.json.
struct SuccessRecord: Codable {
    let schemaVersion: Int       // 1
    let gameId: String
    let gameName: String
    let gameVersion: String?
    let source: String?          // "gog", "steam"
    let engine: String?
    let graphicsApi: String?     // "directdraw", "direct3d8"
    let verifiedAt: String       // ISO8601 string
    let wineVersion: String?
    let bottleType: String?      // "wow64", "standard"
    let os: String?
    let executable: ExecutableInfo
    let workingDirectory: WorkingDirectoryInfo?
    let environment: [String: String]
    let dllOverrides: [DLLOverrideRecord]
    let gameConfigFiles: [GameConfigFile]
    let registry: [RegistryRecord]
    let gameSpecificDlls: [GameSpecificDLL]
    let pitfalls: [PitfallRecord]
    let resolutionNarrative: String?
    let tags: [String]
}

// MARK: - Success Database

/// File-backed success database stored in ~/.cellar/successdb/.
/// Provides CRUD operations and query methods for success records.
struct SuccessDatabase {

    /// Load a success record for a specific game.
    static func load(gameId: String) -> SuccessRecord? {
        let url = CellarPaths.successdbFile(for: gameId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SuccessRecord.self, from: data)
    }

    /// Save a success record (overwrites existing).
    static func save(_ record: SuccessRecord) throws {
        try FileManager.default.createDirectory(
            at: CellarPaths.successdbDir,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(record)
        try data.write(to: CellarPaths.successdbFile(for: record.gameId), options: .atomic)
    }

    /// Load all success records (in-memory scan for queries).
    static func loadAll() -> [SuccessRecord] {
        let dir = CellarPaths.successdbDir
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(SuccessRecord.self, from: data)
        }
    }

    /// Query by game_id — tries exact match first, then fuzzy substring match across all records.
    static func queryByGameId(_ gameId: String) -> SuccessRecord? {
        // 1. Exact match
        if let exact = load(gameId: gameId) { return exact }

        // 2. Fuzzy match: extract meaningful words from the query (strip version numbers, prefixes)
        let queryWords = extractGameWords(gameId)
        guard !queryWords.isEmpty else { return nil }

        // 3. Score all records by word overlap
        let candidates = loadAll().map { record -> (SuccessRecord, Double) in
            let recordWords = extractGameWords(record.gameId)
                + extractGameWords(record.gameName)
            let overlap = queryWords.filter { word in
                recordWords.contains { $0.contains(word) || word.contains($0) }
            }
            let score = queryWords.isEmpty ? 0 : Double(overlap.count) / Double(queryWords.count)
            return (record, score)
        }
        .filter { $0.1 >= 0.5 }  // at least 50% word overlap
        .sorted { $0.1 > $1.1 }

        return candidates.first?.0
    }

    /// Extract meaningful words from a game identifier, stripping version numbers and common prefixes.
    private static func extractGameWords(_ input: String) -> [String] {
        let lowered = input.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")

        // Strip common installer prefixes
        let stripped = lowered
            .replacingOccurrences(of: "setup ", with: "")
            .replacingOccurrences(of: "install ", with: "")

        return stripped.split(separator: " ")
            .map(String.init)
            .filter { word in
                // Skip version numbers (e.g., "2007", "1630", "v1", "10")
                guard word.count > 1 else { return false }
                if word.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
                if word.hasPrefix("v") && word.dropFirst().allSatisfy({ $0.isNumber || $0 == "." }) { return false }
                // Skip noise words
                let noise: Set<String> = ["the", "of", "and", "gog", "goty", "edition", "revision", "exe", "bin"]
                return !noise.contains(word)
            }
    }

    /// Query by tags (any overlap).
    static func queryByTags(_ tags: [String]) -> [SuccessRecord] {
        let lowerTags = Set(tags.map { $0.lowercased() })
        return loadAll().filter { record in
            !Set(record.tags.map { $0.lowercased() }).isDisjoint(with: lowerTags)
        }
    }

    /// Query by engine (substring match).
    static func queryByEngine(_ engine: String) -> [SuccessRecord] {
        let lower = engine.lowercased()
        return loadAll().filter {
            $0.engine?.lowercased().contains(lower) == true
        }
    }

    /// Query by graphics API (substring match).
    static func queryByGraphicsApi(_ api: String) -> [SuccessRecord] {
        let lower = api.lowercased()
        return loadAll().filter {
            $0.graphicsApi?.lowercased().contains(lower) == true
        }
    }

    /// Query by symptom using keyword overlap fuzzy matching.
    /// Returns records sorted by relevance score (descending).
    static func queryBySymptom(_ symptom: String) -> [(record: SuccessRecord, score: Double)] {
        let queryWords = Set(symptom.lowercased().split(separator: " ").map(String.init)
            .filter { $0.count > 2 })  // skip tiny words
        guard !queryWords.isEmpty else { return [] }

        return loadAll().flatMap { record in
            record.pitfalls.map { pitfall -> (SuccessRecord, Double) in
                let symptomWords = Set(pitfall.symptom.lowercased().split(separator: " ")
                    .map(String.init).filter { $0.count > 2 })
                let overlap = queryWords.intersection(symptomWords).count
                let maxWords = max(queryWords.count, symptomWords.count)
                let score = maxWords > 0 ? Double(overlap) / Double(maxWords) : 0
                return (record, score)
            }
        }
        .filter { $0.1 > 0.3 }
        .sorted { $0.1 > $1.1 }
    }

    /// Query by multi-signal similarity. Returns records ranked by overlap score.
    /// Requires at least engine OR graphicsApi match for a result to be included.
    static func queryBySimilarity(
        engine: String?,
        graphicsApi: String?,
        tags: [String],
        symptom: String?
    ) -> [(record: SuccessRecord, score: Int)] {
        let allRecords = loadAll()

        let scored: [(record: SuccessRecord, score: Int)] = allRecords.compactMap { record in
            var score = 0

            // Engine match (strongest signal, weight 3)
            if let engine = engine, let recordEngine = record.engine,
               recordEngine.lowercased().contains(engine.lowercased()) {
                score += 3
            }

            // Graphics API match (strong signal, weight 2)
            if let api = graphicsApi, let recordApi = record.graphicsApi,
               recordApi.lowercased().contains(api.lowercased()) {
                score += 2
            }

            // Require at least engine OR graphics API match
            guard score > 0 else { return nil }

            // Tag overlap (weight 1 each)
            let lowerTags = Set(tags.map { $0.lowercased() })
            let recordTags = Set(record.tags.map { $0.lowercased() })
            score += lowerTags.intersection(recordTags).count

            // Symptom match (weight 1)
            if let symptom = symptom {
                let queryWords = Set(symptom.lowercased().split(separator: " ")
                    .map(String.init).filter { $0.count > 2 })
                for pitfall in record.pitfalls {
                    let pitfallWords = Set(pitfall.symptom.lowercased().split(separator: " ")
                        .map(String.init).filter { $0.count > 2 })
                    if !queryWords.intersection(pitfallWords).isEmpty {
                        score += 1
                        break
                    }
                }
            }

            return (record: record, score: score)
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(5))
    }
}
