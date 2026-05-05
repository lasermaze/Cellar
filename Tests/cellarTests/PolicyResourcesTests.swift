import Testing
import Foundation
@testable import cellar

@Suite("PolicyResources — Bundle lookup, loader, and schema validation")
struct PolicyResourcesTests {

    // MARK: Test 1: Bundle.module subdirectory lookup

    @Test("Bundle.module can find policy/system_prompt.md via resourcePath")
    func bundleLookup() {
        // .copy("Resources") places files under <bundle>/Resources/policy/ for main target,
        // but Bundle.module.resourcePath already points to the Resources/ directory.
        // The loader handles both layouts; here we confirm at least one resolves.
        guard let resourcePath = Bundle.module.resourcePath else {
            Issue.record("Bundle.module.resourcePath is nil")
            return
        }
        // Try the layout where resourcePath already IS the Resources/ subdirectory
        let directURL = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("policy")
            .appendingPathComponent("system_prompt.md")
        // Also try the nested layout for non-test builds
        let nestedURL = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("policy")
            .appendingPathComponent("system_prompt.md")
        let found = FileManager.default.fileExists(atPath: directURL.path)
                 || FileManager.default.fileExists(atPath: nestedURL.path)
        #expect(found,
                "policy/system_prompt.md should exist under Bundle.module (checked \(directURL.path) and \(nestedURL.path))")
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
        #expect(pr.fetchPageAllowlist.contains("winehq.org"), "fetchPageAllowlist should contain winehq.org")
        #expect(pr.fetchPageAllowlist.contains("githubusercontent.com"), "fetchPageAllowlist should contain githubusercontent.com")
        #expect(!pr.fetchPageAllowlist.isEmpty, "fetchPageAllowlist should be non-empty")
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

    @Test("_loadVersionedEnvAllowlist throws schemaVersionMismatch when version != expected")
    func versionMismatch() throws {
        // Build a minimal JSON blob with schema_version: 99
        let jsonData = try #require(
            "{\"schema_version\": 99, \"allowed_keys\": []}".data(using: .utf8)
        )

        #expect(throws: PolicyError.self) {
            _ = try PolicyResources._loadVersionedEnvAllowlist(from: jsonData, expectedVersion: 1)
        }
    }

    // MARK: Test 5: fetchPageAllowlist is non-empty and covers required domains

    @Test("PolicyResources.shared.fetchPageAllowlist is a non-empty Set<String> containing required domains")
    func fetchPageAllowlistNonEmpty() {
        let pr = PolicyResources.shared
        #expect(pr.fetchPageAllowlist.contains("winehq.org"), "fetchPageAllowlist should contain winehq.org")
        #expect(pr.fetchPageAllowlist.contains("githubusercontent.com"), "fetchPageAllowlist should contain githubusercontent.com")
        #expect(!pr.fetchPageAllowlist.isEmpty, "fetchPageAllowlist should be non-empty")
    }

    @Test("fetchPageAllowlist covers all required wine/gaming domains")
    func fetchPageAllowlistCoverage() {
        let al = PolicyResources.shared.fetchPageAllowlist
        let required = ["winehq.org", "pcgamingwiki.com", "protondb.com",
                        "github.com", "githubusercontent.com", "reddit.com"]
        for domain in required {
            #expect(al.contains(domain), "\(domain) must be in fetchPageAllowlist")
        }
    }

    // MARK: Test 6: winetricksVerbAllowlist is non-empty

    @Test("PolicyResources.shared.winetricksVerbAllowlist is a non-empty Set<String>")
    func winetricksVerbAllowlistNonEmpty() {
        let verbs = PolicyResources.shared.winetricksVerbAllowlist
        #expect(!verbs.isEmpty, "winetricksVerbAllowlist should be non-empty")
    }

    // MARK: Test 6: winetricksVerbAllowlist matches AgentTools literal (loss-free move)

    @Test("PolicyResources.shared.winetricksVerbAllowlist equals AgentTools.agentValidWinetricksVerbs")
    func winetricksVerbAllowlistMatchesAgentTools() {
        #expect(
            PolicyResources.shared.winetricksVerbAllowlist == AIService.agentValidWinetricksVerbs,
            "winetricksVerbAllowlist must match AgentTools literal exactly — no regressions"
        )
    }

    // MARK: Test 7: winetricks_verbs.json loaded via Bundle.module resourcePath fallback

    @Test("winetricks_verbs.json is accessible via Bundle.module resourcePath")
    func winetricksVerbsBundleLookup() {
        guard let resourcePath = Bundle.module.resourcePath else {
            Issue.record("Bundle.module.resourcePath is nil")
            return
        }
        let directURL = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("policy")
            .appendingPathComponent("winetricks_verbs.json")
        let nestedURL = URL(fileURLWithPath: resourcePath)
            .appendingPathComponent("Resources")
            .appendingPathComponent("policy")
            .appendingPathComponent("winetricks_verbs.json")
        let found = FileManager.default.fileExists(atPath: directURL.path)
                 || FileManager.default.fileExists(atPath: nestedURL.path)
        #expect(found,
                "winetricks_verbs.json should exist under Bundle.module (checked \(directURL.path) and \(nestedURL.path))")
    }
}
