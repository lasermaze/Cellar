import Foundation

// MARK: - KimiAdapter

/// ProviderAdapter implementation for the Kimi (Moonshot AI) OpenAI-compatible Chat Completions API.
///
/// Owns:
/// - OpenAI-compat message array (OpenAIToolRequest.Message elements)
/// - Kimi base URL (api.moonshot.ai), Bearer auth header
/// - Tool argument decoding (JSON string → JSONValue)
/// - Retry/backoff logic (3 attempts, exponential: 1s / 2s / 4s)
///
/// Anti-patterns avoided:
/// - Does NOT forward reasoning_content into subsequent messages
/// - Does NOT assume partial/safety flags beyond what OpenAI-compat wire format provides
final class KimiAdapter: ProviderAdapter {

    // MARK: Properties

    private let apiKey: String
    private let modelName: String
    private let openAITools: [OpenAIToolDef]
    private var messages: [OpenAIToolRequest.Message] = []

    // MARK: Init

    init(descriptor: ModelDescriptor, apiKey: String, tools: [ToolDefinition], systemPrompt: String) {
        self.apiKey = apiKey
        self.modelName = descriptor.id

        // Convert ToolDefinition → OpenAIToolDef
        self.openAITools = tools.map { td in
            OpenAIToolDef(
                type: "function",
                function: OpenAIToolDef.FunctionDef(
                    name: td.name,
                    description: td.description,
                    parameters: td.inputSchema
                )
            )
        }

        // Prepend system message
        if !systemPrompt.isEmpty {
            messages.append(OpenAIToolRequest.Message(
                role: "system",
                content: systemPrompt,
                toolCalls: nil,
                toolCallId: nil
            ))
        }
    }

    // MARK: Message Building

    func appendUserMessage(_ text: String) {
        messages.append(OpenAIToolRequest.Message(
            role: "user",
            content: text,
            toolCalls: nil,
            toolCallId: nil
        ))
    }

    func appendAssistantResponse(_ response: AgentLoopProviderResponse) {
        // Serialize each tool call's JSONValue input back to a JSON string for arguments field
        let toolCallMessages: [OpenAIToolRequest.ToolCall]? = response.toolCalls.isEmpty ? nil : response.toolCalls.compactMap { call in
            guard let argumentsData = try? JSONEncoder().encode(call.input),
                  let argumentsString = String(data: argumentsData, encoding: .utf8) else {
                return nil
            }
            return OpenAIToolRequest.ToolCall(
                id: call.id,
                type: "function",
                function: OpenAIToolRequest.FunctionCall(name: call.name, arguments: argumentsString)
            )
        }

        // Use the first text block as content (or nil if only tool calls)
        let textContent: String? = response.textBlocks.isEmpty ? nil : response.textBlocks.joined(separator: "\n")

        messages.append(OpenAIToolRequest.Message(
            role: "assistant",
            content: textContent,
            toolCalls: toolCallMessages,
            toolCallId: nil
        ))
    }

    func appendToolResults(_ results: [(id: String, content: String, isError: Bool)]) {
        // OpenAI format requires SEPARATE messages for each tool result
        for result in results {
            messages.append(OpenAIToolRequest.Message(
                role: "tool",
                content: result.content,
                toolCalls: nil,
                toolCallId: result.id
            ))
        }
    }

    // MARK: API Call

    func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) async throws -> AgentLoopProviderResponse {
        let backoffNanos: [UInt64] = [1_000_000_000, 2_000_000_000, 4_000_000_000]

        for attempt in 1...3 {
            do {
                let response = try await callKimi(maxTokens: maxTokens)
                return try translateKimiResponse(response)
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

    // MARK: Private

    private func callKimi(maxTokens: Int) async throws -> OpenAIToolResponse {
        let requestBody = OpenAIToolRequest(
            model: modelName,
            maxTokens: maxTokens,
            messages: messages,
            tools: openAITools.isEmpty ? nil : openAITools
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var urlRequest = URLRequest(url: URL(string: "https://api.moonshot.ai/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        let responseData = try await agentCallAPI(request: urlRequest)

        do {
            return try JSONDecoder().decode(OpenAIToolResponse.self, from: responseData)
        } catch {
            let rawBody = String(data: responseData, encoding: .utf8) ?? "(binary)"
            throw AgentLoopError.decodingError("Failed to decode OpenAIToolResponse: \(error). Body: \(rawBody.prefix(500))")
        }
    }

    private func translateKimiResponse(_ response: OpenAIToolResponse) throws -> AgentLoopProviderResponse {
        guard let choice = response.choices.first else {
            throw AgentLoopError.decodingError("No choices in Kimi response")
        }

        let message = choice.message
        var textBlocks: [String] = []
        var toolCalls: [AgentToolCall] = []

        if let content = message.content, !content.isEmpty {
            textBlocks.append(content)
        }

        if let rawToolCalls = message.toolCalls {
            for call in rawToolCalls {
                // Parse arguments JSON string → JSONValue
                let argumentsData = Data(call.function.arguments.utf8)
                let input: JSONValue
                do {
                    input = try JSONDecoder().decode(JSONValue.self, from: argumentsData)
                } catch {
                    throw AgentLoopError.decodingError("Failed to decode tool arguments for '\(call.function.name)': \(error)")
                }
                toolCalls.append(AgentToolCall(id: call.id, name: call.function.name, input: input))
            }
        }

        let stopReason: AgentLoopProviderResponse.StopReason
        switch choice.finishReason {
        case "stop":        stopReason = .endTurn
        case "tool_calls":  stopReason = .toolUse
        case "length":      stopReason = .maxTokens
        default:            stopReason = .other(choice.finishReason)
        }

        return AgentLoopProviderResponse(
            textBlocks: textBlocks,
            toolCalls: toolCalls,
            stopReason: stopReason,
            inputTokens: response.usage?.promptTokens ?? 0,
            outputTokens: response.usage?.completionTokens ?? 0
        )
    }
}
