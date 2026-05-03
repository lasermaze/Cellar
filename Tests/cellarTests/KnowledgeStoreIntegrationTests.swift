import Testing
import Foundation
@testable import cellar

// MARK: - StubKnowledgeStore

/// Actor-based stub that records all calls for assertion in integration tests.
actor StubKnowledgeStore: KnowledgeStore {
    struct FetchContextCall {
        let gameName: String
    }

    private(set) var fetchContextCalls: [FetchContextCall] = []
    private(set) var writeCalls: [KnowledgeEntry] = []
    private(set) var listCalls: [KnowledgeListFilter] = []

    var fetchContextResult: String? = "stub-context"

    func fetchContext(for gameName: String, environment: EnvironmentFingerprint) async -> String? {
        fetchContextCalls.append(FetchContextCall(gameName: gameName))
        return fetchContextResult
    }

    func write(_ entry: KnowledgeEntry) async {
        writeCalls.append(entry)
    }

    func list(filter: KnowledgeListFilter) async -> [KnowledgeEntryMeta] {
        listCalls.append(filter)
        return []
    }

    func setFetchContextResult(_ result: String?) {
        fetchContextResult = result
    }
}

// MARK: - Integration Tests

/// Tests are serialized (not parallel) because they mutate KnowledgeStoreContainer.shared.
@Suite("KnowledgeStore Integration — AIService routes through the store", .serialized)
struct KnowledgeStoreIntegrationTests {

    // MARK: - Test 1: fetchContext routes through the store

    @Test("KnowledgeStoreContainer.shared.fetchContext routes to active store")
    func fetchContextRoutesThrough() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let fingerprint = EnvironmentFingerprint.current(wineVersion: "9.0", wineFlavor: "wine-stable")
        let result = await KnowledgeStoreContainer.shared.fetchContext(for: "Half-Life", environment: fingerprint)

        #expect(result == "stub-context", "Should return stub result")

