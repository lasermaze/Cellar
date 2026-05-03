import Foundation

public enum SessionOutcome: String {
    case success
    case failed
    case partial
    var headerLabel: String {
        switch self {
        case .success: return "success"
        case .failed:  return "failed"
        case .partial: return "partial"
        }
    }
    var fieldLabel: String {
        switch self {
        case .success: return "SUCCESS"
        case .failed:  return "FAILED"
        case .partial: return "PARTIAL"
        }
    }
}

struct WikiService: Sendable {

    /// Maximum total characters of wiki content to return (prevents context bloat)
    private static let maxContentLength = 4000

    /// Maximum number of pages to load
    private static let maxPages = 3

    // MARK: - Cache Helpers

    private static let cacheTTL: TimeInterval = 3600

    private static func isCacheFresh(_ url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mdate = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(mdate) < cacheTTL
    }

    private static func readCache(_ relativePath: String) -> String? {
        let file = CellarPaths.wikiCacheFile(for: relativePath)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try? String(contentsOf: file, encoding: .utf8)
    }

    private static func writeCache(_ relativePath: String, _ content: String) {
        let file = CellarPaths.wikiCacheFile(for: relativePath)
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? content.write(to: file, atomically: true, encoding: .utf8)
    }

    private static func fetchPage(_ relativePath: String) async -> String? {
        // Fresh cache short-circuit
        if let cached = readCache(relativePath), isCacheFresh(CellarPaths.wikiCacheFile(for: relativePath)) {
            return cached
        }
        // Network fetch
        let urlString = "https://raw.githubusercontent.com/\(CellarPaths.memoryRepo)/main/wiki/\(relativePath)"
        if let url = URL(string: urlString) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 5
            if let (data, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse, http.statusCode == 200,
               let body = String(data: data, encoding: .utf8) {
                writeCache(relativePath, body)
                return body
            }
        }
        // Stale-on-failure: return any cached copy even if expired
        return readCache(relativePath)
    }

    // MARK: - Read Path (thin wrappers — Plan 04)

    /// Fetch relevant wiki context for a game engine and optional symptom keywords.
    /// Plan 04: thin wrapper — delegates to KnowledgeStoreContainer.shared.fetchContext.
    static func fetchContext(engine: String?, symptoms: [String] = [], maxPages: Int = 3) async -> String? {
        let env = EnvironmentFingerprint.current(wineVersion: "", wineFlavor: "")
        return await KnowledgeStoreContainer.shared.fetchContext(for: engine ?? "", environment: env)
    }

    /// Search wiki pages by query string, returning formatted content or a no-match message.
    /// Plan 04: thin wrapper — delegates to KnowledgeStoreContainer.shared.list + fetchContext.
    /// ALWAYS returns non-nil String (preserves API contract per RESEARCH.md pitfall #7).
    static func search(query: String, maxResults: Int = 3) async -> String {
        let filter = KnowledgeListFilter(kind: nil, slug: slugify(query), maxResults: maxResults)
        let metas = await KnowledgeStoreContainer.shared.list(filter: filter)
        let env = EnvironmentFingerprint.current(wineVersion: "", wineFlavor: "")
        let context = await KnowledgeStoreContainer.shared.fetchContext(for: query, environment: env)
        if metas.isEmpty && context == nil {
            return "No relevant wiki pages found for '\(query)'"
        }
        var parts: [String] = []
        if let ctx = context { parts.append(ctx) }
        if !metas.isEmpty {
            let metaLines = metas.map { "[\($0.kind.rawValue)] \($0.slug)" }.joined(separator: "\n")
            parts.append("Available entries:\n\(metaLines)")
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Ingest

    private struct WikiAppendPayload: Encodable {
        let page: String
        let entry: String
        let commitMessage: String
        let overwrite: Bool?
    }

    private static var wikiProxyURL: URL? {
        let override = ProcessInfo.processInfo.environment["CELLAR_WIKI_PROXY_URL"]
        let defaultURL = "https://cellar-memory-proxy.sook40.workers.dev/api/wiki/append"
        return URL(string: override ?? defaultURL)
    }

    static func postWikiAppend(page: String, entry: String, commitMessage: String, overwrite: Bool = false) async {
        guard let url = wikiProxyURL else { return }
        let payload = WikiAppendPayload(page: page, entry: entry, commitMessage: commitMessage, overwrite: overwrite ? true : nil)
        guard let body = try? JSONEncoder().encode(payload) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                fputs("wiki-append: HTTP \(http.statusCode) for \(page)\n", stderr)
            }
        } catch {
            fputs("wiki-append: \(error.localizedDescription) for \(page)\n", stderr)
        }
    }

