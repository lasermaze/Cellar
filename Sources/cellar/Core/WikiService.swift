import Foundation

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

    // MARK: - Read Path

    /// Fetch relevant wiki context for a game engine and optional symptom keywords.
    /// Returns formatted wiki content block, or nil if wiki unavailable or no relevant pages found.
    static func fetchContext(engine: String?, symptoms: [String] = [], maxPages: Int = 3) async -> String? {
        guard let indexContent = await fetchPage("index.md") else {
            return nil
        }

        let keywords = extractKeywords(gameName: engine ?? "", symptoms: symptoms)
        let pagePaths = findRelevantPages(in: indexContent, keywords: keywords, limit: maxPages)
        guard !pagePaths.isEmpty else { return nil }

        var totalLength = 0
        var pageContents: [String] = []
        for path in pagePaths {
            guard let content = await fetchPage(path) else { continue }
            if totalLength + content.count > maxContentLength && !pageContents.isEmpty { break }
            pageContents.append(content)
            totalLength += content.count
        }

        guard !pageContents.isEmpty else { return nil }
        let combined = pageContents.joined(separator: "\n\n---\n\n")
        return "--- WIKI KNOWLEDGE ---\n\(combined)\n--- END WIKI KNOWLEDGE ---"
    }

    /// Search wiki pages by query string, returning formatted content or a no-match message.
    /// Used by the query_wiki agent tool for mid-session lookups.
    static func search(query: String, maxResults: Int = 3) async -> String {
        guard let indexContent = await fetchPage("index.md") else {
            return "Wiki not available"
        }

        let keywords = query.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 }
        let pagePaths = findRelevantPages(in: indexContent, keywords: keywords, limit: maxResults)
        guard !pagePaths.isEmpty else {
            return "No relevant wiki pages found for '\(query)'"
        }

        var pageContents: [String] = []
        var totalLength = 0
        for path in pagePaths {
            guard let content = await fetchPage(path) else { continue }
            if totalLength + content.count > maxContentLength && !pageContents.isEmpty { break }
            pageContents.append("[\(path)]\n\(content)")
            totalLength += content.count
        }

        if pageContents.isEmpty {
            return "No relevant wiki pages found for '\(query)'"
        }
        return pageContents.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Ingest

    private struct WikiAppendPayload: Encodable {
        let page: String
        let entry: String
        let commitMessage: String
    }

    private static var wikiProxyURL: URL? {
        let override = ProcessInfo.processInfo.environment["CELLAR_WIKI_PROXY_URL"]
        let defaultURL = "https://cellar-memory-proxy.sook40.workers.dev/api/wiki/append"
        return URL(string: override ?? defaultURL)
    }

    static func postWikiAppend(page: String, entry: String, commitMessage: String) async {
        guard let url = wikiProxyURL else { return }
        let payload = WikiAppendPayload(page: page, entry: entry, commitMessage: commitMessage)
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

    /// Ingest learnings from a successful game session into wiki pages via the Cloudflare Worker.
    /// POSTs each derived update to the Worker wiki-append endpoint.
    /// Best-effort — failures are logged to stderr but never block the user.
    static func ingest(record: SuccessRecord) async {
        let commitMessage = "wiki: ingest from \(record.gameName)"

        // 1. Append pitfalls to matching symptom pages
        for pitfall in record.pitfalls {
            let symptomSlug = slugify(pitfall.symptom)
            let candidates = ["symptoms/crash-on-launch.md", "symptoms/black-screen.md", "symptoms/d3d-errors.md"]
            let bestPage = findBestMatch(slug: symptomSlug, symptom: pitfall.symptom, candidates: candidates)
            let entry = formatPitfall(pitfall, gameName: record.gameName)
            await postWikiAppend(page: bestPage, entry: entry, commitMessage: commitMessage)
        }

        // 2. Append engine/graphics info to engine pages
        if let engine = record.engine?.lowercased() {
            let enginePages: [String: String] = [
                "directdraw": "engines/directdraw.md",
                "unity": "engines/unity.md",
                "dxvk": "engines/dxvk.md",
            ]
            let key = enginePages.keys.first { engine.contains($0) || (record.graphicsApi?.lowercased().contains($0) ?? false) }
            if let key = key, let pagePath = enginePages[key] {
                let entry = formatEngineEntry(record: record)
                await postWikiAppend(page: pagePath, entry: entry, commitMessage: commitMessage)
            }
        }

        // Also check graphicsApi independently (e.g., graphicsApi: "directdraw" without engine set)
        if let gfx = record.graphicsApi?.lowercased(), record.engine == nil || !(record.engine?.lowercased().contains(gfx) ?? false) {
            if gfx.contains("directdraw") || gfx.contains("ddraw") {
                let entry = formatEngineEntry(record: record)
                await postWikiAppend(page: "engines/directdraw.md", entry: entry, commitMessage: commitMessage)
            }
        }

        // 3. Append DLL override patterns to relevant pages
        for override in record.dllOverrides {
            if let source = override.source, source.lowercased().contains("cnc-ddraw") {
                let entry = "- \(record.gameName): `\(override.dll)=\(override.mode)` via \(source)"
                await postWikiAppend(page: "engines/directdraw.md", entry: entry, commitMessage: commitMessage)
            }
        }

        // 4. Append log entry summarizing this ingest
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let logEntry = "## [\(dateStr)] ingest | \(record.gameName) (gameId: \(record.gameId))"
        await postWikiAppend(page: "log.md", entry: logEntry, commitMessage: commitMessage)
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
