import Foundation

/// Stateless service that fetches, filters, ranks, and formats collective memory entries
/// for a given game. The single public entry point is `fetchBestEntry(for:wineURL:)`.
///
/// All errors are swallowed — the function returns nil when no compatible entry is available,
/// or when any network/parsing failure occurs. A local file cache at ~/.cellar/cache/memory/
/// provides offline resilience with a 1-hour TTL.
struct CollectiveMemoryService {

    // MARK: - Public API (thin wrapper — delegates to KnowledgeStoreContainer.shared)

    /// Fetch the best collective memory entry for a game and return a formatted context block,
    /// or nil if no compatible entry is available or any step fails.
    ///
    /// Plan 04: thin wrapper — delegates entirely to KnowledgeStoreContainer.shared.fetchContext.
    /// Legacy callers continue to compile without changes.
    static func fetchBestEntry(
        for gameName: String,
        wineURL: URL
    ) async -> String? {
        let env = EnvironmentFingerprint.current(
            wineVersion: detectWineVersion(wineURL: wineURL) ?? "",
            wineFlavor: detectWineFlavor(wineURL: wineURL)
        )
        return await KnowledgeStoreContainer.shared.fetchContext(for: gameName, environment: env)
    }

    // MARK: - Internal Static Shims (used by AIService to build EnvironmentFingerprint)

    /// Internal wrapper for detectWineVersion — allows AIService to build the fingerprint.
    static func detectWineVersionInternal(wineURL: URL) -> String? {
        detectWineVersion(wineURL: wineURL)
    }

    /// Internal wrapper for detectWineFlavor — allows AIService to build the fingerprint.
    static func detectWineFlavorInternal(wineURL: URL) -> String {
        detectWineFlavor(wineURL: wineURL)
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
