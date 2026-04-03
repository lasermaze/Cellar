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

    /// JSON Schema tool definitions for all agent tools.
    static let toolDefinitions: [ToolDefinition] = [

        // 1. inspect_game — no required params; game context is implicit
        ToolDefinition(
            name: "inspect_game",
            description: "Inspect the game setup: executable type (PE32/PE32+), game directory files, bottle state, installed DLLs in system32, and bundled recipe info. Call this first to understand what you're working with.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        ),

        // 2. read_log — optional lines param
        ToolDefinition(
            name: "read_log",
            description: "Read the Wine stderr log from the most recent game launch. Returns the last 8000 characters of the log file. Use this after launch_game to diagnose errors.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "lines": .object([
                        "type": .string("number"),
                        "description": .string("Number of lines to return from the end (default 200, max ~8000 chars)")
                    ])
                ]),
                "required": .array([])
            ])
        ),

        // 3. read_registry — required key_path, optional value_name
        ToolDefinition(
            name: "read_registry",
            description: "Read Wine registry values directly from user.reg or system.reg. Use key paths like 'HKCU\\\\Software\\\\Wine\\\\DllOverrides'. Returns all values in the matching section, or a specific value if value_name is provided.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key_path": .object([
                        "type": .string("string"),
                        "description": .string("Windows registry key path, e.g. HKCU\\\\Software\\\\Wine\\\\DllOverrides or HKLM\\\\System\\\\CurrentControlSet\\\\Control")
                    ]),
                    "value_name": .object([
                        "type": .string("string"),
                        "description": .string("Optional: specific value name to read. If omitted, returns all values in the section.")
                    ])
                ]),
                "required": .array([.string("key_path")])
            ])
        ),

        // 4. ask_user — required question, optional options array
        ToolDefinition(
            name: "ask_user",
            description: "Ask the user a question and return their answer. Use for decisions that require user input — e.g. confirming a potentially destructive action, or gathering info about their game version. Keep questions concise.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "question": .object([
                        "type": .string("string"),
                        "description": .string("The question to ask the user")
                    ]),
                    "options": .object([
                        "type": .string("array"),
                        "description": .string("Optional: numbered choices to present to the user"),
                        "items": .object(["type": .string("string")])
                    ])
                ]),
                "required": .array([.string("question")])
            ])
        ),

        // 5. set_environment — required key, value
        ToolDefinition(
            name: "set_environment",
            description: "Set a Wine environment variable for the next launch_game call. Variables accumulate across multiple calls. Common variables: WINEDLLOVERRIDES, WINEFSYNC, WINEESYNC, MESA_GL_VERSION_OVERRIDE, WINEDEBUG.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key": .object([
                        "type": .string("string"),
                        "description": .string("Environment variable name (e.g. WINEDLLOVERRIDES)")
                    ]),
                    "value": .object([
                        "type": .string("string"),
                        "description": .string("Environment variable value (e.g. ddraw=n,b)")
                    ])
                ]),
                "required": .array([.string("key"), .string("value")])
            ])
        ),

        // 6. set_registry — required key_path, value_name, data
        ToolDefinition(
            name: "set_registry",
            description: "Write a value to the Wine registry via wine regedit. Use for persistent game configuration. Data format: 'dword:00000001', '\"string value\"', 'hex:...'.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "key_path": .object([
                        "type": .string("string"),
                        "description": .string("Registry key path, e.g. HKCU\\\\Software\\\\Wine\\\\Direct3D")
                    ]),
                    "value_name": .object([
                        "type": .string("string"),
                        "description": .string("Registry value name")
                    ]),
                    "data": .object([
                        "type": .string("string"),
                        "description": .string("Registry data in .reg format: dword:00000001, \"string\", hex:ff,00,...")
                    ])
                ]),
                "required": .array([.string("key_path"), .string("value_name"), .string("data")])
            ])
        ),

        // 7. install_winetricks — required verb
        ToolDefinition(
            name: "install_winetricks",
            description: "Install a winetricks verb into the game's Wine bottle. Only verbs from the known-safe allowlist are permitted. Use for runtime dependencies like vcrun2019, d3dx9, dotnet48.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "verb": .object([
                        "type": .string("string"),
                        "description": .string("Winetricks verb to install. Allowed verbs: dotnet48, dotnet40, dotnet35, vcrun2019, vcrun2015, vcrun2013, vcrun2010, vcrun2008, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, dinput8, dinput, quartz, wmp9, wmp10, dsound, xinput, physx, xact, xactengine3_7")
                    ])
                ]),
                "required": .array([.string("verb")])
            ])
        ),

        // 8. place_dll — required dll_name, optional target
        ToolDefinition(
            name: "place_dll",
            description: "Download and place a DLL replacement from the known registry. Targets: game_dir (next to EXE), system32 (Wine System32), syswow64 (Wine SysWOW64 for 32-bit system DLLs in wow64 bottles). If target is omitted, auto-detects based on bottle type and DLL metadata. Auto-applies required WINEDLLOVERRIDES and writes companion config files.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "dll_name": .object([
                        "type": .string("string"),
                        "description": .string("DLL name from the known registry (e.g. cnc-ddraw)")
                    ]),
                    "target": .object([
                        "type": .string("string"),
                        "enum": .array([.string("game_dir"), .string("system32"), .string("syswow64")]),
                        "description": .string("Placement target. If omitted, auto-detects: system DLLs use syswow64 in wow64 bottles, others use game_dir.")
                    ])
                ]),
                "required": .array([.string("dll_name")])
            ])
        ),

        // 9. launch_game — optional extra_winedebug, diagnostic
        ToolDefinition(
            name: "launch_game",
            description: "Launch the game with Wine using the currently accumulated environment variables. Runs pre-flight checks (exe exists, DLL files present), returns exit code, elapsed time, stderr tail, detected errors, and loaded DLL summary. Maximum 8 real launches per session. Diagnostic launches (diagnostic=true) do NOT count toward the limit.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "extra_winedebug": .object([
                        "type": .string("string"),
                        "description": .string("Optional additional WINEDEBUG channels (e.g. +d3d,+opengl). Merged with existing WINEDEBUG.")
                    ]),
                    "diagnostic": .object([
                        "type": .string("boolean"),
                        "description": .string("If true, this is a quick diagnostic launch (shorter timeout, more verbose output). Does NOT count toward the 8-launch limit. Default false.")
                    ])
                ]),
                "required": .array([])
            ])
        ),

        // 10. save_recipe — required name, optional notes
        ToolDefinition(
            name: "save_recipe",
            description: "Save the current working configuration as a user recipe file for future launches. Call this when the game launches successfully. The recipe captures the accumulated environment variables.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Human-readable recipe name (e.g. 'Cossacks European Wars - Working Config')")
                    ]),
                    "notes": .object([
                        "type": .string("string"),
                        "description": .string("Optional notes about the configuration or what fixed the game")
                    ])
                ]),
                "required": .array([.string("name")])
            ])
        ),

        // 11. write_game_file — required relative_path, content
        ToolDefinition(
            name: "write_game_file",
            description: "Write a config or data file into the game directory. Use for files like ddraw.ini, mode.dat, or custom config files the game needs. Paths are relative to the game executable's directory. Windows backslash paths are auto-converted. WARNING: This OVERWRITES the entire file. If modifying an existing config file (e.g. .ini), use check_file_access to verify it exists first, then read it via inspect_game or read_log context. Never write a partial version of an existing config — include ALL original sections/keys plus your changes. A backup is created automatically (.cellar-backup).",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "relative_path": .object([
                        "type": .string("string"),
                        "description": .string("File path relative to the game executable directory (e.g. 'ddraw.ini' or 'data/mode.dat')")
                    ]),
                    "content": .object([
                        "type": .string("string"),
                        "description": .string("The text content to write to the file")
                    ])
                ]),
                "required": .array([.string("relative_path"), .string("content")])
            ])
        ),

        // 11b. read_game_file — required relative_path
        ToolDefinition(
            name: "read_game_file",
            description: "Read a file from the game directory. Use this BEFORE write_game_file to see the current contents of config files (.ini, .cfg, etc.) so you can make targeted edits without losing existing settings. Returns the file contents (up to 16000 chars). Paths are relative to the game executable's directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "relative_path": .object([
                        "type": .string("string"),
                        "description": .string("File path relative to the game executable directory (e.g. 'DeusEx.ini' or 'data/config.cfg')")
                    ])
                ]),
                "required": .array([.string("relative_path")])
            ])
        ),

        // --- Diagnostic Tools (Phase 07-03) ---

        // 12. trace_launch — optional debug_channels, timeout_seconds
        ToolDefinition(
            name: "trace_launch",
            description: "Run a short diagnostic Wine launch with debug channels enabled. The game is killed after timeout_seconds. Returns structured DLL load analysis (which DLLs loaded, from where, native vs builtin), any dialog/msgbox text detected, and errors. Use this BEFORE configuring — trace first, then fix. Does NOT count toward the launch limit.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "debug_channels": .object([
                        "type": .string("array"),
                        "description": .string("Wine debug channels to enable (default [\"+loaddll\"])"),
                        "items": .object(["type": .string("string")])
                    ]),
                    "timeout_seconds": .object([
                        "type": .string("number"),
                        "description": .string("Seconds to wait before killing the process (default 5)")
                    ])
                ]),
                "required": .array([])
            ])
        ),

        // 13. check_file_access — required paths array
        ToolDefinition(
            name: "check_file_access",
            description: "Check if the game can find files it needs by verifying file existence relative to the game executable's directory. Use to diagnose 'file not found' errors caused by wrong working directory.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "paths": .object([
                        "type": .string("array"),
                        "description": .string("Relative file paths to check from the game executable's directory"),
                        "items": .object(["type": .string("string")])
                    ])
                ]),
                "required": .array([.string("paths")])
            ])
        ),

        // 14. verify_dll_override — required dll_name
        ToolDefinition(
            name: "verify_dll_override",
            description: "Verify that a DLL override is actually working by comparing the configured override (env/registry) with what Wine actually loaded (via a short trace). Explains discrepancies like 'native DLL exists in game_dir but Wine loaded builtin from syswow64'.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "dll_name": .object([
                        "type": .string("string"),
                        "description": .string("DLL name to verify (e.g. \"ddraw\")")
                    ])
                ]),
                "required": .array([.string("dll_name")])
            ])
        ),

        // 15. query_successdb — optional query params
        ToolDefinition(
            name: "query_successdb",
            description: "Query the local success database for known-working game configurations. Query by game_id (exact), tags (overlap), engine (substring), graphics_api (substring), symptom (fuzzy keyword match against pitfalls), or similar_games (composite multi-signal similarity search). Call this BEFORE web research — local knowledge is faster and more reliable.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "game_id": .object([
                        "type": .string("string"),
                        "description": .string("Exact game ID to look up (e.g. 'cossacks-european-wars')")
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "description": .string("Tags to match (any overlap). E.g. ['directdraw', '2d-rts']"),
                        "items": .object(["type": .string("string")])
                    ]),
                    "engine": .object([
                        "type": .string("string"),
                        "description": .string("Engine name substring to match (e.g. 'unreal', 'source')")
                    ]),
                    "graphics_api": .object([
                        "type": .string("string"),
                        "description": .string("Graphics API substring to match (e.g. 'directdraw', 'd3d9')")
                    ]),
                    "symptom": .object([
                        "type": .string("string"),
                        "description": .string("Symptom description for fuzzy matching against known pitfalls (e.g. 'black screen on launch')")
                    ]),
                    "similar_games": .object([
                        "type": .string("object"),
                        "description": .string("Find games with similar characteristics. Returns cross-game matches ranked by signal overlap (engine weight 3, graphics_api weight 2, tags weight 1 each, symptom weight 1). Requires at least engine or graphics_api."),
                        "properties": .object([
                            "engine": .object(["type": .string("string"), "description": .string("Engine to match (e.g. 'unreal')")]),
                            "graphics_api": .object(["type": .string("string"), "description": .string("Graphics API to match (e.g. 'directdraw')")]),
                            "tags": .object(["type": .string("array"), "description": .string("Tags for overlap scoring"), "items": .object(["type": .string("string")])]),
                            "symptom": .object(["type": .string("string"), "description": .string("Symptom for pitfall matching")])
                        ])
                    ])
                ]),
                "required": .array([])
            ])
        ),

        // 16. save_success — required game_name, many optional detail params
        ToolDefinition(
            name: "save_success",
            description: "Save a comprehensive success record after the game launches successfully. Captures everything: environment, DLL overrides with placement details, game config files, registry settings, pitfalls (what went wrong and how it was fixed), and a resolution narrative. This replaces save_recipe for detailed records.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "game_name": .object([
                        "type": .string("string"),
                        "description": .string("Human-readable game name (e.g. 'Cossacks: European Wars')")
                    ]),
                    "game_version": .object([
                        "type": .string("string"),
                        "description": .string("Game version if known")
                    ]),
                    "source": .object([
                        "type": .string("string"),
                        "description": .string("Game source: 'gog', 'steam', 'disc', 'other'")
                    ]),
                    "engine": .object([
                        "type": .string("string"),
                        "description": .string("Game engine if known (e.g. 'custom', 'unreal', 'source')")
                    ]),
                    "graphics_api": .object([
                        "type": .string("string"),
                        "description": .string("Primary graphics API: 'directdraw', 'direct3d8', 'direct3d9', 'opengl'")
                    ]),
                    "bottle_type": .object([
                        "type": .string("string"),
                        "description": .string("Wine bottle type: 'wow64' or 'standard'")
                    ]),
                    "working_directory_notes": .object([
                        "type": .string("string"),
                        "description": .string("Notes about working directory requirements")
                    ]),
                    "dll_overrides": .object([
                        "type": .string("array"),
                        "description": .string("DLL overrides applied. Each object: {dll, mode, placement?, source?}"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "game_config_files": .object([
                        "type": .string("array"),
                        "description": .string("Game config files modified. Each: {path, purpose, critical_settings?}"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "registry": .object([
                        "type": .string("array"),
                        "description": .string("Registry entries set. Each: {key, value_name, data, purpose?}"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "game_specific_dlls": .object([
                        "type": .string("array"),
                        "description": .string("Game-specific DLLs placed. Each: {filename, source, placement, version?}"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "pitfalls": .object([
                        "type": .string("array"),
                        "description": .string("Pitfalls encountered. Each: {symptom, cause, fix, wrong_fix?}"),
                        "items": .object(["type": .string("object")])
                    ]),
                    "resolution_narrative": .object([
                        "type": .string("string"),
                        "description": .string("Free-text narrative of the resolution process and what finally worked")
                    ]),
                    "tags": .object([
                        "type": .string("array"),
                        "description": .string("Searchable tags for this game (e.g. ['directdraw', '2d-rts', 'gog', 'cnc-ddraw'])"),
                        "items": .object(["type": .string("string")])
                    ])
                ]),
                "required": .array([.string("game_name")])
            ])
        ),

        // 17. search_web — required query
        ToolDefinition(
            name: "search_web",
            description: "Search the web for game-specific Wine compatibility info. Targets WineHQ, ProtonDB, PCGamingWiki, and forums. Results are cached per game for 7 days. Returns structured snippets, not full pages — use fetch_page to read a specific URL. Call this after checking query_successdb.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object([
                        "type": .string("string"),
                        "description": .string("Search query for Wine compatibility info (e.g. 'Cossacks European Wars Wine compatibility')")
                    ])
                ]),
                "required": .array([.string("query")])
            ])
        ),

        // 18. fetch_page — required url
        ToolDefinition(
            name: "fetch_page",
            description: "Fetch a URL and extract structured content using SwiftSoup HTML parsing. Returns text_content (up to 8000 chars) plus extracted_fixes containing Wine-specific fix data (env vars, DLL overrides, registry entries, winetricks verbs, INI changes) when detected. Use after search_web to read promising result pages. Specialized parsers for WineHQ AppDB and PCGamingWiki; generic parser for other sites.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "url": .object([
                        "type": .string("string"),
                        "description": .string("URL to fetch and extract text from")
                    ])
                ]),
                "required": .array([.string("url")])
            ])
        ),

        // 19. list_windows — no required params
        ToolDefinition(
            name: "list_windows",
            description: "Query the macOS window list for Wine processes. Returns window sizes, owner process names, and titles (titles require Screen Recording permission). Use after launch_game to check if the game is showing a dialog (small window) or running normally (large window). If Screen Recording permission is denied, returns bounds and owner only with instructions to grant permission.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([:]),
                "required": .array([])
            ])
        ),

        // 20. query_compatibility — required game_name
        ToolDefinition(
            name: "query_compatibility",
            description: "Query Lutris and ProtonDB community databases for Wine compatibility data on a game. Returns environment variables, DLL overrides, winetricks verbs, registry edits from Lutris installer scripts, and ProtonDB tier rating. Use this for on-demand lookups if compatibility data wasn't in the initial context or you need to check a different game name.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "game_name": .object([
                        "type": .string("string"),
                        "description": .string("Game name to search for (e.g. 'Deus Ex', 'Cossacks European Wars')")
                    ])
                ]),
                "required": .array([.string("game_name")])
            ])
        )
    ]

    // MARK: - Dispatch

    /// Dispatch a tool call by name. Returns a JSON string result. Never throws.
    func execute(toolName: String, input: JSONValue) async -> String {
        // Check web control flags before executing any tool
        if shouldAbort {
            return "{\"error\": \"Agent stopped by user.\", \"STOP\": true}"
        }
        if userForceConfirmed && toolName != "save_success" && toolName != "save_recipe" {
            // User confirmed game works — force save and stop
            taskState = .userConfirmedOk
            let saveInput: JSONValue = .object([
                "game_name": .string(entry.name),
                "resolution_narrative": .string("User confirmed game is working from web UI.")
            ])
            _ = saveSuccess(input: saveInput)
            // Force savedAfterConfirm regardless of save result (save may fail on permissions)
            taskState = .savedAfterConfirm
            return "{\"user_override\": \"User confirmed game is working from web UI. Config saved. Stop now.\", \"STOP\": true}"
        }

        let result: String
        switch toolName {
        case "inspect_game":        result = inspectGame(input: input)
        case "read_log":            result = readLog(input: input)
        case "read_registry":       result = readRegistry(input: input)
        case "ask_user":            result = askUser(input: input)
        case "set_environment":     result = setEnvironment(input: input)
        case "set_registry":        result = setRegistry(input: input)
        case "install_winetricks":  result = installWinetricks(input: input)
        case "place_dll":           result = await placeDLL(input: input)
        case "launch_game":         result = launchGame(input: input)
        case "save_recipe":         result = saveRecipe(input: input)
        case "write_game_file":     result = writeGameFile(input: input)
        case "read_game_file":      result = readGameFile(input: input)
        case "query_successdb":     result = querySuccessdb(input: input)
        case "save_success":        result = saveSuccess(input: input)
        case "trace_launch":        result = traceLaunch(input: input)
        case "check_file_access":   result = checkFileAccess(input: input)
        case "verify_dll_override": result = verifyDllOverride(input: input)
        case "search_web":          result = await searchWeb(input: input)
        case "fetch_page":          result = await fetchPage(input: input)
        case "list_windows":        result = listWindows(input: input)
        case "query_compatibility": result = await queryCompatibility(input: input)
        default:
            return jsonResult(["error": "Unknown tool: \(toolName)"])
        }

        // Track action tools in pendingActions for changes_since_last diff
        switch toolName {
        case "set_environment":
            if let key = input["key"]?.asString, let value = input["value"]?.asString {
                pendingActions.append("set_environment(\(key)=\(value))")
            }
        case "set_registry":
            if let keyPath = input["key_path"]?.asString, let name = input["value_name"]?.asString {
                pendingActions.append("set_registry(\(keyPath), \(name))")
            }
        case "install_winetricks":
            if let verb = input["verb"]?.asString {
                pendingActions.append("install_winetricks(\(verb))")
            }
        case "place_dll":
            if let dllName = input["dll_name"]?.asString {
                pendingActions.append("place_dll(\(dllName))")
            }
        case "write_game_file":
            if let path = input["relative_path"]?.asString {
                pendingActions.append("write_game_file(\(path))")
            }
        default:
            break
        }

        return result
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
