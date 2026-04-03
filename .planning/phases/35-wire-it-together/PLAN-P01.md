---
phase: 35-wire-it-together
plan: P01
type: execute
wave: 1
depends_on: []
files_modified:
  - Sources/cellar/Web/Controllers/LaunchController.swift
  - Sources/cellar/Core/AIService.swift
  - Sources/cellar/Core/Tools/LaunchTools.swift
  - Sources/cellar/Core/Tools/SaveTools.swift
autonomous: true
requirements: [INT-01, INT-02, INT-03, INT-04, BUG-02]

must_haves:
  truths:
    - "`swift build` compiles without errors"
    - "Stop route calls AgentControl.abort() — not `tools.shouldAbort = true`"
    - "Confirm route calls AgentControl.confirm() — not `tools.userForceConfirmed = true`"
    - "Post-loop save uses `await` — no fire-and-forget Task.detached"
    - "AIService creates AgentControl, MiddlewareContext, middleware chain, and AgentEventLog"
    - "AgentLoop.run() called with toolExecutor returning ToolResult, control, and middlewareContext"
    - "No remaining references to `tools.shouldAbort`, `tools.userForceConfirmed`, or `tools.taskState` in AIService"
    - "No remaining references to `taskState` in LaunchTools or SaveTools"
  artifacts:
    - Sources/cellar/Web/Controllers/LaunchController.swift
    - Sources/cellar/Core/AIService.swift
  key_links:
    - "ActiveAgents.register(gameId:tools:control:) ← called from LaunchController.runAgentLaunch via onToolsCreated callback"
    - "ActiveAgents.getControl(gameId:) ← called from stop and confirm routes"
    - "AIService.runAgentLoop() → AgentLoop.run(initialMessage:toolExecutor:control:middlewareContext:)"
---

<objective>
Wire all Phase 31-34 pieces together so `swift build` passes and the agent loop works end-to-end.

Purpose: Phases 33-34 broke callers by changing AgentLoop.run() signature and removing TaskState/bare vars from AgentTools. This plan updates all callers: AIService.runAgentLoop(), ActiveAgents, LaunchController stop/confirm routes, and removes stale taskState references from tool files.

Output: Compilable codebase with new agent loop architecture fully connected.
</objective>

<execution_context>
@/Users/peter/.claude/get-shit-done/workflows/execute-plan.md
@/Users/peter/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/ROADMAP.md
@.planning/phases/35-wire-it-together/35-CONTEXT.md
@.planning/agent-loop-rewrite-brief.md

@Sources/cellar/Web/Controllers/LaunchController.swift
@Sources/cellar/Core/AIService.swift
@Sources/cellar/Core/AgentLoop.swift
@Sources/cellar/Core/AgentControl.swift
@Sources/cellar/Core/AgentMiddleware.swift
@Sources/cellar/Core/AgentEventLog.swift
@Sources/cellar/Core/Tools/LaunchTools.swift
@Sources/cellar/Core/Tools/SaveTools.swift

<interfaces>
<!-- Key types and contracts from Phase 31-34 that the executor needs. -->

From AgentLoop.swift — new run() signature:
```swift
mutating func run(
    initialMessage: String,
    toolExecutor: (String, JSONValue) async -> ToolResult,
    control: AgentControl,
    middlewareContext: MiddlewareContext
) async -> AgentLoopResult
```

From AgentLoop.swift — AgentLoop init (now takes middleware + prepareStep):
```swift
init(
    provider: AgentLoopProvider,
    maxIterations: Int = 20,
    maxTokens: Int = 4096,
    budgetCeiling: Double = 5.00,
    middleware: [AgentMiddleware] = [],
    prepareStep: PrepareStepHook? = nil,
    onOutput: (@Sendable (AgentEvent) -> Void)? = nil
)
```

From AgentLoop.swift — AgentStopReason:
```swift
enum AgentStopReason: Sendable {
    case completed
    case userAborted
    case userConfirmed
    case budgetExhausted
    case maxIterations
    case apiError(String)
}
```

From AgentControl.swift:
```swift
final class AgentControl: Sendable {
    var shouldAbort: Bool { ... }
    var userForceConfirmed: Bool { ... }
    func abort() { ... }
    func confirm() { ... }
}
```

