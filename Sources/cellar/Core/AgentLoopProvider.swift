import Foundation

// MARK: - AgentLoopProviderResponse

/// The normalized response returned by any AgentLoopProvider implementation.
/// Abstracts away Anthropic and OpenAI/Deepseek response format differences.
struct AgentLoopProviderResponse {
    enum StopReason {
        case endTurn
        case toolUse
        case maxTokens
        case other(String)
    }

    let textBlocks: [String]
    let toolCalls: [(id: String, name: String, input: JSONValue)]
    let stopReason: StopReason
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - AgentLoopProvider Protocol

/// Abstracts all provider-specific API communication for the agent loop.
///
/// The provider owns the conversation message array entirely.
/// AgentLoop never holds provider-specific message types — it works
/// only with normalized `AgentLoopProviderResponse` values.
protocol AgentLoopProvider {
    var modelName: String { get }
    func pricingPerToken() -> (input: Double, output: Double)
    mutating func appendUserMessage(_ text: String)
    mutating func appendAssistantResponse(_ response: AgentLoopProviderResponse)
    mutating func appendToolResults(_ results: [(id: String, content: String, isError: Bool)])
    mutating func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) throws -> AgentLoopProviderResponse
}

// MARK: - Per-Provider Pricing Map

/// Pricing per token for known models (input, output in USD).
let modelPricing: [String: (input: Double, output: Double)] = [
    "claude-sonnet-4-6": (input: 3.0 / 1_000_000, output: 15.0 / 1_000_000),
    "claude-opus-4-6":   (input: 15.0 / 1_000_000, output: 75.0 / 1_000_000),
    "deepseek-chat":     (input: 0.27 / 1_000_000, output: 1.10 / 1_000_000),
    "deepseek-reasoner": (input: 0.55 / 1_000_000, output: 2.19 / 1_000_000),
]

// MARK: - Shared HTTP Helper

/// Synchronous HTTP call using DispatchSemaphore to bridge async URLSession.
/// Used by both AnthropicAgentProvider and DeepseekAgentProvider.
func agentCallAPI(request: URLRequest) throws -> Data {
    // Use a class box for Swift 6 Sendable compliance — avoids captured-var mutation warning
    final class ResultBox: @unchecked Sendable {
        var value: Result<Data, Error> = .failure(AgentLoopError.noResponse)
    }
    let box = ResultBox()
    let semaphore = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            box.value = .failure(error)
        } else if let data = data {
            let httpResponse = response as? HTTPURLResponse
            if let code = httpResponse?.statusCode, code >= 400 {
                let body = String(data: data, encoding: .utf8) ?? "(binary)"
                box.value = .failure(AgentLoopError.httpError(statusCode: code, body: body))
            } else {
                box.value = .success(data)
            }
        }
        semaphore.signal()
    }.resume()

    semaphore.wait()
    return try box.value.get()
}

// MARK: - AnthropicAgentProvider

/// AgentLoopProvider implementation that uses the Anthropic tool-use API format.
struct AnthropicAgentProvider: AgentLoopProvider {

    // MARK: Properties

    let apiKey: String
    let modelName: String
    private let tools: [ToolDefinition]
    private let systemPrompt: String
    private var messages: [AnthropicToolRequest.Message] = []

    // MARK: Init

    init(apiKey: String, model: String, tools: [ToolDefinition], systemPrompt: String) {
        self.apiKey = apiKey
        self.modelName = model
        self.tools = tools
        self.systemPrompt = systemPrompt
    }

    // MARK: Pricing

    func pricingPerToken() -> (input: Double, output: Double) {
        modelPricing[modelName] ?? (0.0, 0.0)
    }

    // MARK: Message Building

    mutating func appendUserMessage(_ text: String) {
        messages.append(AnthropicToolRequest.Message(role: "user", content: .text(text)))
    }

