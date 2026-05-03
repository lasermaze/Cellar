import Foundation

/// Stateless service that pushes a working game configuration to the collective memory
/// via the Cloudflare Worker write proxy. The private key never ships with the binary.
///
/// The single public entry point is `push(record:gameName:wineURL:)`.
/// All errors are swallowed — the function returns without side effects when the proxy
/// is unreachable, returns an error status, or any network/encoding failure occurs.
struct CollectiveMemoryWriteService {

    // MARK: - Proxy URL

    /// Proxy URL for collective memory writes.
    /// Reads CELLAR_MEMORY_PROXY_URL from environment, falls back to production Worker.
    private static var proxyURL: String {
        ProcessInfo.processInfo.environment["CELLAR_MEMORY_PROXY_URL"]
            ?? "https://cellar-memory-proxy.sook40.workers.dev/api/contribute"
    }

    // MARK: - Public API

    /// Push a working game configuration to the collective memory repo via the proxy.
    /// Never throws. All errors are caught and logged internally.
    ///
    /// - Parameters:
    ///   - record: The locally-saved SuccessRecord to contribute.
    ///   - gameName: The display name of the game.
    ///   - wineURL: URL to the wine binary (used to detect Wine version and flavor).
    static func push(record: SuccessRecord, gameName: String, wineURL: URL) async {
        // Step 1: Detect Wine version
        guard let wineVersion = detectWineVersion(wineURL: wineURL) else {
            logPushEvent("WARN", gameId: record.gameId, "Could not detect Wine version, skipping push")
            return
        }

        // Step 2: Detect Wine flavor
        let wineFlavor = detectWineFlavor(wineURL: wineURL)

        // Step 3: Build environment fingerprint
        let fingerprint = EnvironmentFingerprint.current(wineVersion: wineVersion, wineFlavor: wineFlavor)
        let environmentHash = fingerprint.computeHash()

        // Step 4: Build ISO8601 timestamp
        let formatter = ISO8601DateFormatter()
        let lastConfirmed = formatter.string(from: Date())

        // Step 5: Transform SuccessRecord -> CollectiveMemoryEntry
        let workingConfig = WorkingConfig(
            environment: record.environment,
            dllOverrides: record.dllOverrides,
            registry: record.registry,
            launchArgs: [],
            setupDeps: []
        )

        let entry = CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: record.gameId,
            gameName: gameName,
            config: workingConfig,
            environment: fingerprint,
            environmentHash: environmentHash,
            reasoning: record.resolutionNarrative ?? "",
            engine: record.engine,
            graphicsApi: record.graphicsApi,
            confirmations: 1,
            lastConfirmed: lastConfirmed
        )

