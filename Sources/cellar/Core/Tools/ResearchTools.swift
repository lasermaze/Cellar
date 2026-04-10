import Foundation
@preconcurrency import SwiftSoup

// MARK: - Research Cache (private to this file — only used by searchWeb)

private struct ResearchCache: Codable {
    let gameId: String
    let fetchedAt: String  // ISO8601
    let results: [ResearchResult]

    func isStale() -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: fetchedAt) else { return true }
        return Date().timeIntervalSince(date) > 7 * 24 * 3600
    }
}

private struct ResearchResult: Codable {
    let source: String  // "winehq", "pcgamingwiki", "duckduckgo"
    let url: String
    let title: String
    let snippet: String
}

// MARK: - Research Tools Extension

extension AgentTools {

    // MARK: 17. search_web

    func searchWeb(input: JSONValue) async -> String {
        guard let query = input["query"]?.asString, !query.isEmpty else {
            return jsonResult(["error": "query is required"])
        }

        // Check research cache
        let cacheFile = CellarPaths.researchCacheFile(for: gameId)
        if let cacheData = try? Data(contentsOf: cacheFile),
           let cache = try? JSONDecoder().decode(ResearchCache.self, from: cacheData),
           !cache.isStale() {
            let resultDicts: [[String: String]] = cache.results.map { r in
                ["source": r.source, "url": r.url, "title": r.title, "snippet": r.snippet]
            }
            return jsonResult([
                "results": resultDicts,
                "from_cache": true,
                "result_count": cache.results.count,
                "game_id": gameId
            ])
        }

        // Build DuckDuckGo HTML search URL
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURLString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)+wine+compatibility"
        guard let searchURL = URL(string: searchURLString) else {
            return jsonResult(["error": "Failed to build search URL"])
        }

        // Fetch using async/await
        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let htmlData: Data
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            htmlData = data
        } catch {
            return jsonResult(["error": "Search failed: \(error.localizedDescription)"])
        }

        guard let html = String(data: htmlData, encoding: .utf8) else {
            return jsonResult(["error": "Search failed: Failed to decode response"])
        }

        // Parse HTML results
        var results: [ResearchResult] = []

        // Extract result blocks: look for result__a links and result__snippet
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.dotMatchesLineSeparators])
        let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators])

        let nsHTML = html as NSString
        let linkMatches = linkRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []
        let snippetMatches = snippetRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []

        let maxResults = min(linkMatches.count, 8)
        for i in 0..<maxResults {
            let linkMatch = linkMatches[i]
            let urlStr = nsHTML.substring(with: linkMatch.range(at: 1))
            let rawTitle = nsHTML.substring(with: linkMatch.range(at: 2))

            // Strip HTML tags from title
            let title = rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Get snippet if available
            var snippet = ""
            if i < snippetMatches.count {
                let snippetMatch = snippetMatches[i]
                let rawSnippet = nsHTML.substring(with: snippetMatch.range(at: 1))
                snippet = rawSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Determine source from URL
            let source: String
            if urlStr.contains("winehq.org") {
                source = "winehq"
            } else if urlStr.contains("pcgamingwiki.com") {
                source = "pcgamingwiki"
            } else if urlStr.contains("protondb.com") {
                source = "protondb"
            } else {
                source = "duckduckgo"
            }

            results.append(ResearchResult(source: source, url: urlStr, title: title, snippet: snippet))
        }

        // Save to research cache (single write after all results collected)
        let formatter = ISO8601DateFormatter()
        let cache = ResearchCache(gameId: gameId, fetchedAt: formatter.string(from: Date()), results: results)
        if let cacheData = try? JSONEncoder().encode(cache) {
            try? FileManager.default.createDirectory(at: CellarPaths.researchCacheDir, withIntermediateDirectories: true)
            try? cacheData.write(to: cacheFile)
        }

        let resultDicts: [[String: String]] = results.map { r in
            ["source": r.source, "url": r.url, "title": r.title, "snippet": r.snippet]
        }
        return jsonResult([
            "results": resultDicts,
            "from_cache": false,
            "result_count": results.count,
            "game_id": gameId
        ])
    }

    // MARK: 18. fetch_page

    func fetchPage(input: JSONValue) async -> String {
        guard let urlStr = input["url"]?.asString, !urlStr.isEmpty,
              let pageURL = URL(string: urlStr) else {
            return jsonResult(["error": "url is required and must be a valid URL"])
        }

        // Fetch using async/await
        var request = URLRequest(url: pageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let pageData: Data
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            pageData = data
        } catch {
            return jsonResult(["error": "Fetch failed: \(error.localizedDescription)", "url": urlStr])
        }

        guard let rawHTML = String(data: pageData, encoding: .utf8) ?? String(data: pageData, encoding: .ascii) else {
            return jsonResult(["error": "Fetch failed: Failed to decode page content", "url": urlStr])
        }

        // Parse with SwiftSoup + PageParser for structured extraction
        do {
            let doc = try SwiftSoup.parse(rawHTML)
            let parser = selectParser(for: pageURL)
            let parsed = try parser.parse(document: doc, url: pageURL)

            // Truncate textContent to 8000 chars
            let truncated = parsed.textContent.count > 8000
            let textContent = truncated ? String(parsed.textContent.prefix(8000)) : parsed.textContent

            // Build result with both text_content and extracted_fixes
            var result: [String: Any] = [
                "url": urlStr,
                "text_content": textContent,
                "length": textContent.count,
                "truncated": truncated,
            ]

            // Add extracted_fixes as serialized dict
            if !parsed.extractedFixes.isEmpty {
                let fixesData = try JSONEncoder().encode(parsed.extractedFixes)
                if let fixesDict = try JSONSerialization.jsonObject(with: fixesData) as? [String: Any] {
                    result["extracted_fixes"] = fixesDict
                }
            }

            return jsonResult(result)
        } catch {
            // Fallback: regex stripping if SwiftSoup parsing fails
            var cleaned = rawHTML
                .replacingOccurrences(of: #"<script[^>]*>[\s\S]*?</script>"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            cleaned = cleaned
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
            cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let truncated = cleaned.count > 8000
            if truncated {
                cleaned = String(cleaned.prefix(8000))
            }
            return jsonResult([
                "url": urlStr,
                "text_content": cleaned,
                "length": cleaned.count,
                "truncated": truncated,
                "parse_error": error.localizedDescription
            ])
        }
    }

    // MARK: - Wiki Lookup

    func queryWiki(input: JSONValue) -> String {
        guard case .object(let obj) = input,
              case .string(let query) = obj["query"] else {
            return jsonResult(["error": "query parameter required"])
        }
        return WikiService.search(query: query)
    }

    // MARK: - Compatibility Lookup

    func queryCompatibility(input: JSONValue) async -> String {
        guard case .object(let obj) = input,
              case .string(let gameName) = obj["game_name"] else {
            return "Error: game_name parameter required"
        }

        guard let report = await CompatibilityService.fetchReport(for: gameName) else {
            return "No compatibility data found for '\(gameName)'. Lutris and ProtonDB had no matching entries."
        }

        return report.formatForAgent()
    }

}
