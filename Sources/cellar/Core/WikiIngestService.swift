import Foundation

// MARK: - WikiIngestService

/// Orchestrates the fetch-format-POST pipeline for pre-compiling game wiki pages.
/// Fetches data from Lutris/ProtonDB (via CompatibilityService), WineHQ AppDB, and
/// PCGamingWiki, formats a structured markdown page, and POSTs it to the cellar-memory
/// Worker at wiki/games/{slug}.md.
struct WikiIngestService: Sendable {

    /// Maximum characters of free-text community notes per source
    private static let maxNotesLength = 1500

    // MARK: - Public API

    /// Ingest a single game: fetch all sources, format a wiki page, and POST to Worker.
    /// Returns true on success, false if skipped (TTL) or no data found.
    @discardableResult
    static func ingest(gameName: String) async -> Bool {
        let slug = WikiService.slugify(gameName)

        // a0. TTL check — skip if page was updated within 7 days
        if await isRecentlyUpdated(slug: slug, gameName: gameName) {
            return false
        }

        // a. Fetch CompatibilityReport (Lutris + ProtonDB)
        let report = await CompatibilityService.fetchReport(for: gameName)

        // b. Fetch WineHQ page (fixes + text)
        let wineHQPage = await fetchWineHQPage(gameName: gameName)

        // c. Fetch PCGamingWiki page (fixes + text)
        let pcgwPage = await fetchPCGWPage(gameName: gameName)

        // d. Skip if all sources returned nil/empty
        let hasReport = report != nil
        let hasWineHQ = wineHQPage.map { !$0.extractedFixes.isEmpty } ?? false
        let hasPCGW = pcgwPage.map { !$0.extractedFixes.isEmpty } ?? false
        let hasWineHQText = wineHQPage.map { !$0.textContent.isEmpty } ?? false
        let hasPCGWText = pcgwPage.map { !$0.textContent.isEmpty } ?? false
        guard hasReport || hasWineHQ || hasPCGW || hasWineHQText || hasPCGWText else {
            fputs("wiki-ingest: no data found for '\(gameName)', skipping\n", stderr)
            return false
        }

        // e. Format the page content
        let pageContent = formatGamePage(
            gameName: gameName,
            report: report,
            wineHQPage: wineHQPage,
            pcgwPage: pcgwPage
        )

        // g. POST full page content to games/{slug}.md
        let pagePath = "games/\(slug).md"
        await WikiService.postWikiAppend(
            page: pagePath,
            entry: pageContent,
            commitMessage: "wiki: ingest \(gameName)"
        )

        return true
    }

    // MARK: - TTL Check

    /// Returns true if the existing page was updated within the last 7 days.
    private static func isRecentlyUpdated(slug: String, gameName: String) async -> Bool {
        let rawURL = "https://raw.githubusercontent.com/\(CellarPaths.memoryRepo)/main/wiki/games/\(slug).md"
        guard let url = URL(string: rawURL) else { return false }

        guard let html = await fetchHTML(from: url) else {
            return false
        }

        let pattern = #"\*\*Last updated:\*\*\s*(\d{4}-\d{2}-\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let dateRange = Range(match.range(at: 1), in: html) else {
            return false
        }

        let dateStr = String(html[dateRange])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let pageDate = formatter.date(from: dateStr) else { return false }

        let daysSince = Calendar.current.dateComponents([.day], from: pageDate, to: Date()).day ?? 0
        if daysSince < 7 {
            fputs("wiki-ingest: skipping '\(gameName)' — wiki page updated \(daysSince) day(s) ago\n", stderr)
            return true
        }

