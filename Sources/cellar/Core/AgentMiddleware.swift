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
