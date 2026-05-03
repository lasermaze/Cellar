import Testing
import Foundation
@testable import cellar

@Suite("PolicyResources — Bundle lookup, loader, and schema validation")
struct PolicyResourcesTests {

    // MARK: Test 1: Bundle.module subdirectory lookup

    @Test("Bundle.module can find policy/system_prompt.md")
    func bundleLookup() {
        let url = Bundle.module.url(forResource: "policy/system_prompt", withExtension: "md")
        #expect(url != nil, "Bundle.module should resolve policy/system_prompt.md — verify .copy(Resources) in Package.swift and that the file exists at Sources/cellar/Resources/policy/system_prompt.md")
    }

    // MARK: Test 2: Loader happy path

    @Test("PolicyResources.shared loads all policy files successfully")
    func loaderHappyPath() {
        let pr = PolicyResources.shared

        #expect(!pr.systemPrompt.isEmpty, "systemPrompt should be non-empty")
        #expect(pr.envAllowlist.contains("WINEDLLOVERRIDES"), "envAllowlist should contain WINEDLLOVERRIDES")
        #expect(pr.registryAllowlist.first?.hasPrefix("HKEY_") == true, "registryAllowlist first entry should start with HKEY_")
        #expect(pr.engineDefinitions.count > 0, "engineDefinitions should be non-empty")
        #expect(pr.dllRegistry.contains(where: { $0.name == "cnc-ddraw" }), "dllRegistry should contain cnc-ddraw")
        #expect(pr.toolSchemas["set_environment"] != nil, "toolSchemas should have set_environment entry")
    }

    // MARK: Test 3: Frontmatter parsing

    @Test("parsePolicyFrontmatter extracts version and body from synthetic markdown")
    func frontmatterParsing() throws {
        let input = "---\nschema_version: 7\n---\nbody content here"
        let (version, body) = try parsePolicyFrontmatter(input)
        #expect(version == 7, "Should parse schema_version: 7")
        #expect(body == "body content here", "Should return body after closing ---")
    }

    // MARK: Test 4: Version mismatch throws

    @Test("loadVersionedJSON throws schemaVersionMismatch when version != expected")
    func versionMismatch() throws {
        // Build a minimal JSON blob with schema_version: 99
        let jsonData = try #require(
            "{\"schema_version\": 99, \"allowed_keys\": []}".data(using: .utf8)
        )

        #expect(throws: PolicyError.self) {
            _ = try PolicyResources._loadVersionedEnvAllowlist(from: jsonData, expectedVersion: 1)
        }
    }
}
