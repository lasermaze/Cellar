import Testing
import Foundation
@testable import cellar

// MARK: - MockHTTP

/// A test double for HTTPClient that responds with canned data per URL pattern.
final class MockHTTP: HTTPClient, @unchecked Sendable {

    struct Stub {
        let urlContains: String
        let statusCode: Int
        let body: Data
    }

    var stubs: [Stub] = []

    /// Records the last request body sent via POST (for write tests).
    var lastRequestBody: Data?
    var lastRequestURL: URL?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequestURL = request.url
        if let body = request.httpBody {
            lastRequestBody = body
        }

        let urlString = request.url?.absoluteString ?? ""
        for stub in stubs {
            if urlString.contains(stub.urlContains) {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: stub.statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (stub.body, response)
            }
        }
        // Default: 404 with empty body
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(), response)
    }

    func stub(urlContains: String, statusCode: Int, body: Data) {
        stubs.append(Stub(urlContains: urlContains, statusCode: statusCode, body: body))
    }

    func stub(urlContains: String, statusCode: Int, body: String) {
        stub(urlContains: urlContains, statusCode: statusCode, body: Data(body.utf8))
    }

    /// Make mock throw a network error for matching URLs.
    var throwErrorForURLContaining: String?
}

// MARK: - ThrowingMockHTTP

/// Mock that always throws a network error (simulates offline / DNS failure).
final class ThrowingMockHTTP: HTTPClient, @unchecked Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        throw URLError(.notConnectedToInternet)
    }
}

// MARK: - Test Helpers

private func makeTempCache() -> (KnowledgeCache, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("KSRemoteTest-\(UUID().uuidString)", isDirectory: true)
    return (KnowledgeCache(cacheDir: dir), dir)
}

private func cleanup(_ dir: URL) {
    try? FileManager.default.removeItem(at: dir)
}

private func makeConfigEntry(gameId: String = "test-game", gameName: String = "Test Game") -> ConfigEntry {
    let config = WorkingConfig(
        environment: ["DXVK_HUD": "1"],
        dllOverrides: [],
        registry: [],
        launchArgs: [],
        setupDeps: []
    )
    let env = EnvironmentFingerprint(
        arch: "arm64",
        wineVersion: "9.0",
        macosVersion: "15.0.0",
        wineFlavor: "wine-stable"
    )
    return CollectiveMemoryEntry(
        schemaVersion: 1,
        gameId: gameId,
        gameName: gameName,
        config: config,
        environment: env,
        environmentHash: "abc123",
        reasoning: "test entry",
        engine: nil,
        graphicsApi: nil,
        confirmations: 1,
        lastConfirmed: "2026-05-03T00:00:00Z"
    )
}

private func makeRemoteStore(
    http: HTTPClient,
    cacheDir: URL,
    memoryRepo: String = "owner/repo",
    wikiProxyURL: URL = URL(string: "https://mock.worker.dev")!
) -> KnowledgeStoreRemote {
    let cache = KnowledgeCache(cacheDir: cacheDir)
    return KnowledgeStoreRemote(
        cache: cache,
        http: http,
        memoryRepo: memoryRepo,
        wikiProxyURL: wikiProxyURL
    )
}

// MARK: - KnowledgeStoreRemoteTests

@Suite("KnowledgeStoreRemote — network adapter with TTL+stale cache")
struct KnowledgeStoreRemoteTests {

    // MARK: - Test 1: fetchContext returns merged context

