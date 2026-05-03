import Foundation

// MARK: - AnthropicAdapter

/// ProviderAdapter implementation for the Anthropic Messages API.
///
/// Owns:
/// - Anthropic-specific message array (AnthropicToolRequest.Message elements)
/// - URL, auth header, request encoding, response decoding
/// - Retry/backoff logic (3 attempts, exponential: 1s / 2s / 4s)
final class AnthropicAdapter: ProviderAdapter {

    // MARK: Properties

    private let apiKey: String
    private let modelName: String
    private let tools: [ToolDefinition]
    private let systemPrompt: String
    private var messages: [AnthropicToolRequest.Message] = []

    // MARK: Init

    init(descriptor: ModelDescriptor, apiKey: String, tools: [ToolDefinition], systemPrompt: String) {
        self.apiKey = apiKey
        self.modelName = descriptor.id
        self.tools = tools
        self.systemPrompt = systemPrompt
    }

    // MARK: Message Building

    func appendUserMessage(_ text: String) {
        messages.append(AnthropicToolRequest.Message(role: "user", content: .text(text)))
    }

    func appendAssistantResponse(_ response: AgentLoopProviderResponse) {
        var blocks: [ToolContentBlock] = []
        for text in response.textBlocks {
            blocks.append(.text(text))
        }
        for call in response.toolCalls {
            blocks.append(.toolUse(id: call.id, name: call.name, input: call.input))
        }
        messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(blocks)))
    }

    func appendToolResults(_ results: [(id: String, content: String, isError: Bool)]) {
        let resultBlocks: [ToolContentBlock] = results.map { result in
            .toolResult(toolUseId: result.id, content: result.content, isError: result.isError)
        }
        messages.append(AnthropicToolRequest.Message(role: "user", content: .blocks(resultBlocks)))
    }

    // MARK: API Call

    func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) async throws -> AgentLoopProviderResponse {
        let backoffNanos: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]

        for attempt in 1...3 {
            do {
                let response = try await callAnthropic(maxTokens: maxTokens)
                return translateAnthropicResponse(response)
            } catch let error as AgentLoopError {
                if case .httpError(let code, _) = error {
                    if code >= 400 && code < 500 && code != 429 {
                        throw error  // Fatal 4xx (not rate limit) — do not retry
                    }
                }
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    try await Task.sleep(nanoseconds: backoffNanos[attempt - 1])
                }
            } catch {
                // Network errors (URLError etc) — retriable
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    try await Task.sleep(nanoseconds: backoffNanos[attempt - 1])
                }
            }
        }
        throw AgentLoopError.apiUnavailable
    }

    // MARK: Internal Testable Helpers

    /// Translates a decoded AnthropicToolResponse into the canonical provider response.
    /// Internal so unit tests can call it directly without an HTTP round-trip.
    func translateResponse(_ response: AnthropicToolResponse) -> AgentLoopProviderResponse {
        translateAnthropicResponse(response)
    }

    /// Returns the tool_use blocks that appendAssistantResponse would emit for a given response.
    /// Internal for encode round-trip tests — avoids exposing the full messages array.
    func encodedAssistantBlocks(for response: AgentLoopProviderResponse) -> [ToolContentBlock] {
        var blocks: [ToolContentBlock] = []
        for text in response.textBlocks { blocks.append(.text(text)) }
        for call in response.toolCalls { blocks.append(.toolUse(id: call.id, name: call.name, input: call.input)) }
        return blocks
    }

    // MARK: Private

    private func callAnthropic(maxTokens: Int) async throws -> AnthropicToolResponse {
        let requestBody = AnthropicToolRequest(
            model: modelName,
            maxTokens: maxTokens,
            system: systemPrompt.isEmpty ? nil : systemPrompt,
            messages: messages,
            tools: tools.isEmpty ? nil : tools
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.httpBody = bodyData

        let responseData = try await agentCallAPI(request: urlRequest)

        do {
            return try JSONDecoder().decode(AnthropicToolResponse.self, from: responseData)
        } catch {
            let rawBody = String(data: responseData, encoding: .utf8) ?? "(binary)"
            throw AgentLoopError.decodingError("Failed to decode AnthropicToolResponse: \(error). Body: \(rawBody.prefix(500))")
        }
    }

    private func translateAnthropicResponse(_ response: AnthropicToolResponse) -> AgentLoopProviderResponse {
        var textBlocks: [String] = []
        var toolCalls: [AgentToolCall] = []

        for block in response.content {
            switch block {
            case .text(let t):
                if !t.isEmpty { textBlocks.append(t) }
            case .toolUse(let id, let name, let input):
                toolCalls.append(AgentToolCall(id: id, name: name, input: input))
            case .toolResult:
                break // Tool results don't appear in assistant responses
            }
        }

        let stopReason: AgentLoopProviderResponse.StopReason
        switch response.stopReason {
        case "end_turn":   stopReason = .endTurn
        case "tool_use":   stopReason = .toolUse
        case "max_tokens": stopReason = .maxTokens
        default:           stopReason = .other(response.stopReason)
        }

        return AgentLoopProviderResponse(
            textBlocks: textBlocks,
            toolCalls: toolCalls,
            stopReason: stopReason,
            inputTokens: response.usage?.inputTokens ?? 0,
            outputTokens: response.usage?.outputTokens ?? 0
        )
    }
}
