import Foundation
import Testing
@testable import cellar

@Suite("PageParser Tests")
struct PageParserTests {

    // MARK: - ExtractedFixes.isEmpty

    @Test("ExtractedFixes.isEmpty returns true when all arrays empty")
    func extractedFixesIsEmptyWhenAllEmpty() {
        let fixes = ExtractedFixes.empty
        #expect(fixes.isEmpty)
    }

    @Test("ExtractedFixes.isEmpty returns false when envVars has entries")
    func extractedFixesNotEmptyWithEnvVars() {
        var fixes = ExtractedFixes.empty
        fixes.envVars.append(ExtractedEnvVar(name: "WINEDEBUG", value: "-all", context: "test"))
        #expect(!fixes.isEmpty)
    }

    @Test("ExtractedFixes.isEmpty returns false when dlls has entries")
    func extractedFixesNotEmptyWithDlls() {
        var fixes = ExtractedFixes.empty
        fixes.dlls.append(ExtractedDLL(name: "ddraw", mode: "native", context: "test"))
        #expect(!fixes.isEmpty)
    }

    // MARK: - Parser canHandle

    @Test("WineHQParser.canHandle returns true for appdb.winehq.org URLs")
    func wineHQCanHandle() {
        let parser = WineHQParser()
        let url = URL(string: "https://appdb.winehq.org/objectManager.php?sClass=version&iId=12345")!
        #expect(parser.canHandle(url: url))
    }

    @Test("WineHQParser.canHandle returns false for other URLs")
    func wineHQCannotHandleOther() {
        let parser = WineHQParser()
        let url = URL(string: "https://pcgamingwiki.com/wiki/SomeGame")!
        #expect(!parser.canHandle(url: url))
    }

    @Test("PCGamingWikiParser.canHandle returns true for pcgamingwiki.com URLs")
    func pcgwCanHandle() {
        let parser = PCGamingWikiParser()
        let url = URL(string: "https://www.pcgamingwiki.com/wiki/SomeGame")!
        #expect(parser.canHandle(url: url))
    }

    @Test("PCGamingWikiParser.canHandle returns false for other URLs")
    func pcgwCannotHandleOther() {
        let parser = PCGamingWikiParser()
        let url = URL(string: "https://appdb.winehq.org/something")!
        #expect(!parser.canHandle(url: url))
    }

    @Test("GenericParser.canHandle returns true for any URL")
    func genericCanHandleAnything() {
        let parser = GenericParser()
        #expect(parser.canHandle(url: URL(string: "https://example.com")!))
        #expect(parser.canHandle(url: URL(string: "https://forums.wine.org/thread/123")!))
    }

    // MARK: - extractWineFixes

    @Test("extractWineFixes finds env vars like WINEDEBUG=-all")
    func extractEnvVars() {
        let text = "Try setting WINEDEBUG=-all before running"
        let fixes = extractWineFixes(from: text, context: "test")
        #expect(fixes.envVars.count == 1)
        #expect(fixes.envVars.first?.name == "WINEDEBUG")
        #expect(fixes.envVars.first?.value == "-all")
    }

    @Test("extractWineFixes finds DLL overrides like ddraw=native")
    func extractDllOverrides() {
        let text = "Set ddraw.dll=native in winecfg"
        let fixes = extractWineFixes(from: text, context: "test")
        #expect(fixes.dlls.count == 1)
        #expect(fixes.dlls.first?.name == "ddraw")
        #expect(fixes.dlls.first?.mode == "native")
    }

    @Test("extractWineFixes finds WINEDLLOVERRIDES compound and extracts individual DLLs")
    func extractCompoundDllOverrides() {
        let text = """
        WINEDLLOVERRIDES="ddraw=native;dinput=builtin"
        """
        let fixes = extractWineFixes(from: text, context: "test")
        #expect(fixes.dlls.count >= 2)
        let dllNames = Set(fixes.dlls.map { $0.name })
        #expect(dllNames.contains("ddraw"))
        #expect(dllNames.contains("dinput"))
    }

