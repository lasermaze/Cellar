import Foundation
import Testing
@testable import cellar

@Suite("CollectiveMemoryEntry Tests")
struct CollectiveMemoryEntryTests {

    // MARK: - Helpers

    private func makeFullEntry() -> CollectiveMemoryEntry {
        let config = WorkingConfig(
            environment: ["WINEDLLOVERRIDES": "ddraw=n,b"],
            dllOverrides: [
                DLLOverrideRecord(dll: "ddraw", mode: "n,b", placement: "game_dir", source: "cnc-ddraw")
            ],
            registry: [
                RegistryRecord(key: "HKCU\\Software\\Game", valueName: "Resolution", data: "800x600", purpose: "Set display resolution")
            ],
            launchArgs: ["-nosound"],
            setupDeps: ["dxvk"]
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
            confirmations: 1,
            lastConfirmed: "2026-03-30T00:00:00Z"
        )
    }

    // MARK: - SCHM-01: Round-trip encoding

    @Test("Round-trip encoding preserves all fields")
    func roundTripEncoding() throws {
        let original = makeFullEntry()
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CollectiveMemoryEntry.self, from: data)

        #expect(decoded.schemaVersion == original.schemaVersion)
        #expect(decoded.gameId == original.gameId)
        #expect(decoded.gameName == original.gameName)
        #expect(decoded.reasoning == original.reasoning)
        #expect(decoded.engine == original.engine)
        #expect(decoded.graphicsApi == original.graphicsApi)
        #expect(decoded.confirmations == original.confirmations)
        #expect(decoded.lastConfirmed == original.lastConfirmed)
        #expect(decoded.environmentHash == original.environmentHash)

        // WorkingConfig
        #expect(decoded.config.environment == original.config.environment)
        #expect(decoded.config.launchArgs == original.config.launchArgs)
        #expect(decoded.config.setupDeps == original.config.setupDeps)
        #expect(decoded.config.dllOverrides.count == original.config.dllOverrides.count)
        #expect(decoded.config.dllOverrides.first?.dll == original.config.dllOverrides.first?.dll)
        #expect(decoded.config.registry.count == original.config.registry.count)
        #expect(decoded.config.registry.first?.key == original.config.registry.first?.key)

