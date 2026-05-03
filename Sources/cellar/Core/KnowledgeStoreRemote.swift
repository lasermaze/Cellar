import Foundation

// MARK: - HTTPClient Protocol

/// Minimal seam for injectable HTTP — enables MockHTTP in tests without real network calls.
/// URLSession already conforms via its async `data(for:)` API.
protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {}

// MARK: - KnowledgeStoreRemote

/// Network-backed KnowledgeStore adapter.
///
/// Reads: GitHub raw URLs for config entries and game pages; api.github.com for session listing.
/// Writes: POSTs to the Cloudflare Worker `/api/knowledge/write` endpoint.
/// Cache: 1-hour TTL KnowledgeCache with stale-on-failure fallback (matches CollectiveMemoryService behavior).
///
/// Sanitizer: uses PolicyResources.shared allowlists at call time — no inline duplication.
struct KnowledgeStoreRemote: KnowledgeStore {

    // MARK: - Properties

    let cache: KnowledgeCache
    let http: HTTPClient
    let memoryRepo: String
    let wikiProxyURL: URL

    // MARK: - Init

    init(
        cache: KnowledgeCache = KnowledgeCache(cacheDir: CellarPaths.knowledgeCacheDir),
        http: HTTPClient = URLSession.shared,
        memoryRepo: String = CellarPaths.memoryRepo,
        wikiProxyURL: URL = CellarPaths.wikiProxyURL
    ) {
        self.cache = cache
        self.http = http
        self.memoryRepo = memoryRepo
        self.wikiProxyURL = wikiProxyURL
    }

    // MARK: - KnowledgeStore: fetchContext

    /// Fetch unified context (config + game page + recent sessions) for the agent prompt.
    /// All three fetches run concurrently. Each falls back to stale cache on network failure.
    /// Returns nil when no context is available from any source.
    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String? {
        let slug = slugify(gameName)

        // Run all three fetches concurrently
        async let cfg = fetchConfig(slug: slug)
        async let page = fetchGamePage(slug: slug)
        async let sessions = fetchRecentSessions(slug: slug, limit: 3)

        let (configEntry, gamePage, sessionTexts) = await (cfg, page, sessions)

        var sections: [String] = []

        if let entry = configEntry {
            sections.append("## Community config\n\(formatConfigEntry(entry))")
        }
        if let pageText = gamePage {
            sections.append("## Game page\n\(pageText)")
        }
        if !sessionTexts.isEmpty {
            sections.append("## Recent sessions\n\(sessionTexts.joined(separator: "\n\n---\n\n"))")
        }

        guard !sections.isEmpty else { return nil }

        let combined = sections.joined(separator: "\n\n")
        return String(combined.prefix(4000))
    }

    // MARK: - KnowledgeStore: write

    /// Write a knowledge entry to the Worker. Sanitizes first. Swallows all errors.
    func write(_ entry: KnowledgeEntry) async {
        let sanitized = sanitize(entry)
        await postToWorker(sanitized)
    }

    // MARK: - KnowledgeStore: list