    @Test("extractWineFixes finds winetricks verbs")
    func extractWinetricksVerbs() {
        let text = "Run winetricks vcrun2019 d3dx9 to install runtimes"
        let fixes = extractWineFixes(from: text, context: "test")
        #expect(fixes.winetricks.count == 2)
        let verbs = Set(fixes.winetricks.map { $0.verb })
        #expect(verbs.contains("vcrun2019"))
        #expect(verbs.contains("d3dx9"))
    }

    @Test("extractWineFixes finds registry paths")
    func extractRegistryPaths() {
        let text = "Edit HKCU\\Software\\Wine\\Direct3D to set MaxVersionGL"
        let fixes = extractWineFixes(from: text, context: "test")
        #expect(fixes.registry.count == 1)
        #expect(fixes.registry.first?.path.contains("HKCU\\Software\\Wine\\Direct3D") == true)
    }

    // MARK: - Parser parse() integration

    @Test("WineHQ parser extracts text from panel-forum panel-body elements")
    func wineHQParserExtractsComments() throws {
        let html = """
        <html><body>
        <div class="panel panel-default panel-forum">
            <div class="panel-heading">Test Comment</div>
            <div class="panel-body">Set WINEDEBUG=-all and use ddraw.dll=native</div>
        </div>
        </body></html>
        """
        let parser = WineHQParser()
        let url = URL(string: "https://appdb.winehq.org/objectManager.php?sClass=version&iId=1")!
        let result = try parser.parseHTML(html, url: url)
        #expect(!result.textContent.isEmpty)
        #expect(!result.extractedFixes.isEmpty)
    }

    @Test("PCGamingWiki parser extracts text from mw-parser-output elements")
    func pcgwParserExtractsContent() throws {
        let html = """
        <html><body>
        <div class="mw-parser-output">
            <p>This game has Wine compatibility issues.</p>
            <pre>WINEDEBUG=-all wine game.exe</pre>
            <table class="wikitable"><tr><td>Fix info</td></tr></table>
        </div>
        </body></html>
        """
        let parser = PCGamingWikiParser()
        let url = URL(string: "https://www.pcgamingwiki.com/wiki/TestGame")!
        let result = try parser.parseHTML(html, url: url)
        #expect(!result.textContent.isEmpty)
        #expect(!result.extractedFixes.isEmpty)
    }

    @Test("Generic parser extracts text from pre, code, and table elements")
    func genericParserExtractsElements() throws {
        let html = """
        <html><body>
            <p>Some content about Wine.</p>
            <pre>WINEDEBUG=-all</pre>
            <code>ddraw.dll=native</code>
            <table><tr><td>winetricks vcrun2019</td></tr></table>
        </body></html>
        """
        let parser = GenericParser()
        let url = URL(string: "https://forums.example.com/thread/123")!
        let result = try parser.parseHTML(html, url: url)
        #expect(!result.textContent.isEmpty)
        #expect(!result.extractedFixes.isEmpty)
    }

    @Test("All parsers produce both textContent and extractedFixes in ParsedPage")
    func allParsersProduceBothFields() throws {
        let html = """
        <html><body>
        <div class="panel panel-default panel-forum">
            <div class="panel-body">Use WINEDEBUG=-all</div>
        </div>
        </body></html>
        """
        let url = URL(string: "https://appdb.winehq.org/test")!
        let parser = selectParser(for: url)
        let result = try parser.parseHTML(html, url: url)
        // ParsedPage should have both fields
        let _ = result.textContent
        let _ = result.extractedFixes
    }

    // MARK: - selectParser

    @Test("selectParser returns WineHQParser for appdb.winehq.org")
    func selectParserWineHQ() {
        let parser = selectParser(for: URL(string: "https://appdb.winehq.org/test")!)
        #expect(parser is WineHQParser)
    }

    @Test("selectParser returns PCGamingWikiParser for pcgamingwiki.com")
    func selectParserPCGW() {
        let parser = selectParser(for: URL(string: "https://www.pcgamingwiki.com/wiki/Test")!)
        #expect(parser is PCGamingWikiParser)
    }

    @Test("selectParser returns GenericParser for unknown URLs")
    func selectParserGeneric() {
        let parser = selectParser(for: URL(string: "https://example.com")!)
        #expect(parser is GenericParser)
    }
}
