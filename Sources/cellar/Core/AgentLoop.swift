import Foundation

// MARK: - AgentLoopResult

/// Result returned when the agent loop terminates.
struct AgentLoopResult {
    /// Concatenated text from all assistant text blocks across the run.
    let finalText: String
    /// Number of API calls made (tool-use iterations).
    let iterationsUsed: Int
    /// True if loop ended because the model returned "end_turn". False if max iterations reached or error occurred.
    let completed: Bool
    /// Total input tokens consumed across all iterations.
    let totalInputTokens: Int
    /// Total output tokens consumed across all iterations.
    let totalOutputTokens: Int
    /// Estimated cost in USD based on token usage.
    let estimatedCostUSD: Double
}

// MARK: - AgentLoop

/// Drives the Anthropic tool-use send-execute-return cycle.
///
/// Usage:
/// ```swift
/// let loop = AgentLoop(apiKey: key, tools: [myTool], systemPrompt: "...")
/// let result = loop.run(initialMessage: "...", toolExecutor: { name, input in
///     // execute tool, return result string
///     return "tool output"
/// })
/// ```
struct AgentLoop {

    // MARK: Properties

    let apiKey: String
    let model: String
    let tools: [ToolDefinition]
    let systemPrompt: String
    let maxIterations: Int
    let maxTokens: Int

    // MARK: Init

    init(
        apiKey: String,
        tools: [ToolDefinition],
        systemPrompt: String,
        model: String = "claude-opus-4-6",
        maxIterations: Int = 20,
        maxTokens: Int = 4096
    ) {
        self.apiKey = apiKey
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.model = model
        self.maxIterations = maxIterations
        self.maxTokens = maxTokens
    }

    // MARK: Run

    /// Execute the agent loop with an initial user message.
    ///
    /// - Parameters:
    ///   - initialMessage: The first user message to send.
    ///   - toolExecutor: Closure called for each tool use. Receives tool name and input JSONValue. Returns result string.
    /// - Returns: AgentLoopResult with finalText, iterationsUsed, and completed flag.
    func run(
        initialMessage: String,
        toolExecutor: (String, JSONValue) -> String
    ) -> AgentLoopResult {
        var messages: [AnthropicToolRequest.Message] = []
        var iterationCount = 0
        var allText: [String] = []

        // Step 1: Append initial user message
        messages.append(AnthropicToolRequest.Message(role: "user", content: .text(initialMessage)))

        // Step 2: Main loop
        while iterationCount < maxIterations {
            iterationCount += 1

            // Step 2a: Call Anthropic API
            print("[Agent iteration \(iterationCount)/\(maxIterations)]")
            let response: AnthropicToolResponse
            do {
                response = try callAnthropic(messages: messages)
            } catch {
                let errorMessage = "Agent API error (iteration \(iterationCount)): \(error.localizedDescription)"
                print(errorMessage)
                return AgentLoopResult(finalText: errorMessage, iterationsUsed: iterationCount, completed: false, totalInputTokens: 0, totalOutputTokens: 0, estimatedCostUSD: 0.0)
            }

            // Step 2b: Print and collect text blocks
            for block in response.content {
                if case .text(let text) = block, !text.isEmpty {
                    print("Agent: \(text)")
                    allText.append(text)
                }
            }

            // Step 2c: Handle stop reason
            switch response.stopReason {
            case "end_turn":
                return AgentLoopResult(
                    finalText: allText.joined(separator: "\n"),
                    iterationsUsed: iterationCount,
                    completed: true,
                    totalInputTokens: 0,
                    totalOutputTokens: 0,
                    estimatedCostUSD: 0.0
                )

            case "tool_use":
                // Append assistant turn with full content (text + tool_use blocks)
                messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))

                // Execute each tool call and collect tool_result blocks
                var resultBlocks: [ToolContentBlock] = []
                for block in response.content {
                    if case .toolUse(let id, let name, let input) = block {
                        print("-> \(name)")
                        let result = toolExecutor(name, input)
                        resultBlocks.append(.toolResult(toolUseId: id, content: result, isError: false))
                    }
                }

                // Append user turn with tool results
                // Per Anthropic API: tool_result blocks must be the content of the user turn
                messages.append(AnthropicToolRequest.Message(role: "user", content: .blocks(resultBlocks)))

            case "max_tokens":
                // Response was truncated — append what we got and ask the model to continue
                print("[Agent: response truncated, continuing...]")
                messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                messages.append(AnthropicToolRequest.Message(role: "user", content: .text("Your response was truncated due to length. Please continue where you left off. If you were about to call a tool, call it now.")))

            default:
                // Truly unexpected stop reason — return what we have
                print("[Agent: unexpected stop_reason '\(response.stopReason)']")
                return AgentLoopResult(
                    finalText: allText.joined(separator: "\n"),
                    iterationsUsed: iterationCount,
                    completed: false,
                    totalInputTokens: 0,
                    totalOutputTokens: 0,
                    estimatedCostUSD: 0.0
                )
            }
        }

        // Max iterations reached
        return AgentLoopResult(
            finalText: allText.joined(separator: "\n"),
            iterationsUsed: iterationCount,
            completed: false,
            totalInputTokens: 0,
            totalOutputTokens: 0,
            estimatedCostUSD: 0.0
        )
    }

    // MARK: - Private HTTP

    /// Call the Anthropic messages API synchronously.
    /// Uses DispatchSemaphore + URLSession.shared (background delegate queue) to bridge async URLSession.
    private func callAnthropic(messages: [AnthropicToolRequest.Message]) throws -> AnthropicToolResponse {
        let requestBody = AnthropicToolRequest(
            model: model,
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

        let responseData = try callAPI(request: urlRequest)

        do {
            let response = try JSONDecoder().decode(AnthropicToolResponse.self, from: responseData)
            return response
        } catch {
            // Provide debugging context: include raw response body
            let rawBody = String(data: responseData, encoding: .utf8) ?? "(binary)"
            throw AgentLoopError.decodingError("Failed to decode AnthropicToolResponse: \(error). Body: \(rawBody.prefix(500))")
        }
    }

    /// Synchronous HTTP call using DispatchSemaphore to bridge async URLSession.
    /// Pattern mirrors AIService.callAPI (which is private and cannot be reused directly).
    private func callAPI(request: URLRequest) throws -> Data {
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
}

// MARK: - AgentLoopError

enum AgentLoopError: Error, LocalizedError {
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case noResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body.prefix(500))"
        case .decodingError(let detail):
            return "Failed to decode agent response: \(detail)"
        case .noResponse:
            return "No response from agent API"
        }
    }
}
