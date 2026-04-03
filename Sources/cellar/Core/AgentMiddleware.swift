import Foundation

// MARK: - AgentMiddleware

/// A composable hook that can observe and intercept agent loop execution.
///
/// Middleware implementations are called at three points in each iteration:
/// - `beforeTool`: before each tool is executed (can short-circuit)
/// - `afterTool`: after each tool completes (observe only)
/// - `afterStep`: after all tools in one iteration complete (can inject user message)
protocol AgentMiddleware {
    /// Called before each tool execution. Return nil to allow the tool to run,
    /// or return a ToolResult to short-circuit and use that result instead.
    func beforeTool(name: String, input: JSONValue, context: MiddlewareContext) -> ToolResult?

    /// Called after each tool execution. Observe results and update context state.
    func afterTool(name: String, input: JSONValue, result: ToolResult, context: MiddlewareContext)

    /// Called after all tools in one iteration complete.
    /// Return a String to inject as a user message, or nil to inject nothing.
    func afterStep(context: MiddlewareContext) -> String?
}

// MARK: - MiddlewareContext

/// Shared mutable state passed by reference to all middleware on every hook call.
///
/// The agent loop owns this object and reads the injection flags after each step.
final class MiddlewareContext {
    // MARK: Loop-provided state

    /// Thread-safe control channel (abort / confirm signals from the web UI).
    let control: AgentControl

    /// Number of iterations completed so far in this run.
    var iterationCount: Int = 0

    /// Estimated cost in USD accumulated so far in this run.
    var estimatedCost: Double = 0

    /// Maximum allowed spend for this session in USD.
    var budgetCeiling: Double = 5.0

    /// Rolling window of the last 8 action-tool names, updated by SpinDetector.
    var recentActionTools: [String] = []

    // MARK: Middleware-set injection flags (read by the agent loop after afterStep)

    /// Set by BudgetTracker when a budget warning message should be injected.
    var shouldInjectBudgetWarning = false

    /// The budget warning message to inject, set by BudgetTracker.
    var budgetWarningMessage: String? = nil

    /// Set by SpinDetector when a pivot nudge message should be injected.
    var shouldInjectPivotNudge = false

    /// The pivot nudge message to inject, set by SpinDetector.
    var pivotNudgeMessage: String? = nil

    // MARK: Init

    init(control: AgentControl, budgetCeiling: Double) {
        self.control = control
        self.budgetCeiling = budgetCeiling
    }
}

// MARK: - BudgetTracker

/// Middleware that monitors token spend and injects budget warnings at 50% and 80% thresholds.
///
/// - At 50%: emits a `.budgetWarning(percentage: 50)` event (no user-message injection).
/// - At 80%: sets `context.shouldInjectBudgetWarning = true` so the loop injects a warning message.
final class BudgetTracker: AgentMiddleware {
    private var hasAlertedAt50 = false
    private var hasWarnedAt80 = false
    private var hasSentWarningMessage = false

    let emit: (AgentEvent) -> Void

    init(emit: @escaping (AgentEvent) -> Void) {
        self.emit = emit
    }

    func beforeTool(name: String, input: JSONValue, context: MiddlewareContext) -> ToolResult? {
        return nil  // Budget does not block individual tools
    }

    func afterTool(name: String, input: JSONValue, result: ToolResult, context: MiddlewareContext) {
        // No per-tool action needed
    }

    func afterStep(context: MiddlewareContext) -> String? {
        guard context.budgetCeiling > 0 else { return nil }
        let fraction = context.estimatedCost / context.budgetCeiling

        if fraction >= 0.5 && !hasAlertedAt50 {
            hasAlertedAt50 = true
            emit(.budgetWarning(percentage: 50))
        }

        if fraction >= 0.8 && !hasSentWarningMessage {
            hasWarnedAt80 = true
            hasSentWarningMessage = true
            let cost = context.estimatedCost
            let ceiling = context.budgetCeiling
            let pct = Int(fraction * 100)
            let message = "[BUDGET WARNING: \(pct)% of session budget used ($\(String(format: "%.2f", cost)) / $\(String(format: "%.2f", ceiling))). Begin wrapping up - save progress and finalize results soon.]"
            context.shouldInjectBudgetWarning = true
            context.budgetWarningMessage = message
            return message
        }

        return nil
    }
}

// MARK: - SpinDetector

/// Middleware that detects repetitive action-tool patterns and injects a pivot nudge.
///
/// Tracks which action tools have been called recently (via `context.recentActionTools`).
/// Detects two patterns in the last 6 action-tool calls:
/// - A→B→A→B→A→B (2-tool repeating cycle)
/// - Same tool called 4 or more times
///
/// One-shot: once a nudge is sent, no further nudges are injected this session.
final class SpinDetector: AgentMiddleware {
    private var hasSentNudge = false

    let actionTools: Set<String> = [
        "set_environment",
        "set_registry",
        "install_winetricks",
        "place_dll",
        "write_game_file",
        "launch_game"
    ]

    let emit: (AgentEvent) -> Void

    init(emit: @escaping (AgentEvent) -> Void) {
        self.emit = emit
    }

    func beforeTool(name: String, input: JSONValue, context: MiddlewareContext) -> ToolResult? {
        return nil  // Spin detector does not block tools
    }

    func afterTool(name: String, input: JSONValue, result: ToolResult, context: MiddlewareContext) {
        guard actionTools.contains(name) else { return }
        context.recentActionTools.append(name)
        if context.recentActionTools.count > 8 {
            context.recentActionTools.removeFirst()
        }
    }

    func afterStep(context: MiddlewareContext) -> String? {
        guard !hasSentNudge, context.recentActionTools.count >= 6 else { return nil }

        let last6 = Array(context.recentActionTools.suffix(6))
        var spinDetected = false

        // Check for 2-tool repeating cycle: A→B→A→B→A→B
        let pair = [last6[0], last6[1]]
        if last6[2] == pair[0] && last6[3] == pair[1] && last6[4] == pair[0] && last6[5] == pair[1] {
            spinDetected = true
        }

        // Check for same tool called 4+ times in the last 6
        if !spinDetected {
            let counts = Dictionary(grouping: last6, by: { $0 }).mapValues { $0.count }
            if let maxCount = counts.values.max(), maxCount >= 4 {
                spinDetected = true
            }
        }

        guard spinDetected else { return nil }

        hasSentNudge = true
        emit(.status("[Spin detected — pivot nudge injected]"))

        let nudgeMsg = "[PIVOT CHECK: You've been repeating similar configuration+launch cycles. Step back: what NEW evidence do you have that this approach will work? If the last 2+ launches had the same symptom, return to research — call search_web with a different query angle and fetch_page on at least 2 new results before launching again.]"
        context.shouldInjectPivotNudge = true
        context.pivotNudgeMessage = nudgeMsg
        return nudgeMsg
    }
}
