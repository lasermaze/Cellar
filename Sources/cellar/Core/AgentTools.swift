import Foundation

// MARK: - AgentTools

/// Coordinator for all agent tool implementations.
///
/// Reference type (class) to allow mutable state accumulation across tool calls
/// within a single agent loop run — env vars, launch count, installed deps.
///
/// Tool implementations live in Core/Tools/ as extensions on this class:
///   - DiagnosticTools.swift: inspect_game, read_log, read_registry, trace_launch, check_file_access, verify_dll_override
///   - ConfigTools.swift: set_environment, set_registry, install_winetricks, place_dll, write_game_file, read_game_file
///   - LaunchTools.swift: launch_game, ask_user, list_windows
///   - SaveTools.swift: save_recipe, query_successdb, save_success
///   - ResearchTools.swift: search_web, fetch_page, query_compatibility
final class AgentTools: @unchecked Sendable {

    // MARK: - Injected Context

    let gameId: String
    let entry: GameEntry
    let executablePath: String      // resolved full path to game EXE
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess

    // MARK: - Control Channel

    /// Thread-safe control channel — set by AIService before loop starts.
    var control: AgentControl!

    // MARK: - User Input Handler

    /// Callback to ask the user a question. Returns their answer.
    /// Default implementation uses readLine() (CLI). Override for web UI.
    var askUserHandler: @Sendable (_ question: String, _ options: [String]?) -> String = { question, options in
        print("\nAgent question: \(question)")
        if let opts = options, !opts.isEmpty {
            for (index, option) in opts.enumerated() {
                print("  \(index + 1). \(option)")
            }
            print("Enter number or free text: ", terminator: "")
        } else {
            print("Your answer: ", terminator: "")
        }
        fflush(stdout)
        return readLine() ?? ""
    }

    // MARK: - Mutable State

    /// Wine environment variables accumulated across set_environment calls.
    var accumulatedEnv: [String: String] = [:]
    /// Number of times launch_game has been called.
    var launchCount: Int = 0
    /// Maximum allowed launches per agent session.
    let maxLaunches: Int = 8
    /// Winetricks verbs already installed (to skip duplicates).
    var installedDeps: Set<String> = []
    /// Log file from the most recent launch_game call.
    var lastLogFile: URL? = nil

    /// Actions applied since the last launch (for changes_since_last tracking).
    /// Internal so extension files (LaunchTools, DiagnosticTools) can read/write.
    var pendingActions: [String] = []
    /// Actions that were pending at the time of the last launch.
    var lastAppliedActions: [String] = []
    /// Previous launch diagnostics for computing changes between launches.
    var previousDiagnostics: WineDiagnostics? = nil
    /// Set by save_failure tool to signal the failure branch should write a session log entry
    /// even when no other substantive material exists.
    var hasSubstantiveFailure: Bool = false

    /// Stable per-session short ID (8 hex chars). Used for the on-disk draft file path.
    let sessionShortId: String = String(UUID().uuidString.prefix(8)).lowercased()

    /// Mid-session observation buffer (populated by update_wiki tool, flushed by AIService at session end).
    lazy var draftBuffer: SessionDraftBuffer = SessionDraftBuffer(shortId: sessionShortId)

    // MARK: - Init

    init(
        gameId: String,
        entry: GameEntry,
        executablePath: String,
        bottleURL: URL,
        wineURL: URL,
        wineProcess: WineProcess
    ) {
        self.gameId = gameId
        self.entry = entry
        self.executablePath = executablePath
        self.bottleURL = bottleURL
        self.wineURL = wineURL
        self.wineProcess = wineProcess
    }

    // MARK: - Session Handoff

    /// Capture current session state for handoff to a future session.
    func captureHandoff(stopReason: String, lastText: String, iterationsUsed: Int, costUSD: Double) -> SessionHandoff {
        // Take last 1000 chars of agent text as status summary
        let statusText = String(lastText.suffix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)

        return SessionHandoff(
            gameId: gameId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            stopReason: stopReason,
            iterationsUsed: iterationsUsed,
            estimatedCostUSD: costUSD,
            accumulatedEnv: accumulatedEnv,
            installedDeps: Array(installedDeps),
            launchCount: launchCount,
            lastStatus: statusText
        )
    }

    // MARK: - Tool Definitions