From AgentMiddleware.swift:
```swift
protocol AgentMiddleware { ... }
final class MiddlewareContext { init(control: AgentControl, budgetCeiling: Double) }
final class BudgetTracker: AgentMiddleware { init(emit: @escaping (AgentEvent) -> Void) }
final class SpinDetector: AgentMiddleware { init(emit: @escaping (AgentEvent) -> Void) }
final class EventLogger: AgentMiddleware { init(eventLog: AgentEventLog) }
```

From AgentEventLog.swift:
```swift
final class AgentEventLog {
    init(gameId: String)
    func append(_ entry: AgentLogEntry)
}
enum AgentLogEntry: Codable {
    case sessionStarted(gameId: String, timestamp: String)
    case sessionEnded(reason: String, iterations: Int, cost: Double)
    // ... other cases
}
```

From AgentTools.swift — current state:
```swift
var control: AgentControl!  // Set by AIService before loop starts
func execute(toolName: String, input: JSONValue) async -> ToolResult  // Returns ToolResult, not String
```
Note: `taskState`, `shouldAbort`, `userForceConfirmed`, `isTaskComplete` properties NO LONGER EXIST on AgentTools.
The `TaskState` enum no longer exists anywhere.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update LaunchController and fix stale tool file references</name>
  <files>Sources/cellar/Web/Controllers/LaunchController.swift, Sources/cellar/Core/Tools/LaunchTools.swift, Sources/cellar/Core/Tools/SaveTools.swift</files>
  <action>
**LaunchController.swift — ActiveAgents class (lines 66-88):**

Replace the entire `ActiveAgents` class with a version that stores `AgentControl` alongside `AgentTools`:

```swift
private final class ActiveAgents: @unchecked Sendable {
    static let shared = ActiveAgents()
    private let lock = NSLock()
    private var agents: [String: AgentTools] = [:]
    private var controls: [String: AgentControl] = [:]

    func register(gameId: String, tools: AgentTools, control: AgentControl) {
        lock.lock()
        agents[gameId] = tools
        controls[gameId] = control
        lock.unlock()
    }

    func getTools(gameId: String) -> AgentTools? {
        lock.lock()
        defer { lock.unlock() }
        return agents[gameId]
    }

    func getControl(gameId: String) -> AgentControl? {
        lock.lock()
        defer { lock.unlock() }
        return controls[gameId]
    }

    func remove(gameId: String) {
        lock.lock()
        agents.removeValue(forKey: gameId)
        controls.removeValue(forKey: gameId)
        lock.unlock()
    }
}
```

Key changes: `get` renamed to `getTools`, new `getControl` method, `register` takes `control` parameter, `remove` cleans both dicts.

**LaunchController.swift — Stop route (around line 169-181):**

Replace `tools.shouldAbort = true` with `AgentControl.abort()`:
```swift
app.post("games", ":gameId", "launch", "stop") { req async throws -> Response in
    guard let gameId = req.parameters.get("gameId") else { throw Abort(.badRequest) }
    ActiveAgents.shared.getControl(gameId: gameId)?.abort()
    await LaunchGuard.shared.release()
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "text/html")
    return Response(status: .ok, headers: headers,
                    body: .init(string: "<span style='color: var(--error);'>Agent stopped</span>"))
}
```

**LaunchController.swift — Confirm route (around line 183-194):**

Replace `tools.userForceConfirmed = true` with `AgentControl.confirm()`:
```swift
app.post("games", ":gameId", "launch", "confirm") { req async throws -> Response in
    guard let gameId = req.parameters.get("gameId") else { throw Abort(.badRequest) }
    ActiveAgents.shared.getControl(gameId: gameId)?.confirm()
    var headers = HTTPHeaders()
    headers.add(name: .contentType, value: "text/html")
    return Response(status: .ok, headers: headers,
                    body: .init(string: "<span style='color: var(--success);'>Confirmed! Saving config...</span>"))
}
```

**LaunchController.swift — runAgentLaunch `onToolsCreated` callback (around line 434-436):**

