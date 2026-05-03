import Testing
@testable import cellar

@Suite("Security — Env Allowlist, Registry Validation, sanitizeEntry")
struct SecurityTests {

    // MARK: - Env Key Allowlist

    @Test("allowedEnvKeys contains exactly 13 Wine-related keys")
    func allowedEnvKeysCount() {
        #expect(AgentTools.allowedEnvKeys.count == 13)
    }

    @Test("allowedEnvKeys includes WINEDLLOVERRIDES")
    func allowedEnvKeysIncludesOverrides() {
        #expect(AgentTools.allowedEnvKeys.contains("WINEDLLOVERRIDES"))
    }

    @Test("allowedEnvKeys includes WINEFSYNC and WINEESYNC")
    func allowedEnvKeysIncludesFsyncEsync() {
        #expect(AgentTools.allowedEnvKeys.contains("WINEFSYNC"))
        #expect(AgentTools.allowedEnvKeys.contains("WINEESYNC"))
    }

    @Test("allowedEnvKeys includes DXVK_HUD")
    func allowedEnvKeysIncludesDxvk() {
        #expect(AgentTools.allowedEnvKeys.contains("DXVK_HUD"))
    }

    @Test("allowedEnvKeys rejects PATH")
    func allowedEnvKeysRejectsPath() {
        #expect(!AgentTools.allowedEnvKeys.contains("PATH"))
    }

    @Test("allowedEnvKeys rejects HOME")
    func allowedEnvKeysRejectsHome() {
        #expect(!AgentTools.allowedEnvKeys.contains("HOME"))
    }

    @Test("allowedEnvKeys rejects LD_PRELOAD")
    func allowedEnvKeysRejectsLdPreload() {
        #expect(!AgentTools.allowedEnvKeys.contains("LD_PRELOAD"))
    }

    @Test("allowedEnvKeys rejects DYLD_INSERT_LIBRARIES")
    func allowedEnvKeysRejectsDyldInsert() {
        #expect(!AgentTools.allowedEnvKeys.contains("DYLD_INSERT_LIBRARIES"))
    }

    // MARK: - sanitizeEntry — Environment