    /// Ingest learnings from a successful game session into wiki pages via the KnowledgeStore.
    /// Plan 04: thin wrapper — builds GamePageEntry and delegates to KnowledgeStoreContainer.shared.write(.gamePage).
    static func ingest(record: SuccessRecord) async {
        if let gamePage = buildIngestedGamePage(record: record) {
            await KnowledgeStoreContainer.shared.write(.gamePage(gamePage))
        }
    }

    // MARK: - Session Log (thin wrappers — Plan 04)

    /// Write a per-session log entry for a successful or partial session.
    /// Plan 04: thin wrapper — delegates to KnowledgeStoreContainer.shared.write(.sessionLog).
    static func postSessionLog(
        record: SuccessRecord,
        outcome: SessionOutcome,
        duration: TimeInterval,
        wineURL: URL?,
        midSessionNotes: [(timestamp: String, content: String)] = []
    ) async {
        let entry = SessionLogEntry(
            path: sessionLogFilename(record: record),
            body: formatSuccessSessionBody(record: record, duration: duration, wineURL: wineURL, midSessionNotes: midSessionNotes),
            commitMessage: "session: \(outcome.headerLabel) for \(record.gameName)"
        )
        await KnowledgeStoreContainer.shared.write(.sessionLog(entry))
    }

    /// Write a per-session log entry for a failed session (no SuccessRecord available).
    /// Plan 04: thin wrapper — delegates to KnowledgeStoreContainer.shared.write(.sessionLog).
    static func postFailureSessionLog(
        gameId: String,
        gameName: String,
        narrative: String,
        actionsAttempted: [String],
        launchCount: Int,
        duration: TimeInterval,
        wineURL: URL?,
        stopReason: String,
        midSessionNotes: [(timestamp: String, content: String)] = []
    ) async {
        let entry = SessionLogEntry(
            path: failureSessionLogFilename(gameId: gameId),
            body: formatFailureSessionBody(
                gameId: gameId, gameName: gameName, narrative: narrative,
                actionsAttempted: actionsAttempted, launchCount: launchCount,
                duration: duration, wineURL: wineURL, stopReason: stopReason,
                midSessionNotes: midSessionNotes
            ),
            commitMessage: "session: failure for \(gameName)"
        )
        await KnowledgeStoreContainer.shared.write(.sessionLog(entry))
    }

    // MARK: - Internal Static Shims (used by AIService after Task 1 rewire)

    /// Build the path for a success session log file.
    static func sessionLogFilename(record: SuccessRecord) -> String {
        let dateStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let slug = slugify(record.gameName)
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        return "sessions/\(dateStr)-\(slug)-\(shortId).md"
    }

    /// Build the path for a failure session log file.
    static func failureSessionLogFilename(gameId: String) -> String {
        let dateStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let slug = slugify(gameId)
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        return "sessions/\(dateStr)-\(slug)-\(shortId).md"
    }

    /// Build the body for a success session log entry.
    static func formatSuccessSessionBody(
        record: SuccessRecord,
        duration: TimeInterval,
        wineURL: URL?,
        midSessionNotes: [(timestamp: String, content: String)]
    ) -> String {
        let dateStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        let body = formatSessionEntry(
            record: record,
            outcome: .success,
            duration: duration,
            wineURL: wineURL,
            shortId: shortId,
            dateStr: dateStr,
            midSessionNotes: midSessionNotes
        )
        return scrubPaths(body)
    }