The `onToolsCreated` callback currently calls `ActiveAgents.shared.register(gameId: gameId, tools: tools)`. But `control` isn't available here since it's created inside AIService. Two options:
1. Change AIService's `onToolsCreated` signature to also pass control — complex
2. Have AIService accept a register callback that receives both

The simplest approach: keep `onToolsCreated` as-is for now. Add a separate `onControlCreated` callback or have AIService call a registration function.

**SIMPLEST CORRECT APPROACH**: Since AIService creates `control` and also has `tools`, change `onToolsCreated` to accept both:
- In AIService's function signature: `onToolsCreated: ((AgentTools, AgentControl) -> Void)? = nil`
- In AIService: call `onToolsCreated?(tools, control)` after creating both
- In LaunchController: `onToolsCreated: { tools, control in ActiveAgents.shared.register(gameId: gameId, tools: tools, control: control) }`

Update the `onToolsCreated` usage in runAgentLaunch (around line 434):
```swift
onToolsCreated: { tools, control in
    ActiveAgents.shared.register(gameId: gameId, tools: tools, control: control)
}
```

**LaunchTools.swift — Remove all `taskState` references (lines 28, 182, 184, 189-190):**

Line 28: Remove `taskState = .exhausted` — max launch enforcement now returns an error string; the loop handles stop semantics via ToolResult. Simply delete this line.

Lines 182-190: In the `launch_game` ask-user feedback section, remove all taskState assignments. The user confirmation flow is now handled by AgentControl.confirm() from the web UI, not by tracking state in the tool. Delete these lines:
- `taskState = .userConfirmedOk` (line 182)
- `taskState = .working` (line 184)
- `if taskState == .userConfirmedOk {` and `taskState = .working` (lines 189-190)

**SaveTools.swift — Remove `taskState` references (lines 197-198):**

Remove the block:
```swift
if taskState == .userConfirmedOk {
    taskState = .savedAfterConfirm
}
```
Post-loop save now handles this in AIService. The save_success tool just saves and returns success/failure — no state tracking.
  </action>
  <verify>
    <automated>cd /Users/peter/Documents/Cellar && grep -rn "taskState\|tools\.shouldAbort\|tools\.userForceConfirmed" Sources/cellar/Web/Controllers/LaunchController.swift Sources/cellar/Core/Tools/LaunchTools.swift Sources/cellar/Core/Tools/SaveTools.swift | grep -v "^Binary" && echo "FAIL: stale references found" || echo "PASS: no stale references"</automated>
  </verify>
  <done>ActiveAgents stores and exposes AgentControl. Stop route calls abort(), confirm route calls confirm(). No taskState references remain in LaunchTools or SaveTools. onToolsCreated callback passes both tools and control.</done>
</task>

<task type="auto">
  <name>Task 2: Rewrite AIService.runAgentLoop() to use new architecture</name>
  <files>Sources/cellar/Core/AIService.swift</files>
  <action>