        return false
    }

    // MARK: - Source Fetchers

    private static func fetchWineHQPage(gameName: String) async -> ParsedPage? {
        guard let encoded = gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://appdb.winehq.org/objectManager.php?sClass=application&sTitle=\(encoded)") else {
            return nil
        }
        guard let html = await fetchHTML(from: url), !html.isEmpty else { return nil }
        // Detect bot-protection pages (Anubis/Cloudflare challenge)
        if html.contains("Making sure you're not a bot") || html.contains("Anubis") || html.contains("proof-of-work") {
            return nil
        }
        guard let parsed = try? WineHQParser().parseHTML(html, url: url) else { return nil }
        if parsed.extractedFixes.isEmpty && parsed.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return parsed
    }

    private static func fetchPCGWPage(gameName: String) async -> ParsedPage? {
        let titleWithUnderscores = gameName
            .split(separator: " ")
            .map { String($0.prefix(1).uppercased() + $0.dropFirst()) }
            .joined(separator: "_")
        guard let encoded = titleWithUnderscores.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.pcgamingwiki.com/wiki/\(encoded)") else {
            return nil
        }
        guard let html = await fetchHTML(from: url), !html.isEmpty else { return nil }
        guard let parsed = try? PCGamingWikiParser().parseHTML(html, url: url) else { return nil }
        if parsed.extractedFixes.isEmpty && parsed.textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        return parsed
    }

    // MARK: - HTML Fetch Helper

    private static func fetchHTML(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let body = String(data: data, encoding: .utf8) else {
            return nil
        }
        return body
    }

    // MARK: - Page Formatter

    private static func formatGamePage(
        gameName: String,
        report: CompatibilityReport?,
        wineHQPage: ParsedPage?,
        pcgwPage: ParsedPage?
    ) -> String {
        let wineHQFixes = wineHQPage?.extractedFixes
        let pcgwFixes = pcgwPage?.extractedFixes

        let dateStr = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter.string(from: Date())
        }()

        // Build sources list
        var sources: [String] = []
        if let r = report {
            if r.installerCount > 0 { sources.append("Lutris") }
            if r.protonTier != nil { sources.append("ProtonDB") }
        }
        if wineHQPage != nil { sources.append("WineHQ") }
        if pcgwPage != nil { sources.append("PCGamingWiki") }
        let sourcesLine = sources.isEmpty ? "none" : sources.joined(separator: ", ")

        var lines: [String] = []

        // Header
        lines.append("# \(gameName)")
        lines.append("")
        lines.append("**Last updated:** \(dateStr) | Sources: \(sourcesLine)")
        lines.append("")

        // Compatibility section
        lines.append("## Compatibility")
        lines.append("")
        if let r = report, let tier = r.protonTier {
            let confidence = r.protonConfidence ?? "unknown"
            let total = r.protonTotal.map { "\($0)" } ?? "unknown"
            lines.append("**ProtonDB:** \(tier) (\(confidence), \(total) reports)")
        } else {
            lines.append("**ProtonDB:** No ProtonDB data available")
        }
        lines.append("")

        // Known Working Configuration (Lutris)
        lines.append("## Known Working Configuration (Lutris)")
        lines.append("")

        lines.append("**Environment variables:**")
        if let r = report, !r.lutrisEnvVars.isEmpty {
            for v in r.lutrisEnvVars {
                lines.append("- \(v.name)=\(v.value)")
            }
        } else {
            lines.append("(none)")
        }
        lines.append("")

        lines.append("**DLL overrides:**")
        if let r = report, !r.lutrisDlls.isEmpty {
            for dll in r.lutrisDlls {
                lines.append("- \(dll.name): \(dll.mode)")
            }
        } else {
            lines.append("(none)")
        }
        lines.append("")

        lines.append("**Winetricks:**")
        if let r = report, !r.lutrisWinetricks.isEmpty {
            for v in r.lutrisWinetricks {
                lines.append("- \(v.verb)")
            }
        } else {
            lines.append("(none)")
        }
        lines.append("")

        // Fixes section (WineHQ + PCGamingWiki combined)
        lines.append("## Fixes (WineHQ / PCGamingWiki)")
        lines.append("")

        // Combined env vars, deduplicated by key name
        let combinedEnvVars: [ExtractedEnvVar] = {
            var seen = Set<String>()
            var result: [ExtractedEnvVar] = []
            for fixes in [wineHQFixes, pcgwFixes].compactMap({ $0 }) {
                for v in fixes.envVars {
                    if seen.insert(v.name).inserted {
                        result.append(v)
                    }
                }
            }
            return result
        }()
        lines.append("**Environment variables:**")
        if combinedEnvVars.isEmpty {
            lines.append("(none)")
        } else {
            for v in combinedEnvVars {
                lines.append("- \(v.name)=\(v.value)")
            }
        }
        lines.append("")

        // Combined DLL overrides, deduplicated by name
        let combinedDlls: [ExtractedDLL] = {
            var seen = Set<String>()
            var result: [ExtractedDLL] = []
            for fixes in [wineHQFixes, pcgwFixes].compactMap({ $0 }) {
                for dll in fixes.dlls {
                    if seen.insert(dll.name.lowercased()).inserted {
                        result.append(dll)
                    }
                }
            }
            return result
        }()
        lines.append("**DLL overrides:**")
        if combinedDlls.isEmpty {
            lines.append("(none)")
        } else {
            for dll in combinedDlls {
                lines.append("- \(dll.name): \(dll.mode)")
            }
        }
        lines.append("")

        // Combined winetricks, deduplicated
        let combinedWinetricks: [ExtractedVerb] = {
            var seen = Set<String>()
            var result: [ExtractedVerb] = []
            for fixes in [wineHQFixes, pcgwFixes].compactMap({ $0 }) {
                for v in fixes.winetricks {
                    if seen.insert(v.verb.lowercased()).inserted {
                        result.append(v)
                    }
                }
            }
            return result
        }()
        lines.append("**Winetricks:**")
        if combinedWinetricks.isEmpty {
            lines.append("(none)")
        } else {
            for v in combinedWinetricks {
                lines.append("- \(v.verb)")
            }
        }
        lines.append("")

        // INI changes (PCGamingWiki only)
        let iniChanges = pcgwFixes?.iniChanges ?? []
        lines.append("**INI changes:**")
        if iniChanges.isEmpty {
            lines.append("(none)")
        } else {
            for ini in iniChanges {
                let file = ini.file.map { "\($0): " } ?? ""
                lines.append("- \(file)\(ini.key)=\(ini.value)")
            }
        }
        lines.append("")

        // Community Notes — free-text tips and tricks from WineHQ and PCGamingWiki
        let wineHQText = wineHQPage?.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pcgwText = pcgwPage?.textContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !wineHQText.isEmpty || !pcgwText.isEmpty {
            lines.append("## Community Notes")
            lines.append("")

            if !wineHQText.isEmpty {
                lines.append("### WineHQ AppDB")
                lines.append("")
                let truncated = truncateToLastSentence(wineHQText, maxLength: maxNotesLength)
                // Quote each line for readability
                for line in truncated.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        lines.append("> \(trimmed)")
                    }
                }
                lines.append("")
            }

            if !pcgwText.isEmpty {
                lines.append("### PCGamingWiki")
                lines.append("")
                let truncated = truncateToLastSentence(pcgwText, maxLength: maxNotesLength)
                for line in truncated.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        lines.append("> \(trimmed)")
                    }
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// Truncate text to maxLength, cutting at the last sentence boundary to avoid mid-word cutoff.
    private static func truncateToLastSentence(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let truncated = String(text.prefix(maxLength))
        // Find last sentence-ending punctuation
        if let lastPeriod = truncated.lastIndex(where: { $0 == "." || $0 == "!" || $0 == "?" }) {
            return String(truncated[...lastPeriod])
        }
        // Fall back to last newline
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[...lastNewline])
        }
        return truncated + "..."
    }
}
