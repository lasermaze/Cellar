import Testing
import Foundation
@testable import cellar

// MARK: - Fixtures

private let fixtureDescriptor = ModelDescriptor(
    id: "claude-sonnet-4-6",
    provider: .anthropic,
    inputPricePerToken: 0.000003,
    outputPricePerToken: 0.000015,
    maxOutputTokens: 8192
)

private let fixtureCalls: [AgentToolCall] = [
    AgentToolCall(id: "call_1", name: "inspect_game", input: .object([:])),
    AgentToolCall(id: "call_2", name: "set_environment", input: .object([
        "key": .string("WINEDLLOVERRIDES"), "value": .string("ddraw=n,b")
    ])),
    AgentToolCall(id: "call_3", name: "search_web", input: .object([
        "query": .string("starcraft wine"),
        "tags": .array([.string("rts"), .string("blizzard")])
    ])),
]

// MARK: - AnthropicAdapterTests

@Suite("AnthropicAdapter — tool call encode/decode")
struct AnthropicAdapterTests {

    private func makeAdapter() -> AnthropicAdapter {
        AnthropicAdapter(descriptor: fixtureDescriptor, apiKey: "test", tools: [], systemPrompt: "")
    }

    /// Builds an AnthropicToolResponse fixture with N tool_use content blocks.
    private func makeAnthropicResponse(calls: [AgentToolCall]) -> AnthropicToolResponse {
        let blocks: [ToolContentBlock] = calls.map { call in
            .toolUse(id: call.id, name: call.name, input: call.input)
        }
        return AnthropicToolResponse(content: blocks, stopReason: "tool_use", usage: nil)
    }

    @Test("decodesToolUseBlocks — id, name, input preserved")
    func decodesToolUseBlocks() {
        let adapter = makeAdapter()
        let response = makeAnthropicResponse(calls: Array(fixtureCalls.prefix(2)))
        let result = adapter.translateResponse(response)

        #expect(result.toolCalls.count == 2)
        #expect(result.toolCalls[0].id == "call_1")
        #expect(result.toolCalls[0].name == "inspect_game")
        #expect(result.toolCalls[0].input == .object([:]))
        #expect(result.toolCalls[1].id == "call_2")
        #expect(result.toolCalls[1].name == "set_environment")
        #expect(result.toolCalls[1].input == .object([
            "key": .string("WINEDLLOVERRIDES"), "value": .string("ddraw=n,b")
        ]))
        if case .toolUse = result.stopReason {} else { Issue.record("Expected stopReason .toolUse") }
    }

    @Test("encodesToolUseInAssistantTurn — all ids, names, and inputs preserved")
    func encodesToolUseInAssistantTurn() throws {
        let adapter = makeAdapter()
        let providerResponse = AgentLoopProviderResponse(
            textBlocks: [],
            toolCalls: fixtureCalls,
            stopReason: .toolUse,
            inputTokens: 0,
            outputTokens: 0
        )
        let blocks = adapter.encodedAssistantBlocks(for: providerResponse)

        // All three tool calls should appear as toolUse blocks
        let toolUseBlocks = blocks.compactMap { block -> (id: String, name: String, input: JSONValue)? in
            if case .toolUse(let id, let name, let input) = block { return (id, name, input) }
            return nil
        }
        #expect(toolUseBlocks.count == 3)
        #expect(toolUseBlocks[0].id == "call_1")
        #expect(toolUseBlocks[0].name == "inspect_game")
        #expect(toolUseBlocks[1].id == "call_2")
        #expect(toolUseBlocks[2].id == "call_3")
        #expect(toolUseBlocks[2].name == "search_web")
        // Verify nested array input is preserved
        if case .object(let obj) = toolUseBlocks[2].input,
           case .array(let arr) = obj["tags"] {
            #expect(arr == [.string("rts"), .string("blizzard")])
        } else {
            Issue.record("Expected nested array input for call_3")
        }
    }

    @Test("roundTrip — encode then decode yields original AgentToolCall values")
    func roundTrip() throws {
        let adapter = makeAdapter()
        // Step 1: build a provider response with all fixture calls
        let providerResponse = AgentLoopProviderResponse(
            textBlocks: [],
            toolCalls: fixtureCalls,
            stopReason: .toolUse,
            inputTokens: 0,
            outputTokens: 0
        )
        // Step 2: encode to Anthropic tool_use blocks
        let encodedBlocks = adapter.encodedAssistantBlocks(for: providerResponse)
        // Step 3: build an AnthropicToolResponse from those blocks
        let wireResponse = AnthropicToolResponse(content: encodedBlocks, stopReason: "tool_use", usage: nil)
        // Step 4: decode back to AgentLoopProviderResponse
        let decoded = adapter.translateResponse(wireResponse)
        // Step 5: assert round-trip equality
        #expect(decoded.toolCalls == fixtureCalls)
    }
}
