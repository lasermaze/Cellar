import Foundation

/// Stateless service that fetches, filters, ranks, and formats collective memory entries
/// for a given game. The single public entry point is `fetchBestEntry(for:wineURL:)`.
///
/// All errors are swallowed — the function returns nil when no compatible entry is available,
/// or when any network/parsing failure occurs. A local file cache at ~/.cellar/cache/memory/
/// provides offline resilience with a 1-hour TTL.
struct CollectiveMemoryService {

    // MARK: - Public API

    /// Fetch the best collective memory entry for a game and return a formatted context block,
    /// or nil if no compatible entry is available or any step fails.
    ///
    /// - Parameters:
    ///   - gameName: The display name of the game (used to build the slug for the file path).
    ///   - wineURL: URL to the wine binary (used to detect the local Wine version and flavor).
    /// - Returns: A formatted multi-line context block string, or nil.
    static func fetchBestEntry(
        for gameName: String,
        wineURL: URL
    ) async -> String? {
        // Step 1: Detect local Wine version
        guard let localWineVersion = detectWineVersion(wineURL: wineURL) else {
            fputs("[CollectiveMemoryService] Could not detect Wine version for environment fingerprint\n", stderr)
            return nil
        }

        // Step 2: Detect Wine flavor
        let localFlavor = detectWineFlavor(wineURL: wineURL)

        // Step 3: Build slug and cache path
        let slug = slugify(gameName)
        let cacheFile = CellarPaths.memoryCacheFile(for: slug)

        // Step 4: Serve from cache if fresh (< 1 hour old)
        if isCacheFresh(cacheFile), let cachedData = loadFromCache(cacheFile) {
            return decodeAndFormat(data: cachedData, gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor)
        }

        // Step 5: Build GitHub Contents API request (anonymous — public repo)
        let urlString = "https://api.github.com/repos/\(CellarPaths.memoryRepo)/contents/entries/\(slug).json"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        // Step 6: Async fetch
        guard let (data, statusCode) = await performFetch(request: request) else {
            fputs("[CollectiveMemoryService] Network error fetching collective memory for '\(gameName)'\n", stderr)
            // Fallback to stale cache on network error
            if let staleData = loadFromCache(cacheFile) {
                return decodeAndFormat(data: staleData, gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor)
            }
            return nil
        }

        // 404 = exact slug not found — try fuzzy match against repo listing
        // 403/429 = rate limited — serve stale cache
        guard statusCode == 200 else {
            if statusCode == 403 || statusCode == 429 {
                fputs("[CollectiveMemoryService] HTTP \(statusCode) (rate limited) — serving stale cache if available\n", stderr)
                if let staleData = loadFromCache(cacheFile) {
                    return decodeAndFormat(data: staleData, gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor)
                }
            } else if statusCode == 404 {
                // Try fuzzy match: list entries directory and find closest match
                if let matchedData = await fuzzyFetchEntry(gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor) {
                    return matchedData
                }
            } else {
                fputs("[CollectiveMemoryService] HTTP \(statusCode) fetching collective memory for '\(gameName)'\n", stderr)
            }
            return nil
        }

        // Step 7: Cache the successful response
        try? FileManager.default.createDirectory(at: CellarPaths.memoryCacheDir, withIntermediateDirectories: true)
        try? data.write(to: cacheFile, options: .atomic)

        // Step 8: Decode and format
        return decodeAndFormat(data: data, gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor)
    }

    // MARK: - Fuzzy Match

    /// When exact slug doesn't match (404), list entries/ directory and find closest match by word overlap.
    private static func fuzzyFetchEntry(gameName: String, localWineVersion: String, localFlavor: String) async -> String? {
        let listURL = "https://api.github.com/repos/\(CellarPaths.memoryRepo)/contents/entries"
        guard let url = URL(string: listURL) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        guard let (data, statusCode) = await performFetch(request: request), statusCode == 200 else {
            return nil
        }

        // Parse directory listing — array of objects with "name" field
        struct GHFile: Decodable { let name: String }
        guard let files = try? JSONDecoder().decode([GHFile].self, from: data) else { return nil }

        let entryNames = files.compactMap { f -> String? in
            f.name.hasSuffix(".json") ? String(f.name.dropLast(5)) : nil  // strip .json
        }

        // Score each entry name against the game name using word overlap
        let queryWords = SuccessDatabase.extractGameWords(slugify(gameName))
        guard !queryWords.isEmpty else { return nil }

        let bestMatch = entryNames.map { entrySlug -> (String, Double) in
            let entryWords = SuccessDatabase.extractGameWords(entrySlug)
            let overlap = queryWords.filter { word in
                entryWords.contains { $0.contains(word) || word.contains($0) }
            }
            let score = Double(overlap.count) / Double(queryWords.count)
            return (entrySlug, score)
        }
        .filter { $0.1 >= 0.5 }
        .sorted { $0.1 > $1.1 }
        .first

        guard let (matchedSlug, _) = bestMatch else { return nil }

        // Fetch the matched entry
        let matchURL = "https://api.github.com/repos/\(CellarPaths.memoryRepo)/contents/entries/\(matchedSlug).json"
        guard let matchRequestURL = URL(string: matchURL) else { return nil }

        var matchRequest = URLRequest(url: matchRequestURL)
        matchRequest.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        matchRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        matchRequest.timeoutInterval = 5

        guard let (matchData, matchStatus) = await performFetch(request: matchRequest), matchStatus == 200 else {
            return nil
        }

        // Cache under the original slug for next time
        let cacheFile = CellarPaths.memoryCacheFile(for: slugify(gameName))
        try? FileManager.default.createDirectory(at: CellarPaths.memoryCacheDir, withIntermediateDirectories: true)
        try? matchData.write(to: cacheFile, options: .atomic)

        return decodeAndFormat(data: matchData, gameName: gameName, localWineVersion: localWineVersion, localFlavor: localFlavor)
    }