    @Test("fetchContext returns merged context (config + game page + sessions) with 4000-char cap")
    func fetchContextMergesAllSources() async {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        let slug = slugify("Test Game")
        let configEntries = [makeConfigEntry()]
        let configJSON = (try? JSONEncoder().encode(configEntries)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        // Stub config fetch (GitHub raw)
        mock.stub(urlContains: "entries/\(slug).json", statusCode: 200, body: configJSON)
        // Stub game page fetch
        mock.stub(urlContains: "games/\(slug).md", statusCode: 200, body: "# Test Game\nGame page content.")
        // Stub sessions listing (GitHub API)
        mock.stub(urlContains: "contents/wiki/sessions", statusCode: 200, body: "[]")

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Test Game", environment: env)

        #expect(result != nil, "Should return non-nil context when all sources succeed")
        // 4000 char cap enforced
        if let result = result {
            #expect(result.count <= 4000, "Context must be capped at 4000 characters")
        }
    }

    // MARK: - Test 2: fetchContext falls back to stale cache on 403/429

    @Test("fetchContext falls back to stale cache on 403/429 network error")
    func fetchContextStaleOnRateLimit() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        let slug = slugify("Test Game")
        let configEntries = [makeConfigEntry()]
        let configData = (try? JSONEncoder().encode(configEntries)) ?? Data()

        // Pre-populate stale cache
        let cache = KnowledgeCache(cacheDir: dir)
        try cache.write(key: "config/\(slug).json", data: configData)
        // Backdate mtime so it's stale
        let cacheFile = cache.fileURL(for: "config/\(slug).json")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -7200)],
            ofItemAtPath: cacheFile.path
        )

        // Network returns 403
        mock.stub(urlContains: "entries/\(slug).json", statusCode: 403, body: "")
        mock.stub(urlContains: "games/\(slug).md", statusCode: 403, body: "")
        mock.stub(urlContains: "contents/wiki/sessions", statusCode: 403, body: "")

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Test Game", environment: env)

        #expect(result != nil, "Should fall back to stale cache on 403 rate limit")
    }

    // MARK: - Test 3: fetchContext returns nil when no cache AND network fails

    @Test("fetchContext returns nil when no cache exists and network fails")
    func fetchContextNilWhenBothFail() async {
        let throwingHttp = ThrowingMockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        let store = makeRemoteStore(http: throwingHttp, cacheDir: dir)
        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Nonexistent Game", environment: env)

        #expect(result == nil, "Should return nil when both network fails and cache is empty")
    }

    // MARK: - Test 4: write(.config) POSTs to /api/knowledge/write with correct body

    @Test("write(.config) POSTs to /api/knowledge/write with kind=config and entry payload")
    func writeConfigPostsCorrectBody() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        // Stub the write endpoint
        mock.stub(urlContains: "/api/knowledge/write", statusCode: 200, body: #"{"ok":true,"action":"upserted"}"#)

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let entry = makeConfigEntry()
        await store.write(.config(entry))

        #expect(mock.lastRequestBody != nil, "Should have made a POST request")

        if let body = mock.lastRequestBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["kind"] as? String == "config", "Kind must be 'config'")
            #expect(json["entry"] != nil, "Entry payload must be present")
        }
    }

    // MARK: - Test 5: write(.gamePage) POSTs with kind=gamePage

    @Test("write(.gamePage) POSTs to /api/knowledge/write with kind=gamePage")
    func writeGamePagePostsCorrectBody() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        mock.stub(urlContains: "/api/knowledge/write", statusCode: 200, body: #"{"ok":true,"action":"appended"}"#)

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let gamePage = GamePageEntry(slug: "half-life", autoContent: "# Half-Life\nContent.", commitMessage: nil)
        await store.write(.gamePage(gamePage))

        if let body = mock.lastRequestBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["kind"] as? String == "gamePage", "Kind must be 'gamePage'")
        }
    }

    // MARK: - Test 6: write(.sessionLog) POSTs with kind=sessionLog and overwrite=false

    @Test("write(.sessionLog) POSTs with kind=sessionLog and overwrite=false")
    func writeSessionLogPostsCorrectBody() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        mock.stub(urlContains: "/api/knowledge/write", statusCode: 200, body: #"{"ok":true,"action":"created"}"#)

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let sessionEntry = SessionLogEntry(
            path: "sessions/2026-05-03-test-game-abc12345.md",
            body: "# Test Game session",
            commitMessage: nil
        )
        await store.write(.sessionLog(sessionEntry))

        if let body = mock.lastRequestBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            #expect(json["kind"] as? String == "sessionLog", "Kind must be 'sessionLog'")
            // entry is a WikiAppendPayload: { "page": "...", "entry": "...", "overwrite": false }
            if let entryDict = json["entry"] as? [String: Any] {
                #expect(entryDict["overwrite"] as? Bool == false, "Session logs must use overwrite=false")
                #expect(entryDict["page"] != nil, "Session log entry must have a page path")
            }
        }
    }

    // MARK: - Test 7: write swallows non-fatal errors and never crashes

    @Test("write swallows non-fatal errors — never throws or crashes the agent loop")
    func writeSwallowsErrors() async {
        let throwingHttp = ThrowingMockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        let store = makeRemoteStore(http: throwingHttp, cacheDir: dir)
        let entry = makeConfigEntry()

        // Must not throw — swallowed internally
        await store.write(.config(entry))
        // Test passes if we reach here without crashing
        #expect(true, "write must never throw or crash even on network failure")
    }

    // MARK: - Test 8: Sanitizer filters env keys not in PolicyResources.envAllowlist

    @Test("Sanitizer in write path removes env keys not in PolicyResources.envAllowlist")
    func sanitizerFiltersDisallowedEnvKeys() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        mock.stub(urlContains: "/api/knowledge/write", statusCode: 200, body: #"{"ok":true,"action":"upserted"}"#)

        let store = makeRemoteStore(http: mock, cacheDir: dir)

        // Build entry with one allowed key (DXVK_HUD) and one disallowed key (MALICIOUS_KEY)
        let config = WorkingConfig(
            environment: ["DXVK_HUD": "1", "MALICIOUS_KEY": "malicious_value"],
            dllOverrides: [],
            registry: [],
            launchArgs: [],
            setupDeps: []
        )
        let env = EnvironmentFingerprint(
            arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable"
        )
        let entry = CollectiveMemoryEntry(
            schemaVersion: 1, gameId: "test-game", gameName: "Test Game",
            config: config, environment: env, environmentHash: "abc123",
            reasoning: "", engine: nil, graphicsApi: nil, confirmations: 1,
            lastConfirmed: "2026-05-03T00:00:00Z"
        )

        await store.write(.config(entry))

        // Decode the posted body and verify MALICIOUS_KEY is absent
        if let body = mock.lastRequestBody,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let entryDict = json["entry"] as? [String: Any],
           let configDict = entryDict["config"] as? [String: Any],
           let environment = configDict["environment"] as? [String: String] {
            #expect(environment["MALICIOUS_KEY"] == nil, "MALICIOUS_KEY must be removed by sanitizer")
        }
    }

    // MARK: - Test 9: list() queries api.github.com and returns parsed metadata

    @Test("list(filter:) calls api.github.com and returns parsed KnowledgeEntryMeta")
    func listQueriesGitHubAPI() async throws {
        let mock = MockHTTP()
        let (_, dir) = makeTempCache()
        defer { cleanup(dir) }

        // Stub the GitHub API directory listing
        let listing = """
        [
          {"name": "test-game.json", "path": "entries/test-game.json", "type": "file"},
          {"name": "half-life.json", "path": "entries/half-life.json", "type": "file"}
        ]
        """
        mock.stub(urlContains: "api.github.com", statusCode: 200, body: listing)

        let store = makeRemoteStore(http: mock, cacheDir: dir)
        let filter = KnowledgeListFilter(kind: .config, slug: nil, maxResults: 10)
        let results = await store.list(filter: filter)

        #expect(results.count == 2, "Should return 2 entries from the GitHub API listing")
        #expect(results.allSatisfy { $0.kind == .config }, "All results should be config kind")
    }
}
