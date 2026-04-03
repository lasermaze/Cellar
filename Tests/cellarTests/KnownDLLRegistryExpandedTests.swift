import Testing
@testable import cellar

@Suite("KnownDLLRegistry — Expanded Registry (4 entries)")
struct KnownDLLRegistryExpandedTests {

    @Test("Registry has exactly 4 entries")
    func registryCount() {
        #expect(KnownDLLRegistry.registry.count == 4)
    }

    @Test("find cnc-ddraw returns correct entry")
    func findCncDdraw() {
        let dll = KnownDLLRegistry.find(name: "cnc-ddraw")
        #expect(dll != nil)
        #expect(dll?.dllFileName == "ddraw.dll")
        #expect(dll?.githubRepo == "cnc-ddraw")
    }

    @Test("find dgvoodoo2 returns correct entry")
    func findDgVoodoo2() {
        let dll = KnownDLLRegistry.find(name: "dgvoodoo2")
        #expect(dll != nil)
        #expect(dll?.githubOwner != nil)
    }

    @Test("find dxwrapper returns correct entry")
    func findDxwrapper() {
        let dll = KnownDLLRegistry.find(name: "dxwrapper")
        #expect(dll != nil)
    }

    @Test("find dxvk returns correct entry")
    func findDxvk() {
        let dll = KnownDLLRegistry.find(name: "dxvk")
        #expect(dll != nil)
    }

    @Test("find is case-insensitive")
    func findCaseInsensitive() {
        #expect(KnownDLLRegistry.find(name: "CNC-DDRAW") != nil)
        #expect(KnownDLLRegistry.find(name: "DXVK") != nil)
    }

    @Test("find returns nil for unknown DLL")
    func findUnknown() {
        #expect(KnownDLLRegistry.find(name: "nonexistent-dll") == nil)
    }

    @Test("cnc-ddraw has ddraw n,b override")
    func cncDdrawOverrides() {
        let dll = KnownDLLRegistry.find(name: "cnc-ddraw")!
        #expect(dll.requiredOverrides["ddraw"] == "n,b")
    }

    @Test("cnc-ddraw has companion file ddraw.ini")
    func cncDdrawCompanionFile() {
        let dll = KnownDLLRegistry.find(name: "cnc-ddraw")!
        #expect(dll.companionFiles.first?.filename == "ddraw.ini")
    }
}