    private func makeTestEntry(
        env: [String: String] = [:],
        dllOverrides: [DLLOverrideRecord] = [],
        registry: [RegistryRecord] = [],
        launchArgs: [String] = [],
        setupDeps: [String] = []
    ) -> CollectiveMemoryEntry {
        CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: "test-game",
            gameName: "Test Game",
            config: WorkingConfig(
                environment: env,
                dllOverrides: dllOverrides,
                registry: registry,
                launchArgs: launchArgs,
                setupDeps: setupDeps
            ),
            environment: EnvironmentFingerprint(
                arch: "arm64", wineVersion: "9.0", macosVersion: "14.0.0", wineFlavor: "crossover"
            ),
            environmentHash: "abc123",
            reasoning: "test reasoning",
            engine: nil,
            graphicsApi: nil,
            confirmations: 1,
            lastConfirmed: "2026-01-01T00:00:00Z"
        )
    }

    @Test("sanitizeEntry drops disallowed env key")
    func sanitizeEntryDropsDisallowedEnvKey() {
        let entry = makeTestEntry(env: ["PATH": "/evil", "WINEDLLOVERRIDES": "ddraw=n,b"])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.environment["PATH"] == nil)
        #expect(sanitized.config.environment["WINEDLLOVERRIDES"] == "ddraw=n,b")
    }

    @Test("sanitizeEntry keeps all allowed env keys")
    func sanitizeEntryKeepsAllowedKeys() {
        let entry = makeTestEntry(env: ["WINEFSYNC": "1", "DXVK_HUD": "fps"])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.environment["WINEFSYNC"] == "1")
        #expect(sanitized.config.environment["DXVK_HUD"] == "fps")
    }

    @Test("sanitizeEntry truncates env value to 200 chars")
    func sanitizeEntryTruncatesEnvValue() {
        let longValue = String(repeating: "A", count: 300)
        let entry = makeTestEntry(env: ["WINEDEBUG": longValue])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.environment["WINEDEBUG"]?.count == 200)
    }

    // MARK: - sanitizeEntry — DLL Overrides

    @Test("sanitizeEntry keeps valid DLL mode n,b")
    func sanitizeEntryKeepsValidDllMode() {
        let dll = DLLOverrideRecord(dll: "ddraw", mode: "n,b", placement: nil, source: nil)
        let entry = makeTestEntry(dllOverrides: [dll])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.dllOverrides.count == 1)
        #expect(sanitized.config.dllOverrides.first?.mode == "n,b")
    }

    @Test("sanitizeEntry accepts all valid DLL modes")
    func sanitizeEntryAcceptsAllValidModes() {
        let modes = ["n", "b", "n,b", "b,n", ""]
        let dlls = modes.map { DLLOverrideRecord(dll: "test", mode: $0, placement: nil, source: nil) }
        let entry = makeTestEntry(dllOverrides: dlls)
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.dllOverrides.count == 5)
    }

    @Test("sanitizeEntry drops DLL override with invalid mode")
    func sanitizeEntryDropsInvalidDllMode() {
        let dll = DLLOverrideRecord(dll: "evil", mode: "malicious", placement: nil, source: nil)
        let entry = makeTestEntry(dllOverrides: [dll])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.dllOverrides.isEmpty)
    }

    @Test("sanitizeEntry truncates DLL name to 50 chars")
    func sanitizeEntryTruncatesDllName() {
        let longDll = String(repeating: "x", count: 100)
        let dll = DLLOverrideRecord(dll: longDll, mode: "n", placement: nil, source: nil)
        let entry = makeTestEntry(dllOverrides: [dll])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.dllOverrides.first?.dll.count == 50)
    }

    // MARK: - sanitizeEntry — Registry

    @Test("sanitizeEntry keeps registry with HKEY_CURRENT_USER prefix")
    func sanitizeEntryKeepsValidRegistry() {
        let reg = RegistryRecord(key: "HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides", valueName: "ddraw", data: "native", purpose: nil)
        let entry = makeTestEntry(registry: [reg])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.registry.count == 1)
    }

    @Test("sanitizeEntry drops registry with HKEY_CLASSES_ROOT prefix")
    func sanitizeEntryDropsClassesRoot() {
        let reg = RegistryRecord(key: "HKEY_CLASSES_ROOT\\evil", valueName: "val", data: "data", purpose: nil)
        let entry = makeTestEntry(registry: [reg])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.registry.isEmpty)
    }

    @Test("sanitizeEntry truncates registry key to 200 chars")
    func sanitizeEntryTruncatesRegistryKey() {
        // Key must start with an allowed prefix from registry_allowlist.json
        let longKey = "HKEY_CURRENT_USER\\Software\\" + String(repeating: "x", count: 300)
        let reg = RegistryRecord(key: longKey, valueName: "v", data: "d", purpose: nil)
        let entry = makeTestEntry(registry: [reg])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.registry.first?.key.count == 200)
    }

    // MARK: - sanitizeEntry — Launch Args

    @Test("sanitizeEntry caps launch args at 5 entries")
    func sanitizeEntryCapsLaunchArgs() {
        let args = (0..<10).map { "arg\($0)" }
        let entry = makeTestEntry(launchArgs: args)
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.launchArgs.count == 5)
    }

    @Test("sanitizeEntry truncates each launch arg to 100 chars")
    func sanitizeEntryTruncatesLaunchArgs() {
        let longArg = String(repeating: "z", count: 200)
        let entry = makeTestEntry(launchArgs: [longArg])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.launchArgs.first?.count == 100)
    }

    // MARK: - sanitizeEntry — Setup Deps

    @Test("sanitizeEntry filters setupDeps against winetricks allowlist")
    func sanitizeEntryFiltersSetupDeps() {
        let entry = makeTestEntry(setupDeps: ["dotnet48", "evil_verb", "vcrun2019"])
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.config.setupDeps.contains("dotnet48"))
        #expect(sanitized.config.setupDeps.contains("vcrun2019"))
        #expect(!sanitized.config.setupDeps.contains("evil_verb"))
    }

    // MARK: - sanitizeEntry — Reasoning preserved but not injected

    @Test("sanitizeEntry preserves reasoning field in struct")
    func sanitizeEntryPreservesReasoning() {
        let entry = makeTestEntry()
        let sanitized = CollectiveMemoryService.sanitizeEntry(entry)
        #expect(sanitized.reasoning == "test reasoning")
    }
}
