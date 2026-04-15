import Foundation

// MARK: - WikiIngestService

/// Orchestrates the fetch-format-POST pipeline for pre-compiling game wiki pages.
/// Fetches data from Lutris/ProtonDB (via CompatibilityService), WineHQ AppDB, and
/// PCGamingWiki, formats a structured markdown page, and POSTs it to the cellar-memory
/// Worker at wiki/games/{slug}.md.
struct WikiIngestService: Sendable {

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

        // b. Fetch WineHQ fixes
        let wineHQFixes = await fetchWineHQFixes(gameName: gameName)

        // c. Fetch PCGamingWiki fixes
        let pcgwFixes = await fetchPCGWFixes(gameName: gameName)

        // d. Skip if all sources returned nil/empty
        let hasReport = report != nil
        let hasWineHQ = wineHQFixes.map { !$0.isEmpty } ?? false
        let hasPCGW = pcgwFixes.map { !$0.isEmpty } ?? false
        guard hasReport || hasWineHQ || hasPCGW else {
            fputs("wiki-ingest: no data found for '\(gameName)', skipping\n", stderr)
            return false
        }

        // e. Format the page content
        let pageContent = formatGamePage(
            gameName: gameName,
            report: report,
            wineHQFixes: wineHQFixes,
            pcgwFixes: pcgwFixes
        )

        // f. slug already computed above (step a0)

        // g. POST full page content to games/{slug}.md
        let pagePath = "games/\(slug).md"
        await WikiService.postWikiAppend(
            page: pagePath,
            entry: pageContent,
            commitMessage: "wiki: ingest \(gameName)"
        )

        // h. Return success
        return true
    }

    // MARK: - TTL Check

    /// Returns true if the existing page was updated within the last 7 days.
    private static func isRecentlyUpdated(slug: String, gameName: String) async -> Bool {
        let rawURL = "https://raw.githubusercontent.com/\(CellarPaths.memoryRepo)/main/wiki/games/\(slug).md"
        guard let url = URL(string: rawURL) else { return false }

        guard let html = await fetchHTML(from: url) else {
            // Network error or 404 — assume stale, proceed with ingest
            return false
        }

        // Parse "**Last updated:** yyyy-MM-dd" line
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

    private static func fetchWineHQFixes(gameName: String) async -> ExtractedFixes? {
        guard let encoded = gameName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://appdb.winehq.org/objectManager.php?sClass=application&sTitle=\(encoded)") else {
            return nil
        }
        guard let html = await fetchHTML(from: url), !html.isEmpty else { return nil }
        let parsed = try? WineHQParser().parseHTML(html, url: url)
        let fixes = parsed?.extractedFixes
        return (fixes?.isEmpty == false) ? fixes : nil
    }

    private static func fetchPCGWFixes(gameName: String) async -> ExtractedFixes? {
        // Replace spaces with underscores, percent-encode for URL path
        let titleWithUnderscores = gameName
            .split(separator: " ")
            .map { String($0.prefix(1).uppercased() + $0.dropFirst()) }
            .joined(separator: "_")
        guard let encoded = titleWithUnderscores.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://www.pcgamingwiki.com/wiki/\(encoded)") else {
            return nil
        }
        guard let html = await fetchHTML(from: url), !html.isEmpty else { return nil }
        let parsed = try? PCGamingWikiParser().parseHTML(html, url: url)
        let fixes = parsed?.extractedFixes
        return (fixes?.isEmpty == false) ? fixes : nil
    }

    // MARK: - HTML Fetch Helper

    /// Perform a GET request, return the HTML body on HTTP 200, nil otherwise. Timeout: 15 seconds.
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
        wineHQFixes: ExtractedFixes?,
        pcgwFixes: ExtractedFixes?
    ) -> String {
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
        if wineHQFixes != nil { sources.append("WineHQ") }
        if pcgwFixes != nil { sources.append("PCGamingWiki") }
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

        return lines.joined(separator: "\n")
    }
}
