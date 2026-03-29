import Foundation

// MARK: - AgentLoopResult

/// Why the agent loop stopped.
enum AgentStopReason: Sendable {
    case completed
    case budgetExhausted
    case maxIterations
    case apiError(String)
}

/// Result returned when the agent loop terminates.
struct AgentLoopResult: Sendable {
    /// Concatenated text from all assistant text blocks across the run.
    let finalText: String
    /// Number of API calls made (tool-use iterations).
    let iterationsUsed: Int
    /// True if loop ended because the model returned "end_turn". False if max iterations reached or error occurred.
    let completed: Bool
    /// Why the loop stopped.
    let stopReason: AgentStopReason
    /// Total input tokens consumed across all iterations.
    let totalInputTokens: Int
    /// Total output tokens consumed across all iterations.
    let totalOutputTokens: Int
    /// Estimated cost in USD based on token usage.
    let estimatedCostUSD: Double
}

// MARK: - AgentEvent

/// Events emitted during agent loop execution for external consumers (web UI, logging).
enum AgentEvent: Sendable {
    case iteration(number: Int, total: Int)
    case text(String)
    case toolCall(name: String)
    case toolResult(name: String, truncated: String)
    case cost(inputTokens: Int, outputTokens: Int, usd: Double)
    case budgetWarning(percentage: Int)
    case status(String)
    case error(String)
    case completed(AgentLoopResult)
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
    let budgetCeiling: Double
    let onOutput: (@Sendable (AgentEvent) -> Void)?

    // MARK: Init

    init(
        apiKey: String,
        tools: [ToolDefinition],
        systemPrompt: String,
        model: String = "claude-opus-4-6",
        maxIterations: Int = 20,
        maxTokens: Int = 4096,
        budgetCeiling: Double = 5.00,
        onOutput: (@Sendable (AgentEvent) -> Void)? = nil
    ) {
        self.apiKey = apiKey
        self.tools = tools
        self.systemPrompt = systemPrompt
        self.model = model
        self.maxIterations = maxIterations
        self.maxTokens = maxTokens
        self.budgetCeiling = budgetCeiling
        self.onOutput = onOutput
    }

    // MARK: Emit