    /// Build the body for a failure session log entry.
    static func formatFailureSessionBody(
        gameId: String,
        gameName: String,
        narrative: String,
        actionsAttempted: [String],
        launchCount: Int,
        duration: TimeInterval,
        wineURL: URL?,
        stopReason: String,
        midSessionNotes: [(timestamp: String, content: String)]
    ) -> String {
        let dateStr = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        let body = formatFailureEntry(
            gameName: gameName,
            narrative: narrative,
            actionsAttempted: actionsAttempted,
            launchCount: launchCount,
            duration: duration,
            wineURL: wineURL,
            stopReason: stopReason,
            shortId: shortId,
            dateStr: dateStr,
            midSessionNotes: midSessionNotes
        )
        return scrubPaths(body)
    }

    /// Build a GamePageEntry from a SuccessRecord (for KnowledgeStore.write(.gamePage)).
    static func buildIngestedGamePage(record: SuccessRecord) -> GamePageEntry? {
        let slug = slugify(record.gameName)
        // Build the page body from the ingest logic (pitfalls, engine, DLL patterns, log)
        var parts: [String] = []

        for pitfall in record.pitfalls {
            let symptomSlug = slugify(pitfall.symptom)
            let candidates = ["symptoms/crash-on-launch.md", "symptoms/black-screen.md", "symptoms/d3d-errors.md"]
            let bestPage = findBestMatch(slug: symptomSlug, symptom: pitfall.symptom, candidates: candidates)
            parts.append("[\(bestPage)] \(formatPitfall(pitfall, gameName: record.gameName))")
        }

        if let engine = record.engine?.lowercased() {
            let enginePages: [String: String] = [
                "directdraw": "engines/directdraw.md",
                "unity": "engines/unity.md",
                "dxvk": "engines/dxvk.md",
            ]
            let key = enginePages.keys.first { engine.contains($0) || (record.graphicsApi?.lowercased().contains($0) ?? false) }
            if let key = key, let pagePath = enginePages[key] {
                parts.append("[\(pagePath)] \(formatEngineEntry(record: record))")
            }
        }

        if let gfx = record.graphicsApi?.lowercased(), record.engine == nil || !(record.engine?.lowercased().contains(gfx) ?? false) {
            if gfx.contains("directdraw") || gfx.contains("ddraw") {
                parts.append("[engines/directdraw.md] \(formatEngineEntry(record: record))")
            }
        }

        for override in record.dllOverrides {
            if let source = override.source, source.lowercased().contains("cnc-ddraw") {
                parts.append("[engines/directdraw.md] - \(record.gameName): `\(override.dll)=\(override.mode)` via \(source)")
            }
        }

        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        parts.append("[log.md] ## [\(dateStr)] ingest | \(record.gameName) (gameId: \(record.gameId))")

        guard !parts.isEmpty else { return nil }

        return GamePageEntry(
            slug: slug,
            autoContent: parts.joined(separator: "\n"),
            commitMessage: "wiki: ingest from \(record.gameName)"
        )
    }

    // MARK: - Ingest Helpers

    /// Format a pitfall as a wiki bullet point
    private static func formatPitfall(_ pitfall: PitfallRecord, gameName: String) -> String {
        var line = "- **\(gameName)**: \(pitfall.symptom) → \(pitfall.fix) (cause: \(pitfall.cause))"
        if let wrongFix = pitfall.wrongFix {
            line += " [wrong fix: \(wrongFix)]"
        }
        return line
    }

    /// Format engine/graphics entry for a wiki page
    private static func formatEngineEntry(record: SuccessRecord) -> String {
        var parts = ["- **\(record.gameName)**"]
        if let gfx = record.graphicsApi { parts.append("(\(gfx))") }
        if !record.environment.isEmpty {
            let envStr = record.environment.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            parts.append("env: `\(envStr)`")
        }
        if let wine = record.wineVersion { parts.append("on Wine \(wine)") }
        return parts.joined(separator: " ")
    }

