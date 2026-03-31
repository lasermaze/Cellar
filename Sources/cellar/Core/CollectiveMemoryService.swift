import Foundation

/// Stateless service that fetches, filters, ranks, and formats collective memory entries
/// for a given game. The single public entry point is `fetchBestEntry(for:wineURL:)`.
///
/// All errors are swallowed — the function returns nil when no compatible entry is available,
/// when auth is not configured, or when any network/parsing failure occurs.
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
    ) -> String? {
        // Step 1: Auth check
        let authResult = GitHubAuthService.shared.getToken()
        guard case .token(let token) = authResult else {
            return nil
        }

        // Step 2: Detect local Wine version
        guard let localWineVersion = detectWineVersion(wineURL: wineURL) else {
            return nil
        }

        // Step 3: Detect Wine flavor
        let localFlavor = detectWineFlavor(wineURL: wineURL)

        // Step 4: Build GitHub Contents API request
        let slug = slugify(gameName)
        let urlString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries/\(slug).json"
        guard let url = URL(string: urlString) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        // Step 5: Synchronous fetch
        guard let (data, statusCode) = performFetch(request: request) else {
            return nil
        }

        // 404 = no entry yet, normal flow; any other 4xx/5xx = skip silently
        guard statusCode == 200 else {
            return nil
        }

        // Step 6: Decode entries array
        let entries: [CollectiveMemoryEntry]
        do {
            entries = try JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
        } catch {
            return nil
        }

        guard !entries.isEmpty else {
            return nil
        }

        // Step 7: Filter by arch (hard incompatible)
        #if arch(arm64)
        let localArch = "arm64"
        #else
        let localArch = "x86_64"
        #endif
        let archFiltered = entries.filter { $0.environment.arch == localArch }

        guard !archFiltered.isEmpty else {
            return nil
        }

        // Step 8: Score each entry by environment similarity
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

        // Step 9: Assess staleness and flavor mismatch for warnings
        let entryMajor = majorVersion(from: best.entry.environment.wineVersion) ?? 0
        let isStale = (localMajor - entryMajor) > 1
        let flavorMismatch = best.entry.environment.wineFlavor != localFlavor

        // Step 10: Pick fallback (second-best with a different config, if available)
        let fallback: CollectiveMemoryEntry? = ranked.dropFirst().first(where: { candidate in
            // Only include as fallback if it has a meaningfully different config
            candidate.entry.environmentHash != best.entry.environmentHash
        })?.entry

        // Step 11: Format and return context block
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

    /// Perform a synchronous HTTP fetch using DispatchSemaphore.
    /// Returns (data, statusCode) on any HTTP response, nil on network error.
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

        lines.append("")
        lines.append("Agent's Reasoning (from prior session):")
        lines.append("  \"\(entry.reasoning)\"")

        // Fallback entry — different config the agent can try if the best match fails
        if let fallback = fallback {
            lines.append("")
            lines.append("## Fallback Config")
            lines.append("Confirmations: \(fallback.confirmations) | Environment: \(fallback.environment.arch), Wine \(fallback.environment.wineVersion) (\(fallback.environment.wineFlavor)), macOS \(fallback.environment.macosVersion)")
            lines.append("")
            lines.append("Working Config:")
            lines.append(contentsOf: formatConfigBlock(fallback))
            if !fallback.reasoning.isEmpty {
                lines.append("")
                lines.append("Reasoning: \"\(fallback.reasoning)\"")
            }
        }

        lines.append("--- END COLLECTIVE MEMORY ---")

        return lines.joined(separator: "\n")
    }
}