    /// Emit a structured event AND preserve CLI print output.
    private func emit(_ event: AgentEvent) {
        onOutput?(event)
        switch event {
        case .iteration(let n, let total):
            print("[Agent iteration \(n)/\(total)]")
        case .text(let text):
            print("Agent: \(text)")
        case .toolCall(let name):
            print("-> \(name)")
        case .toolResult:
            break // not printed in CLI
        case .cost:
            break // printed separately at session end
        case .budgetWarning(let pct):
            print("[Budget: \(pct)% used]")
        case .status(let msg):
            print(msg)
        case .error(let msg):
            print(msg)
        case .completed:
            break
        }
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
        toolExecutor: (String, JSONValue) -> String,
        canStop: (() -> Bool)? = nil
    ) -> AgentLoopResult {
        var messages: [AnthropicToolRequest.Message] = []
        var iterationCount = 0
        var allText: [String] = []

        // Resilience state
        var currentMaxTokens = maxTokens
        let maxTokensCeiling = 32768
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var hasAlertedAt50 = false
        var hasWarnedAt80 = false
        var hasSentBudgetHalt = false
        var hasSentBudgetWarningMessage = false
        var consecutiveContinuations = 0

        // Pricing constants (Sonnet 4.6: $3/$15 per MTok)
        let inputPricePerToken  = 3.0 / 1_000_000.0
        let outputPricePerToken = 15.0 / 1_000_000.0

        func estimatedCost() -> Double {
            Double(totalInputTokens) * inputPricePerToken + Double(totalOutputTokens) * outputPricePerToken
        }

        func makeResult(text: String, iterations: Int, completed: Bool, stopReason: AgentStopReason) -> AgentLoopResult {
            let result = AgentLoopResult(
                finalText: text,
                iterationsUsed: iterations,
                completed: completed,
                stopReason: stopReason,
                totalInputTokens: totalInputTokens,
                totalOutputTokens: totalOutputTokens,
                estimatedCostUSD: estimatedCost()
            )
            emit(.cost(inputTokens: totalInputTokens, outputTokens: totalOutputTokens, usd: estimatedCost()))
            emit(.completed(result))
            return result
        }

        // Step 1: Append initial user message
        messages.append(AnthropicToolRequest.Message(role: "user", content: .text(initialMessage)))

        // Step 2: Main loop
        while iterationCount < maxIterations {
            iterationCount += 1

            // Step 2a: Call Anthropic API with retry
            emit(.iteration(number: iterationCount, total: maxIterations))
            let response: AnthropicToolResponse
            do {
                response = try callAnthropicWithRetry(messages: messages, maxTokens: currentMaxTokens)
            } catch let error as AgentLoopError {
                if case .apiUnavailable = error {
                    emit(.error("API unavailable after 3 attempts. Your game state is unchanged."))
                } else {
                    emit(.error("Agent API error (iteration \(iterationCount)): \(error.localizedDescription)"))
                }
                return makeResult(
                    text: allText.joined(separator: "\n") + "\n\(error.localizedDescription)",
                    iterations: iterationCount,
                    completed: false,
                    stopReason: .apiError(error.localizedDescription)
                )
            } catch {
                emit(.error("Agent API error (iteration \(iterationCount)): \(error.localizedDescription)"))
                return makeResult(
                    text: allText.joined(separator: "\n") + "\n\(error.localizedDescription)",
                    iterations: iterationCount,
                    completed: false,
                    stopReason: .apiError(error.localizedDescription)
                )
            }

            // Step 2b: Accumulate token usage
            if let usage = response.usage {
                totalInputTokens += usage.inputTokens
                totalOutputTokens += usage.outputTokens
            }

            // Step 2c: Check budget thresholds
            let currentCost = estimatedCost()
            let budgetFraction = budgetCeiling > 0 ? currentCost / budgetCeiling : 0

            if budgetFraction >= 0.5 && !hasAlertedAt50 {
                emit(.budgetWarning(percentage: 50))
                emit(.cost(inputTokens: totalInputTokens, outputTokens: totalOutputTokens, usd: currentCost))
                hasAlertedAt50 = true
            }

            if budgetFraction >= 1.0 && !hasSentBudgetHalt {
                // Inject halt directive, let agent make one final call to save
                let stopMsg = "[BUDGET LIMIT REACHED: $\(String(format: "%.2f", budgetCeiling)) session budget exhausted. You must stop now. Call save_success or save_recipe if you have a working configuration, then stop.]"
                messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                messages.append(AnthropicToolRequest.Message(role: "user", content: .text(stopMsg)))
                hasSentBudgetHalt = true
                // Make one final API call for the agent to save
                if let finalResponse = try? callAnthropicWithRetry(messages: messages, maxTokens: currentMaxTokens) {
                    if let usage = finalResponse.usage {
                        totalInputTokens += usage.inputTokens
                        totalOutputTokens += usage.outputTokens
                    }
                    for block in finalResponse.content {
                        if case .text(let t) = block, !t.isEmpty { allText.append(t) }
                    }
                }
                return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: false, stopReason: .budgetExhausted)
            }

            if budgetFraction >= 0.8 && !hasWarnedAt80 {
                hasWarnedAt80 = true
            }

            // Step 2d: Print and collect text blocks
            for block in response.content {
                if case .text(let text) = block, !text.isEmpty {
                    emit(.text(text))
                    allText.append(text)
                }
            }

            // Step 2e: Handle stop reason
            switch response.stopReason {
            case "end_turn":
                let hasContent = response.content.contains {
                    if case .text(let t) = $0, !t.isEmpty { return true }
                    if case .toolUse = $0 { return true }
                    return false
                }

                let agentCanStop = canStop?() ?? true  // nil callback = always allow (backward compat)

                if hasContent && !agentCanStop && consecutiveContinuations < 3 {
                    // Agent tried to stop but task isn't done yet
                    consecutiveContinuations += 1
                    emit(.status("[Agent tried to stop, but task is not complete (\(consecutiveContinuations)/3). Continuing...]"))
                    messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                    messages.append(AnthropicToolRequest.Message(role: "user", content: .text("You cannot stop yet — the game has not been confirmed working by the user, or you haven't saved a success record after confirmation. Continue diagnosing and fixing. Use your tools to investigate and apply a fix, then launch_game again.")))
                } else if hasContent {
                    return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: true, stopReason: .completed)
                } else {
                    // Empty end_turn — send continuation prompt
                    emit(.status("[Agent: empty response, sending continuation...]"))
                    messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                    messages.append(AnthropicToolRequest.Message(role: "user", content: .text("Please continue. What would you like to do next?")))
                }

            case "tool_use":
                // Agent is doing work — reset stuck-loop counter
                consecutiveContinuations = 0

                // Reset max_tokens after successful non-truncated response
                if currentMaxTokens > maxTokens {
                    currentMaxTokens = maxTokens
                }

                // Append assistant turn with full content (text + tool_use blocks)
                messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))

                // Execute each tool call and collect tool_result blocks
                var resultBlocks: [ToolContentBlock] = []
                for block in response.content {
                    if case .toolUse(let id, let name, let input) = block {
                        emit(.toolCall(name: name))
                        let result = toolExecutor(name, input)
                        emit(.toolResult(name: name, truncated: String(result.prefix(200))))
                        resultBlocks.append(.toolResult(toolUseId: id, content: result, isError: false))
                    }
                }

                // Inject budget warning as text block alongside tool results if threshold crossed
                if hasWarnedAt80 && !hasSentBudgetWarningMessage {
                    let cost = estimatedCost()
                    let pct = budgetCeiling > 0 ? Int(cost / budgetCeiling * 100) : 0
                    let warnMsg = "[BUDGET WARNING: \(pct)% of session budget used ($\(String(format: "%.2f", cost)) / $\(String(format: "%.2f", budgetCeiling))). Begin wrapping up - save progress and finalize results soon.]"
                    resultBlocks.append(.text(warnMsg))
                    hasSentBudgetWarningMessage = true
                }

                // Append user turn with tool results
                messages.append(AnthropicToolRequest.Message(role: "user", content: .blocks(resultBlocks)))

            case "max_tokens":
                let hasIncompleteToolUse = response.content.contains {
                    if case .toolUse = $0 { return true }
                    return false
                }
                if hasIncompleteToolUse && currentMaxTokens < maxTokensCeiling {
                    // Check if doubling would push past 80% budget — if so, use continuation instead
                    let projectedOutputTokens = totalOutputTokens + (currentMaxTokens * 2)
                    let projectedCost = Double(totalInputTokens) * inputPricePerToken + Double(projectedOutputTokens) * outputPricePerToken
                    if budgetCeiling > 0 && projectedCost / budgetCeiling >= 0.8 {
                        // Budget override: use continuation prompt instead of escalating
                        emit(.status("[Agent: max_tokens hit, but escalation would exceed budget. Using continuation...]"))
                        messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                        messages.append(AnthropicToolRequest.Message(role: "user", content: .text("Your response was truncated. Continue.")))
                    } else {
                        // Safe to escalate — do NOT append truncated response to messages
                        let newMax = min(currentMaxTokens * 2, maxTokensCeiling)
                        emit(.status("[Agent: max_tokens hit with incomplete tool_use, retrying with \(newMax)...]"))
                        currentMaxTokens = newMax
                        // Do NOT increment iteration count — this is a retry, not a new step
                        iterationCount -= 1
                        // Fall through to next iteration with same messages (no append)
                    }
                } else if hasIncompleteToolUse {
                    // At ceiling and still truncated — fall back to continuation
                    emit(.status("[Agent: max_tokens hit at ceiling (\(maxTokensCeiling)), using continuation...]"))
                    messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                    messages.append(AnthropicToolRequest.Message(role: "user", content: .text("Your response was truncated. Continue.")))
                } else {
                    // Text-only truncation — safe to append and continue
                    emit(.status("[Agent: response truncated, continuing...]"))
                    messages.append(AnthropicToolRequest.Message(role: "assistant", content: .blocks(response.content)))
                    messages.append(AnthropicToolRequest.Message(role: "user", content: .text("Your response was truncated. Continue.")))
                    // Reset max_tokens after text-only truncation
                    if currentMaxTokens > maxTokens {
                        currentMaxTokens = maxTokens
                    }
                }

            default:
                // Truly unexpected stop reason — return what we have
                emit(.error("[Agent: unexpected stop_reason '\(response.stopReason)']"))
                return makeResult(
                    text: allText.joined(separator: "\n"),
                    iterations: iterationCount,
                    completed: false,
                    stopReason: .apiError("unexpected stop_reason '\(response.stopReason)'")
                )
            }
        }

        // Max iterations reached
        return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: false, stopReason: .maxIterations)
    }

    // MARK: - Private Retry

    /// Call the Anthropic API with retry logic for transient errors.
    /// Retries 3 times with exponential backoff (1s, 2s, 4s) for 5xx, 429, and network errors.
    /// 4xx errors (except 429) abort immediately.
    private func callAnthropicWithRetry(
        messages: [AnthropicToolRequest.Message],
        maxTokens: Int
    ) throws -> AnthropicToolResponse {
        let backoffSeconds: [Double] = [1.0, 2.0, 4.0]

        for attempt in 1...3 {
            do {
                return try callAnthropic(messages: messages, overrideMaxTokens: maxTokens)
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

    // MARK: - Private HTTP

    /// Call the Anthropic messages API synchronously.
    /// Uses DispatchSemaphore + URLSession.shared (background delegate queue) to bridge async URLSession.
    private func callAnthropic(messages: [AnthropicToolRequest.Message], overrideMaxTokens: Int? = nil) throws -> AnthropicToolResponse {
        let requestBody = AnthropicToolRequest(
            model: model,
            maxTokens: overrideMaxTokens ?? self.maxTokens,
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
    case apiUnavailable

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, let body):
            return "HTTP \(statusCode): \(body.prefix(500))"
        case .decodingError(let detail):
            return "Failed to decode agent response: \(detail)"
        case .noResponse:
            return "No response from agent API"
        case .apiUnavailable:
            return "API unavailable after 3 attempts. Your game state is unchanged."
        }
    }
}
