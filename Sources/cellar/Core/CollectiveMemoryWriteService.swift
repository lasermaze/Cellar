import Foundation

/// Stateless service that pushes a working game configuration to the collective memory GitHub repo.
/// The single public entry point is `push(record:gameName:wineURL:)`.
///
/// All errors are swallowed — the function returns without side effects when auth is unavailable,
/// when any network/parsing failure occurs, or when a conflict cannot be resolved after one retry.
struct CollectiveMemoryWriteService {

    // MARK: - Public API

    /// Push a working game configuration to the collective memory repo.
    /// Never throws. All errors are caught and logged internally.
    ///
    /// - Parameters:
    ///   - record: The locally-saved SuccessRecord to contribute.
    ///   - gameName: The display name of the game.
    ///   - wineURL: URL to the wine binary (used to detect Wine version and flavor).
    static func push(record: SuccessRecord, gameName: String, wineURL: URL) {
        // Step 1: Auth check
        let authResult = GitHubAuthService.shared.getToken()
        guard case .token(let token) = authResult else {
            // Auth not configured — silent skip
            return
        }

        // Step 2: Detect Wine version
        guard let wineVersion = detectWineVersion(wineURL: wineURL) else {
            logPushEvent("WARN", gameId: record.gameId, "Could not detect Wine version, skipping push")
            return
        }

        // Step 3: Detect Wine flavor
        let wineFlavor = detectWineFlavor(wineURL: wineURL)

        // Step 4: Build environment fingerprint
        let fingerprint = EnvironmentFingerprint.current(wineVersion: wineVersion, wineFlavor: wineFlavor)
        let environmentHash = fingerprint.computeHash()

        // Step 5: Build ISO8601 timestamp
        let formatter = ISO8601DateFormatter()
        let lastConfirmed = formatter.string(from: Date())

        // Step 6: Transform SuccessRecord -> CollectiveMemoryEntry
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

        // Step 7: Push to GitHub
        do {
            try pushEntry(entry: entry, token: token)
        } catch {
            fputs("[CollectiveMemoryWriteService] Push failed for '\(record.gameId)': \(error)\n", stderr)
            logPushEvent("ERROR", gameId: record.gameId, "Push failed: \(error)")
        }
    }

