import Foundation
@preconcurrency import SwiftSoup

// MARK: - Data Models

struct ExtractedEnvVar: Codable {
    let name: String
    let value: String
    let context: String
}

struct ExtractedRegistry: Codable {
    let path: String
    let value: String?
    let context: String
}

struct ExtractedDLL: Codable {
    let name: String
    let mode: String
    let context: String
}

struct ExtractedVerb: Codable {
    let verb: String
    let context: String
}

struct ExtractedINI: Codable {
    let file: String?
    let key: String
    let value: String
    let context: String
}

struct ExtractedFixes: Codable {
    var envVars: [ExtractedEnvVar]
    var registry: [ExtractedRegistry]
    var dlls: [ExtractedDLL]
    var winetricks: [ExtractedVerb]
    var iniChanges: [ExtractedINI]

    var isEmpty: Bool {
        envVars.isEmpty && registry.isEmpty && dlls.isEmpty &&
        winetricks.isEmpty && iniChanges.isEmpty
    }

    static let empty = ExtractedFixes(envVars: [], registry: [], dlls: [], winetricks: [], iniChanges: [])

    mutating func merge(_ other: ExtractedFixes) {
        envVars += other.envVars
        registry += other.registry
        dlls += other.dlls
        winetricks += other.winetricks
        iniChanges += other.iniChanges
    }
}

struct ParsedPage {
    let textContent: String
    let extractedFixes: ExtractedFixes
}

// MARK: - Protocol

protocol PageParser {
    func canHandle(url: URL) -> Bool
    func parse(document: Document, url: URL) throws -> ParsedPage
}

extension PageParser {
    /// Convenience: parse from raw HTML string
    func parseHTML(_ html: String, url: URL) throws -> ParsedPage {
        let doc = try SwiftSoup.parse(html)
        return try parse(document: doc, url: url)
    }
}

// MARK: - Regex Extraction

