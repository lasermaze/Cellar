import Testing
import Foundation
@testable import cellar

// MARK: - Fixtures

private let kimiDescriptor = ModelDescriptor(
    id: "moonshot-v1-8k",
    provider: .kimi,
    inputPricePerToken: 0.0000012,
    outputPricePerToken: 0.0000012,
    maxOutputTokens: 4096
)

private let kimiFixtureCalls: [AgentToolCall] = [
    AgentToolCall(id: "call_1", name: "inspect_game", input: .object([:])),
    AgentToolCall(id: "call_2", name: "set_environment", input: .object([
        "key": .string("WINEDLLOVERRIDES"), "value": .string("ddraw=n,b")
    ])),
    AgentToolCall(id: "call_3", name: "search_web", input: .object([
        "query": .string("starcraft wine"),
        "tags": .array([.string("rts"), .string("blizzard")])
    ])),
]

// MARK: - Helpers

/// Serializes a JSONValue to the stringified-JSON format used by OpenAI tool_calls.
private func kimiStringify(_ value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

/// Builds an OpenAIToolResponse fixture from AgentToolCall values.
private func makeKimiOpenAIResponse(calls: [AgentToolCall]) throws -> OpenAIToolResponse {
    let toolCalls = try calls.map { call in
        OpenAIToolResponse.ToolCall(
            id: call.id,
            type: "function",
            function: OpenAIToolResponse.FunctionCall(name: call.name, arguments: try kimiStringify(call.input))
        )
    }
    let message = OpenAIToolResponse.Message(role: "assistant", content: nil, toolCalls: toolCalls)
    let choice = OpenAIToolResponse.Choice(message: message, finishReason: "tool_calls")
    return OpenAIToolResponse(choices: [choice], usage: nil)
}

// MARK: - KimiAdapterTests

@Suite("KimiAdapter — tool call encode/decode")
struct KimiAdapterTests {

    private func makeAdapter() -> KimiAdapter {
        KimiAdapter(descriptor: kimiDescriptor, apiKey: "test", tools: [], systemPrompt: "")
    }

    @Test("decodesOpenAIToolCalls — id, name, and arguments JSON parse correctly")
    func decodesOpenAIToolCalls() throws {
        let adapter = makeAdapter()
        let wireResponse = try makeKimiOpenAIResponse(calls: Array(kimiFixtureCalls.prefix(2)))
        let result = try adapter.translateResponse(wireResponse)

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

    @Test("encodesToolCallsInAssistantMessage — arguments round-trip to original input")
    func encodesToolCallsInAssistantMessage() throws {
        let adapter = makeAdapter()
        let providerResponse = AgentLoopProviderResponse(
            textBlocks: [],
            toolCalls: kimiFixtureCalls,
            stopReason: .toolUse,
            inputTokens: 0,
            outputTokens: 0
        )
        guard let encoded = adapter.encodedAssistantToolCalls(for: providerResponse) else {
            Issue.record("Expected non-nil tool calls from encoder")
            return
        }
        #expect(encoded.count == 3)
        #expect(encoded[0].id == "call_1")
        #expect(encoded[1].id == "call_2")
        #expect(encoded[2].id == "call_3")
        // Decode arguments back to JSONValue and compare
        for (enc, original) in zip(encoded, kimiFixtureCalls) {
            let data = Data(enc.function.arguments.utf8)
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            #expect(decoded == original.input)
            #expect(enc.function.name == original.name)
        }
    }

    @Test("roundTrip — encode then decode yields original AgentToolCall values")
    func roundTrip() throws {
        let adapter = makeAdapter()
        let providerResponse = AgentLoopProviderResponse(
            textBlocks: [],
            toolCalls: kimiFixtureCalls,
            stopReason: .toolUse,
            inputTokens: 0,
            outputTokens: 0
        )
        // Encode to OpenAI wire format
        guard let encoded = adapter.encodedAssistantToolCalls(for: providerResponse) else {
            Issue.record("Expected encoded tool calls")
            return
        }
        // Build an OpenAIToolResponse from the encoded tool calls
        let wireToolCalls = encoded.map { enc in
            OpenAIToolResponse.ToolCall(
                id: enc.id, type: enc.type,
                function: OpenAIToolResponse.FunctionCall(name: enc.function.name, arguments: enc.function.arguments)
            )
        }
        let message = OpenAIToolResponse.Message(role: "assistant", content: nil, toolCalls: wireToolCalls)
        let choice = OpenAIToolResponse.Choice(message: message, finishReason: "tool_calls")
        let wireResponse = OpenAIToolResponse(choices: [choice], usage: nil)
        // Decode back to AgentLoopProviderResponse
        let decoded = try adapter.translateResponse(wireResponse)
        #expect(decoded.toolCalls == kimiFixtureCalls)
    }
}