    /// Sync all local success records to collective memory.
    /// The write service handles deduplication: same environmentHash increments
    /// confirmations, different hash appends a new entry, new game creates the file.
    /// Returns (synced, failed) counts.
    static func syncAll(wineURL: URL) -> (synced: Int, failed: Int) {
        let config = CellarConfig.load()
        guard config.contributeMemory == true else {
            return (0, 0)
        }

        let authResult = GitHubAuthService.shared.getToken()
        guard case .token = authResult else {
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

            push(record: record, gameName: record.gameName, wineURL: wineURL)

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

    // MARK: - Private: GitHub Contents API Flow

    /// GET + merge + PUT flow against GitHub Contents API.
    /// Throws on unrecoverable errors; caller wraps in do/catch.
    private static func pushEntry(entry: CollectiveMemoryEntry, token: String) throws {
        let slug = slugify(entry.gameName)
        let urlString = "https://api.github.com/repos/\(GitHubAuthService.shared.memoryRepo)/contents/entries/\(slug).json"
        guard let url = URL(string: urlString) else {
            logPushEvent("ERROR", gameId: entry.gameId, "Invalid URL for slug: \(slug)")
            return
        }

        // First attempt
        let firstAttempt = performMergeAndPut(entry: entry, token: token, url: url)
        if firstAttempt == .ok { return }

        // 409 conflict: one retry
        if firstAttempt == .conflict {
            logPushEvent("INFO", gameId: entry.gameId, "409 conflict on first PUT, retrying with re-fetch")
            let retryResult = performMergeAndPut(entry: entry, token: token, url: url)
            if retryResult == .conflict {
                logPushEvent("WARN", gameId: entry.gameId, "409 conflict on retry, giving up")
            }
            // Otherwise ok or error — both handled internally
        }
        // .error is logged inside performMergeAndPut already
    }

    private enum MergeResult { case ok, conflict, error }

    /// Perform a single GET → merge → PUT cycle. Returns result type.
    private static func performMergeAndPut(
        entry: CollectiveMemoryEntry,
        token: String,
        url: URL
    ) -> MergeResult {
        // GET with standard JSON Accept (returns sha + base64 content)
        var getRequest = URLRequest(url: url)
        getRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        getRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        getRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        getRequest.timeoutInterval = 5

        let sha: String?
        var mergedEntries: [CollectiveMemoryEntry]
        var commitMessage: String

        logPushEvent("INFO", gameId: entry.gameId, "GET \(url.absoluteString)")
        if let (data, statusCode) = performRequest(request: getRequest) {
            logPushEvent("INFO", gameId: entry.gameId, "GET status: \(statusCode)")
            switch statusCode {
            case 200:
                // Decode existing file
                guard let contentsResponse = try? JSONDecoder().decode(GitHubContentsResponse.self, from: data) else {
                    logPushEvent("ERROR", gameId: entry.gameId, "Failed to decode GitHub contents response")
                    return .error
                }
                sha = contentsResponse.sha

                // Decode base64 (GitHub wraps at 60 chars per RFC 2045 — strip newlines first)
                let cleanBase64 = contentsResponse.content.replacingOccurrences(of: "\n", with: "")
                guard let fileData = Data(base64Encoded: cleanBase64),
                      let existingEntries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: fileData) else {
                    logPushEvent("ERROR", gameId: entry.gameId, "Failed to decode existing entries")
                    return .error
                }

                // Merge: find by environmentHash
                if let idx = existingEntries.firstIndex(where: { $0.environmentHash == entry.environmentHash }) {
                    // Increment confirmation
                    let existing = existingEntries[idx]
                    let formatter = ISO8601DateFormatter()
                    let updated = CollectiveMemoryEntry(
                        schemaVersion: existing.schemaVersion,
                        gameId: existing.gameId,
                        gameName: existing.gameName,
                        config: existing.config,
                        environment: existing.environment,
                        environmentHash: existing.environmentHash,
                        reasoning: existing.reasoning,
                        engine: existing.engine,
                        graphicsApi: existing.graphicsApi,
                        confirmations: existing.confirmations + 1,
                        lastConfirmed: formatter.string(from: Date())
                    )
                    var entries = existingEntries
                    entries[idx] = updated
                    mergedEntries = entries
                    commitMessage = "Update \(entry.gameName) (+1 confirmation)"
                } else {
                    // Append new environment entry
                    mergedEntries = existingEntries + [entry]
                    commitMessage = "Update \(entry.gameName) (new environment)"
                }

            case 404:
                // New file
                sha = nil
                mergedEntries = [entry]
                commitMessage = "Add \(entry.gameName) entry"

            default:
                logPushEvent("WARN", gameId: entry.gameId, "Unexpected GET status: \(statusCode)")
                return .error
            }
        } else {
            fputs("[CollectiveMemoryWriteService] Network error during push for '\(entry.gameId)'\n", stderr)
            logPushEvent("ERROR", gameId: entry.gameId, "Network error on GET")
            return .error
        }

        // Encode entries array to base64
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let fileData = try? encoder.encode(mergedEntries) else {
            fputs("[CollectiveMemoryWriteService] Failed to encode entry for '\(entry.gameId)'\n", stderr)
            logPushEvent("ERROR", gameId: entry.gameId, "Failed to encode entries array")
            return .error
        }
        let base64Content = fileData.base64EncodedString()

        // Build PUT body (sha omitted for new files)
        var putBody: [String: Any] = [
            "message": commitMessage,
            "content": base64Content
        ]
        if let sha = sha {
            putBody["sha"] = sha
        }

        guard let putBodyData = try? JSONSerialization.data(withJSONObject: putBody) else {
            logPushEvent("ERROR", gameId: entry.gameId, "Failed to serialize PUT body")
            return .error
        }

        var putRequest = URLRequest(url: url)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        putRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        putRequest.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        putRequest.httpBody = putBodyData
        putRequest.timeoutInterval = 5

        logPushEvent("INFO", gameId: entry.gameId, "PUT \(url.absoluteString)")
        if let (_, statusCode) = performRequest(request: putRequest) {
            switch statusCode {
            case 200, 201:
                logPushEvent("INFO", gameId: entry.gameId, "Push succeeded: \(commitMessage)")
                return .ok
            case 409:
                fputs("[CollectiveMemoryWriteService] Conflict on push for '\(entry.gameId)' — retrying\n", stderr)
                return .conflict
            default:
                fputs("[CollectiveMemoryWriteService] HTTP \(statusCode) on push for '\(entry.gameId)'\n", stderr)
                logPushEvent("WARN", gameId: entry.gameId, "PUT returned \(statusCode): \(commitMessage)")
                return .error
            }
        } else {
            fputs("[CollectiveMemoryWriteService] Network error during push for '\(entry.gameId)'\n", stderr)
            logPushEvent("ERROR", gameId: entry.gameId, "Network error on PUT")
            return .error
        }
    }

    // MARK: - Private: HTTP

    /// Perform a synchronous HTTP request using DispatchSemaphore.
    /// Returns (data, statusCode) on any HTTP response, nil on network error.
    private static func performRequest(request: URLRequest) -> (data: Data, statusCode: Int)? {
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

    // MARK: - Internal Types

    /// GitHub Contents API response for a single file (GET with standard JSON Accept).
    private struct GitHubContentsResponse: Codable {
        let sha: String
        let content: String
    }
}