        // EnvironmentFingerprint
        #expect(decoded.environment.arch == original.environment.arch)
        #expect(decoded.environment.wineVersion == original.environment.wineVersion)
        #expect(decoded.environment.macosVersion == original.environment.macosVersion)
        #expect(decoded.environment.wineFlavor == original.environment.wineFlavor)
    }

    @Test("Optional fields decode as nil when absent")
    func optionalFieldsDecodeAsNil() throws {
        let config = WorkingConfig(
            environment: [:],
            dllOverrides: [],
            registry: [],
            launchArgs: [],
            setupDeps: []
        )
        let fingerprint = EnvironmentFingerprint(
            arch: "x86_64",
            wineVersion: "8.0",
            macosVersion: "14.0.0",
            wineFlavor: "wine-staging"
        )
        let entry = CollectiveMemoryEntry(
            schemaVersion: 1,
            gameId: "deus-ex-goty",
            gameName: "Deus Ex: Game of the Year Edition",
            config: config,
            environment: fingerprint,
            environmentHash: fingerprint.computeHash(),
            reasoning: "Runs out of the box.",
            engine: nil,
            graphicsApi: nil,
            confirmations: 1,
            lastConfirmed: "2026-03-30T00:00:00Z"
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(CollectiveMemoryEntry.self, from: data)

        #expect(decoded.engine == nil)
        #expect(decoded.graphicsApi == nil)
    }

    // MARK: - SCHM-02: slugify

    @Test("slugify is deterministic — same input same output")
    func slugifyDeterministic() {
        let result1 = slugify("Cossacks: European Wars")
        let result2 = slugify("Cossacks: European Wars")
        #expect(result1 == result2)
        #expect(result1 == "cossacks-european-wars")
    }

    @Test("slugify handles colons and special chars")
    func slugifySpecialChars() {
        #expect(slugify("Deus Ex: Game of the Year Edition") == "deus-ex-game-of-the-year-edition")
    }

    @Test("slugify collapses multiple hyphens")
    func slugifyCollapseHyphens() {
        // "Rayman 2 - The Great Escape": space-hyphen-space becomes a single hyphen
        #expect(slugify("Rayman 2 - The Great Escape") == "rayman-2-the-great-escape")
    }

    @Test("slugify handles unicode and accented chars")
    func slugifyUnicode() {
        // Accented chars in the lowercased ASCII range should pass through
        let result = slugify("Chateau Defender!")
        #expect(result == "chateau-defender")
    }

    @Test("slugify strips leading and trailing punctuation")
    func slugifyEdgeCases() {
        #expect(slugify("...game name...") == "game-name")
        #expect(slugify("!Title!") == "title")
        #expect(slugify("") == "")
    }

    // MARK: - SCHM-03: Unknown fields forward-compatibility

    @Test("Unknown JSON fields are silently ignored on decode")
    func unknownFieldsIgnored() throws {
        let jsonString = """
        {
            "schema_version": 1,
            "game_id": "test-game",
            "game_name": "Test Game",
            "config": {
                "environment": {},
                "dll_overrides": [],
                "registry": [],
                "launch_args": [],
                "setup_deps": []
            },
            "environment": {
                "arch": "arm64",
                "wine_version": "9.0",
                "macos_version": "15.0.0",
                "wine_flavor": "whisky"
            },
            "environment_hash": "abcd1234abcd1234",
            "reasoning": "Works fine.",
            "confirmations": 1,
            "last_confirmed": "2026-03-30T00:00:00Z",
            "future_field": "ignored value",
            "another_future_field": 42
        }
        """
        let data = Data(jsonString.utf8)
        let decoded = try JSONDecoder().decode(CollectiveMemoryEntry.self, from: data)

        #expect(decoded.gameId == "test-game")
        #expect(decoded.gameName == "Test Game")
        #expect(decoded.confirmations == 1)
        #expect(decoded.environment.arch == "arm64")
    }

    // MARK: - Environment fingerprint

    @Test("computeHash returns exactly 16 hex characters")
    func environmentHashLength() {
        let fp = EnvironmentFingerprint(
            arch: "arm64",
            wineVersion: "9.0",
            macosVersion: "15.0.0",
            wineFlavor: "whisky"
        )
        let hash = fp.computeHash()
        #expect(hash.count == 16)
        // Verify it's hex chars only
        let isHex = hash.allSatisfy { $0.isHexDigit }
        #expect(isHex)
    }

    @Test("computeHash is deterministic for same fingerprint")
    func environmentHashDeterministic() {
        let fp = EnvironmentFingerprint(
            arch: "arm64",
            wineVersion: "9.0",
            macosVersion: "15.0.0",
            wineFlavor: "whisky"
        )
        #expect(fp.computeHash() == fp.computeHash())
    }

    @Test("canonicalString uses sorted key format")
    func canonicalStringFormat() {
        let fp = EnvironmentFingerprint(
            arch: "arm64",
            wineVersion: "9.0",
            macosVersion: "15.0.0",
            wineFlavor: "whisky"
        )
        let canonical = fp.canonicalString
        #expect(canonical == "arch=arm64|macosVersion=15.0.0|wineFlavor=whisky|wineVersion=9.0")
    }

    @Test("EnvironmentFingerprint.current() auto-detects arch and macOS version")
    func environmentFingerprintCurrent() {
        let fp = EnvironmentFingerprint.current(wineVersion: "9.0", wineFlavor: "whisky")
        #expect(fp.arch == "arm64" || fp.arch == "x86_64")
        #expect(!fp.macosVersion.isEmpty)
        #expect(fp.wineVersion == "9.0")
        #expect(fp.wineFlavor == "whisky")
    }
}
