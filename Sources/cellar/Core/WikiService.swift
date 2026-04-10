import Foundation

struct WikiService: Sendable {

    /// Maximum total characters of wiki content to return (prevents context bloat)
    private static let maxContentLength = 4000

    /// Maximum number of pages to load
    private static let maxPages = 3

    /// Fetch relevant wiki context for a game name and optional symptom keywords.
    /// Returns formatted wiki content block, or nil if wiki unavailable or no relevant pages found.
    static func fetchContext(for gameName: String, symptoms: [String] = []) -> String? {
        guard let wikiDir = Bundle.module.url(forResource: "wiki", withExtension: nil) else {
            return nil
        }
        let indexURL = wikiDir.appendingPathComponent("index.md")
        guard let indexContent = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return nil
        }

        let keywords = extractKeywords(gameName: gameName, symptoms: symptoms)
        let pagePaths = findRelevantPages(in: indexContent, keywords: keywords, limit: maxPages)
        guard !pagePaths.isEmpty else { return nil }

        var totalLength = 0
        var pageContents: [String] = []
        for path in pagePaths {
            let pageURL = wikiDir.appendingPathComponent(path)
            guard let content = try? String(contentsOf: pageURL, encoding: .utf8) else { continue }
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
    static func search(query: String) -> String {
        guard let wikiDir = Bundle.module.url(forResource: "wiki", withExtension: nil) else {
            return "Wiki not available"
        }
        let indexURL = wikiDir.appendingPathComponent("index.md")
        guard let indexContent = try? String(contentsOf: indexURL, encoding: .utf8) else {
            return "Wiki index not available"
        }

        let keywords = query.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 }
        let pagePaths = findRelevantPages(in: indexContent, keywords: keywords, limit: maxPages)
        guard !pagePaths.isEmpty else {
            return "No relevant wiki pages found for '\(query)'"
        }

        var pageContents: [String] = []
        var totalLength = 0
        for path in pagePaths {
            let pageURL = wikiDir.appendingPathComponent(path)
            guard let content = try? String(contentsOf: pageURL, encoding: .utf8) else { continue }
            if totalLength + content.count > maxContentLength && !pageContents.isEmpty { break }
            pageContents.append("[\(path)]\n\(content)")
            totalLength += content.count
        }

        return pageContents.joined(separator: "\n\n---\n\n")
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
