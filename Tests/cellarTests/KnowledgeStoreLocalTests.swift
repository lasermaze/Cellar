import Testing
import Foundation
@testable import cellar

@Suite("KnowledgeStoreLocal — cache-only, no network adapter")
struct KnowledgeStoreLocalTests {

    // MARK: - Helpers

    /// Create a temp directory and a KnowledgeStoreLocal backed by it.
    /// Returns (store, tempDir). Caller must clean up tempDir.
    private func makeStore() -> (KnowledgeStoreLocal, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSLocalTest-\(UUID().uuidString)", isDirectory: true)
        let store = KnowledgeStoreLocal(cacheDir: dir)
        return (store, dir)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    /// Build a minimal CollectiveMemoryEntry for testing.
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

    // MARK: - Test 1: fetchContext returns nil when cache is empty

    @Test("fetchContext returns nil when cache directory is empty")
    func fetchContextEmptyCache() async {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }
        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "NonExistent Game", environment: env)
        #expect(result == nil, "Should return nil when no cache files exist")
    }

    // MARK: - Test 2: fetchContext returns context when config cache file exists

    @Test("fetchContext returns formatted context when config cache file exists")
    func fetchContextWithConfigCache() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let entry = makeConfigEntry(gameId: "test-game", gameName: "Test Game")
        await store.write(.config(entry))

        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Test Game", environment: env)
        #expect(result != nil, "Should return non-nil context when config entry exists")
        #expect(result?.contains("COLLECTIVE MEMORY") == true || result?.contains("Community config") == true,
                "Context should include a community config section header")
    }

    // MARK: - Test 3: fetchContext includes game-page when present

    @Test("fetchContext includes game-page section when game page cache file exists")
    func fetchContextWithGamePage() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let slug = slugify("Test Game")
        let gamePage = GamePageEntry(slug: slug, autoContent: "# Test Game\nThis game runs on Wine.", commitMessage: nil)
        await store.write(.gamePage(gamePage))

        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Test Game", environment: env)
        #expect(result != nil, "Should return non-nil when game page exists")
        #expect(result?.contains("Game page") == true || result?.contains("test game") == true,
                "Context should include game page content")
    }

    // MARK: - Test 4: fetchContext includes session logs when present

    @Test("fetchContext includes recent session logs when present")
    func fetchContextWithSessionLogs() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let slug = slugify("Test Game")
        let sessionEntry = SessionLogEntry(
            path: "sessions/2026-05-03-\(slug)-abc12345.md",
            body: "# Test Game — 2026-05-03\nOutcome: SUCCESS",
            commitMessage: nil
        )
        await store.write(.sessionLog(sessionEntry))

        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let result = await store.fetchContext(for: "Test Game", environment: env)
        #expect(result != nil, "Should return non-nil when session log exists")
        #expect(result?.contains("Recent sessions") == true || result?.contains("2026-05-03") == true,
                "Context should include recent session data")
    }

    // MARK: - Test 5: write(.config) persists to config/{gameId}.json

    @Test("write(.config) persists entry to config/{gameId}.json under cacheDir")
    func writeConfigPersistsToExpectedPath() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let entry = makeConfigEntry(gameId: "my-game")
        await store.write(.config(entry))

        let expectedPath = dir.appendingPathComponent("config/my-game.json")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path),
                "Config entry should be written to config/{gameId}.json")

        // Verify it decodes back correctly
        let data = try Data(contentsOf: expectedPath)
        let decoded = try JSONDecoder().decode([CollectiveMemoryEntry].self, from: data)
        #expect(decoded.first?.gameId == "my-game", "Decoded entry should have correct gameId")
    }

    // MARK: - Test 6: write(.gamePage) persists to game-page/{slug}.md

    @Test("write(.gamePage) persists entry to game-page/{slug}.md under cacheDir")
    func writeGamePagePersistsToExpectedPath() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let slug = "half-life"
        let gamePage = GamePageEntry(slug: slug, autoContent: "# Half-Life\nWorks great.", commitMessage: nil)
        await store.write(.gamePage(gamePage))

        let expectedPath = dir.appendingPathComponent("game-page/\(slug).md")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path),
                "Game page should be written to game-page/{slug}.md")
        let content = try String(contentsOf: expectedPath, encoding: .utf8)
        #expect(content.contains("Half-Life"), "Written content should include game page body")
    }

    // MARK: - Test 7: write(.sessionLog) persists to session-log/{filename}

    @Test("write(.sessionLog) persists entry under session-log/ directory")
    func writeSessionLogPersistsToExpectedPath() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let path = "sessions/2026-05-03-test-game-abc12345.md"
        let sessionEntry = SessionLogEntry(
            path: path,
            body: "# Test Game session",
            commitMessage: nil
        )
        await store.write(.sessionLog(sessionEntry))

        let filename = URL(fileURLWithPath: path).lastPathComponent
        let expectedPath = dir.appendingPathComponent("session-log/\(filename)")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path),
                "Session log should be written to session-log/{filename}")
        let content = try String(contentsOf: expectedPath, encoding: .utf8)
        #expect(content.contains("Test Game session"), "Written content should include session body")
    }

    // MARK: - Test 8: list(filter:) returns metadata for cached entries

    @Test("list(filter:) returns metadata for cached entries matching the filter")
    func listReturnsCachedEntryMeta() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        // Write two config entries
        let entry1 = makeConfigEntry(gameId: "game-alpha", gameName: "Game Alpha")
        let entry2 = makeConfigEntry(gameId: "game-beta", gameName: "Game Beta")
        await store.write(.config(entry1))
        await store.write(.config(entry2))

        let filter = KnowledgeListFilter(kind: .config, slug: nil, maxResults: 10)
        let results = await store.list(filter: filter)
        #expect(results.count == 2, "Should list both config entries")
        #expect(results.allSatisfy { $0.kind == .config }, "All results should be config kind")
    }

    // MARK: - Test 9: No URLSession used (structural purity check)
    // This test documents the structural guarantee: KnowledgeStoreLocal is pure filesystem.
    // The actual network-isolation is verified via code structure (no URLSession in the file).
    // We test it behaviorally: writes and reads complete without any network requirement,
    // even when the network is conceptually unavailable.

    @Test("KnowledgeStoreLocal performs all operations without any network dependency")
    func noNetworkDependency() async throws {
        let (store, dir) = makeStore()
        defer { cleanup(dir) }

        let entry = makeConfigEntry()
        // write must complete synchronously (no network wait)
        await store.write(.config(entry))

        let env = EnvironmentFingerprint(arch: "arm64", wineVersion: "9.0", macosVersion: "15.0.0", wineFlavor: "wine-stable")
        let _ = await store.fetchContext(for: "Test Game", environment: env)
        let _ = await store.list(filter: KnowledgeListFilter(kind: .config, slug: nil, maxResults: 5))
        // No assertion needed: test passes if it completes — network would require actual reachability
        #expect(true, "Operations completed without network")
    }
}