/// Extract Wine-specific fix artifacts from text content using regex patterns.
func extractWineFixes(from text: String, context: String) -> ExtractedFixes {
    var fixes = ExtractedFixes.empty

    // Track what we've already extracted to deduplicate
    var seenEnvVars = Set<String>()
    var seenDlls = Set<String>()
    var seenVerbs = Set<String>()
    var seenRegistry = Set<String>()

    // --- WINEDLLOVERRIDES compound extraction (must come before individual DLL matching) ---
    let dllOverridePattern = #"WINEDLLOVERRIDES\s*=\s*["']?([^"'\n]+)"#
    var compoundDllNames = Set<String>()

    if let regex = try? NSRegularExpression(pattern: dllOverridePattern, options: []) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            if match.numberOfRanges > 1 {
                let overrideStr = nsText.substring(with: match.range(at: 1))
                // Parse "dll1=mode;dll2=mode" format
                let parts = overrideStr.split(separator: ";")
                for part in parts {
                    let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
                    if kv.count == 2 {
                        let dllName = kv[0].trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: ".dll", with: "")
                        let mode = kv[1].trimmingCharacters(in: .whitespaces)
                        let key = "\(dllName)=\(mode)"
                        if !seenDlls.contains(key) {
                            seenDlls.insert(key)
                            compoundDllNames.insert(dllName.lowercased())
                            fixes.dlls.append(ExtractedDLL(name: dllName, mode: mode, context: context))
                        }
                    }
                }
            }
        }
    }

    // --- Environment variables ---
    let envVarPattern = #"(WINE(?:DEBUG|_CPU_TOPOLOGY)|DXVK_\w+|MESA_\w+|STAGING_\w+)\s*=\s*([^\s,;"']+)"#
    if let regex = try? NSRegularExpression(pattern: envVarPattern, options: []) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            if match.numberOfRanges > 2 {
                let name = nsText.substring(with: match.range(at: 1))
                let value = nsText.substring(with: match.range(at: 2))
                let key = "\(name)=\(value)"
                if !seenEnvVars.contains(key) {
                    seenEnvVars.insert(key)
                    fixes.envVars.append(ExtractedEnvVar(name: name, value: value, context: context))
                }
            }
        }
    }

    // --- Individual DLL overrides (not from WINEDLLOVERRIDES) ---
    let dllPattern = #"(\w+(?:\.dll)?)\s*=\s*(native|builtin|n,b|b,n|n|b|disabled)"#
    if let regex = try? NSRegularExpression(pattern: dllPattern, options: []) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            if match.numberOfRanges > 2 {
                let fullRange = match.range
                // Skip if this match is inside a WINEDLLOVERRIDES= context
                let prefixStart = max(0, fullRange.location - 30)
                let prefixRange = NSRange(location: prefixStart, length: fullRange.location - prefixStart)
                let prefix = nsText.substring(with: prefixRange)
                if prefix.contains("WINEDLLOVERRIDES") { continue }

                var dllName = nsText.substring(with: match.range(at: 1))
                let mode = nsText.substring(with: match.range(at: 2))

                // Strip .dll suffix for normalized name
                dllName = dllName.replacingOccurrences(of: ".dll", with: "")

                // Skip generic words that happen to precede =native etc.
                let genericWords: Set<String> = ["set", "use", "the", "for", "and", "type", "mode", "value", "name", "option"]
                if genericWords.contains(dllName.lowercased()) { continue }

                // Skip if already captured from WINEDLLOVERRIDES
                if compoundDllNames.contains(dllName.lowercased()) { continue }

                let key = "\(dllName)=\(mode)"
                if !seenDlls.contains(key) {
                    seenDlls.insert(key)
                    fixes.dlls.append(ExtractedDLL(name: dllName, mode: mode, context: context))
                }
            }
        }
    }

    // --- Winetricks verbs ---
    // Common English stop words that should not be treated as winetricks verbs
    let verbStopWords: Set<String> = [
        "to", "the", "and", "for", "run", "set", "use", "with", "from", "install",
        "before", "after", "then", "also", "like", "this", "that", "will", "can",
        "may", "should", "must", "just", "try", "runtimes", "fixes", "first",
        "next", "some", "all", "any", "not", "but", "or", "if", "in", "on", "at",
    ]
    let winetricksPattern = #"winetricks\s+((?:[a-z0-9_]+\s*)+)"#
    if let regex = try? NSRegularExpression(pattern: winetricksPattern, options: .caseInsensitive) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            if match.numberOfRanges > 1 {
                let verbString = nsText.substring(with: match.range(at: 1))
                let verbs = verbString.split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                    .filter {
                        $0.count >= 2 &&
                        $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } &&
                        !verbStopWords.contains($0.lowercased())
                    }
                for verb in verbs {
                    if !seenVerbs.contains(verb.lowercased()) {
                        seenVerbs.insert(verb.lowercased())
                        fixes.winetricks.append(ExtractedVerb(verb: verb, context: context))
                    }
                }
            }
        }
    }

    // --- Registry paths ---
    let registryPattern = #"(HKCU|HKLM|HKEY_CURRENT_USER|HKEY_LOCAL_MACHINE)\\[\\A-Za-z0-9_ ]+"#
    if let regex = try? NSRegularExpression(pattern: registryPattern, options: []) {
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let path = nsText.substring(with: match.range)
            if !seenRegistry.contains(path) {
                seenRegistry.insert(path)
                fixes.registry.append(ExtractedRegistry(path: path, value: nil, context: context))
            }
        }
    }

    // --- INI changes (only near .ini/.cfg file references) ---
    let iniFilePattern = #"(\w+\.(?:ini|cfg))"#
    if let iniFileRegex = try? NSRegularExpression(pattern: iniFilePattern, options: .caseInsensitive) {
        let nsText = text as NSString
        let iniFileMatches = iniFileRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for fileMatch in iniFileMatches {
            let fileName = nsText.substring(with: fileMatch.range)
            // Look for key=value patterns within ~200 chars of the .ini/.cfg reference
            let searchStart = max(0, fileMatch.range.location - 100)
            let searchEnd = min(nsText.length, fileMatch.range.location + fileMatch.range.length + 200)
            let searchRange = NSRange(location: searchStart, length: searchEnd - searchStart)
            let searchText = nsText.substring(with: searchRange)

            let kvPattern = #"(\w+)\s*=\s*(\w+)"#
            if let kvRegex = try? NSRegularExpression(pattern: kvPattern, options: []) {
                let nsSearch = searchText as NSString
                let kvMatches = kvRegex.matches(in: searchText, options: [], range: NSRange(location: 0, length: nsSearch.length))
                for kvMatch in kvMatches {
                    if kvMatch.numberOfRanges > 2 {
                        let key = nsSearch.substring(with: kvMatch.range(at: 1))
                        let value = nsSearch.substring(with: kvMatch.range(at: 2))
                        // Skip the filename itself and generic words
                        let skipKeys: Set<String> = ["ini", "cfg", "file", "set", "the", "dll"]
                        if skipKeys.contains(key.lowercased()) { continue }
                        if key.hasSuffix(".ini") || key.hasSuffix(".cfg") { continue }
                        fixes.iniChanges.append(ExtractedINI(file: fileName, key: key, value: value, context: context))
                    }
                }
            }
        }
    }

    return fixes
}

// MARK: - Parser Implementations

struct WineHQParser: PageParser {
    func canHandle(url: URL) -> Bool {
        url.host?.contains("appdb.winehq.org") == true
    }