    /// Slugify a string for fuzzy matching
    static func slugify(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    /// Find the best matching page from candidates by keyword overlap with symptom text
    private static func findBestMatch(slug: String, symptom: String, candidates: [String]) -> String {
        let words = symptom.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 }
        var bestScore = 0
        var bestPage: String?
        for candidate in candidates {
            let score = words.reduce(0) { acc, word in
                acc + (candidate.lowercased().contains(word) ? 1 : 0)
            }
            if score > bestScore {
                bestScore = score
                bestPage = candidate
            }
        }
        // Fall back to crash-on-launch as the catch-all symptom page
        return bestPage ?? "symptoms/crash-on-launch.md"
    }

    // MARK: - Session Log Helpers

    private static func parseWineVersion(from url: URL?) -> String {
        guard let url = url else { return "unknown" }
        // wineURL is typically /usr/local/cellar/wine-staging/8.21.0/bin/wine64 or similar
        // Walk up two levels: bin -> 8.21.0
        let twoUp = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        return twoUp.isEmpty || twoUp == "/" ? "unknown" : twoUp
    }

    private static func scrubPaths(_ text: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return text.replacingOccurrences(of: home, with: "~")
    }

    private static func formatSessionEntry(
        record: SuccessRecord,
        outcome: SessionOutcome,
        duration: TimeInterval,
        wineURL: URL?,
        shortId: String,
        dateStr: String,
        midSessionNotes: [(timestamp: String, content: String)]
    ) -> String {
        let runnerLabel = "Wine \(parseWineVersion(from: wineURL))"
        let durationMin = max(1, Int(duration / 60.0))
        let narrative = (record.resolutionNarrative ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tldr = narrative.isEmpty
            ? "Session ended (\(outcome.headerLabel)) after \(durationMin) min."
            : String(narrative.split(separator: "\n").first ?? Substring(narrative))

        var worked: [String] = []
        for (k, v) in record.environment.sorted(by: { $0.key < $1.key }) {
            worked.append("- env: `\(k)=\(v)`")
        }
        for ovr in record.dllOverrides {
            worked.append("- dll override: `\(ovr.dll)=\(ovr.mode)`" + (ovr.source.map { " (source: \($0))" } ?? ""))
        }
        if let engine = record.engine { worked.append("- engine: \(engine)") }
        if let gfx = record.graphicsApi { worked.append("- graphics: \(gfx)") }
        if worked.isEmpty { worked.append("- (none recorded)") }

        var didnt: [String] = []
        for p in record.pitfalls {
            didnt.append("- \(p.symptom)" + (p.fix.isEmpty ? "" : " — tried: \(p.fix)"))
        }
        if didnt.isEmpty { didnt.append("- (none recorded)") }

        var midSection = ""
        if !midSessionNotes.isEmpty {
            midSection = "\n## Mid-session observations\n"
            for note in midSessionNotes {
                midSection += "- [\(note.timestamp)] \(note.content)\n"
            }
        }

        return """
        # \(record.gameName) — \(dateStr) (\(outcome.headerLabel))

        **Runner:** \(runnerLabel)
        **Outcome:** \(outcome.fieldLabel)
        **Duration:** \(durationMin) minutes
        **Session:** \(shortId)

        ## TL;DR
        \(tldr)

        ## What worked
        \(worked.joined(separator: "\n"))

        ## What didn't work
        \(didnt.joined(separator: "\n"))

        ## Quirks
        - (none recorded)

        ## Narrative
        \(narrative.isEmpty ? "(no narrative provided)" : narrative)
        \(midSection)
        """
    }

    private static func formatFailureEntry(
        gameName: String,
        narrative: String,
        actionsAttempted: [String],
        launchCount: Int,
        duration: TimeInterval,
        wineURL: URL?,
        stopReason: String,
        shortId: String,
        dateStr: String,
        midSessionNotes: [(timestamp: String, content: String)]
    ) -> String {
        let runnerLabel = "Wine \(parseWineVersion(from: wineURL))"
        let durationMin = max(1, Int(duration / 60.0))
        let trimmedNarrative = narrative.trimmingCharacters(in: .whitespacesAndNewlines)
        let tldr = trimmedNarrative.isEmpty
            ? "Failed after \(launchCount) launches (\(stopReason))."
            : String(trimmedNarrative.split(separator: "\n").first ?? Substring(trimmedNarrative))

        let didnt: [String] = actionsAttempted.isEmpty
            ? ["- (no actions recorded)"]
            : actionsAttempted.map { "- \($0)" }

        var midSection = ""
        if !midSessionNotes.isEmpty {
            midSection = "\n## Mid-session observations\n"
            for note in midSessionNotes {
                midSection += "- [\(note.timestamp)] \(note.content)\n"
            }
        }

        return """
        # \(gameName) — \(dateStr) (failed)

        **Runner:** \(runnerLabel)
        **Outcome:** FAILED
        **Duration:** \(durationMin) minutes
        **Session:** \(shortId)
        **Stop reason:** \(stopReason)
        **Launches attempted:** \(launchCount)

        ## TL;DR
        \(tldr)

        ## What worked
        - (session did not reach a working state)

        ## What didn't work
        \(didnt.joined(separator: "\n"))

        ## Quirks
        - (none recorded)

        ## Narrative
        \(trimmedNarrative.isEmpty ? "(no narrative provided)" : trimmedNarrative)
        \(midSection)
        """
    }

    // MARK: - Session Retrieval

    private static func sessionsListingURL() -> URL? {
        let repo = CellarPaths.memoryRepo
        return URL(string: "https://api.github.com/repos/\(repo)/contents/wiki/sessions")
    }

    private struct GHContentsItem: Decodable {
        let name: String
        let path: String
        let type: String
    }

    private static func listRecentSessions(forSlug slug: String, max: Int) async -> [String] {
        guard let url = sessionsListingURL() else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 { return [] }
            let items = (try? JSONDecoder().decode([GHContentsItem].self, from: data)) ?? []
            // Filenames sort lexicographically; ISO8601 dates make most-recent = greatest filename.
            let matches = items
                .filter { $0.type == "file" && $0.name.hasSuffix(".md") && $0.name.contains("-\(slug)-") }
                .sorted { $0.name > $1.name }
                .prefix(max)
            return matches.map { $0.path.replacingOccurrences(of: "wiki/", with: "") }
        } catch {
            return []
        }
    }