    /// List entries by querying api.github.com for the kind's directory.
    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta] {
        let kinds: [KnowledgeEntry.Kind] = filter.kind.map { [$0] } ?? KnowledgeEntry.Kind.allCases
        var results: [KnowledgeEntryMeta] = []

        for kind in kinds {
            let path = githubContentsPath(for: kind)
            let urlString = "https://api.github.com/repos/\(memoryRepo)/contents/\(path)"
            guard let url = URL(string: urlString) else { continue }

            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.timeoutInterval = 5

            guard let (data, response) = try? await http.data(for: request),
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200 else { continue }

            struct GHItem: Decodable {
                let name: String
                let path: String
                let type: String
            }

            guard let items = try? JSONDecoder().decode([GHItem].self, from: data) else { continue }

            let kindResults: [KnowledgeEntryMeta] = items
                .filter { $0.type == "file" }
                .compactMap { item -> KnowledgeEntryMeta? in
                    let slug = URL(fileURLWithPath: item.name).deletingPathExtension().lastPathComponent
                    if let filterSlug = filter.slug, !slug.contains(filterSlug) { return nil }
                    return KnowledgeEntryMeta(kind: kind, slug: slug, path: item.path, lastModified: nil)
                }
                .sorted { $0.slug > $1.slug }

            results.append(contentsOf: kindResults)
        }

        return Array(results.prefix(filter.maxResults))
    }

    // MARK: - Private: Fetch helpers

    /// Fetch config entry from GitHub raw. Falls back to stale cache on 403/429 or network error.
    private func fetchConfig(slug: String) async -> CollectiveMemoryEntry? {
        let cacheKey = "config/\(slug).json"
        let urlString = "https://raw.githubusercontent.com/\(memoryRepo)/main/entries/\(slug).json"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 5

        if cache.isFresh(key: cacheKey), let cached = cache.read(key: cacheKey) {
            return decodeConfigEntries(cached)?.first
        }

        do {
            let (data, response) = try await http.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try? cache.write(key: cacheKey, data: data)
                return decodeConfigEntries(data)?.first
            }
            // Rate limited or other error — serve stale
            if let stale = cache.readStale(key: cacheKey) {
                return decodeConfigEntries(stale)?.first
            }
            return nil
        } catch {
            // Network failure — serve stale
            if let stale = cache.readStale(key: cacheKey) {
                return decodeConfigEntries(stale)?.first
            }
            return nil
        }
    }

    /// Fetch game page markdown from GitHub raw. Falls back to stale cache on error.
    private func fetchGamePage(slug: String) async -> String? {
        let cacheKey = "game-page/\(slug).md"
        let urlString = "https://raw.githubusercontent.com/\(memoryRepo)/main/wiki/games/\(slug).md"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        if cache.isFresh(key: cacheKey), let cached = cache.read(key: cacheKey) {
            return String(data: cached, encoding: .utf8)
        }

        do {
            let (data, response) = try await http.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                try? cache.write(key: cacheKey, data: data)
                return String(data: data, encoding: .utf8)
            }
            // Serve stale on any non-200
            if let stale = cache.readStale(key: cacheKey) {
                return String(data: stale, encoding: .utf8)
            }
            return nil
        } catch {
            if let stale = cache.readStale(key: cacheKey) {
                return String(data: stale, encoding: .utf8)
            }
            return nil
        }
    }

    /// Fetch the most recent N session logs for a game slug.
    /// Lists wiki/sessions/ via api.github.com, filters by slug, fetches top N by filename DESC.
    private func fetchRecentSessions(slug: String, limit: Int) async -> [String] {
        let listURLString = "https://api.github.com/repos/\(memoryRepo)/contents/wiki/sessions"
        guard let listURL = URL(string: listURLString) else { return [] }

        var listRequest = URLRequest(url: listURL)
        listRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        listRequest.timeoutInterval = 5

        struct GHContentsItem: Decodable {
            let name: String
            let path: String
            let type: String
        }

        guard let (data, response) = try? await http.data(for: listRequest),
              let httpResp = response as? HTTPURLResponse,
              httpResp.statusCode == 200,
              let items = try? JSONDecoder().decode([GHContentsItem].self, from: data) else {
            return []
        }

        let matching = items
            .filter { $0.type == "file" && $0.name.hasSuffix(".md") && $0.name.contains("-\(slug)-") }
            .sorted { $0.name > $1.name }
            .prefix(limit)

        var texts: [String] = []
        for item in matching {
            // Derive relative path: item.path is "wiki/sessions/..." — strip "wiki/"
            let relativePath = item.path.replacingOccurrences(of: "wiki/", with: "")
            let cacheKey = "session-log/\(item.name)"

            if cache.isFresh(key: cacheKey), let cached = cache.read(key: cacheKey),
               let text = String(data: cached, encoding: .utf8) {
                texts.append(text)
                continue
            }

            let rawURLString = "https://raw.githubusercontent.com/\(memoryRepo)/main/wiki/\(relativePath)"
            guard let rawURL = URL(string: rawURLString) else { continue }
            var rawReq = URLRequest(url: rawURL)
            rawReq.timeoutInterval = 5

            if let (rawData, rawResp) = try? await http.data(for: rawReq),
               let rawHttp = rawResp as? HTTPURLResponse,
               rawHttp.statusCode == 200,
               let text = String(data: rawData, encoding: .utf8) {
                try? cache.write(key: cacheKey, data: rawData)
                texts.append(text)
            }
        }
        return texts
    }

    // MARK: - Private: Write helpers

    /// Sanitize a KnowledgeEntry before writing.
    /// Reads PolicyResources.shared allowlists at call time (not init time).
    private func sanitize(_ entry: KnowledgeEntry) -> KnowledgeEntry {
        switch entry {
        case .config(let configEntry):
            return .config(sanitizeConfigEntry(configEntry))
        case .gamePage, .sessionLog:
            // No sanitization needed for page content — the Worker validates origin/structure
            return entry
        }
    }

    /// Sanitize a CollectiveMemoryEntry using PolicyResources allowlists.
    /// Mirrors CollectiveMemoryService.sanitizeEntry logic, reading PolicyResources.shared directly.
    private func sanitizeConfigEntry(_ entry: CollectiveMemoryEntry) -> CollectiveMemoryEntry {
        // Environment: filter against PolicyResources.shared.envAllowlist
        let sanitizedEnv = entry.config.environment.reduce(into: [String: String]()) { result, pair in
            let (key, value) = pair
            guard PolicyResources.shared.envAllowlist.contains(key) else {
                fputs("[KnowledgeStoreRemote] Dropping disallowed env key: \(key)\n", stderr)
                return
            }
            result[key] = String(value.prefix(200))
        }

        // DLL overrides: validate mode
        let validDLLModes: Set<String> = ["n", "b", "n,b", "b,n", ""]
        let sanitizedDLLOverrides = entry.config.dllOverrides.compactMap { override -> DLLOverrideRecord? in
            guard validDLLModes.contains(override.mode) else {
                fputs("[KnowledgeStoreRemote] Dropping DLL override with invalid mode '\(override.mode)'\n", stderr)
                return nil
            }
            return DLLOverrideRecord(
                dll: String(override.dll.prefix(50)),
                mode: override.mode,
                placement: override.placement,
                source: override.source.map { String($0.prefix(100)) }
            )
        }

        // Registry: validate prefix against PolicyResources.shared.registryAllowlist
        let sanitizedRegistry = entry.config.registry.compactMap { record -> RegistryRecord? in
            let truncatedKey = String(record.key.prefix(200))
            guard PolicyResources.shared.registryAllowlist.contains(where: { truncatedKey.hasPrefix($0) }) else {
                fputs("[KnowledgeStoreRemote] Dropping registry record with disallowed key: \(record.key)\n", stderr)
                return nil
            }
            return RegistryRecord(
                key: truncatedKey,
                valueName: String(record.valueName.prefix(100)),
                data: String(record.data.prefix(200)),
                purpose: record.purpose
            )
        }

        // Launch args: max 5, each max 100 chars
        let sanitizedLaunchArgs = Array(entry.config.launchArgs.prefix(5)).map { String($0.prefix(100)) }

        // Setup deps: filter against PolicyResources.shared.winetricksVerbAllowlist
        let sanitizedSetupDeps = entry.config.setupDeps.filter {
            PolicyResources.shared.winetricksVerbAllowlist.contains($0)
        }

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

    // MARK: - Private: Wiki append payload

    /// The Worker /api/knowledge/write endpoint expects:
    ///   - For config:     { "kind": "config",     "entry": <CollectiveMemoryEntry JSON> }
    ///   - For gamePage:   { "kind": "gamePage",   "entry": { "page": "...", "entry": "...", "overwrite": true } }
    ///   - For sessionLog: { "kind": "sessionLog", "entry": { "page": "...", "entry": "...", "overwrite": false } }
    private struct WikiAppendPayload: Encodable {
        let page: String
        let entry: String
        let overwrite: Bool
    }

    private struct WorkerWriteEnvelope: Encodable {
        let kind: String
        let entry: WikiAppendPayload
    }

    private struct WorkerWriteEnvelopeConfig: Encodable {
        let kind: String
        let entry: CollectiveMemoryEntry
    }

    /// POST a KnowledgeEntry to the Worker /api/knowledge/write endpoint.
    /// Never throws — all errors are logged and swallowed.
    private func postToWorker(_ entry: KnowledgeEntry) async {
        let writeURL = wikiProxyURL.appendingPathComponent("api/knowledge/write")

        // Build the request body with proper shapes per entry kind
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bodyData: Data

        switch entry {
        case .config(let configEntry):
            let envelope = WorkerWriteEnvelopeConfig(kind: "config", entry: configEntry)
            guard let data = try? encoder.encode(envelope) else {
                fputs("[KnowledgeStoreRemote] Failed to encode config entry for \(entry.slug)\n", stderr)
                return
            }
            bodyData = data
        case .gamePage(let pageEntry):
            let payload = WikiAppendPayload(
                page: "games/\(pageEntry.slug).md",
                entry: pageEntry.autoContent,
                overwrite: true
            )
            let envelope = WorkerWriteEnvelope(kind: "gamePage", entry: payload)
            guard let data = try? encoder.encode(envelope) else {
                fputs("[KnowledgeStoreRemote] Failed to encode gamePage entry for \(entry.slug)\n", stderr)
                return
            }
            bodyData = data
        case .sessionLog(let sessionEntry):
            let filename = URL(fileURLWithPath: sessionEntry.path).lastPathComponent
            let pagePath = "sessions/\(filename)"
            let payload = WikiAppendPayload(
                page: pagePath,
                entry: sessionEntry.body,
                overwrite: false
            )
            let envelope = WorkerWriteEnvelope(kind: "sessionLog", entry: payload)
            guard let data = try? encoder.encode(envelope) else {
                fputs("[KnowledgeStoreRemote] Failed to encode sessionLog entry for \(entry.slug)\n", stderr)
                return
            }
            bodyData = data
        }

        guard !bodyData.isEmpty else {
            fputs("[KnowledgeStoreRemote] Empty body for \(entry.slug)\n", stderr)
            return
        }

        var request = URLRequest(url: writeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 10

        do {
            let (_, response) = try await http.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if !(200...299).contains(http.statusCode) {
                logWriteError("HTTP \(http.statusCode) from Worker for \(entry.slug)")
            }
        } catch {
            logWriteError("Network error writing \(entry.slug): \(error.localizedDescription)")
        }
    }

    // MARK: - Private: Helpers

    /// Decode a JSON array of CollectiveMemoryEntry from data. Returns nil on failure.
    private func decodeConfigEntries(_ data: Data) -> [CollectiveMemoryEntry]? {
        try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
    }

    /// Format a CollectiveMemoryEntry for agent injection (single entry summary).
    private func formatConfigEntry(_ entry: CollectiveMemoryEntry) -> String {
        var lines: [String] = []
        lines.append("Game: \(entry.gameName) | Confirmations: \(entry.confirmations)")
        lines.append("Environment: \(entry.environment.arch), Wine \(entry.environment.wineVersion) (\(entry.environment.wineFlavor)), macOS \(entry.environment.macosVersion)")

        if !entry.config.environment.isEmpty {
            lines.append("Environment variables:")
            for (key, value) in entry.config.environment.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key)=\(value)")
            }
        }
        if !entry.config.dllOverrides.isEmpty {
            lines.append("DLL overrides:")
            for override in entry.config.dllOverrides {
                let sourcePart = override.source.map { " (\($0))" } ?? ""
                lines.append("  \(override.dll) -> \(override.mode)\(sourcePart)")
            }
        }
        if !entry.config.setupDeps.isEmpty {
            lines.append("Setup deps: \(entry.config.setupDeps.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    /// Map KnowledgeEntry.Kind to the GitHub contents API path.
    private func githubContentsPath(for kind: KnowledgeEntry.Kind) -> String {
        switch kind {
        case .config: return "entries"
        case .gamePage: return "wiki/games"
        case .sessionLog: return "wiki/sessions"
        }
    }

    /// Append one line to ~/.cellar/logs/memory-push.log.
    private func logWriteError(_ message: String) {
        fputs("[KnowledgeStoreRemote] \(message)\n", stderr)
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) ERROR knowledge-write \(message)\n"
        guard let lineData = line.data(using: .utf8) else { return }

        let logFile = CellarPaths.logsDir.appendingPathComponent("memory-push.log")
        try? FileManager.default.createDirectory(at: CellarPaths.logsDir, withIntermediateDirectories: true)

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
