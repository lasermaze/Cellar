import Testing
@testable import cellar

@Suite("AgentTools — Tool Definitions and Allowlists")
struct AgentToolDefinitionTests {

    @Test("toolDefinitions has at least 20 tools")
    func toolCount() {
        #expect(AgentTools.toolDefinitions.count >= 20)
    }

    @Test("All tool names are unique")
    func toolNamesUnique() {
        let names = AgentTools.toolDefinitions.map(\.name)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count)
    }

    @Test("inspect_game tool exists")
    func inspectGameExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "inspect_game" })
    }

    @Test("launch_game tool exists")
    func launchGameExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "launch_game" })
    }

    @Test("set_environment tool exists")
    func setEnvironmentExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "set_environment" })
    }

    @Test("set_registry tool exists")
    func setRegistryExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "set_registry" })
    }

    @Test("save_success tool exists")
    func saveSuccessExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "save_success" })
    }

    @Test("search_web tool exists")
    func searchWebExists() {
        #expect(AgentTools.toolDefinitions.contains { $0.name == "search_web" })
    }

    @Test("All tools have non-empty description")
    func allToolsHaveDescription() {
        for tool in AgentTools.toolDefinitions {
            #expect(!tool.description.isEmpty, "Tool '\(tool.name)' has empty description")
        }
    }

    // MARK: - Winetricks Verb Allowlist

    @Test("Winetricks allowlist contains common verbs")
    func winetricksCommonVerbs() {
        let verbs = AIService.agentValidWinetricksVerbs
        #expect(verbs.contains("dotnet48"))
        #expect(verbs.contains("vcrun2019"))
        #expect(verbs.contains("d3dx9"))
        #expect(verbs.contains("xinput"))
    }

    @Test("Winetricks allowlist does not contain dangerous verbs")
    func winetricksNoDangerousVerbs() {
        let verbs = AIService.agentValidWinetricksVerbs
        #expect(!verbs.contains("annihilate"))
        #expect(!verbs.contains("sandbox"))
    }
}
