import Testing
import Foundation
@testable import cellar

@Suite("CellarConfig — Configuration Loading and Models")
struct CellarConfigTests {

    @Test("Default budget ceiling is 15.00")
    func defaultBudget() {
        #expect(CellarConfig.defaultBudgetCeiling == 15.00)
    }

    @Test("CellarConfig JSON round-trip preserves all fields")
    func jsonRoundTrip() throws {
        let config = CellarConfig(budgetCeiling: 25.0, aiProvider: "deepseek", aiModel: "deepseek-reasoner", contributeMemory: true)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(CellarConfig.self, from: data)
        #expect(decoded.budgetCeiling == 25.0)
        #expect(decoded.aiProvider == "deepseek")
        #expect(decoded.aiModel == "deepseek-reasoner")
        #expect(decoded.contributeMemory == true)
    }

    @Test("CellarConfig decodes with nil optional fields")
    func jsonNilOptionals() throws {
        let json = #"{"budget": 10.0}"#
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(CellarConfig.self, from: data)
        #expect(decoded.budgetCeiling == 10.0)
        #expect(decoded.aiProvider == nil)
        #expect(decoded.aiModel == nil)
        #expect(decoded.contributeMemory == nil)
    }

    @Test("CellarConfig CodingKeys map to correct JSON keys")
    func codingKeys() throws {
        let config = CellarConfig(budgetCeiling: 5.0, aiProvider: "claude", aiModel: "claude-opus-4-6", contributeMemory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(config)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"budget\""))
        #expect(json.contains("\"ai_provider\""))
        #expect(json.contains("\"ai_model\""))
        #expect(json.contains("\"contribute_memory\""))
    }

    // MARK: - AIService Fallback Models

    @Test("fallbackModels has entries for all 3 providers")
    func fallbackModelsProviders() {
        #expect(AIService.fallbackModels["claude"] != nil)
        #expect(AIService.fallbackModels["deepseek"] != nil)
        #expect(AIService.fallbackModels["kimi"] != nil)
    }

    @Test("Claude default model is claude-sonnet-4-6")
    func claudeDefaultModel() {
        #expect(AIService.fallbackModels["claude"]?.first?.id == "claude-sonnet-4-6")
    }

    @Test("Deepseek default model is deepseek-chat")
    func deepseekDefaultModel() {
        #expect(AIService.fallbackModels["deepseek"]?.first?.id == "deepseek-chat")
    }

    @Test("Kimi default model is moonshot-v1-8k")
    func kimiDefaultModel() {
        #expect(AIService.fallbackModels["kimi"]?.first?.id == "moonshot-v1-8k")
    }

    // MARK: - AIProvider Enum

    @Test("AIProvider has anthropic case with apiKey")
    func providerAnthropic() {
        let provider = AIProvider.anthropic(apiKey: "test")
        if case .anthropic(let key) = provider {
            #expect(key == "test")
        } else {
            #expect(Bool(false), "Expected .anthropic case")
        }
    }

    @Test("AIProvider has kimi case")
    func providerKimi() {
        let provider = AIProvider.kimi(apiKey: "kimi-key")
        if case .kimi(let key) = provider {
            #expect(key == "kimi-key")
        } else {
            #expect(Bool(false), "Expected .kimi case")
        }
    }
}
