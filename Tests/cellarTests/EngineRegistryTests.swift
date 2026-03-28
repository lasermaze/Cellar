import Testing
@testable import cellar

@Suite("EngineRegistry Tests")
struct EngineRegistryTests {

    // MARK: - detect() tests

    @Test("detect returns GSC/DMCR with high confidence from file patterns")
    func detectGSCFromFilePatterns() {
        let result = EngineRegistry.detect(
            gameFiles: ["fsgame.ltx", "game.exe"],
            peImports: [],
            binaryStrings: []
        )
        #expect(result != nil)
        #expect(result?.name == "GSC/DMCR")
        #expect(result?.family == "gsc")
        #expect(result?.confidence == "high")
    }

    @Test("detect returns Unity from file patterns")
    func detectUnityFromFilePatterns() {
        let result = EngineRegistry.detect(
            gameFiles: ["UnityPlayer.dll", "Game_Data/"],
            peImports: [],
            binaryStrings: []
        )
        #expect(result != nil)
        #expect(result?.name == "Unity")
        #expect(result?.family == "unity")
    }

    @Test("detect returns nil when no signals match")
    func detectReturnsNilForNoMatch() {
        let result = EngineRegistry.detect(
            gameFiles: ["readme.txt"],
            peImports: [],
            binaryStrings: []
        )
        #expect(result == nil)
    }

    @Test("detect is case-insensitive for file patterns")
    func detectIsCaseInsensitive() {
        let result = EngineRegistry.detect(
            gameFiles: ["FSGAME.LTX"],
            peImports: [],
            binaryStrings: []
        )
        #expect(result != nil)
        #expect(result?.name == "GSC/DMCR")
    }

    @Test("detect returns low confidence for single weak string signal")
    func detectSingleWeakSignalReturnsLowConfidence() {
        let result = EngineRegistry.detect(
            gameFiles: [],
            peImports: [],
            binaryStrings: ["Westwood Studios"]
        )
        #expect(result != nil)
        #expect(result?.confidence == "low")
    }

    @Test("detect returns high confidence when multiple signals agree")
    func detectMultipleSignalsReturnHighConfidence() {
        let result = EngineRegistry.detect(
            gameFiles: ["war3.mpq"],
            peImports: [],
            binaryStrings: ["Blizzard Entertainment"]
        )
        #expect(result != nil)
        #expect(result?.confidence == "high")
    }

    // MARK: - detectGraphicsApi() tests

    @Test("detectGraphicsApi returns directdraw for ddraw.dll")
    func detectGraphicsApiDirectDraw() {
        let result = EngineRegistry.detectGraphicsApi(peImports: ["ddraw.dll", "kernel32.dll"])
        #expect(result == "directdraw")
    }

    @Test("detectGraphicsApi returns direct3d9 for d3d9.dll")
    func detectGraphicsApiDirect3D9() {
        let result = EngineRegistry.detectGraphicsApi(peImports: ["d3d9.dll"])
        #expect(result == "direct3d9")
    }

    @Test("detectGraphicsApi returns nil when no graphics DLL present")
    func detectGraphicsApiReturnsNilForNoGraphicsDLL() {
        let result = EngineRegistry.detectGraphicsApi(peImports: ["kernel32.dll", "user32.dll"])
        #expect(result == nil)
    }

    @Test("detectGraphicsApi is case-insensitive")
    func detectGraphicsApiIsCaseInsensitive() {
        let result = EngineRegistry.detectGraphicsApi(peImports: ["DDRAW.DLL"])
        #expect(result == "directdraw")
    }

    // MARK: - Engine registry completeness

    @Test("registry contains all 8 engine families")
    func registryContainsAllEightFamilies() {
        let families = Set(EngineRegistry.engines.map { $0.family })
        let expected: Set<String> = ["gsc", "unreal1", "build", "idtech", "unity", "unreal4", "westwood", "blizzard"]
        #expect(families == expected)
    }

    // MARK: - Signal tracking

    @Test("detect returns tracked signals from all signal types")
    func detectReturnsSignals() {
        let result = EngineRegistry.detect(
            gameFiles: ["fsgame.ltx"],
            peImports: ["ddraw.dll"],
            binaryStrings: ["GSC Game World"]
        )
        #expect(result != nil)
        let signals = result!.signals
        #expect(signals.contains("file:fsgame.ltx"))
        #expect(signals.contains("import:ddraw.dll"))
        #expect(signals.contains("string:GSC Game World"))
    }

    // MARK: - Graphics API priority

    @Test("detectGraphicsApi prefers higher DX version when multiple present")
    func detectGraphicsApiPrefersHigherDX() {
        let result = EngineRegistry.detectGraphicsApi(peImports: ["d3d9.dll", "d3d11.dll"])
        #expect(result == "direct3d11")
    }

    // MARK: - Extension pattern matching

    @Test("detect matches extension patterns like *.mpq")
    func detectMatchesExtensionPatterns() {
        let result = EngineRegistry.detect(
            gameFiles: ["custom_archive.mpq"],
            peImports: ["ddraw.dll", "dsound.dll"],
            binaryStrings: []
        )
        #expect(result != nil)
        #expect(result?.family == "blizzard")
    }
}
