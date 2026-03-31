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

/// Drives the provider tool-use send-execute-return cycle.
///
/// Usage:
/// ```swift
/// let provider = AnthropicAgentProvider(apiKey: key, model: "...", tools: [myTool], systemPrompt: "...")
/// var loop = AgentLoop(provider: provider)
/// let result = loop.run(initialMessage: "...", toolExecutor: { name, input in
///     // execute tool, return result string
///     return "tool output"
/// })
/// ```
struct AgentLoop {

    // MARK: Properties

    var provider: AgentLoopProvider  // var because protocol methods are mutating
    let maxIterations: Int
    let maxTokens: Int
    let budgetCeiling: Double
    let onOutput: (@Sendable (AgentEvent) -> Void)?

    // MARK: Init

    init(
        provider: AgentLoopProvider,
        maxIterations: Int = 20,
        maxTokens: Int = 4096,
        budgetCeiling: Double = 5.00,
        onOutput: (@Sendable (AgentEvent) -> Void)? = nil
    ) {
        self.provider = provider
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
    mutating func run(
        initialMessage: String,
        toolExecutor: (String, JSONValue) -> String,
        canStop: (() -> Bool)? = nil
    ) -> AgentLoopResult {
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

        // Pricing from provider
        let pricing = provider.pricingPerToken()
        let inputPricePerToken = pricing.input
        let outputPricePerToken = pricing.output

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
        provider.appendUserMessage(initialMessage)

        // Step 2: Main loop
        while iterationCount < maxIterations {
            iterationCount += 1

            // Step 2a: Call provider API with retry
            emit(.iteration(number: iterationCount, total: maxIterations))
            let response: AgentLoopProviderResponse
            do {
                response = try provider.callWithRetry(maxTokens: currentMaxTokens, emit: emit)
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
            totalInputTokens += response.inputTokens
            totalOutputTokens += response.outputTokens

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
                provider.appendAssistantResponse(response)
                provider.appendUserMessage(stopMsg)
                hasSentBudgetHalt = true
                // Make one final API call for the agent to save
                if let finalResponse = try? provider.callWithRetry(maxTokens: currentMaxTokens, emit: emit) {
                    totalInputTokens += finalResponse.inputTokens
                    totalOutputTokens += finalResponse.outputTokens
                    for text in finalResponse.textBlocks {
                        if !text.isEmpty { allText.append(text) }
                    }
                }
                return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: false, stopReason: .budgetExhausted)
            }

            if budgetFraction >= 0.8 && !hasWarnedAt80 {
                hasWarnedAt80 = true
            }

            // Step 2d: Print and collect text blocks
            for text in response.textBlocks {
                if !text.isEmpty {
                    emit(.text(text))
                    allText.append(text)
                }
            }

            // Step 2e: Handle stop reason
            switch response.stopReason {
            case .endTurn:
                let hasContent = !response.textBlocks.isEmpty || !response.toolCalls.isEmpty

                let agentCanStop = canStop?() ?? true  // nil callback = always allow (backward compat)

                if hasContent && !agentCanStop && consecutiveContinuations < 3 {
                    // Agent tried to stop but task isn't done yet
                    consecutiveContinuations += 1
                    emit(.status("[Agent tried to stop, but task is not complete (\(consecutiveContinuations)/3). Continuing...]"))
                    provider.appendAssistantResponse(response)
                    provider.appendUserMessage("You cannot stop yet — the game has not been confirmed working by the user, or you haven't saved a success record after confirmation. Continue diagnosing and fixing. Use your tools to investigate and apply a fix, then launch_game again.")
                } else if hasContent {
                    return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: true, stopReason: .completed)
                } else {
                    // Empty end_turn — send continuation prompt
                    emit(.status("[Agent: empty response, sending continuation...]"))
                    provider.appendAssistantResponse(response)
                    provider.appendUserMessage("Please continue. What would you like to do next?")
                }

            case .toolUse:
                // Agent is doing work — reset stuck-loop counter
                consecutiveContinuations = 0

                // Reset max_tokens after successful non-truncated response
                if currentMaxTokens > maxTokens {
                    currentMaxTokens = maxTokens
                }

                // Append assistant turn with full content (text + tool_use blocks)
                provider.appendAssistantResponse(response)

                // Execute each tool call and collect results
                var results: [(id: String, content: String, isError: Bool)] = []
                for call in response.toolCalls {
                    emit(.toolCall(name: call.name))
                    let result = toolExecutor(call.name, call.input)
                    emit(.toolResult(name: call.name, truncated: String(result.prefix(200))))
                    results.append((id: call.id, content: result, isError: false))
                }

                // Inject budget warning as a user message alongside tool results if threshold crossed
                if hasWarnedAt80 && !hasSentBudgetWarningMessage {
                    let cost = estimatedCost()
                    let pct = budgetCeiling > 0 ? Int(cost / budgetCeiling * 100) : 0
                    let warnMsg = "[BUDGET WARNING: \(pct)% of session budget used ($\(String(format: "%.2f", cost)) / $\(String(format: "%.2f", budgetCeiling))). Begin wrapping up - save progress and finalize results soon.]"
                    provider.appendToolResults(results)
                    provider.appendUserMessage(warnMsg)
                    hasSentBudgetWarningMessage = true
                } else {
                    provider.appendToolResults(results)
                }

            case .maxTokens:
                let hasIncompleteToolUse = !response.toolCalls.isEmpty
                if hasIncompleteToolUse && currentMaxTokens < maxTokensCeiling {
                    // Check if doubling would push past 80% budget — if so, use continuation instead
                    let projectedOutputTokens = totalOutputTokens + (currentMaxTokens * 2)
                    let projectedCost = Double(totalInputTokens) * inputPricePerToken + Double(projectedOutputTokens) * outputPricePerToken
                    if budgetCeiling > 0 && projectedCost / budgetCeiling >= 0.8 {
                        // Budget override: use continuation prompt instead of escalating
                        emit(.status("[Agent: max_tokens hit, but escalation would exceed budget. Using continuation...]"))
                        provider.appendAssistantResponse(response)
                        provider.appendUserMessage("Your response was truncated. Continue.")
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
                    provider.appendAssistantResponse(response)
                    provider.appendUserMessage("Your response was truncated. Continue.")
                } else {
                    // Text-only truncation — safe to append and continue
                    emit(.status("[Agent: response truncated, continuing...]"))
                    provider.appendAssistantResponse(response)
                    provider.appendUserMessage("Your response was truncated. Continue.")
                    // Reset max_tokens after text-only truncation
                    if currentMaxTokens > maxTokens {
                        currentMaxTokens = maxTokens
                    }
                }

            case .other(let reason):
                // Truly unexpected stop reason — return what we have
                emit(.error("[Agent: unexpected stop_reason '\(reason)']"))
                return makeResult(
                    text: allText.joined(separator: "\n"),
                    iterations: iterationCount,
                    completed: false,
                    stopReason: .apiError("unexpected stop_reason '\(reason)'")
                )
            }
        }

        // Max iterations reached
        return makeResult(text: allText.joined(separator: "\n"), iterations: iterationCount, completed: false, stopReason: .maxIterations)
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
