import Foundation

// MARK: - KnowledgeStoreLocal

/// Cache-only KnowledgeStore. No network. Reads from and writes to a local cache directory.
///
/// Use cases: offline mode, deterministic tests, replay debugging.
/// Default cache dir: ~/.cellar/cache/knowledge/
///
/// Cache layout:
///   config/{gameId}.json        — JSON-encoded [CollectiveMemoryEntry] array (matches wire format)
///   game-page/{slug}.md         — raw markdown body
///   session-log/{filename}.md   — raw session log markdown body
struct KnowledgeStoreLocal: KnowledgeStore {

    // MARK: - Properties

    let cache: KnowledgeCache

    // MARK: - Init

    init(cacheDir: URL = CellarPaths.knowledgeCacheDir) {
        // Local cache never expires (TTL = infinity)
        self.cache = KnowledgeCache(cacheDir: cacheDir, ttl: .infinity)
    }

    // MARK: - KnowledgeStore

    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String? {
        let slug = slugify(gameName)
        var sections: [String] = []
        var totalLength = 0
        let cap = 4000

        // 1. Config entry (community config)
        if let configText = loadConfigSection(slug: slug) {
            sections.append("## Community config\n\(configText)")
            totalLength += configText.count
        }

        // 2. Game page
        if totalLength < cap, let pageText = loadGamePageSection(slug: slug) {
            sections.append("## Game page\n\(pageText)")
            totalLength += pageText.count
        }

        // 3. Recent session logs (up to 3)
        if totalLength < cap {
            let sessionTexts = loadRecentSessionsSection(slug: slug, limit: 3)
            if !sessionTexts.isEmpty {
                sections.append("## Recent sessions\n\(sessionTexts.joined(separator: "\n\n---\n\n"))")
            }
        }

        guard !sections.isEmpty else { return nil }

        let combined = sections.joined(separator: "\n\n")
        return String(combined.prefix(cap))
    }

    func write(_ entry: KnowledgeEntry) async {
        switch entry {
        case .config(let configEntry):
            writeConfig(configEntry)
        case .gamePage(let pageEntry):
            writeGamePage(pageEntry)
        case .sessionLog(let sessionEntry):
            writeSessionLog(sessionEntry)
        }
    }

    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta] {
        var results: [KnowledgeEntryMeta] = []
        let kinds: [KnowledgeEntry.Kind] = filter.kind.map { [$0] } ?? KnowledgeEntry.Kind.allCases

        for kind in kinds {
            let kindDir = kindDirectory(for: kind)
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: kindDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for fileURL in items {
                let filename = fileURL.deletingPathExtension().lastPathComponent
                let slug = filename

                // Apply slug filter if provided
                if let filterSlug = filter.slug, !slug.contains(filterSlug) {
                    continue
                }

                let modDate = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                results.append(KnowledgeEntryMeta(
                    kind: kind,
                    slug: slug,
                    path: fileURL.path,
                    lastModified: modDate
                ))
            }
        }

        // Sort by mtime descending, cap at maxResults
        results.sort { ($0.lastModified ?? .distantPast) > ($1.lastModified ?? .distantPast) }
        return Array(results.prefix(filter.maxResults))
    }

    // MARK: - Private: Read helpers

    private func loadConfigSection(slug: String) -> String? {
        let key = "config/\(slug).json"
        guard let data = cache.read(key: key) else { return nil }

        // Decode as array of CollectiveMemoryEntry (matches wire format)
        guard let entries = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: data),
              !entries.isEmpty else { return nil }

        // Return the first entry formatted (no env-based ranking in local adapter)
        return formatConfigEntry(entries[0])
    }

    private func loadGamePageSection(slug: String) -> String? {
        let key = "game-page/\(slug).md"
        guard let data = cache.read(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func loadRecentSessionsSection(slug: String, limit: Int) -> [String] {
        let sessionDir = cache.cacheDir.appendingPathComponent("session-log")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: sessionDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        // Filter by slug substring; sort by filename descending (ISO date prefix sorts correctly)
        let matching = items
            .filter { $0.lastPathComponent.contains(slug) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)

        return matching.compactMap { url in
            try? String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: - Private: Write helpers

    private func writeConfig(_ entry: CollectiveMemoryEntry) {
        let key = "config/\(entry.gameId).json"
        // Read existing entries to merge/replace (keep one entry per gameId)
        var entries: [CollectiveMemoryEntry] = []
        if let existing = cache.read(key: key),
           let decoded = try? JSONDecoder().decode([CollectiveMemoryEntry].self, from: existing) {
            // Replace existing entry with same environmentHash, or append
            entries = decoded.filter { $0.environmentHash != entry.environmentHash }
        }
        entries.insert(entry, at: 0)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? cache.write(key: key, data: data)
    }

    private func writeGamePage(_ entry: GamePageEntry) {
        let key = "game-page/\(entry.slug).md"
        guard let data = entry.autoContent.data(using: .utf8) else { return }
        try? cache.write(key: key, data: data)
    }

    private func writeSessionLog(_ entry: SessionLogEntry) {
        let filename = URL(fileURLWithPath: entry.path).lastPathComponent
        let key = "session-log/\(filename)"
        guard let data = entry.body.data(using: .utf8) else { return }
        try? cache.write(key: key, data: data)
    }

    // MARK: - Private: Format helpers

    private func formatConfigEntry(_ entry: CollectiveMemoryEntry) -> String {
        var lines: [String] = []
        lines.append("Game: \(entry.gameName) | Confirmations: \(entry.confirmations)")
        lines.append("Environment: \(entry.environment.arch), Wine \(entry.environment.wineVersion) (\(entry.environment.wineFlavor)), macOS \(entry.environment.macosVersion)")

        // Environment variables
        if !entry.config.environment.isEmpty {
            lines.append("Environment variables:")
            for (key, value) in entry.config.environment.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key)=\(value)")
            }
        }

        // DLL overrides
        if !entry.config.dllOverrides.isEmpty {
            lines.append("DLL overrides:")
            for override in entry.config.dllOverrides {
                let sourcePart = override.source.map { " (\($0))" } ?? ""
                lines.append("  \(override.dll) -> \(override.mode)\(sourcePart)")
            }
        }

        // Setup deps
        if !entry.config.setupDeps.isEmpty {
            lines.append("Setup deps: \(entry.config.setupDeps.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Private: Kind-to-directory mapping

    private func kindDirectory(for kind: KnowledgeEntry.Kind) -> URL {
        switch kind {
        case .config:
            return cache.cacheDir.appendingPathComponent("config")
        case .gamePage:
            return cache.cacheDir.appendingPathComponent("game-page")
        case .sessionLog:
            return cache.cacheDir.appendingPathComponent("session-log")
        }
    }
}
