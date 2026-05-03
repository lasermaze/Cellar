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
}