    func parse(document: Document, url: URL) throws -> ParsedPage {
        var allText = ""
        var fixes = ExtractedFixes.empty

        // Extract test results from table rows
        if let testRows = try? document.select("table.whq-table tr") {
            for row in testRows {
                if let text = try? row.text(), !text.isEmpty {
                    allText += text + "\n"
                }
            }
        }

        // Extract comments from panel-forum elements
        let comments = (try? document.select("div.panel-forum .panel-body")) ?? Elements()
        if comments.isEmpty() {
            // Fallback to generic extraction if no forum panels found
            return try GenericParser().parse(document: document, url: url)
        }

        for comment in comments {
            if let text = try? comment.text(), !text.isEmpty {
                allText += text + "\n"
                let commentFixes = extractWineFixes(from: text, context: "WineHQ AppDB comment")
                fixes.merge(commentFixes)
            }
        }

        return ParsedPage(textContent: allText, extractedFixes: fixes)
    }
}

struct PCGamingWikiParser: PageParser {
    func canHandle(url: URL) -> Bool {
        url.host?.contains("pcgamingwiki.com") == true
    }

    func parse(document: Document, url: URL) throws -> ParsedPage {
        var allText = ""
        var fixes = ExtractedFixes.empty

        // Check if mw-parser-output exists
        let parserOutput = try? document.select(".mw-parser-output")
        if parserOutput == nil || parserOutput!.isEmpty() {
            return try GenericParser().parse(document: document, url: url)
        }

        // Extract code blocks
        let codeBlocks = (try? document.select(".mw-parser-output pre, .mw-parser-output code")) ?? Elements()
        for block in codeBlocks {
            if let text = try? block.text(), !text.isEmpty {
                let blockFixes = extractWineFixes(from: text, context: "PCGamingWiki")
                fixes.merge(blockFixes)
            }
        }

        // Extract table content
        let tables = (try? document.select(".mw-parser-output table.wikitable")) ?? Elements()
        for table in tables {
            if let cells = try? table.select("td") {
                for cell in cells {
                    if let text = try? cell.text(), !text.isEmpty {
                        let cellFixes = extractWineFixes(from: text, context: "PCGamingWiki")
                        fixes.merge(cellFixes)
                    }
                }
            }
        }

        // Extract fix-related section content AND build targeted textContent
        let headings = (try? document.select(".mw-parser-output h2, .mw-parser-output h3")) ?? Elements()
        let fixKeywords = ["fix", "workaround", "improvement", "issue", "essential", "note", "bug",
                           "compatibility", "wine", "proton", "linux", "crash", "audio", "video",
                           "graphic", "display", "input", "network", "other information"]
        for heading in headings {
            if let headingText = try? heading.text().lowercased(),
               fixKeywords.contains(where: { headingText.contains($0) }) {
                // Add the section heading to text
                if let title = try? heading.text() {
                    allText += "### \(title)\n"
                }
                // Gather sibling content until next heading
                var sibling = try? heading.nextElementSibling()
                while let el = sibling {
                    let tagName = el.tagName()
                    if tagName == "h2" || tagName == "h3" { break }
                    if let text = try? el.text(), !text.isEmpty {
                        let sectionFixes = extractWineFixes(from: text, context: "PCGamingWiki")
                        fixes.merge(sectionFixes)
                        allText += text + "\n"
                    }
                    sibling = try? el.nextElementSibling()
                }
            }
        }

        // Capture intro paragraph (first <p> in content — game description)
        if let paragraphs = try? document.select(".mw-parser-output p") {
            for p in paragraphs {
                if let introText = try? p.text(), introText.count >= 30 {
                    allText = introText + "\n\n" + allText
                    break
                }
            }
        }

        return ParsedPage(textContent: allText, extractedFixes: fixes)
    }
}

struct GenericParser: PageParser {
    func canHandle(url: URL) -> Bool {
        true
    }

    func parse(document: Document, url: URL) throws -> ParsedPage {
        var fixes = ExtractedFixes.empty

        // Extract pre, code, and table elements
        let codeBlocks = (try? document.select("pre, code")) ?? Elements()
        for block in codeBlocks {
            if let text = try? block.text(), !text.isEmpty {
                let blockFixes = extractWineFixes(from: text, context: "Web page")
                fixes.merge(blockFixes)
            }
        }

        let tables = (try? document.select("table")) ?? Elements()
        for table in tables {
            if let text = try? table.text(), !text.isEmpty {
                let tableFixes = extractWineFixes(from: text, context: "Web page")
                fixes.merge(tableFixes)
            }
        }

        // Build text content from body
        var textContent = ""
        if let body = document.body() {
            textContent = (try? body.text()) ?? ""
        }

        // Truncate to 8000 characters
        if textContent.count > 8000 {
            textContent = String(textContent.prefix(8000))
        }

        return ParsedPage(textContent: textContent, extractedFixes: fixes)
    }
}

// MARK: - Parser Dispatch

func selectParser(for url: URL) -> PageParser {
    let parsers: [PageParser] = [WineHQParser(), PCGamingWikiParser(), GenericParser()]
    return parsers.first { $0.canHandle(url: url) } ?? GenericParser()
}