        // Step 6: POST to proxy
        await postToProxy(entry: entry)
    }

    /// Sync all local success records to collective memory via the proxy.
    /// Returns (synced, failed) counts.
    static func syncAll(wineURL: URL) async -> (synced: Int, failed: Int) {
        let config = CellarConfig.load()
        guard config.contributeMemory == true else {
            return (0, 0)
        }

        let records = SuccessDatabase.loadAll()
        guard !records.isEmpty else { return (0, 0) }

        var synced = 0, failed = 0

        for record in records {
            // Snapshot log line count before push to detect success
            let logFile = CellarPaths.logsDir.appendingPathComponent("memory-push.log")
            let lineCountBefore = (try? String(contentsOf: logFile, encoding: .utf8))?
                .components(separatedBy: "\n").count ?? 0

            await push(record: record, gameName: record.gameName, wineURL: wineURL)

            // Check if push logged a success line
            let logAfter = (try? String(contentsOf: logFile, encoding: .utf8)) ?? ""
            let linesAfter = logAfter.components(separatedBy: "\n")
            let newLines = linesAfter.dropFirst(max(0, lineCountBefore - 1))
            if newLines.contains(where: { $0.contains("Push succeeded") }) {
                synced += 1
            } else {
                failed += 1
            }
        }

        return (synced: synced, failed: failed)
    }

    // MARK: - Internal Static Shims (used by AIService after Task 1 rewire)

    /// Build a CollectiveMemoryEntry from a SuccessRecord for KnowledgeStore.write(.config).
    static func buildConfigEntry(record: SuccessRecord, gameName: String, wineURL: URL) -> CollectiveMemoryEntry? {
        guard let wineVersion = detectWineVersion(wineURL: wineURL) else { return nil }
        let wineFlavor = detectWineFlavor(wineURL: wineURL)
        let fingerprint = EnvironmentFingerprint.current(wineVersion: wineVersion, wineFlavor: wineFlavor)
        let environmentHash = fingerprint.computeHash()
        let formatter = ISO8601DateFormatter()
        let lastConfirmed = formatter.string(from: Date())
        let workingConfig = WorkingConfig(
            environment: record.environment,
            dllOverrides: record.dllOverrides,
            registry: record.registry,
            launchArgs: [],
            setupDeps: []
        )
        return CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: record.gameId,
            gameName: gameName,
            config: workingConfig,
            environment: fingerprint,
            environmentHash: environmentHash,
            reasoning: record.resolutionNarrative ?? "",
            engine: record.engine,
            graphicsApi: record.graphicsApi,
            confirmations: 1,
            lastConfirmed: lastConfirmed
        )
    }

    // MARK: - Private: Proxy POST

    /// POST entry JSON to the Cloudflare Worker proxy.
    private static func postToProxy(entry: CollectiveMemoryEntry) async {
        guard let url = URL(string: proxyURL) else {
            logPushEvent("ERROR", gameId: entry.gameId, "Invalid proxy URL: \(proxyURL)")
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Wrap in {"entry": ...} as expected by the Worker
        struct ProxyPayload: Encodable {
            let entry: CollectiveMemoryEntry
        }
        guard let bodyData = try? encoder.encode(ProxyPayload(entry: entry)) else {
            logPushEvent("ERROR", gameId: entry.gameId, "Failed to encode entry for proxy")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 10

        logPushEvent("INFO", gameId: entry.gameId, "POST \(url.absoluteString)")

        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else {
            fputs("[CollectiveMemoryWriteService] Network error posting to proxy for '\(entry.gameId)'\n", stderr)
            logPushEvent("ERROR", gameId: entry.gameId, "Network error on POST to proxy")
            return
        }

        switch http.statusCode {
        case 200, 201:
            logPushEvent("INFO", gameId: entry.gameId, "Push succeeded via proxy (HTTP \(http.statusCode))")
        case 429:
            fputs("[CollectiveMemoryWriteService] Rate limited by proxy for '\(entry.gameId)'\n", stderr)
            logPushEvent("WARN", gameId: entry.gameId, "Proxy rate limit (429) — skipping")
        default:
            fputs("[CollectiveMemoryWriteService] HTTP \(http.statusCode) from proxy for '\(entry.gameId)'\n", stderr)
            logPushEvent("WARN", gameId: entry.gameId, "Proxy returned HTTP \(http.statusCode)")
        }
    }

    // MARK: - Private: Wine Detection

    /// Run `wine --version` via Process and parse the version string.
    /// Returns nil on any failure.
    private static func detectWineVersion(wineURL: URL) -> String? {
        do {
            let process = Process()
            process.executableURL = wineURL
            process.arguments = ["--version"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: outputData, encoding: .utf8) else {
                return nil
            }

            // Parse "wine-9.0 (Staging)" or "wine-10.3"
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

    // MARK: - Private: Logging

    /// Append one line to ~/.cellar/logs/memory-push.log.
    private static func logPushEvent(_ level: String, gameId: String, _ message: String) {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) \(level) \(gameId) \(message)\n"

        guard let lineData = line.data(using: .utf8) else { return }

        let logsDir = CellarPaths.logsDir
        let logFile = logsDir.appendingPathComponent("memory-push.log")

        // Create logs directory if needed
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        // Append to log file (create if it does not exist)
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(lineData)
                try? handle.close()
            }
        } else {
            try? lineData.write(to: logFile, options: .atomic)
        }
    }
}