    // MARK: - Private

    /// Extract search keywords from game name and symptom list.
    /// Splits on non-alphanumeric, lowercases, filters short words.
    private static func extractKeywords(gameName: String, symptoms: [String]) -> [String] {
        let nameWords = gameName.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 }
        let symptomWords = symptoms.flatMap {
            $0.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 }
        }
        return nameWords + symptomWords
    }

    /// Score index.md lines by keyword relevance, return top page paths.
    /// Each line in index.md looks like:
    /// - [engines/directdraw.md](engines/directdraw.md) — DirectDraw games: cnc-ddraw wrapper
    private static func findRelevantPages(in indexContent: String, keywords: [String], limit: Int) -> [String] {
        let lines = indexContent.components(separatedBy: .newlines)
        // Match markdown links: [path](path)
        let linkPattern = "\\[([^\\]]+)\\]\\(([^)]+)\\)"
        guard let regex = try? NSRegularExpression(pattern: linkPattern) else { return [] }

        var scored: [(path: String, score: Int)] = []

        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let pathRange = Range(match.range(at: 2), in: line) else { continue }
            let path = String(line[pathRange])
            guard path.hasSuffix(".md") else { continue }

            let lowLine = line.lowercased()
            let score = keywords.reduce(0) { acc, kw in
                acc + (lowLine.contains(kw) ? 1 : 0)
            }
            if score > 0 {
                scored.append((path: path, score: score))
            }
        }

        return scored.sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0.path }
    }
}