    mutating func appendAssistantResponse(_ response: AgentLoopProviderResponse) {
        var blocks: [ToolContentBlock] = []
        for text in response.textBlocks {
            blocks.append(.text(text))
        }
        for call in response.toolCalls {
            blocks.append(.toolUse(id: call.id, name: call.name, input: call.input))
        }
        messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(blocks)))
    }

    mutating func appendToolResults(_ results: [(id: String, content: String, isError: Bool)]) {
        let resultBlocks: [ToolContentBlock] = results.map { result in
            .toolResult(toolUseId: result.id, content: result.content, isError: result.isError)
        }
        messages.append(AnthropicToolRequest.Message(role: "user", content: .blocks(resultBlocks)))
    }

    // MARK: API Call

    mutating func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) throws -> AgentLoopProviderResponse {
        let backoffSeconds: [Double] = [1.0, 2.0, 4.0]

        for attempt in 1...3 {
            do {
                let response = try callAnthropic(maxTokens: maxTokens)
                return translateAnthropicResponse(response)
            } catch let error as AgentLoopError {
                if case .httpError(let code, _) = error {
                    if code >= 400 && code < 500 && code != 429 {
                        throw error  // Fatal 4xx (not rate limit) — do not retry
                    }
                }
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    Thread.sleep(forTimeInterval: backoffSeconds[attempt - 1])
                }
            } catch {
                // Network errors (URLError etc) — retriable
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    Thread.sleep(forTimeInterval: backoffSeconds[attempt - 1])
                }
            }
        }
        throw AgentLoopError.apiUnavailable
    }

    // MARK: Private

    private func callAnthropic(maxTokens: Int) throws -> AnthropicToolResponse {
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

        let responseData = try agentCallAPI(request: urlRequest)

        do {
            return try JSONDecoder().decode(AnthropicToolResponse.self, from: responseData)
        } catch {
            let rawBody = String(data: responseData, encoding: .utf8) ?? "(binary)"
            throw AgentLoopError.decodingError("Failed to decode AnthropicToolResponse: \(error). Body: \(rawBody.prefix(500))")
        }
    }

    private func translateAnthropicResponse(_ response: AnthropicToolResponse) -> AgentLoopProviderResponse {
        var textBlocks: [String] = []
        var toolCalls: [(id: String, name: String, input: JSONValue)] = []

        for block in response.content {
            switch block {
            case .text(let t):
                if !t.isEmpty { textBlocks.append(t) }
            case .toolUse(let id, let name, let input):
                toolCalls.append((id: id, name: name, input: input))
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

// MARK: - DeepseekAgentProvider

/// AgentLoopProvider implementation that uses the OpenAI-compatible API format for Deepseek.
///
/// Anti-patterns avoided:
/// - Does NOT use deepseek-reasoner as default (it doesn't support function calling).
/// - Does NOT forward reasoning_content from responses into subsequent messages.
/// - Decodes tool arguments from JSON string (not direct cast).
struct DeepseekAgentProvider: AgentLoopProvider {

    // MARK: Properties

    let apiKey: String
    let modelName: String
    private let openAITools: [OpenAIToolDef]
    private var messages: [OpenAIToolRequest.Message] = []

    // MARK: Init

    init(apiKey: String, model: String = "deepseek-chat", tools: [ToolDefinition], systemPrompt: String) {
        self.apiKey = apiKey
        self.modelName = model

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

    // MARK: Pricing

    func pricingPerToken() -> (input: Double, output: Double) {
        modelPricing[modelName] ?? (0.0, 0.0)
    }

    // MARK: Message Building

    mutating func appendUserMessage(_ text: String) {
        messages.append(OpenAIToolRequest.Message(
            role: "user",
            content: text,
            toolCalls: nil,
            toolCallId: nil
        ))
    }

    mutating func appendAssistantResponse(_ response: AgentLoopProviderResponse) {
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

        // CRITICAL: Do NOT include reasoning_content — strip any reasoning from Deepseek responses
        messages.append(OpenAIToolRequest.Message(
            role: "assistant",
            content: textContent,
            toolCalls: toolCallMessages,
            toolCallId: nil
        ))
    }

    mutating func appendToolResults(_ results: [(id: String, content: String, isError: Bool)]) {
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

    mutating func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) throws -> AgentLoopProviderResponse {
        let backoffSeconds: [Double] = [1.0, 2.0, 4.0]

        for attempt in 1...3 {
            do {
                let response = try callDeepseek(maxTokens: maxTokens)
                return try translateDeepseekResponse(response)
            } catch let error as AgentLoopError {
                if case .httpError(let code, _) = error {
                    if code >= 400 && code < 500 && code != 429 {
                        throw error  // Fatal 4xx (not rate limit) — do not retry
                    }
                }
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    Thread.sleep(forTimeInterval: backoffSeconds[attempt - 1])
                }
            } catch {
                // Network errors (URLError etc) — retriable
                if attempt < 3 {
                    emit(.status("API error, retrying (\(attempt + 1)/3)..."))
                    Thread.sleep(forTimeInterval: backoffSeconds[attempt - 1])
                }
            }
        }
        throw AgentLoopError.apiUnavailable
    }

    // MARK: Private

    private func callDeepseek(maxTokens: Int) throws -> OpenAIToolResponse {
        let requestBody = OpenAIToolRequest(
            model: modelName,
            maxTokens: maxTokens,
            messages: messages,
            tools: openAITools.isEmpty ? nil : openAITools
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var urlRequest = URLRequest(url: URL(string: "https://api.deepseek.com/v1/chat/completions")!)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        let responseData = try agentCallAPI(request: urlRequest)

        do {
            return try JSONDecoder().decode(OpenAIToolResponse.self, from: responseData)
        } catch {
            let rawBody = String(data: responseData, encoding: .utf8) ?? "(binary)"
            throw AgentLoopError.decodingError("Failed to decode OpenAIToolResponse: \(error). Body: \(rawBody.prefix(500))")
        }
    }

    private func translateDeepseekResponse(_ response: OpenAIToolResponse) throws -> AgentLoopProviderResponse {
        guard let choice = response.choices.first else {
            throw AgentLoopError.decodingError("No choices in Deepseek response")
        }

        let message = choice.message
        var textBlocks: [String] = []
        var toolCalls: [(id: String, name: String, input: JSONValue)] = []

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
                toolCalls.append((id: call.id, name: call.function.name, input: input))
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
