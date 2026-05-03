import Testing
import Foundation
@testable import cellar

@Suite("KnowledgeEntry — Codable round-trip and discriminant validation")
struct KnowledgeEntryTests {

    // MARK: - Fixtures

    private func makeConfigEntry() -> CollectiveMemoryEntry {
        let config = WorkingConfig(
            environment: ["WINEDLLOVERRIDES": "ddraw=n,b"],
            dllOverrides: [
                DLLOverrideRecord(dll: "ddraw", mode: "n,b", placement: "game_dir", source: "cnc-ddraw")
            ],
            registry: [
                RegistryRecord(key: "HKCU\\Software\\Game", valueName: "Resolution", data: "800x600", purpose: "Set display")
            ],
            launchArgs: ["-nosound"],
            setupDeps: ["vcrun2019"]
        )
        let fingerprint = EnvironmentFingerprint(
            arch: "arm64",
            wineVersion: "9.0",
            macosVersion: "15.0.0",
            wineFlavor: "whisky"
        )
        return CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: "cossacks-european-wars",
            gameName: "Cossacks: European Wars",
            config: config,
            environment: fingerprint,
            environmentHash: fingerprint.computeHash(),
            reasoning: "Used cnc-ddraw to fix rendering on Apple Silicon.",
            engine: "custom",
            graphicsApi: "directdraw",
            confirmations: 3,
            lastConfirmed: "2026-03-30T00:00:00Z"
        )
    }

    // MARK: Test 1: .config round-trip

    @Test(".config case encodes with kind: \"config\" and round-trips")
    func configRoundTrip() throws {
        let entry = KnowledgeEntry.config(makeConfigEntry())
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(KnowledgeEntry.self, from: data)

        // Verify discriminant in wire JSON
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        if case .string(let kindStr) = json["kind"] {
            #expect(kindStr == "config", "JSON 'kind' field should be 'config'")
        } else {
            Issue.record("JSON 'kind' field missing or not a string")
        }

        // Verify round-trip
        if case .config(let inner) = decoded {
            #expect(inner.gameId == "cossacks-european-wars")
            #expect(inner.confirmations == 3)
        } else {
            Issue.record("Decoded entry should be .config case")
        }
    }

    // MARK: Test 2: .gamePage round-trip

    @Test(".gamePage case encodes with kind: \"gamePage\" and round-trips")
    func gamePageRoundTrip() throws {
        let page = GamePageEntry(
            slug: "half-life",
            autoContent: "## Half-Life\nRuns well with DXVK.",
            commitMessage: "ingest: half-life from protondb"
        )
        let entry = KnowledgeEntry.gamePage(page)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(KnowledgeEntry.self, from: data)

        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        if case .string(let kindStr) = json["kind"] {
            #expect(kindStr == "gamePage", "JSON 'kind' field should be 'gamePage'")
        } else {
            Issue.record("JSON 'kind' field missing or not a string")
        }

        if case .gamePage(let inner) = decoded {
            #expect(inner.slug == "half-life")
            #expect(inner.autoContent.contains("DXVK"))
            #expect(inner.commitMessage == "ingest: half-life from protondb")
        } else {
            Issue.record("Decoded entry should be .gamePage case")
        }
    }

    // MARK: Test 3: .sessionLog round-trip

    @Test(".sessionLog case encodes with kind: \"sessionLog\" and round-trips")
    func sessionLogRoundTrip() throws {
        let log = SessionLogEntry(
            path: "sessions/2026-05-03-half-life-abc123.md",
            body: "# Session Log\nInstalled vcrun2019, launched successfully.",
            commitMessage: "session: half-life success 2026-05-03"
        )
        let entry = KnowledgeEntry.sessionLog(log)
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(KnowledgeEntry.self, from: data)

        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        if case .string(let kindStr) = json["kind"] {
            #expect(kindStr == "sessionLog", "JSON 'kind' field should be 'sessionLog'")
        } else {
            Issue.record("JSON 'kind' field missing or not a string")
        }

        if case .sessionLog(let inner) = decoded {
            #expect(inner.path == "sessions/2026-05-03-half-life-abc123.md")
            #expect(inner.body.contains("vcrun2019"))
            #expect(inner.commitMessage == "session: half-life success 2026-05-03")
        } else {
            Issue.record("Decoded entry should be .sessionLog case")
        }
    }

    // MARK: Test 4: Unknown kind throws DecodingError

    @Test("Decoding unknown kind value throws a DecodingError")
    func unknownKindThrows() throws {
        let json = """
        {"kind": "unknownFutureKind", "entry": {"some": "data"}}
        """
        let data = Data(json.utf8)
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(KnowledgeEntry.self, from: data)
        }
    }

    // MARK: Test 5: KnowledgeWriteRequest wire shape

    @Test("KnowledgeWriteRequest produces {\"kind\":\"config\",\"entry\":{...}} wire shape")
    func writeRequestWireShape() throws {
        let configEntry = makeConfigEntry()
        let knowledgeEntry = KnowledgeEntry.config(configEntry)
        let request = KnowledgeWriteRequest(entry: knowledgeEntry)
        let data = try JSONEncoder().encode(request)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)

        // Outer envelope must have "kind" at the top level
        if case .string(let kindStr) = json["kind"] {
            #expect(kindStr == "config", "Wire shape should have kind='config' at outer level")
        } else {
            Issue.record("Wire shape missing 'kind' field")
        }

        // Must have "entry" field
        #expect(json["entry"] != nil, "Wire shape must have 'entry' field")
    }

    // MARK: - Computed property tests

    @Test(".kind computed property returns correct KnowledgeEntry.Kind")
    func kindProperty() {
        let configEntry = KnowledgeEntry.config(makeConfigEntry())
        #expect(configEntry.kind == .config)

        let pageEntry = KnowledgeEntry.gamePage(GamePageEntry(slug: "game", autoContent: "content", commitMessage: nil))
        #expect(pageEntry.kind == .gamePage)

        let logEntry = KnowledgeEntry.sessionLog(SessionLogEntry(path: "sessions/x.md", body: "body", commitMessage: nil))
        #expect(logEntry.kind == .sessionLog)
    }

    @Test(".slug computed property returns appropriate slug for each kind")
    func slugProperty() {
        let configEntry = KnowledgeEntry.config(makeConfigEntry())
        #expect(configEntry.slug == "cossacks-european-wars")

        let pageEntry = KnowledgeEntry.gamePage(GamePageEntry(slug: "half-life", autoContent: "", commitMessage: nil))
        #expect(pageEntry.slug == "half-life")

        // sessionLog derives slug from path: "sessions/2026-05-03-half-life-abc123.md" -> "2026-05-03-half-life-abc123"
        let logEntry = KnowledgeEntry.sessionLog(SessionLogEntry(path: "sessions/2026-05-03-half-life-abc123.md", body: "", commitMessage: nil))
        #expect(logEntry.slug == "2026-05-03-half-life-abc123")
    }
}