**Replace lines ~928-1092 in AIService.runAgentLoop()** (everything from after the `onToolsCreated` callback definition through the function's return statements).

The current code creates an AgentLoop without middleware, calls run() with `canStop`/`shouldAbort` closures (old signature), has fire-and-forget save in shouldAbort closure, and checks `tools.taskState`.

**Step 1: Change the `onToolsCreated` parameter signature** (around line 652):

From:
```swift
onToolsCreated: ((AgentTools) -> Void)? = nil
```
To:
```swift
onToolsCreated: ((AgentTools, AgentControl) -> Void)? = nil
```

**Step 2: Replace the section from after tools creation through end of function.** After `if let handler = askUserHandler { tools.askUserHandler = handler }` (line 938), replace EVERYTHING through the function's closing brace with:

```swift
// Create thread-safe control channel
let control = AgentControl()
tools.control = control

// Notify caller (LaunchController uses this to register with ActiveAgents)
onToolsCreated?(tools, control)

let config = CellarConfig.load()

// Create provider (keep existing provider creation switch — unchanged)
let agentProvider: AgentLoopProvider
switch provider {
case .anthropic(let apiKey):
    agentProvider = AnthropicAgentProvider(
        apiKey: apiKey,
        model: resolveModel(for: "claude"),
        tools: AgentTools.toolDefinitions,
        systemPrompt: systemPrompt
    )
case .deepseek(let apiKey):
    agentProvider = DeepseekAgentProvider(
        apiKey: apiKey,
        model: resolveModel(for: "deepseek"),
        tools: AgentTools.toolDefinitions,
        systemPrompt: systemPrompt
    )
case .kimi(let apiKey):
    agentProvider = KimiAgentProvider(
        apiKey: apiKey,
        model: resolveModel(for: "kimi"),
        tools: AgentTools.toolDefinitions,
        systemPrompt: systemPrompt
    )
default:
    return .unavailable
}

// Create event log
let eventLog = AgentEventLog(gameId: gameId)
eventLog.append(.sessionStarted(gameId: gameId, timestamp: ISO8601DateFormatter().string(from: Date())))

// Create middleware context
let mwContext = MiddlewareContext(control: control, budgetCeiling: config.budgetCeiling)

// Create middleware chain
let middlewareChain: [AgentMiddleware] = [
    BudgetTracker(emit: { onOutput?($0) }),
    SpinDetector(emit: { onOutput?($0) }),
    EventLogger(eventLog: eventLog),
]

// Create loop with middleware + prepareStep hook
var agentLoop = AgentLoop(
    provider: agentProvider,
    maxIterations: 50,
    maxTokens: 16384,
    budgetCeiling: config.budgetCeiling,
    middleware: middlewareChain,
    prepareStep: nil,
    onOutput: onOutput
)

// Fetch collective memory context (silent skip on any failure)
let memoryContext = await CollectiveMemoryService.fetchBestEntry(
    for: entry.name,
    wineURL: wineURL
)

// Fetch community compatibility data from Lutris + ProtonDB (silent skip on any failure)
let compatContext = await CompatibilityService.fetchReport(for: entry.name)

// Check for handoff from a previous incomplete session
let previousSession = SessionHandoff.read(gameId: gameId)
if previousSession != nil {
    SessionHandoff.delete(gameId: gameId)
}

let launchInstruction = "Launch the game '\(entry.name)' (ID: \(gameId)). The executable is at: \(executablePath). Follow the Research-Diagnose-Adapt workflow: start by querying the success database, then inspect the game. Move quickly to a real launch_game call — research and at most one trace_launch before your first real launch."

var contextParts: [String] = []
if let memoryContext = memoryContext {
    contextParts.append(memoryContext)
}
if let compatReport = compatContext {
    contextParts.append(compatReport.formatForAgent())
}
if let previousSession = previousSession {
    contextParts.append(previousSession.formatForAgent())
}
if previousSession == nil,
   let diagRecord = DiagnosticRecord.readLatest(gameId: gameId) {
    contextParts.append(diagRecord.formatForAgent())
}
contextParts.append(launchInstruction)
let initialMessage = contextParts.joined(separator: "\n\n")

let result = await agentLoop.run(
    initialMessage: initialMessage,
    toolExecutor: { name, input in await tools.execute(toolName: name, input: input) },
    control: control,
    middlewareContext: mwContext
)

// ── POST-LOOP SAVE (the critical fix — BUG-01) ──
// Runs with await. No fire-and-forget. No race condition.
var didSave = false
if result.stopReason == .userConfirmed {
    let saveInput: JSONValue = .object([
        "game_name": .string(entry.name),
        "resolution_narrative": .string("User confirmed game is working from web UI.")
    ])
    _ = await tools.execute(toolName: "save_success", input: saveInput)
    didSave = true
}

// Log session end
eventLog.append(.sessionEnded(
    reason: "\(result.stopReason)",
    iterations: result.iterationsUsed,
    cost: result.estimatedCostUSD
))

// Cost summary
let costStr = String(format: "%.2f", result.estimatedCostUSD)
print("Session cost: $\(costStr) (\(result.totalInputTokens) input + \(result.totalOutputTokens) output tokens, \(result.iterationsUsed) iterations)")

// Post-loop outcomes
let isSuccess = result.stopReason == .completed || didSave
if isSuccess {
    if didSave {
        await handleContributionIfNeeded(
            tools: tools, gameName: entry.name,
            wineURL: wineURL, isWebContext: askUserHandler != nil
        )
    }
    SessionHandoff.delete(gameId: gameId)
    return .success(result.finalText)
} else if result.stopReason == .userAborted {
    return .failed("[STOP:user] Agent stopped by user.")
} else {
    let stopReasonStr: String
    let reason: String
    switch result.stopReason {
    case .budgetExhausted:
        stopReasonStr = "budget_exhausted"
        reason = "[STOP:budget] The AI agent ran out of its $\(costStr) spending budget before finishing."
    case .maxIterations:
        stopReasonStr = "max_iterations"
        reason = "[STOP:iterations] The AI agent used all \(result.iterationsUsed) iterations without finishing."
    case .apiError(let detail):
        stopReasonStr = "api_error"
        reason = "[STOP:api_error] The AI agent couldn't reach the API: \(detail)"
    default:
        stopReasonStr = "unknown"
        reason = "[STOP:unknown]"
    }

    let handoff = tools.captureHandoff(
        stopReason: stopReasonStr,
        lastText: result.finalText,
        iterationsUsed: result.iterationsUsed,
        costUSD: result.estimatedCostUSD
    )
    SessionHandoff.write(handoff)
    print("Session state saved. Relaunch to continue where the agent left off.")
    return .failed(reason)
}
```

**Step 3: Update `handleContributionIfNeeded`** (around line 1123):

Replace `guard tools.taskState == .savedAfterConfirm else { return }` with nothing — remove the guard entirely. The function is now only called when `didSave` is true, so the guard is redundant. Or replace with a simple comment:
```swift
// Called only when post-loop save completed successfully
```

**Step 4: Remove old `onToolsCreated?(tools)` call** (around line 939):

This is replaced by `onToolsCreated?(tools, control)` in the new code above. Make sure the old single-arg call is gone.

**IMPORTANT:** Do NOT change `canStop` or `shouldAbort` closure signatures or pass them — they don't exist in the new AgentLoop.run() signature. The new run() takes `control: AgentControl` directly.
  </action>
  <verify>
    <automated>cd /Users/peter/Documents/Cellar && swift build 2>&1 | tail -20</automated>
  </verify>
  <done>`swift build` succeeds. AIService.runAgentLoop() creates AgentControl, event log, middleware chain. run() called with new 4-arg signature. Post-loop save uses await. No references to canStop, shouldAbort closure, tools.taskState, or fire-and-forget Task.detached for save. handleContributionIfNeeded no longer checks taskState.</done>
</task>

</tasks>

<verification>
1. `swift build` — must compile without errors
2. `grep -rn "tools\.shouldAbort\|tools\.userForceConfirmed\|tools\.taskState\|canStop.*isTaskComplete" Sources/cellar/` — must return zero matches
3. `grep -rn "Task\.detached.*save_success" Sources/cellar/Core/AIService.swift` — must return zero matches (fire-and-forget eliminated)
4. `grep -n "getControl\|\.abort()\|\.confirm()" Sources/cellar/Web/Controllers/LaunchController.swift` — must show stop and confirm routes using AgentControl
5. `grep -n "AgentEventLog\|MiddlewareContext\|BudgetTracker\|SpinDetector\|EventLogger" Sources/cellar/Core/AIService.swift` — must show middleware chain creation
</verification>

<success_criteria>
- `swift build` passes with zero errors
- Stop route calls `AgentControl.abort()`, confirm route calls `AgentControl.confirm()`
- AIService creates AgentControl, MiddlewareContext, middleware chain (BudgetTracker + SpinDetector + EventLogger), and AgentEventLog
- Post-loop save uses `await tools.execute(toolName: "save_success", ...)` — no Task.detached fire-and-forget
- No remaining references to `taskState`, `tools.shouldAbort`, `tools.userForceConfirmed`, or `isTaskComplete` anywhere in the codebase
- `prepareStep: nil` wired as placeholder (INT-04)
</success_criteria>

<output>
After completion, create `.planning/phases/35-wire-it-together/35-P01-SUMMARY.md`
</output>