    /// Tool definitions derived from the AgentToolName enum metadata table.
    /// Single source of truth: adding a case to AgentToolName automatically adds it here.
    static var toolDefinitions: [ToolDefinition] {
        AgentToolName.allCases.map { $0.definition }
    }

    // MARK: - Dispatch

    /// Dispatch a tool call by name. Returns a typed ToolResult. Never throws.
    func execute(toolName: String, input: JSONValue) async -> ToolResult {
        // Check control flags
        if control.shouldAbort {
            return .stop(
                content: jsonResult(["error": "Agent stopped by user."]),
                reason: .userAborted
            )
        }

        // User confirmed — signal stop but DON'T save here.
        // Save happens after the loop, in AIService.runAgentLoop().
        let resolvedTool = AgentToolName(rawValue: toolName)
        if control.userForceConfirmed && resolvedTool != .saveSuccess && resolvedTool != .saveRecipe {
            return .stop(
                content: jsonResult(["user_override": "User confirmed game is working. Stopping."]),
                reason: .userConfirmedWorking
            )
        }

        // Resolve wire name to typed enum — unknown tool returns error immediately.
        guard let tool = resolvedTool else {
            return .error(content: jsonResult(["error": "Unknown tool: \(toolName)"]))
        }

        // Dispatch to tool implementation. Compiler enforces exhaustiveness.
        // Tool implementations in Tools/*.swift keep their JSONValue → String signatures (Phase 31).
        let resultString: String
        switch tool {
        case .inspectGame:       resultString = inspectGame(input: input)
        case .readLog:           resultString = readLog(input: input)
        case .readRegistry:      resultString = readRegistry(input: input)
        case .askUser:           resultString = askUser(input: input)
        case .setEnvironment:    resultString = setEnvironment(input: input)
        case .setRegistry:       resultString = setRegistry(input: input)
        case .installWinetricks: resultString = installWinetricks(input: input)
        case .placeDll:          resultString = await placeDLL(input: input)
        case .launchGame:        resultString = launchGame(input: input)
        case .saveRecipe:        resultString = saveRecipe(input: input)
        case .writeGameFile:     resultString = writeGameFile(input: input)
        case .readGameFile:      resultString = readGameFile(input: input)
        case .querySuccessdb:    resultString = querySuccessdb(input: input)
        case .saveSuccess:       resultString = saveSuccess(input: input)
        case .traceLaunch:       resultString = traceLaunch(input: input)
        case .checkFileAccess:   resultString = checkFileAccess(input: input)
        case .verifyDllOverride: resultString = verifyDllOverride(input: input)
        case .searchWeb:         resultString = await searchWeb(input: input)
        case .fetchPage:         resultString = await fetchPage(input: input)
        case .listWindows:       resultString = listWindows(input: input)
        case .queryCompatibility: resultString = await queryCompatibility(input: input)
        case .queryWiki:         resultString = await queryWiki(input: input)
        case .saveFailure:       resultString = await saveFailure(input: input)
        case .updateWiki:        resultString = await updateWiki(input: input)
        }

        // Track pending actions via enum metadata — single call site, no inline switch.
        if let desc = tool.pendingActionDescription(for: input) {
            pendingActions.append(desc)
        }

        return .success(content: resultString)
    }

    // MARK: - JSON Helper

    /// Serialize a dictionary to a compact JSON string. Returns error JSON on failure.
    /// Internal access — used by all tool extension files.
    func jsonResult(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{\"error\": \"Failed to serialize result\"}"
        }
        return str
    }
}

// MARK: - AIService Extension

extension AIService {
    /// Public accessor for the winetricks verb allowlist — used by AgentTools.installWinetricks.
    static let agentValidWinetricksVerbs: Set<String> = [
        // Runtime dependencies
        "dotnet48", "dotnet40", "dotnet35",
        "vcrun2019", "vcrun2015", "vcrun2013", "vcrun2010", "vcrun2008",
        // DirectX components
        "d3dx9", "d3dx10", "d3dx11_43", "d3dcompiler_47",
        "dinput8", "dinput",
        // Media
        "quartz", "wmp9", "wmp10",
        // Audio
        "dsound",
        // Input
        "xinput",
        // Common game deps
        "physx", "xact", "xactengine3_7"
    ]
}