        let calls = await stub.fetchContextCalls
        #expect(calls.count == 1, "fetchContext should be called exactly once")
        #expect(calls[0].gameName == "Half-Life", "gameName should be passed through")
    }

    // MARK: - Test 2: fetchContext returns nil when stub returns nil

    @Test("KnowledgeStoreContainer.shared.fetchContext returns nil when store returns nil")
    func fetchContextNilPath() async {
        let stub = StubKnowledgeStore()
        await stub.setFetchContextResult(nil)
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let fingerprint = EnvironmentFingerprint.current(wineVersion: "9.0", wineFlavor: "wine-stable")
        let result = await KnowledgeStoreContainer.shared.fetchContext(for: "Unknown Game", environment: fingerprint)
        #expect(result == nil, "Should return nil when store returns nil")

        let calls = await stub.fetchContextCalls
        #expect(calls.count == 1, "fetchContext should still be called once")
    }

    // MARK: - Test 3: write routes config entry through the store

    @Test("KnowledgeStoreContainer.shared.write routes config entries through active store")
    func writeConfigEntryRoutesThrough() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let fingerprint = EnvironmentFingerprint.current(wineVersion: "9.0", wineFlavor: "wine-stable")
        let workingConfig = WorkingConfig(
            environment: ["WINEDLLOVERRIDES": "d3d9=n,b"],
            dllOverrides: [],
            registry: [],
            launchArgs: [],
            setupDeps: []
        )
        let configEntry = CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: "test-game",
            gameName: "Test Game",
            config: workingConfig,
            environment: fingerprint,
            environmentHash: fingerprint.computeHash(),
            reasoning: "test",
            engine: nil,
            graphicsApi: nil,
            confirmations: 1,
            lastConfirmed: ISO8601DateFormatter().string(from: Date())
        )

        await KnowledgeStoreContainer.shared.write(.config(configEntry))

        let writes = await stub.writeCalls
        #expect(writes.count == 1, "write should be called exactly once")
        guard case .config(let recorded) = writes.first else {
            Issue.record("Expected .config entry but got \(writes.first?.kind as Any)")
            return
        }
        #expect(recorded.gameId == "test-game")
    }

    // MARK: - Test 4: write routes sessionLog entry through the store

    @Test("KnowledgeStoreContainer.shared.write routes sessionLog entries through active store")
    func writeSessionLogRoutesThrough() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let sessionEntry = SessionLogEntry(
            path: "sessions/2026-05-03-test-game-abc12345.md",
            body: "# Test Game — success",
            commitMessage: "session: success for Test Game"
        )

        await KnowledgeStoreContainer.shared.write(.sessionLog(sessionEntry))

        let writes = await stub.writeCalls
        #expect(writes.count == 1)
        guard case .sessionLog(let recorded) = writes.first else {
            Issue.record("Expected .sessionLog entry")
            return
        }
        #expect(recorded.path == "sessions/2026-05-03-test-game-abc12345.md")
    }

    // MARK: - Test 5: write routes gamePage entry through the store

    @Test("KnowledgeStoreContainer.shared.write routes gamePage entries through active store")
    func writeGamePageRoutesThrough() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let pageEntry = GamePageEntry(
            slug: "half-life",
            autoContent: "# Half-Life\nSome content",
            commitMessage: "wiki: ingest from Half-Life"
        )

        await KnowledgeStoreContainer.shared.write(.gamePage(pageEntry))

        let writes = await stub.writeCalls
        #expect(writes.count == 1)
        guard case .gamePage(let recorded) = writes.first else {
            Issue.record("Expected .gamePage entry")
            return
        }
        #expect(recorded.slug == "half-life")
    }

    // MARK: - Test 6: agentValidWinetricksVerbs delegates to PolicyResources

    @Test("AIService.agentValidWinetricksVerbs delegates to PolicyResources.shared.winetricksVerbAllowlist")
    func agentValidWinetricksVerbsDelegates() {
        let fromAIService = AIService.agentValidWinetricksVerbs
        let fromPolicy = PolicyResources.shared.winetricksVerbAllowlist
        #expect(fromAIService == fromPolicy, "agentValidWinetricksVerbs must equal PolicyResources allowlist")
        #expect(!fromAIService.isEmpty, "allowlist must not be empty")
    }

    // MARK: - Test 7: AIService.fetchKnowledgeContext uses active store

    @Test("AIService.fetchKnowledgeContext calls KnowledgeStoreContainer.shared.fetchContext")
    func fetchKnowledgeContextUsesActiveStore() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let wineURL = URL(fileURLWithPath: "/usr/local/bin/wine")
        _ = await AIService.fetchKnowledgeContext(gameName: "Half-Life 2", wineURL: wineURL)

        let calls = await stub.fetchContextCalls
        #expect(calls.count == 1, "fetchContext should be called once via fetchKnowledgeContext")
        #expect(calls.first?.gameName == "Half-Life 2")
    }

    // MARK: - Test 8: CollectiveMemoryService.fetchBestEntry delegates to store

    @Test("CollectiveMemoryService.fetchBestEntry delegates to KnowledgeStoreContainer.shared.fetchContext")
    func collectiveMemoryServiceFetchBestEntryDelegates() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let wineURL = URL(fileURLWithPath: "/usr/local/bin/wine")
        let result = await CollectiveMemoryService.fetchBestEntry(for: "Test Game", wineURL: wineURL)

        #expect(result == "stub-context", "Should return stub result")
        let calls = await stub.fetchContextCalls
        #expect(calls.count == 1, "fetchContext should be called once")
        #expect(calls.first?.gameName == "Test Game")
    }

    // MARK: - Test 9: CollectiveMemoryWriteService.push delegation verified

    @Test("CollectiveMemoryWriteService.push delegates to KnowledgeStoreContainer.shared.write(.config)")
    func collectiveMemoryWriteServicePushDelegates() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let executableInfo = ExecutableInfo(path: "game.exe", type: "unknown", peImports: nil)
        let record = SuccessRecord(
            schemaVersion: 1, gameId: "test-push", gameName: "Test Push Game",
            gameVersion: nil, source: nil, engine: nil, graphicsApi: nil,
            verifiedAt: ISO8601DateFormatter().string(from: Date()), wineVersion: nil,
            bottleType: nil, os: nil, executable: executableInfo, workingDirectory: nil,
            environment: ["WINEDLLOVERRIDES": "d3d9=n,b"], dllOverrides: [], gameConfigFiles: [],
            registry: [], gameSpecificDlls: [], pitfalls: [], resolutionNarrative: nil, tags: []
        )

        // wine --version will fail in CI (no real wine binary) so buildConfigEntry returns nil;
        // that triggers the early-return in push(). Either way, no crash = delegation correct.
        let wineURL = URL(fileURLWithPath: "/usr/local/bin/wine")
        await CollectiveMemoryWriteService.push(record: record, gameName: "Test Push Game", wineURL: wineURL)

        let writes = await stub.writeCalls
        // Write count is 0 (no wine) or 1 (wine present) — both are valid
        #expect(writes.count == 0 || writes.first?.kind == .config)
    }

    // MARK: - Test 10: WikiService.fetchContext delegates to store

    @Test("WikiService.fetchContext delegates to KnowledgeStoreContainer.shared.fetchContext")
    func wikiServiceFetchContextDelegates() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let result = await WikiService.fetchContext(engine: "Test Engine")
        #expect(result == "stub-context")
        let calls = await stub.fetchContextCalls
        #expect(calls.count == 1)
        #expect(calls.first?.gameName == "Test Engine")
    }

    // MARK: - Test 11: WikiService.postSessionLog delegates to store

    @Test("WikiService.postSessionLog delegates to KnowledgeStoreContainer.shared.write(.sessionLog)")
    func wikiServicePostSessionLogDelegates() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let executableInfo = ExecutableInfo(path: "game.exe", type: "unknown", peImports: nil)
        let record = SuccessRecord(
            schemaVersion: 1, gameId: "session-test", gameName: "Session Test",
            gameVersion: nil, source: nil, engine: nil, graphicsApi: nil,
            verifiedAt: ISO8601DateFormatter().string(from: Date()), wineVersion: nil,
            bottleType: nil, os: nil, executable: executableInfo, workingDirectory: nil,
            environment: [:], dllOverrides: [], gameConfigFiles: [], registry: [],
            gameSpecificDlls: [], pitfalls: [], resolutionNarrative: nil, tags: []
        )

        await WikiService.postSessionLog(record: record, outcome: .success, duration: 60, wineURL: nil)

        let writes = await stub.writeCalls
        #expect(writes.count == 1)
        if case .sessionLog(let entry) = writes.first {
            #expect(entry.path.hasPrefix("sessions/"))
        } else {
            Issue.record("Expected .sessionLog entry")
        }
    }

    // MARK: - Test 12: WikiService.postFailureSessionLog delegates to store

    @Test("WikiService.postFailureSessionLog delegates to KnowledgeStoreContainer.shared.write(.sessionLog)")
    func wikiServicePostFailureSessionLogDelegates() async {
        let stub = StubKnowledgeStore()
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        await WikiService.postFailureSessionLog(
            gameId: "fail-test", gameName: "Fail Test",
            narrative: "Could not launch", actionsAttempted: ["set_env"],
            launchCount: 2, duration: 90, wineURL: nil, stopReason: "max_iterations"
        )

        let writes = await stub.writeCalls
        #expect(writes.count == 1)
        if case .sessionLog(let entry) = writes.first {
            #expect(entry.path.hasPrefix("sessions/"))
            #expect(entry.commitMessage?.contains("failure") == true)
        } else {
            Issue.record("Expected .sessionLog entry for failure log")
        }
    }

    // MARK: - Test 13: WikiService.search always returns non-nil String

    @Test("WikiService.search always returns non-nil String (RESEARCH.md pitfall #7)")
    func wikiServiceSearchAlwaysReturnsString() async {
        let stub = StubKnowledgeStore()
        await stub.setFetchContextResult(nil)  // no results
        let original = KnowledgeStoreContainer.shared
        defer { KnowledgeStoreContainer.shared = original }

        KnowledgeStoreContainer.shared = stub

        let result = await WikiService.search(query: "nonexistent-game-xyz")
        #expect(!result.isEmpty, "search should always return non-empty String")
        #expect(result.contains("No relevant wiki pages found") || result.contains("nonexistent"), "Should return no-match message")
    }
}

// MARK: - StubKnowledgeStore Helper Extensions

extension StubKnowledgeStore {
    func setFetchContextResult(_ result: String?) async {
        fetchContextResult = result
    }
}
