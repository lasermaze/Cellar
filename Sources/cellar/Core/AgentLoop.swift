import Foundation

// MARK: - AgentLoopResult

/// Why the agent loop stopped.
enum AgentStopReason: Sendable {
    case completed          // Agent called end_turn naturally
    case userAborted        // User clicked stop
    case userConfirmed      // User clicked confirm — caller must save after loop
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

// MARK: - ToolResult

/// Typed result from tool execution. Eliminates string matching for control flow.
enum ToolResult: Sendable {
    /// Tool executed successfully. `content` is the JSON string for the LLM.
    case success(content: String)
    /// Tool executed but the agent should stop after this iteration.
    case stop(content: String, reason: StopReason)
    /// Tool execution failed (still sent to LLM as tool_result).
    case error(content: String)

    enum StopReason: Sendable {
        case userAborted
        case userConfirmedWorking
    }

    /// The JSON string to include in the tool_result message to the LLM.
    var content: String {
        switch self {
        case .success(let c), .stop(let c, _), .error(let c): return c
        }
    }

    var isStop: Bool {
        if case .stop = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - LoopState

/// All mutable state for one agent loop run.
struct LoopState {
    var iterationCount = 0
    var allText: [String] = []
    var currentMaxTokens: Int
    let maxTokensCeiling: Int
    var totalInputTokens = 0
    var totalOutputTokens = 0
    let pricing: (input: Double, output: Double)
    let budgetCeiling: Double

    init(maxTokens: Int, maxTokensCeiling: Int, pricing: (input: Double, output: Double), budgetCeiling: Double) {
        self.currentMaxTokens = maxTokens
        self.maxTokensCeiling = maxTokensCeiling
        self.pricing = pricing
        self.budgetCeiling = budgetCeiling
    }

    var estimatedCost: Double {
        Double(totalInputTokens) * pricing.input + Double(totalOutputTokens) * pricing.output
    }

    var budgetFraction: Double {
        budgetCeiling > 0 ? estimatedCost / budgetCeiling : 0
    }

    mutating func addTokens(input: Int, output: Int) {
        totalInputTokens += input
        totalOutputTokens += output
    }

    func makeResult(completed: Bool, stopReason: AgentStopReason) -> AgentLoopResult {
        AgentLoopResult(
            finalText: allText.joined(separator: "\n"),
            iterationsUsed: iterationCount,
            completed: completed,
            stopReason: stopReason,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            estimatedCostUSD: estimatedCost
        )
    }
}

// MARK: - StepModification + PrepareStepHook

/// Modifications returned by the prepareStep hook before each LLM API call.
struct StepModification {
    var trimMessages: Bool = false
    var injectMessage: String? = nil
    var maxTokensOverride: Int? = nil
}

/// Hook called before each LLM API call. Returns optional modifications for the step.
typealias PrepareStepHook = (Int, LoopState) -> StepModification?

// MARK: - AgentLoop

/// Drives the provider tool-use send-execute-return cycle.
struct AgentLoop {

    // MARK: Properties

    var provider: AgentLoopProvider  // var because protocol methods are mutating
    let maxIterations: Int
    let maxTokens: Int
    let budgetCeiling: Double
    let onOutput: (@Sendable (AgentEvent) -> Void)?
    let middleware: [AgentMiddleware]
    let prepareStep: PrepareStepHook?

    // MARK: Init

    init(
        provider: AgentLoopProvider,
        maxIterations: Int = 20,
        maxTokens: Int = 4096,
        budgetCeiling: Double = 5.00,
        middleware: [AgentMiddleware] = [],
        prepareStep: PrepareStepHook? = nil,
        onOutput: (@Sendable (AgentEvent) -> Void)? = nil
    ) {
        self.provider = provider
        self.maxIterations = maxIterations
        self.maxTokens = maxTokens
        self.budgetCeiling = budgetCeiling
        self.middleware = middleware
        self.prepareStep = prepareStep
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

    mutating func run(
        initialMessage: String,
        toolExecutor: (String, JSONValue) async -> ToolResult,
        control: AgentControl,
        middlewareContext: MiddlewareContext
    ) async -> AgentLoopResult {
        var state = LoopState(
            maxTokens: min(maxTokens, provider.maxOutputTokensLimit),
            maxTokensCeiling: provider.maxOutputTokensLimit,
            pricing: provider.pricingPerToken(),
            budgetCeiling: budgetCeiling
        )

        provider.appendUserMessage(initialMessage)

        while state.iterationCount < maxIterations {
            // ── Check control flags ──
            if control.shouldAbort {
                emit(.status("[Agent aborted by user]"))
                return state.makeResult(completed: false, stopReason: .userAborted)
            }
            if control.userForceConfirmed {
                emit(.status("[User confirmed — stopping agent]"))
                return state.makeResult(completed: true, stopReason: .userConfirmed)
            }

            state.iterationCount += 1
            middlewareContext.iterationCount = state.iterationCount

            // ── prepareStep hook ──
            if let modification = prepareStep?(state.iterationCount, state) {
                if let msg = modification.injectMessage {
                    provider.appendUserMessage(msg)
                }
                if let override = modification.maxTokensOverride {
                    state.currentMaxTokens = override
                }
            }

            // ── Call LLM provider ──
            emit(.iteration(number: state.iterationCount, total: maxIterations))
            let response: AgentLoopProviderResponse
            do {
                response = try await provider.callWithRetry(maxTokens: state.currentMaxTokens, emit: emit)
            } catch {
                return handleAPIError(error, state: &state)
            }

            // ── Track tokens + cost ──
            state.addTokens(input: response.inputTokens, output: response.outputTokens)
            middlewareContext.estimatedCost = state.estimatedCost
            emit(.cost(inputTokens: state.totalInputTokens, outputTokens: state.totalOutputTokens, usd: state.estimatedCost))

            // ── Budget halt check (100%) ──
            if let haltResult = await checkBudgetHalt(state: &state, response: response) {
                return haltResult
            }

            // ── Emit text blocks ──
            for text in response.textBlocks where !text.isEmpty {
                emit(.text(text))
                state.allText.append(text)
            }

            // ── Dispatch on stop reason ──
            switch response.stopReason {
            case .endTurn:
                // Agent chose to stop. Trust it. No tug-of-war.
                return state.makeResult(completed: true, stopReason: .completed)

            case .toolUse:
                let outcome = await executeTools(
                    response: response,
                    toolExecutor: toolExecutor,
                    state: &state,
                    control: control,
                    middlewareContext: middlewareContext
                )
                switch outcome {
                case .continue:
                    break
                case .stopRequested:
                    if control.userForceConfirmed {
                        return state.makeResult(completed: true, stopReason: .userConfirmed)
                    }
                    return state.makeResult(completed: false, stopReason: .userAborted)
                }

            case .maxTokens:
                handleTruncation(response: response, state: &state)

            case .other(let reason):
                emit(.error("[Agent: unexpected stop_reason '\(reason)']"))
                return state.makeResult(completed: false, stopReason: .apiError("unexpected: \(reason)"))
            }
        }

        return state.makeResult(completed: false, stopReason: .maxIterations)
    }

    // MARK: - Helpers

    private enum ToolOutcome { case `continue`, stopRequested }

    private mutating func executeTools(
        response: AgentLoopProviderResponse,
        toolExecutor: (String, JSONValue) async -> ToolResult,
        state: inout LoopState,
        control: AgentControl,
        middlewareContext: MiddlewareContext
    ) async -> ToolOutcome {
        provider.appendAssistantResponse(response)

        // Reset max_tokens after successful non-truncated response
        if state.currentMaxTokens > maxTokens {
            state.currentMaxTokens = min(maxTokens, provider.maxOutputTokensLimit)
        }

        var results: [(id: String, content: String, isError: Bool)] = []
        var stopped = false

        for call in response.toolCalls {
            emit(.toolCall(name: call.name))

            // Middleware: beforeTool (can short-circuit)
            var toolResult: ToolResult? = nil
            for mw in middleware {
                if let override = mw.beforeTool(name: call.name, input: call.input, context: middlewareContext) {
                    toolResult = override
                    break
                }
            }

            // Execute tool if middleware didn't short-circuit
            let result: ToolResult
            if let override = toolResult {
                result = override
            } else {
                result = await toolExecutor(call.name, call.input)
            }
            emit(.toolResult(name: call.name, truncated: String(result.content.prefix(200))))
            results.append((id: call.id, content: result.content, isError: result.isError))

            // Middleware: afterTool
            for mw in middleware {
                mw.afterTool(name: call.name, input: call.input, result: result, context: middlewareContext)
            }

            if result.isStop {
                stopped = true
                break
            }
        }

        provider.appendToolResults(results)

        if stopped { return .stopRequested }

        // Middleware: afterStep — collect injected messages
        for mw in middleware {
            if let message = mw.afterStep(context: middlewareContext) {
                provider.appendUserMessage(message)
            }
        }

        return .continue
    }

    /// Budget halt at 100%: inject halt message, give agent one final call to save, then stop.
    private mutating func checkBudgetHalt(state: inout LoopState, response: AgentLoopProviderResponse) async -> AgentLoopResult? {
        guard state.budgetFraction >= 1.0 else { return nil }

        let ceiling = String(format: "%.2f", budgetCeiling)
        let stopMsg = "[BUDGET LIMIT REACHED: $\(ceiling) session budget exhausted. You must stop now. Call save_success or save_recipe if you have a working configuration, then stop.]"
        provider.appendAssistantResponse(response)
        provider.appendUserMessage(stopMsg)

        // One final API call for agent to save
        if let finalResponse = try? await provider.callWithRetry(maxTokens: state.currentMaxTokens, emit: emit) {
            state.addTokens(input: finalResponse.inputTokens, output: finalResponse.outputTokens)
            for text in finalResponse.textBlocks where !text.isEmpty {
                state.allText.append(text)
            }
        }

        return state.makeResult(completed: false, stopReason: .budgetExhausted)
    }

    private func handleAPIError(_ error: Error, state: inout LoopState) -> AgentLoopResult {
        let description = error.localizedDescription
        if error is AgentLoopError {
            if case .apiUnavailable = error as! AgentLoopError {
                emit(.error("API unavailable after 3 attempts. Your game state is unchanged."))
            } else {
                emit(.error("Agent API error (iteration \(state.iterationCount)): \(description)"))
            }
        } else {
            emit(.error("Agent API error (iteration \(state.iterationCount)): \(description)"))
        }
        state.allText.append(description)
        return state.makeResult(completed: false, stopReason: .apiError(description))
    }

    private mutating func handleTruncation(response: AgentLoopProviderResponse, state: inout LoopState) {
        let hasIncompleteToolUse = !response.toolCalls.isEmpty

        if hasIncompleteToolUse && state.currentMaxTokens < state.maxTokensCeiling {
            // Check if escalation would blow budget
            let projectedOutputTokens = state.totalOutputTokens + (state.currentMaxTokens * 2)
            let projectedCost = Double(state.totalInputTokens) * state.pricing.input + Double(projectedOutputTokens) * state.pricing.output
            if budgetCeiling > 0 && projectedCost / budgetCeiling >= 0.8 {
                emit(.status("[Agent: max_tokens hit, but escalation would exceed budget. Using continuation...]"))
                provider.appendAssistantResponse(response)
                provider.appendUserMessage("Your response was truncated. Continue.")
            } else {
                let newMax = min(state.currentMaxTokens * 2, state.maxTokensCeiling)
                emit(.status("[Agent: max_tokens hit with incomplete tool_use, retrying with \(newMax)...]"))
                state.currentMaxTokens = newMax
                state.iterationCount -= 1  // Retry, don't count as iteration
            }
        } else if hasIncompleteToolUse {
            emit(.status("[Agent: max_tokens hit at ceiling (\(state.maxTokensCeiling)), using continuation...]"))
            provider.appendAssistantResponse(response)
            provider.appendUserMessage("Your response was truncated. Continue.")
        } else {
            emit(.status("[Agent: response truncated, continuing...]"))
            provider.appendAssistantResponse(response)
            provider.appendUserMessage("Your response was truncated. Continue.")
            if state.currentMaxTokens > maxTokens { state.currentMaxTokens = min(maxTokens, provider.maxOutputTokensLimit) }
        }
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
