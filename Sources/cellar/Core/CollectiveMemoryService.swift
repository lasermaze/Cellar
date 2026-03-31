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

        // Step 8: Rank — highest confirmations, tiebreak by Wine version proximity
        let localMajor = majorVersion(from: localWineVersion) ?? 0
        let ranked = archFiltered.sorted { a, b in
            if a.confirmations != b.confirmations { return a.confirmations > b.confirmations }
            let aMaj = majorVersion(from: a.environment.wineVersion) ?? 0
            let bMaj = majorVersion(from: b.environment.wineVersion) ?? 0
            return abs(aMaj - localMajor) < abs(bMaj - localMajor)
        }
        let best = ranked[0]

        // Step 9: Assess staleness and flavor mismatch
        let entryMajor = majorVersion(from: best.environment.wineVersion) ?? 0
        let isStale = (localMajor - entryMajor) > 1
        let flavorMismatch = best.environment.wineFlavor != localFlavor

        // Step 10: Format and return context block
        return formatMemoryContext(
            best,
            isStale: isStale,
            flavorMismatch: flavorMismatch,
            localWineVersion: localWineVersion,
            localFlavor: localFlavor
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

    /// Extract the major version integer from a version string like "9.0" or "10.3".
    private static func majorVersion(from versionString: String) -> Int? {
        let noParens = versionString.split(separator: " ").first.map(String.init) ?? versionString
        let dotParts = noParens.split(separator: ".")
        guard let first = dotParts.first else {
            return nil
        }
        return Int(first)
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

    /// Build the formatted collective memory context block for agent injection.
    private static func formatMemoryContext(
        _ entry: CollectiveMemoryEntry,
        isStale: Bool,
        flavorMismatch: Bool,
        localWineVersion: String,
        localFlavor: String
    ) -> String {
        var lines: [String] = []

        lines.append("--- COLLECTIVE MEMORY ---")
        lines.append("A community-verified configuration exists for this game. Try it first before researching from scratch.")
        lines.append("")
        lines.append("Confirmations: \(entry.confirmations) | Verified environment: \(entry.environment.arch), Wine \(entry.environment.wineVersion), macOS \(entry.environment.macosVersion)")

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

        lines.append("")
        lines.append("Agent's Reasoning (from prior session):")
        lines.append("  \"\(entry.reasoning)\"")
        lines.append("--- END COLLECTIVE MEMORY ---")

        return lines.joined(separator: "\n")
    }
}