    // MARK: - Private Cache Helpers

    /// Returns true if the cache file exists and was modified less than 3600 seconds ago.
    private static func isCacheFresh(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return false
        }
        return Date().timeIntervalSince(modDate) < 3600
    }

    /// Read cache file contents, returning nil on any failure.
    private static func loadFromCache(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    // MARK: - Private Decode + Format Helper

    /// Decode, filter, score, rank, and format a collective memory JSON payload.
    /// Returns nil if the data is malformed, empty, or has no arch-compatible entries.
    private static func decodeAndFormat(
        data: Data,
        gameName: String,
        localWineVersion: String,
        localFlavor: String
    ) -> String? {
        // Decode entries array
        let entries: [CollectiveMemoryEntry]
        do {
            entries = try JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
        } catch {
            fputs("[CollectiveMemoryService] Failed to decode collective memory JSON for '\(gameName)'\n", stderr)
            return nil
        }

        guard !entries.isEmpty else {
            return nil
        }

        // Filter by arch (hard incompatible)
        #if arch(arm64)
        let localArch = "arm64"
        #else
        let localArch = "x86_64"
        #endif
        let archFiltered = entries.filter { $0.environment.arch == localArch }

        guard !archFiltered.isEmpty else {
            return nil
        }

        // Score each entry by environment similarity
        let localMajor = majorVersion(from: localWineVersion) ?? 0
        let localMacosMajor = macosMajorVersion()

        let scored: [(entry: CollectiveMemoryEntry, score: Int)] = archFiltered.map { entry in
            var score = 0

            // Wine flavor match (40 pts) — GPTK vs vanilla is the hardest incompatibility
            if entry.environment.wineFlavor == localFlavor {
                score += 40
            }

            // Wine version proximity (30 pts max)
            let entryWineMajor = majorVersion(from: entry.environment.wineVersion) ?? 0
            let wineDist = abs(localMajor - entryWineMajor)
            switch wineDist {
            case 0: score += 30
            case 1: score += 20
            case 2: score += 10
            default: break
            }

            // macOS version proximity (20 pts max)
            let entryMacosMajor = majorVersion(from: entry.environment.macosVersion) ?? 0
            let macosDist = abs(localMacosMajor - entryMacosMajor)
            switch macosDist {
            case 0: score += 20
            case 1: score += 10
            default: break
            }

            // Confirmations (10 pts max) — tiebreaker, not dominant
            score += min(entry.confirmations, 5) * 2

            return (entry: entry, score: score)
        }

        let ranked = scored.sorted { $0.score > $1.score }
        let best = ranked[0]

        // Assess staleness and flavor mismatch for warnings
        let entryMajor = majorVersion(from: best.entry.environment.wineVersion) ?? 0
        let isStale = (localMajor - entryMajor) > 1
        let flavorMismatch = best.entry.environment.wineFlavor != localFlavor

        // Pick fallback (second-best with a different config, if available)
        let fallback: CollectiveMemoryEntry? = ranked.dropFirst().first(where: { candidate in
            candidate.entry.environmentHash != best.entry.environmentHash
        })?.entry

        // Format and return context block
        return formatMemoryContext(
            best.entry,
            score: best.score,
            isStale: isStale,
            flavorMismatch: flavorMismatch,
            localWineVersion: localWineVersion,
            localFlavor: localFlavor,
            fallback: fallback,
            totalEntries: archFiltered.count
        )
    }

    // MARK: - Private Helpers

    /// Run `wine --version` via Process and parse the version string.
    /// Returns nil on any failure.
    private static func detectWineVersion(wineURL: URL) -> String? {
        do {
            let process = Process()
            process.executableURL = wineURL
            process.arguments = ["--version"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // discard stderr

            try process.run()
            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8) else {
                return nil
            }

            // Parse "wine-9.0 (Staging)" or "wine-10.3"
            // Split on "-", drop first component ("wine"), take remainder joined, split on " ", take first
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let dashParts = trimmed.split(separator: "-", maxSplits: 1)
            guard dashParts.count >= 2 else {
                return nil
            }
            let afterWine = String(dashParts[1])
            let spaceParts = afterWine.split(separator: " ")
            guard let first = spaceParts.first else {
                return nil
            }
            let version = String(first)
            return version.isEmpty ? nil : version
        } catch {
            return nil
        }
    }

    /// Detect Wine flavor by checking for GPTK binary presence.
    private static func detectWineFlavor(wineURL: URL) -> String {
        let gptkPaths = [
            "/usr/local/bin/gameportingtoolkit",
            "/opt/homebrew/bin/gameportingtoolkit"
        ]
        for path in gptkPaths {
            if FileManager.default.fileExists(atPath: path) {
                return "game-porting-toolkit"
            }
        }
        return "wine-stable"
    }

    /// Extract the major version integer from a version string like "9.0", "10.3", or "15.3.1".
    private static func majorVersion(from versionString: String) -> Int? {
        let noParens = versionString.split(separator: " ").first.map(String.init) ?? versionString
        let dotParts = noParens.split(separator: ".")
        guard let first = dotParts.first else {
            return nil
        }
        return Int(first)
    }

    /// Returns the local macOS major version (e.g. 15 for macOS 15.3).
    private static func macosMajorVersion() -> Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// Perform an async HTTP fetch.
    /// Returns (data, statusCode) on any HTTP response, nil on network error.
    private static func performFetch(request: URLRequest) async -> (data: Data, statusCode: Int)? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            return nil
        }
        return (data, http.statusCode)
    }

    /// Format a single entry's config block (shared between best and fallback).
    private static func formatConfigBlock(_ entry: CollectiveMemoryEntry) -> [String] {
        var lines: [String] = []

        // Environment variables
        lines.append("  Environment variables:")
        if entry.config.environment.isEmpty {
            lines.append("    (none)")
        } else {
            for (key, value) in entry.config.environment.sorted(by: { $0.key < $1.key }) {
                lines.append("    \(key)=\(value)")
            }
        }

        // DLL overrides
        lines.append("  DLL overrides:")
        if entry.config.dllOverrides.isEmpty {
            lines.append("    (none)")
        } else {
            for override in entry.config.dllOverrides {
                let sourcePart = override.source.map { " (\($0))" } ?? ""
                lines.append("    \(override.dll) -> \(override.mode)\(sourcePart)")
            }
        }

        // Registry
        lines.append("  Registry:")
        if entry.config.registry.isEmpty {
            lines.append("    (none)")
        } else {
            for record in entry.config.registry {
                lines.append("    \(record.key) \(record.valueName) = \(record.data)")
            }
        }

        // Launch args
        let launchArgsStr = entry.config.launchArgs.isEmpty ? "(none)" : entry.config.launchArgs.joined(separator: " ")
        lines.append("  Launch args: \(launchArgsStr)")

        // Setup deps
        let setupDepsStr = entry.config.setupDeps.isEmpty ? "(none)" : entry.config.setupDeps.joined(separator: ", ")
        lines.append("  Setup deps: \(setupDepsStr)")

        return lines
    }

    /// Sanitize a collective memory entry by validating and truncating all injectable fields.
    /// Drops disallowed env keys, invalid DLL modes, and registry keys with unexpected prefixes.
    /// Logs dropped values to stderr without blocking.
    static func sanitizeEntry(_ entry: CollectiveMemoryEntry) -> CollectiveMemoryEntry {
        // Sanitize environment: filter against allowlist, truncate values to 200 chars
        let sanitizedEnv = entry.config.environment.reduce(into: [String: String]()) { result, pair in
            let (key, value) = pair
            guard AgentTools.allowedEnvKeys.contains(key) else {
                fputs("[CollectiveMemoryService] Dropping disallowed env key: \(key)\n", stderr)
                return
            }
            result[key] = String(value.prefix(200))
        }

        // Sanitize DLL overrides: validate mode, truncate dll/source fields
        let validDLLModes: Set<String> = ["n", "b", "n,b", "b,n", ""]
        let sanitizedDLLOverrides = entry.config.dllOverrides.compactMap { override -> DLLOverrideRecord? in
            guard validDLLModes.contains(override.mode) else {
                fputs("[CollectiveMemoryService] Dropping DLL override with invalid mode '\(override.mode)' for '\(override.dll)'\n", stderr)
                return nil
            }
            return DLLOverrideRecord(
                dll: String(override.dll.prefix(50)),
                mode: override.mode,
                placement: override.placement,
                source: override.source.map { String($0.prefix(100)) }
            )
        }

        // Sanitize registry: validate HKEY prefix, truncate fields
        let allowedRegistryPrefixes = PolicyResources.shared.registryAllowlist
        let sanitizedRegistry = entry.config.registry.compactMap { record -> RegistryRecord? in
            let truncatedKey = String(record.key.prefix(200))
            guard allowedRegistryPrefixes.contains(where: { truncatedKey.hasPrefix($0) }) else {
                fputs("[CollectiveMemoryService] Dropping registry record with disallowed key prefix: \(record.key)\n", stderr)
                return nil
            }
            return RegistryRecord(
                key: truncatedKey,
                valueName: String(record.valueName.prefix(100)),
                data: String(record.data.prefix(200)),
                purpose: record.purpose
            )
        }

        // Sanitize launch args: max 5 entries, each max 100 chars
        let sanitizedLaunchArgs = Array(entry.config.launchArgs.prefix(5)).map { String($0.prefix(100)) }

        // Sanitize setupDeps: filter against known winetricks verbs
        let sanitizedSetupDeps = entry.config.setupDeps.filter { AIService.agentValidWinetricksVerbs.contains($0) }

        let sanitizedConfig = WorkingConfig(
            environment: sanitizedEnv,
            dllOverrides: sanitizedDLLOverrides,
            registry: sanitizedRegistry,
            launchArgs: sanitizedLaunchArgs,
            setupDeps: sanitizedSetupDeps
        )

        return CollectiveMemoryEntry(
            schemaVersion: entry.schemaVersion,
            gameId: entry.gameId,
            gameName: entry.gameName,
            config: sanitizedConfig,
            environment: entry.environment,
            environmentHash: entry.environmentHash,
            reasoning: entry.reasoning,
            engine: entry.engine,
            graphicsApi: entry.graphicsApi,
            confirmations: entry.confirmations,
            lastConfirmed: entry.lastConfirmed
        )
    }

    /// Build the formatted collective memory context block for agent injection.
    private static func formatMemoryContext(
        _ entry: CollectiveMemoryEntry,
        score: Int,
        isStale: Bool,
        flavorMismatch: Bool,
        localWineVersion: String,
        localFlavor: String,
        fallback: CollectiveMemoryEntry?,
        totalEntries: Int
    ) -> String {
        // Sanitize entries before any formatting — strips injection vectors
        let entry = sanitizeEntry(entry)
        let fallback = fallback.map { sanitizeEntry($0) }

        var lines: [String] = []

        lines.append("--- COLLECTIVE MEMORY ---")
        lines.append("A community-verified configuration exists for this game (\(totalEntries) config(s) on file for your arch). The best match for your system is shown first.")
        lines.append("")
        lines.append("## Best Match (score \(score)/100)")
        lines.append("Confirmations: \(entry.confirmations) | Environment: \(entry.environment.arch), Wine \(entry.environment.wineVersion) (\(entry.environment.wineFlavor)), macOS \(entry.environment.macosVersion)")

        if flavorMismatch {
            lines.append("[FLAVOR WARNING: Entry was verified with \(entry.environment.wineFlavor); local Wine flavor is \(localFlavor). Config may still apply.]")
        }

        if isStale {
            let entryMajor = majorVersion(from: entry.environment.wineVersion) ?? 0
            let localMajor = majorVersion(from: localWineVersion) ?? 0
            let diff = localMajor - entryMajor
            lines.append("[STALENESS WARNING: Entry confirmed on Wine \(entryMajor).x; current Wine is \(localMajor).x (\(diff) major versions ahead). Verify compatibility.]")
        }

        lines.append("")
        lines.append("Working Config:")
        lines.append(contentsOf: formatConfigBlock(entry))

        // Fallback entry — different config the agent can try if the best match fails
        if let fallback = fallback {
            lines.append("")
            lines.append("## Fallback Config")
            lines.append("Confirmations: \(fallback.confirmations) | Environment: \(fallback.environment.arch), Wine \(fallback.environment.wineVersion) (\(fallback.environment.wineFlavor)), macOS \(fallback.environment.macosVersion)")
            lines.append("")
            lines.append("Working Config:")
            lines.append(contentsOf: formatConfigBlock(fallback))
        }

        lines.append("--- END COLLECTIVE MEMORY ---")

        return lines.joined(separator: "\n")
    }
}
