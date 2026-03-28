import Foundation

// MARK: - Research Cache

private struct ResearchCache: Codable {
    let gameId: String
    let fetchedAt: String  // ISO8601
    let results: [ResearchResult]

    func isStale() -> Bool {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: fetchedAt) else { return true }
        return Date().timeIntervalSince(date) > 7 * 24 * 3600
    }
}

private struct ResearchResult: Codable {
    let source: String  // "winehq", "pcgamingwiki", "duckduckgo"
    let url: String
    let title: String
    let snippet: String
}

// MARK: - AgentTools

/// Container for all 18 agent tool implementations.
///
/// Reference type (class) to allow mutable state accumulation across tool calls
/// within a single agent loop run — env vars, launch count, installed deps.
final class AgentTools {

    // MARK: - Injected Context

    let gameId: String
    let entry: GameEntry
    let executablePath: String      // resolved full path to game EXE
    let bottleURL: URL
    let wineURL: URL
    let wineProcess: WineProcess

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
            description: "Write a config or data file into the game directory. Use for files like ddraw.ini, mode.dat, or custom config files the game needs. Paths are relative to the game executable's directory. Windows backslash paths are auto-converted.",
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

        // --- Diagnostic Tools (Phase 07-03) ---

        // 12. trace_launch — optional debug_channels, timeout_seconds
        ToolDefinition(
            name: "trace_launch",
            description: "Run a short diagnostic Wine launch with debug channels enabled. The game is killed after timeout_seconds. Returns structured DLL load analysis (which DLLs loaded, from where, native vs builtin) and any errors detected. Use this BEFORE configuring — trace first, then fix. Does NOT count toward the launch limit.",
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
            description: "Query the local success database for known-working game configurations. Query by game_id (exact), tags (overlap), engine (substring), graphics_api (substring), or symptom (fuzzy keyword match against pitfalls). Call this BEFORE web research — local knowledge is faster and more reliable.",
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
            description: "Fetch a specific URL and extract readable text content. Use after search_web to read a promising result page. Returns up to 8000 characters of cleaned text. Good for WineHQ AppDB pages, PCGamingWiki articles, and forum threads.",
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
        )
    ]

    // MARK: - Dispatch

    /// Dispatch a tool call by name. Returns a JSON string result. Never throws.
    func execute(toolName: String, input: JSONValue) -> String {
        switch toolName {
        case "inspect_game":      return inspectGame(input: input)
        case "read_log":          return readLog(input: input)
        case "read_registry":     return readRegistry(input: input)
        case "ask_user":          return askUser(input: input)
        case "set_environment":   return setEnvironment(input: input)
        case "set_registry":      return setRegistry(input: input)
        case "install_winetricks": return installWinetricks(input: input)
        case "place_dll":         return placeDLL(input: input)
        case "launch_game":       return launchGame(input: input)
        case "save_recipe":       return saveRecipe(input: input)
        case "write_game_file":   return writeGameFile(input: input)
        case "query_successdb":   return querySuccessdb(input: input)
        case "save_success":      return saveSuccess(input: input)
        case "trace_launch":      return traceLaunch(input: input)
        case "check_file_access": return checkFileAccess(input: input)
        case "verify_dll_override": return verifyDllOverride(input: input)
        case "search_web":        return searchWeb(input: input)
        case "fetch_page":        return fetchPage(input: input)
        default:
            return jsonResult(["error": "Unknown tool: \(toolName)"])
        }
    }

    // MARK: - JSON Helper

    /// Serialize a dictionary to a compact JSON string. Returns error JSON on failure.
    private func jsonResult(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let str = String(data: data, encoding: .utf8)
        else {
            return "{\"error\": \"Failed to serialize result\"}"
        }
        return str
    }

    // MARK: - Diagnostic Tools

    // MARK: 1. inspect_game

    private func inspectGame(input: JSONValue) -> String {
        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        // Run /usr/bin/file to get PE type
        var exeType = "unknown"
        let fileProcess = Process()
        fileProcess.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        fileProcess.arguments = [executablePath]
        let filePipe = Pipe()
        fileProcess.standardOutput = filePipe
        fileProcess.standardError = Pipe()
        do {
            try fileProcess.run()
            fileProcess.waitUntilExit()
            let data = filePipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                if output.contains("PE32+") {
                    exeType = "PE32+ (64-bit)"
                } else if output.contains("PE32") {
                    exeType = "PE32 (32-bit)"
                } else {
                    exeType = output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            exeType = "error: \(error.localizedDescription)"
        }

        // List files in game directory (top-level only)
        var gameFiles: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: gameDir,
            includingPropertiesForKeys: nil
        ) {
            gameFiles = contents.map { $0.lastPathComponent }.sorted()
        }

        // Subdirectory name scanning (one level deep, directory names only)
        var allGameFiles = gameFiles
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: gameDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            for item in contents {
                if let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                   values.isDirectory == true {
                    allGameFiles.append(item.lastPathComponent + "/")
                }
            }
        }

        // Check bottle existence
        let bottleExists = FileManager.default.fileExists(atPath: bottleURL.path)

        // List DLLs in system32
        var system32DLLs: [String] = []
        let system32Dir = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("windows")
            .appendingPathComponent("system32")
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: system32Dir,
            includingPropertiesForKeys: nil
        ) {
            system32DLLs = contents
                .filter { $0.pathExtension.lowercased() == "dll" }
                .map { $0.lastPathComponent }
                .sorted()
        }

        // Load bundled recipe info
        var recipeInfo: [String: Any] = [:]
        if let recipe = try? RecipeEngine.findBundledRecipe(for: gameId) {
            recipeInfo = [
                "name": recipe.name,
                "environment": recipe.environment,
                "registry_count": recipe.registry.count
            ]
        }

        // PE imports via objdump -p
        var peImports: [String] = []
        let objdumpProcess = Process()
        objdumpProcess.executableURL = URL(fileURLWithPath: "/usr/bin/objdump")
        objdumpProcess.arguments = ["-p", executablePath]
        let objdumpPipe = Pipe()
        objdumpProcess.standardOutput = objdumpPipe
        objdumpProcess.standardError = Pipe()
        do {
            try objdumpProcess.run()
            objdumpProcess.waitUntilExit()
            let objdumpData = objdumpPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: objdumpData, encoding: .utf8) {
                // Primary format: "DLL Name: kernel32.dll"
                let dllNameLines = output.components(separatedBy: "\n")
                    .filter { $0.contains("DLL Name:") }
                for line in dllNameLines {
                    if let colonRange = line.range(of: "DLL Name:") {
                        let name = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            peImports.append(name)
                        }
                    }
                }
                // Fallback: scan for .dll references if no DLL Name: lines found
                if peImports.isEmpty {
                    let dllRefs = output.components(separatedBy: "\n")
                        .compactMap { line -> String? in
                            guard let range = line.range(of: #"\b\w+\.dll\b"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
                            return String(line[range])
                        }
                    peImports = Array(Set(dllRefs)).sorted()
                }
            }
        } catch {
            // objdump failure is non-fatal — return empty array
        }

        // Bottle type detection: check for syswow64 directory
        let syswow64Dir = bottleURL
            .appendingPathComponent("drive_c")
            .appendingPathComponent("windows")
            .appendingPathComponent("syswow64")
        let bottleType = FileManager.default.fileExists(atPath: syswow64Dir.path) ? "wow64" : "standard"

        // Data files listing: common config/data extensions (up to 50)
        let dataExtensions: Set<String> = ["dat", "ini", "cfg", "txt", "xml", "json"]
        var dataFiles: [String] = []
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: gameDir,
            includingPropertiesForKeys: nil
        ) {
            dataFiles = contents
                .filter { dataExtensions.contains($0.pathExtension.lowercased()) }
                .map { $0.lastPathComponent }
                .sorted()
            if dataFiles.count > 50 { dataFiles = Array(dataFiles.prefix(50)) }
        }

        // Known shim DLL detection from PE imports
        let knownShimDLLs: [String: String] = [
            "ddraw.dll": "DirectDraw game — consider cnc-ddraw for improved rendering",
            "d3d8.dll": "Direct3D 8 game — may need d3d8 wrapper or wined3d config",
            "d3d9.dll": "Direct3D 9 game — standard wined3d path",
            "d3d11.dll": "Direct3D 11 game — may need DXVK or wined3d",
            "dinput.dll": "Uses DirectInput — may need dinput winetricks verb",
            "dinput8.dll": "Uses DirectInput8 — may need dinput8 winetricks verb",
            "dsound.dll": "Uses DirectSound — may need dsound winetricks verb"
        ]
        var notableImports: [[String: String]] = []
        for importName in peImports {
            if let note = knownShimDLLs[importName.lowercased()] {
                notableImports.append(["dll": importName, "note": note])
            }
        }

        // Binary string extraction for engine detection
        let binaryStrings = Self.extractBinaryStrings(executablePath)

        // Engine detection from file patterns, PE imports, and binary strings
        let engineResult = EngineRegistry.detect(
            gameFiles: allGameFiles,
            peImports: peImports,
            binaryStrings: binaryStrings
        )
        let graphicsApi = EngineRegistry.detectGraphicsApi(peImports: peImports)

        var result: [String: Any] = [
            "exe_type": exeType,
            "game_files": gameFiles,
            "bottle_exists": bottleExists,
            "system32_dlls": system32DLLs,
            "pe_imports": peImports,
            "bottle_type": bottleType,
            "data_files": dataFiles,
            "notable_imports": notableImports
        ]
        if !recipeInfo.isEmpty {
            result["recipe"] = recipeInfo
        } else {
            result["recipe"] = NSNull()
        }

        // Add engine detection results (only when detection succeeds)
        if let engine = engineResult {
            result["engine"] = engine.name
            result["engine_confidence"] = engine.confidence
            result["engine_family"] = engine.family
            result["detected_signals"] = engine.signals
        }
        if let api = graphicsApi {
            result["graphics_api"] = api
        }

        return jsonResult(result)
    }

    /// Extract printable strings from a binary using /usr/bin/strings.
    /// Returns up to 5000 lines of strings with minimum 10-char length.
    /// Returns empty array on failure (non-fatal).
    private static func extractBinaryStrings(_ path: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/strings")
        process.arguments = ["-n", "10", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            let lines = output.components(separatedBy: "\n")
            // Cap at 5000 lines to avoid performance issues on large executables
            return Array(lines.prefix(5000))
        } catch {
            return []
        }
    }

    // MARK: 2. read_log

    private func readLog(input: JSONValue) -> String {
        // Resolve log file: use lastLogFile or scan for most recent
        var logFileURL: URL? = lastLogFile

        if logFileURL == nil {
            let logDir = CellarPaths.logDir(for: gameId)
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: logDir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) {
                logFileURL = contents
                    .filter { $0.pathExtension == "log" }
                    .sorted { a, b in
                        let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                        let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                        return aDate > bDate
                    }
                    .first
            }
        }

        guard let url = logFileURL else {
            return jsonResult(["error": "No log file found for game '\(gameId)'. Run launch_game first.", "log_content": ""])
        }

        // Read file, return last 8000 chars
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            return jsonResult(["error": "Could not read log file: \(error.localizedDescription)", "log_file": url.path])
        }

        let tail = String(content.suffix(8000))
        return jsonResult(["log_content": tail, "log_file": url.path])
    }

    // MARK: 3. read_registry

    private func readRegistry(input: JSONValue) -> String {
        guard let keyPath = input["key_path"]?.asString, !keyPath.isEmpty else {
            return jsonResult(["error": "key_path is required"])
        }
        let valueName = input["value_name"]?.asString

        // Determine which .reg file to read based on hive prefix
        let regFileURL: URL
        let upperKeyPath = keyPath.uppercased()
        if upperKeyPath.hasPrefix("HKCU") || upperKeyPath.hasPrefix("HKEY_CURRENT_USER") {
            regFileURL = bottleURL.appendingPathComponent("user.reg")
        } else if upperKeyPath.hasPrefix("HKLM") || upperKeyPath.hasPrefix("HKEY_LOCAL_MACHINE") {
            regFileURL = bottleURL.appendingPathComponent("system.reg")
        } else {
            return jsonResult(["error": "Unsupported hive in key_path '\(keyPath)'. Use HKCU or HKLM prefix."])
        }

        // Read reg file — try UTF-8 first, fall back to Windows-1252
        let regContent: String
        do {
            if let content = try? String(contentsOf: regFileURL, encoding: .utf8) {
                regContent = content
            } else {
                regContent = try String(contentsOf: regFileURL, encoding: .windowsCP1252)
            }
        } catch {
            return jsonResult(["error": "Could not read registry file: \(error.localizedDescription)"])
        }

        // Convert Windows key path separators: backslash -> forward slash for .reg search
        // Wine .reg files use backslash in section headers: [HKEY_CURRENT_USER\Software\Wine\DllOverrides]
        // We need to search for the exact Windows format with backslashes
        let lines = regContent.components(separatedBy: "\n")

        // Normalize the search key: expand abbreviations to full form
        let normalizedSearchKey = normalizeRegistryKey(keyPath)

        // Find the section header matching the key path
        var inSection = false
        var values: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for section header: [HKEY_CURRENT_USER\Software\...]
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let sectionKey = String(trimmed.dropFirst().dropLast())
                inSection = (sectionKey.uppercased() == normalizedSearchKey.uppercased())
                if inSection && valueName != nil {
                    // Keep scanning for the specific value
                }
                continue
            }

            guard inSection else { continue }

            // Empty line ends section
            if trimmed.isEmpty {
                if valueName == nil {
                    break // collected all values
                }
                continue
            }

            // Parse value line: "valueName"=data or @=data (default value)
            if trimmed.hasPrefix("\"") || trimmed.hasPrefix("@") {
                if let eqRange = trimmed.range(of: "=") {
                    let nameRaw = String(trimmed[trimmed.startIndex..<eqRange.lowerBound])
                    let data = String(trimmed[eqRange.upperBound...])

                    // Strip surrounding quotes from name
                    let parsedName: String
                    if nameRaw == "@" {
                        parsedName = "(Default)"
                    } else {
                        parsedName = nameRaw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }

                    if let targetName = valueName {
                        if parsedName.lowercased() == targetName.lowercased() {
                            return jsonResult(["values": [parsedName: data], "key_path": keyPath])
                        }
                    } else {
                        values[parsedName] = data
                    }
                }
            }
        }

        if let targetName = valueName {
            return jsonResult(["error": "Value '\(targetName)' not found in '\(keyPath)'", "key_path": keyPath])
        }

        if values.isEmpty && !inSection {
            return jsonResult(["error": "Key path '\(keyPath)' not found in registry", "key_path": keyPath])
        }

        return jsonResult(["values": values, "key_path": keyPath])
    }

    /// Expand HKCU/HKLM abbreviations to full form for .reg file matching.
    private func normalizeRegistryKey(_ keyPath: String) -> String {
        var normalized = keyPath
        if normalized.uppercased().hasPrefix("HKCU\\") {
            normalized = "HKEY_CURRENT_USER\\" + normalized.dropFirst(5)
        } else if normalized.uppercased().hasPrefix("HKLM\\") {
            normalized = "HKEY_LOCAL_MACHINE\\" + normalized.dropFirst(5)
        } else if normalized.uppercased() == "HKCU" {
            normalized = "HKEY_CURRENT_USER"
        } else if normalized.uppercased() == "HKLM" {
            normalized = "HKEY_LOCAL_MACHINE"
        }
        return normalized
    }

    // MARK: 4. ask_user

    private func askUser(input: JSONValue) -> String {
        guard let question = input["question"]?.asString, !question.isEmpty else {
            return jsonResult(["error": "question is required"])
        }

        let options = input["options"]?.asArray?.compactMap { $0.asString }

        print("\nAgent question: \(question)")

        if let opts = options, !opts.isEmpty {
            for (index, option) in opts.enumerated() {
                print("  \(index + 1). \(option)")
            }
            print("Enter number or free text: ", terminator: "")
        } else {
            print("Your answer: ", terminator: "")
        }

        let answer = readLine() ?? ""
        return jsonResult(["answer": answer])
    }

    // MARK: - Action Tools

    // MARK: 5. set_environment

    private func setEnvironment(input: JSONValue) -> String {
        guard let key = input["key"]?.asString, !key.isEmpty else {
            return jsonResult(["error": "key is required"])
        }
        guard let value = input["value"]?.asString else {
            return jsonResult(["error": "value is required"])
        }

        accumulatedEnv[key] = value

        return jsonResult([
            "status": "ok",
            "key": key,
            "value": value,
            "current_env": accumulatedEnv
        ])
    }

    // MARK: 6. set_registry

    private func setRegistry(input: JSONValue) -> String {
        guard let keyPath = input["key_path"]?.asString, !keyPath.isEmpty else {
            return jsonResult(["error": "key_path is required"])
        }
        guard let valueName = input["value_name"]?.asString, !valueName.isEmpty else {
            return jsonResult(["error": "value_name is required"])
        }
        guard let data = input["data"]?.asString else {
            return jsonResult(["error": "data is required"])
        }

        // Build .reg file content
        var regContent = "Windows Registry Editor Version 5.00\n\n"
        regContent += "[\(keyPath)]\n"
        regContent += "\"\(valueName)\"=\(data)\n"

        let tempFile = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".reg")
        do {
            try regContent.write(to: tempFile, atomically: true, encoding: .utf8)
            try wineProcess.applyRegistryFile(at: tempFile)
            try? FileManager.default.removeItem(at: tempFile)
            return jsonResult([
                "status": "ok",
                "key_path": keyPath,
                "value_name": valueName,
                "data": data
            ])
        } catch {
            try? FileManager.default.removeItem(at: tempFile)
            return jsonResult(["error": "Registry edit failed: \(error.localizedDescription)"])
        }
    }

    // MARK: 7. install_winetricks

    private func installWinetricks(input: JSONValue) -> String {
        guard let verb = input["verb"]?.asString, !verb.isEmpty else {
            return jsonResult(["error": "verb is required"])
        }

        // Validate against allowlist
        guard AIService.agentValidWinetricksVerbs.contains(verb) else {
            let allowed = AIService.agentValidWinetricksVerbs.sorted().joined(separator: ", ")
            return jsonResult(["error": "Verb '\(verb)' not in allowed list.", "allowed_verbs": allowed])
        }

        // Skip if already installed
        if installedDeps.contains(verb) {
            return jsonResult(["status": "ok", "verb": verb, "note": "Already installed in this session"])
        }

        // Find winetricks binary
        guard let winetricksURL = DependencyChecker().checkAll().winetricks else {
            return jsonResult(["error": "winetricks not found. Run 'cellar status' to check dependencies."])
        }

        let runner = WinetricksRunner(
            winetricksURL: winetricksURL,
            wineBinary: wineURL,
            bottlePath: bottleURL.path
        )

        do {
            let result = try runner.install(verb: verb)
            if result.success {
                installedDeps.insert(verb)
                return jsonResult([
                    "status": "ok",
                    "verb": verb,
                    "exit_code": Int(result.exitCode),
                    "elapsed_seconds": result.elapsed,
                    "timed_out": result.timedOut
                ])
            } else if result.timedOut {
                return jsonResult(["error": "winetricks '\(verb)' timed out (>5 min stale output)", "verb": verb])
            } else {
                return jsonResult([
                    "error": "winetricks '\(verb)' failed with exit code \(result.exitCode)",
                    "verb": verb,
                    "exit_code": Int(result.exitCode)
                ])
            }
        } catch {
            return jsonResult(["error": "winetricks error: \(error.localizedDescription)", "verb": verb])
        }
    }

    // MARK: 8. place_dll

    private func placeDLL(input: JSONValue) -> String {
        guard let dllName = input["dll_name"]?.asString, !dllName.isEmpty else {
            return jsonResult(["error": "dll_name is required"])
        }

        guard let knownDLL = KnownDLLRegistry.find(name: dllName) else {
            let available = KnownDLLRegistry.registry.map { $0.name }.joined(separator: ", ")
            return jsonResult([
                "error": "DLL '\(dllName)' is not in the known DLL registry. The user should place it manually. Available DLLs: \(available)"
            ])
        }

        // Determine placement target: explicit param or auto-detect
        let detectedTarget: DLLPlacementTarget
        if let targetStr = input["target"]?.asString {
            switch targetStr {
            case "syswow64": detectedTarget = .syswow64
            case "system32": detectedTarget = .system32
            default: detectedTarget = .gameDir
            }
        } else {
            // Auto-detect using KnownDLL metadata and bottle layout
            detectedTarget = knownDLL.isSystemDLL
                ? DLLPlacementTarget.autoDetect(bottleURL: bottleURL, dllBitness: 32, isSystemDLL: true)
                : .gameDir
        }

        // Map target enum to actual directory URL
        let targetDir: URL
        let targetName: String
        switch detectedTarget {
        case .gameDir:
            targetDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            targetName = "game_dir"
        case .system32:
            targetDir = bottleURL.appendingPathComponent("drive_c/windows/system32")
            targetName = "system32"
        case .syswow64:
            targetDir = bottleURL.appendingPathComponent("drive_c/windows/syswow64")
            targetName = "syswow64"
        }

        do {
            print("Downloading \(knownDLL.name) from GitHub...")
            let cachedDLL = try DLLDownloader.downloadAndCache(knownDLL)
            let placedDLL = try DLLDownloader.place(cachedDLL: cachedDLL, into: targetDir)
            print("Placed \(placedDLL.lastPathComponent) in \(targetDir.path)")

            // Write companion files to the same directory as the DLL
            var companionPaths: [String] = []
            for companion in knownDLL.companionFiles {
                let companionURL = targetDir.appendingPathComponent(companion.filename)
                try companion.content.write(to: companionURL, atomically: true, encoding: .utf8)
                companionPaths.append(companionURL.path)
                print("Wrote companion file: \(companion.filename)")
            }

            // Apply required DLL overrides by accumulating into env
            var appliedOverrides: [String: String] = [:]
            for (dll, mode) in knownDLL.requiredOverrides {
                let override = "\(dll)=\(mode)"
                let key = "WINEDLLOVERRIDES"
                let current = accumulatedEnv[key] ?? ""
                accumulatedEnv[key] = current.isEmpty ? override : "\(current);\(override)"
                appliedOverrides[dll] = mode
            }

            return jsonResult([
                "status": "ok",
                "dll_name": knownDLL.name,
                "dll_file": knownDLL.dllFileName,
                "placed_at": placedDLL.path,
                "target": targetName,
                "companion_files": companionPaths,
                "applied_overrides": appliedOverrides
            ])
        } catch {
            return jsonResult(["error": "Failed to download/place \(dllName): \(error.localizedDescription)"])
        }
    }

    // MARK: - Execution Tools

    // MARK: 9. launch_game

    private func launchGame(input: JSONValue) -> String {
        let isDiagnostic = input["diagnostic"]?.asBool ?? false

        // Enforce max launch limit (diagnostic launches are free)
        if !isDiagnostic {
            if launchCount >= maxLaunches {
                return jsonResult([
                    "error": "Maximum launches (\(maxLaunches)) reached for this session. Save a recipe if you found a working configuration.",
                    "launch_number": launchCount
                ])
            }
            launchCount += 1
        }
        let thisLaunchNumber = launchCount

        // Pre-flight checks
        var preflightWarnings: [String] = []
        let fm = FileManager.default

        // a. Verify executable exists
        if !fm.fileExists(atPath: executablePath) {
            preflightWarnings.append("Executable not found at: \(executablePath)")
        }

        // b. Check DLL override files exist where expected
        if let overrides = accumulatedEnv["WINEDLLOVERRIDES"], !overrides.isEmpty {
            let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            let system32Dir = bottleURL.appendingPathComponent("drive_c/windows/system32")
            let syswow64Dir = bottleURL.appendingPathComponent("drive_c/windows/syswow64")
            let pairs = overrides.components(separatedBy: ";")
            for pair in pairs {
                let parts = pair.components(separatedBy: "=")
                guard let dllBase = parts.first?.trimmingCharacters(in: .whitespaces), !dllBase.isEmpty else { continue }
                let mode = parts.count > 1 ? parts[1] : ""
                // Only check native overrides (n or n,b)
                if mode.contains("n") {
                    let dllFile = dllBase.hasSuffix(".dll") ? dllBase : "\(dllBase).dll"
                    let inGameDir = fm.fileExists(atPath: gameDir.appendingPathComponent(dllFile).path)
                    let inSystem32 = fm.fileExists(atPath: system32Dir.appendingPathComponent(dllFile).path)
                    let inSyswow64 = fm.fileExists(atPath: syswow64Dir.appendingPathComponent(dllFile).path)
                    if !inGameDir && !inSystem32 && !inSyswow64 {
                        preflightWarnings.append("DLL override '\(dllBase)=\(mode)' set but \(dllFile) not found in game_dir, system32, or syswow64")
                    }
                }
            }
        }

        // Build environment: start with accumulated env
        var env = accumulatedEnv

        // Merge extra_winedebug if provided
        if let extraDebug = input["extra_winedebug"]?.asString, !extraDebug.isEmpty {
            let current = env["WINEDEBUG"] ?? ""
            env["WINEDEBUG"] = current.isEmpty ? extraDebug : "\(current),\(extraDebug)"
        }

        // Create log file
        let logFile = CellarPaths.logFile(for: gameId, timestamp: Date())

        // Ensure log directory exists
        let logDir = logFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

        let launchLabel = isDiagnostic ? "diagnostic" : "\(thisLaunchNumber)/\(maxLaunches)"
        print("\n[Agent launch \(launchLabel)] Starting game...")

        // Run game via wineProcess
        let result: WineResult
        do {
            result = try wineProcess.run(
                binary: executablePath,
                arguments: [],
                environment: env,
                logFile: logFile
            )
        } catch {
            return jsonResult([
                "error": "Failed to launch game: \(error.localizedDescription)",
                "launch_number": thisLaunchNumber,
                "diagnostic": isDiagnostic
            ])
        }

        // Store last log file for read_log
        lastLogFile = logFile

        // Parse errors from stderr
        let parsedErrors = WineErrorParser.parse(result.stderr)
        let errorDicts: [[String: String]] = parsedErrors.map { wineError in
            var dict: [String: String] = [
                "category": "\(wineError.category)",
                "detail": wineError.detail
            ]
            if let fix = wineError.suggestedFix {
                dict["suggested_fix"] = describeFix(fix)
            }
            return dict
        }

        // Parse +loaddll lines from stderr for DLL load analysis
        let stderrLines = result.stderr.components(separatedBy: "\n")
        var loadedDLLEntries: [String: [String: String]] = [:]
        for line in stderrLines {
            guard line.contains("loaddll") || line.contains("Loaded") else { continue }
            if let match = line.range(of: #"Loaded L"([^"]+)".*\b(native|builtin)\b"#, options: .regularExpression) {
                let matchStr = String(line[match])
                if let pathStart = matchStr.range(of: #"L""#),
                   let pathEnd = matchStr[pathStart.upperBound...].range(of: "\"") {
                    let fullPath = String(matchStr[pathStart.upperBound..<pathEnd.lowerBound])
                    let dllName = URL(fileURLWithPath: fullPath.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                    let loadType = matchStr.hasSuffix("native") ? "native" : "builtin"
                    loadedDLLEntries[dllName] = ["name": dllName, "path": fullPath, "type": loadType]
                }
            }
        }
        let loadedDLLs = loadedDLLEntries.values.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }

        let stderrTail = String(result.stderr.suffix(4000))

        var resultDict: [String: Any] = [
            "exit_code": Int(result.exitCode),
            "elapsed_seconds": result.elapsed,
            "timed_out": result.timedOut,
            "stderr_tail": stderrTail,
            "detected_errors": errorDicts,
            "loaded_dlls": loadedDLLs,
            "log_file": logFile.path,
            "launch_number": thisLaunchNumber,
            "diagnostic": isDiagnostic
        ]
        if !preflightWarnings.isEmpty {
            resultDict["preflight_warnings"] = preflightWarnings
        }

        return jsonResult(resultDict)
    }

    /// Describe a WineFix as a human-readable string for the agent.
    private func describeFix(_ fix: WineFix) -> String {
        switch fix {
        case .installWinetricks(let verb): return "install_winetricks(\(verb))"
        case .setEnvVar(let key, let value): return "set_environment(\(key)=\(value))"
        case .setDLLOverride(let dll, let mode): return "set_environment(WINEDLLOVERRIDES=\(dll)=\(mode))"
        case .placeDLL(let name, let target): return "place_dll(\(name), \(target))"
        case .setRegistry(let key, let name, let data): return "set_registry(\(key), \(name)=\(data))"
        case .compound(let fixes): return fixes.map { describeFix($0) }.joined(separator: " + ")
        }
    }

    // MARK: 10. save_recipe

    private func saveRecipe(input: JSONValue) -> String {
        guard let name = input["name"]?.asString, !name.isEmpty else {
            return jsonResult(["error": "name is required"])
        }
        let notes = input["notes"]?.asString

        // Build recipe from current accumulated state
        let executableFilename = URL(fileURLWithPath: executablePath).lastPathComponent

        let recipe = Recipe(
            id: gameId,
            name: name,
            version: "1.0.0",
            source: "ai-agent",
            executable: executableFilename,
            wineTested: nil,
            environment: accumulatedEnv,
            registry: [],
            launchArgs: [],
            notes: notes,
            setupDeps: installedDeps.isEmpty ? nil : Array(installedDeps).sorted(),
            installDir: nil,
            retryVariants: nil
        )

        do {
            try RecipeEngine.saveUserRecipe(recipe)
            let recipePath = CellarPaths.userRecipeFile(for: gameId).path
            return jsonResult([
                "status": "ok",
                "recipe_path": recipePath,
                "game_id": gameId,
                "environment_vars_saved": accumulatedEnv.count
            ])
        } catch {
            return jsonResult(["error": "Failed to save recipe: \(error.localizedDescription)"])
        }
    }

    // MARK: - Diagnostic Trace Tools (Phase 07-03)

    /// Thread-safe stderr capture for trace_launch (mirrors WineProcess.StderrCapture pattern).
    private final class TraceStderrCapture: @unchecked Sendable {
        private var buffer = ""
        private let lock = NSLock()
        func append(_ str: String) { lock.lock(); buffer += str; lock.unlock() }
        var value: String { lock.lock(); defer { lock.unlock() }; return buffer }
    }

    // MARK: 12. trace_launch

    /// Run a short diagnostic Wine launch with debug channels, kill after timeout.
    /// Returns structured DLL load analysis. Does NOT count toward launch limit.
    func traceLaunch(input: JSONValue) -> String {
        // Extract parameters with defaults
        let debugChannels: [String]
        if let channels = input["debug_channels"]?.asArray {
            debugChannels = channels.compactMap { $0.asString }
        } else {
            debugChannels = ["+loaddll"]
        }
        let timeoutSeconds: Int
        if let ts = input["timeout_seconds"]?.asNumber {
            timeoutSeconds = Int(ts)
        } else {
            timeoutSeconds = 5
        }

        // Build environment: copy accumulated, merge WINEDEBUG channels
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = wineProcess.winePrefix.path
        for (key, value) in accumulatedEnv {
            env[key] = value
        }
        let existingDebug = env["WINEDEBUG"] ?? ""
        let channelsStr = debugChannels.joined(separator: ",")
        env["WINEDEBUG"] = existingDebug.isEmpty ? channelsStr : "\(existingDebug),\(channelsStr)"

        // Create process
        let process = Process()
        process.executableURL = wineProcess.wineBinary
        process.arguments = [executablePath]
        process.environment = env

        // Set CWD to binary's parent directory (matches WineProcess CWD fix)
        let binaryURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = binaryURL.deletingLastPathComponent()

        // Capture stderr
        let stderrPipe = Pipe()
        process.standardOutput = Pipe() // discard stdout
        process.standardError = stderrPipe

        let stderrCapture = TraceStderrCapture()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let str = String(data: data, encoding: .utf8) {
                stderrCapture.append(str)
            }
        }

        // Start process
        do {
            try process.run()
        } catch {
            return jsonResult(["error": "Failed to start trace launch: \(error.localizedDescription)"])
        }

        // Kill timer: terminate process + kill wineserver after timeout
        let killWork = DispatchWorkItem { [weak self] in
            process.terminate()
            try? self?.wineProcess.killWineserver()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(timeoutSeconds), execute: killWork)

        process.waitUntilExit()
        killWork.cancel()

        // Close pipe write ends to unblock readDataToEndOfFile — Wine child processes
        // inherit these descriptors and keep them open indefinitely.
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        try? stderrPipe.fileHandleForWriting.close()

        // Drain remaining stderr
        let remainingData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingData.isEmpty, let str = String(data: remainingData, encoding: .utf8) {
            stderrCapture.append(str)
        }

        // Kill wineserver to clean up (in case timeout didn't fire)
        try? wineProcess.killWineserver()

        let stderr = stderrCapture.value

        // Parse +loaddll lines: trace:loaddll:...Loaded L"path" at addr: native|builtin
        let lines = stderr.components(separatedBy: "\n")
        var dllEntries: [String: [String: String]] = [:] // keyed by DLL name, last occurrence wins

        for line in lines {
            // Match lines containing loaddll trace output
            guard line.contains("trace:loaddll") || line.contains("Loaded") else { continue }

            // Regex: Loaded L"<path>".*: native|builtin
            if let match = line.range(of: #"Loaded L"([^"]+)".*\b(native|builtin)\b"#, options: .regularExpression) {
                let matchStr = String(line[match])
                // Extract path between L" and "
                if let pathStart = matchStr.range(of: #"L""#),
                   let pathEnd = matchStr[pathStart.upperBound...].range(of: "\"") {
                    let fullPath = String(matchStr[pathStart.upperBound..<pathEnd.lowerBound])
                    let dllName = URL(fileURLWithPath: fullPath.replacingOccurrences(of: "\\", with: "/")).lastPathComponent.lowercased()
                    let loadType = matchStr.hasSuffix("native") ? "native" : "builtin"
                    // Deduplicate by DLL name (keep last occurrence)
                    dllEntries[dllName] = [
                        "name": dllName,
                        "path": fullPath,
                        "type": loadType
                    ]
                }
            }
        }

        let loadedDLLs = dllEntries.values.sorted { ($0["name"] ?? "") < ($1["name"] ?? "") }

        // Extract Wine error lines (err: prefix)
        let errors = lines.filter { $0.contains("err:") }.prefix(50).map { String($0) }

        return jsonResult([
            "loaded_dlls": loadedDLLs,
            "errors": Array(errors),
            "timeout_applied": true,
            "raw_line_count": lines.count
        ])
    }

    // MARK: 13. check_file_access

    private func checkFileAccess(input: JSONValue) -> String {
        guard let paths = input["paths"]?.asArray?.compactMap({ $0.asString }), !paths.isEmpty else {
            return jsonResult(["error": "paths array is required and must not be empty"])
        }

        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        let fm = FileManager.default

        var results: [[String: Any]] = []
        for relativePath in paths {
            let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")
            let fullURL = gameDir.appendingPathComponent(normalizedPath)
            let exists = fm.fileExists(atPath: fullURL.path)
            results.append([
                "path": relativePath,
                "exists_from_game_dir": exists,
                "absolute_path": fullURL.path
            ])
        }

        return jsonResult(["results": results, "game_dir": gameDir.path])
    }

    // MARK: 14. verify_dll_override

    private func verifyDllOverride(input: JSONValue) -> String {
        guard let dllName = input["dll_name"]?.asString, !dllName.isEmpty else {
            return jsonResult(["error": "dll_name is required"])
        }

        let dllFileName = dllName.hasSuffix(".dll") ? dllName : "\(dllName).dll"
        let baseName = dllName.replacingOccurrences(of: ".dll", with: "").lowercased()

        // 1. Check configured override in accumulatedEnv
        let configuredOverride: String?
        if let overrides = accumulatedEnv["WINEDLLOVERRIDES"] {
            // Parse override string like "ddraw=n,b;dsound=b"
            let pairs = overrides.components(separatedBy: ";")
            configuredOverride = pairs.first(where: { $0.lowercased().hasPrefix(baseName + "=") })
        } else {
            configuredOverride = nil
        }

        // 2. Check where native DLL files exist
        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        let system32Dir = bottleURL
            .appendingPathComponent("drive_c/windows/system32")
        let syswow64Dir = bottleURL
            .appendingPathComponent("drive_c/windows/syswow64")

        let fm = FileManager.default
        var nativeDllLocations: [String] = []
        if fm.fileExists(atPath: gameDir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("game_dir")
        }
        if fm.fileExists(atPath: system32Dir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("system32")
        }
        if fm.fileExists(atPath: syswow64Dir.appendingPathComponent(dllFileName).path) {
            nativeDllLocations.append("syswow64")
        }

        // 3. Run a short trace launch to see what Wine actually loaded (skip if no executable found)
        let traceResultStr: String
        if fm.fileExists(atPath: executablePath) {
            let traceInput = JSONValue.object([
                "debug_channels": .array([.string("+loaddll")]),
                "timeout_seconds": .number(8)
            ])
            traceResultStr = traceLaunch(input: traceInput)
        } else {
            traceResultStr = jsonResult(["error": "no executable to trace"])
        }

        // Parse trace result to find the DLL
        var actualLoadPath: String? = nil
        var actualLoadType: String? = nil
        if let traceData = traceResultStr.data(using: .utf8),
           let traceJSON = try? JSONSerialization.jsonObject(with: traceData) as? [String: Any],
           let loadedDLLs = traceJSON["loaded_dlls"] as? [[String: String]] {
            for dll in loadedDLLs {
                if let name = dll["name"], name.lowercased() == dllFileName.lowercased() {
                    actualLoadPath = dll["path"]
                    actualLoadType = dll["type"]
                    break
                }
            }
        }

        // 4. Build explanation
        let explanation: String
        let working: Bool

        if let override = configuredOverride {
            if let loadType = actualLoadType {
                let wantsNative = override.contains("n,b") || override.contains("=n")
                if wantsNative && loadType == "native" {
                    explanation = "Override working correctly: configured \(override), loaded native from \(actualLoadPath ?? "unknown")"
                    working = true
                } else if wantsNative && loadType == "builtin" {
                    if nativeDllLocations.isEmpty {
                        explanation = "Override set to \(override) but Wine loaded builtin — no native DLL file found in game_dir, system32, or syswow64"
                    } else {
                        explanation = "Override set to \(override) but Wine loaded builtin from \(actualLoadPath ?? "unknown") — native DLL found in \(nativeDllLocations.joined(separator: ", ")) but Wine did not use it. For system DLLs in wow64 bottles, place in syswow64."
                    }
                    working = false
                } else {
                    explanation = "Override \(override) active, loaded \(loadType) from \(actualLoadPath ?? "unknown")"
                    working = true
                }
            } else {
                explanation = "Override \(override) is configured but DLL '\(dllFileName)' was not observed in trace output — game may not load this DLL at startup"
                working = false
            }
        } else {
            if let loadType = actualLoadType {
                explanation = "No override configured. Wine loaded \(loadType) \(dllFileName) from \(actualLoadPath ?? "unknown")"
                working = loadType == "builtin" // builtin is expected default
            } else {
                explanation = "No override configured and DLL '\(dllFileName)' was not observed in trace output"
                working = true // nothing to verify
            }
        }

        return jsonResult([
            "dll_name": baseName,
            "configured_override": configuredOverride ?? "none",
            "native_dll_locations": nativeDllLocations,
            "actual_load": [
                "path": actualLoadPath ?? "not_found",
                "type": actualLoadType ?? "not_loaded"
            ],
            "explanation": explanation,
            "working": working
        ])
    }

    // MARK: 11. write_game_file

    private func writeGameFile(input: JSONValue) -> String {
        guard let relativePath = input["relative_path"]?.asString, !relativePath.isEmpty else {
            return jsonResult(["error": "relative_path is required"])
        }
        guard let content = input["content"]?.asString else {
            return jsonResult(["error": "content is required"])
        }

        let gameDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()

        // Normalize: replace backslashes with forward slashes
        let normalizedPath = relativePath.replacingOccurrences(of: "\\", with: "/")

        // Build target URL and resolve to canonical path
        let targetURL = gameDir.appendingPathComponent(normalizedPath).standardized

        // Security check: resolved path must be under gameDir
        let gameDirPath = gameDir.standardized.path
        guard targetURL.path.hasPrefix(gameDirPath) else {
            return jsonResult(["error": "Path traversal denied: resolved path is outside the game directory"])
        }

        // Create intermediate directories
        let parentDir = targetURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            return jsonResult(["error": "Failed to create directories: \(error.localizedDescription)"])
        }

        // Write file atomically
        do {
            try content.write(to: targetURL, atomically: true, encoding: .utf8)
            return jsonResult([
                "status": "ok",
                "written_to": targetURL.path
            ])
        } catch {
            return jsonResult(["error": "Failed to write file: \(error.localizedDescription)"])
        }
    }

    // MARK: - Success Database Tools

    // MARK: 15. query_successdb

    private func querySuccessdb(input: JSONValue) -> String {
        // Priority order: game_id (exact), tags, engine, graphics_api, symptom

        if let queryGameId = input["game_id"]?.asString, !queryGameId.isEmpty {
            if let record = SuccessDatabase.queryByGameId(queryGameId) {
                let dict = successRecordToDict(record)
                return jsonResult(["query_type": "game_id", "matches": [dict]])
            } else {
                return jsonResult(["query_type": "game_id", "matches": [] as [Any], "note": "No record found for game_id '\(queryGameId)'"])
            }
        }

        if let tagsArray = input["tags"]?.asArray {
            let tags = tagsArray.compactMap { $0.asString }
            if !tags.isEmpty {
                let records = Array(SuccessDatabase.queryByTags(tags).prefix(5))
                let dicts = records.map { successRecordToDict($0) }
                return jsonResult(["query_type": "tags", "matches": dicts])
            }
        }

        if let engine = input["engine"]?.asString, !engine.isEmpty {
            let records = Array(SuccessDatabase.queryByEngine(engine).prefix(5))
            let dicts = records.map { successRecordToDict($0) }
            return jsonResult(["query_type": "engine", "matches": dicts])
        }

        if let api = input["graphics_api"]?.asString, !api.isEmpty {
            let records = Array(SuccessDatabase.queryByGraphicsApi(api).prefix(5))
            let dicts = records.map { successRecordToDict($0) }
            return jsonResult(["query_type": "graphics_api", "matches": dicts])
        }

        if let symptom = input["symptom"]?.asString, !symptom.isEmpty {
            let results = Array(SuccessDatabase.queryBySymptom(symptom).prefix(3))
            let dicts: [[String: Any]] = results.map { (record, score) in
                var dict = successRecordToDict(record)
                dict["relevance_score"] = score
                return dict
            }
            return jsonResult(["query_type": "symptom", "matches": dicts])
        }

        return jsonResult(["error": "No query parameters provided. Specify game_id, tags, engine, graphics_api, or symptom."])
    }

    // MARK: 16. save_success

    private func saveSuccess(input: JSONValue) -> String {
        guard let gameName = input["game_name"]?.asString, !gameName.isEmpty else {
            return jsonResult(["error": "game_name is required"])
        }

        let exeFilename = URL(fileURLWithPath: executablePath).lastPathComponent
        let executableInfo = ExecutableInfo(path: exeFilename, type: "unknown", peImports: nil)

        let workingDirNotes = input["working_directory_notes"]?.asString
        let workingDir: WorkingDirectoryInfo? = workingDirNotes != nil
            ? WorkingDirectoryInfo(requirement: "must_be_exe_parent", notes: workingDirNotes)
            : nil

        let dllOverrides: [DLLOverrideRecord] = (input["dll_overrides"]?.asArray ?? []).compactMap { item in
            guard let dll = item["dll"]?.asString, let mode = item["mode"]?.asString else { return nil }
            return DLLOverrideRecord(dll: dll, mode: mode, placement: item["placement"]?.asString, source: item["source"]?.asString)
        }

        let gameConfigFiles: [GameConfigFile] = (input["game_config_files"]?.asArray ?? []).compactMap { item in
            guard let path = item["path"]?.asString, let purpose = item["purpose"]?.asString else { return nil }
            var settings: [String: String]? = nil
            if let settingsObj = item["critical_settings"]?.asObject {
                settings = [:]
                for (k, v) in settingsObj {
                    if let str = v.asString { settings?[k] = str }
                }
            }
            return GameConfigFile(path: path, purpose: purpose, criticalSettings: settings)
        }

        let registryRecords: [RegistryRecord] = (input["registry"]?.asArray ?? []).compactMap { item in
            guard let key = item["key"]?.asString,
                  let valueName = item["value_name"]?.asString,
                  let data = item["data"]?.asString else { return nil }
            return RegistryRecord(key: key, valueName: valueName, data: data, purpose: item["purpose"]?.asString)
        }

        let gameSpecificDlls: [GameSpecificDLL] = (input["game_specific_dlls"]?.asArray ?? []).compactMap { item in
            guard let filename = item["filename"]?.asString,
                  let source = item["source"]?.asString,
                  let placement = item["placement"]?.asString else { return nil }
            return GameSpecificDLL(filename: filename, source: source, placement: placement, version: item["version"]?.asString)
        }

        let pitfalls: [PitfallRecord] = (input["pitfalls"]?.asArray ?? []).compactMap { item in
            guard let symptom = item["symptom"]?.asString,
                  let cause = item["cause"]?.asString,
                  let fix = item["fix"]?.asString else { return nil }
            return PitfallRecord(symptom: symptom, cause: cause, fix: fix, wrongFix: item["wrong_fix"]?.asString)
        }

        let tags: [String] = (input["tags"]?.asArray ?? []).compactMap { $0.asString }

        let formatter = ISO8601DateFormatter()
        let verifiedAt = formatter.string(from: Date())

        let record = SuccessRecord(
            schemaVersion: 1,
            gameId: gameId,
            gameName: gameName,
            gameVersion: input["game_version"]?.asString,
            source: input["source"]?.asString,
            engine: input["engine"]?.asString,
            graphicsApi: input["graphics_api"]?.asString,
            verifiedAt: verifiedAt,
            wineVersion: nil,
            bottleType: input["bottle_type"]?.asString,
            os: nil,
            executable: executableInfo,
            workingDirectory: workingDir,
            environment: accumulatedEnv,
            dllOverrides: dllOverrides,
            gameConfigFiles: gameConfigFiles,
            registry: registryRecords,
            gameSpecificDlls: gameSpecificDlls,
            pitfalls: pitfalls,
            resolutionNarrative: input["resolution_narrative"]?.asString,
            tags: tags
        )

        do {
            try SuccessDatabase.save(record)
            let savedPath = CellarPaths.successdbFile(for: gameId).path

            // Backward compatibility: also save as user recipe
            let recipeExeName = URL(fileURLWithPath: executablePath).lastPathComponent
            let recipe = Recipe(
                id: gameId,
                name: gameName,
                version: "1.0.0",
                source: "ai-agent",
                executable: recipeExeName,
                wineTested: nil,
                environment: accumulatedEnv,
                registry: [],
                launchArgs: [],
                notes: input["resolution_narrative"]?.asString,
                setupDeps: installedDeps.isEmpty ? nil : Array(installedDeps).sorted(),
                installDir: nil,
                retryVariants: nil
            )
            try? RecipeEngine.saveUserRecipe(recipe)

            return jsonResult([
                "status": "ok",
                "saved_to": savedPath,
                "game_id": gameId,
                "environment_vars": accumulatedEnv.count,
                "dll_overrides": dllOverrides.count,
                "pitfalls": pitfalls.count,
                "tags": tags
            ])
        } catch {
            return jsonResult(["error": "Failed to save success record: \(error.localizedDescription)"])
        }
    }

    /// Convert a SuccessRecord to a dictionary for JSON output via jsonResult.
    private func successRecordToDict(_ record: SuccessRecord) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(record),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ["game_id": record.gameId, "game_name": record.gameName]
        }
        return dict
    }

    // MARK: - Research Tools

    // MARK: 17. search_web

    private func searchWeb(input: JSONValue) -> String {
        guard let query = input["query"]?.asString, !query.isEmpty else {
            return jsonResult(["error": "query is required"])
        }

        // Check research cache
        let cacheFile = CellarPaths.researchCacheFile(for: gameId)
        if let cacheData = try? Data(contentsOf: cacheFile),
           let cache = try? JSONDecoder().decode(ResearchCache.self, from: cacheData),
           !cache.isStale() {
            let resultDicts: [[String: String]] = cache.results.map { r in
                ["source": r.source, "url": r.url, "title": r.title, "snippet": r.snippet]
            }
            return jsonResult([
                "results": resultDicts,
                "from_cache": true,
                "result_count": cache.results.count,
                "game_id": gameId
            ])
        }

        // Build DuckDuckGo HTML search URL
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURLString = "https://html.duckduckgo.com/html/?q=\(encodedQuery)+wine+compatibility"
        guard let searchURL = URL(string: searchURLString) else {
            return jsonResult(["error": "Failed to build search URL"])
        }

        // Fetch using DispatchSemaphore + ResultBox pattern
        final class ResultBox: @unchecked Sendable {
            var value: Result<Data, Error> = .failure(URLError(.unknown))
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: searchURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                box.value = .failure(error)
            } else if let data = data {
                box.value = .success(data)
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        guard case .success(let htmlData) = box.value,
              let html = String(data: htmlData, encoding: .utf8) else {
            let errorMsg: String
            if case .failure(let err) = box.value {
                errorMsg = err.localizedDescription
            } else {
                errorMsg = "Failed to decode response"
            }
            return jsonResult(["error": "Search failed: \(errorMsg)"])
        }

        // Parse HTML results
        var results: [ResearchResult] = []

        // Extract result blocks: look for result__a links and result__snippet
        let linkPattern = #"<a rel="nofollow" class="result__a" href="([^"]+)"[^>]*>(.*?)</a>"#
        let snippetPattern = #"<a class="result__snippet"[^>]*>(.*?)</a>"#

        let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.dotMatchesLineSeparators])
        let snippetRegex = try? NSRegularExpression(pattern: snippetPattern, options: [.dotMatchesLineSeparators])

        let nsHTML = html as NSString
        let linkMatches = linkRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []
        let snippetMatches = snippetRegex?.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) ?? []

        let maxResults = min(linkMatches.count, 8)
        for i in 0..<maxResults {
            let linkMatch = linkMatches[i]
            let urlStr = nsHTML.substring(with: linkMatch.range(at: 1))
            let rawTitle = nsHTML.substring(with: linkMatch.range(at: 2))

            // Strip HTML tags from title
            let title = rawTitle.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Get snippet if available
            var snippet = ""
            if i < snippetMatches.count {
                let snippetMatch = snippetMatches[i]
                let rawSnippet = nsHTML.substring(with: snippetMatch.range(at: 1))
                snippet = rawSnippet.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Determine source from URL
            let source: String
            if urlStr.contains("winehq.org") {
                source = "winehq"
            } else if urlStr.contains("pcgamingwiki.com") {
                source = "pcgamingwiki"
            } else if urlStr.contains("protondb.com") {
                source = "protondb"
            } else {
                source = "duckduckgo"
            }

            results.append(ResearchResult(source: source, url: urlStr, title: title, snippet: snippet))
        }

        // Save to research cache (single write after all results collected)
        let formatter = ISO8601DateFormatter()
        let cache = ResearchCache(gameId: gameId, fetchedAt: formatter.string(from: Date()), results: results)
        if let cacheData = try? JSONEncoder().encode(cache) {
            try? FileManager.default.createDirectory(at: CellarPaths.researchCacheDir, withIntermediateDirectories: true)
            try? cacheData.write(to: cacheFile)
        }

        let resultDicts: [[String: String]] = results.map { r in
            ["source": r.source, "url": r.url, "title": r.title, "snippet": r.snippet]
        }
        return jsonResult([
            "results": resultDicts,
            "from_cache": false,
            "result_count": results.count,
            "game_id": gameId
        ])
    }

    // MARK: 18. fetch_page

    private func fetchPage(input: JSONValue) -> String {
        guard let urlStr = input["url"]?.asString, !urlStr.isEmpty,
              let pageURL = URL(string: urlStr) else {
            return jsonResult(["error": "url is required and must be a valid URL"])
        }

        // Fetch using DispatchSemaphore + ResultBox pattern
        final class ResultBox: @unchecked Sendable {
            var value: Result<Data, Error> = .failure(URLError(.unknown))
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        var request = URLRequest(url: pageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                box.value = .failure(error)
            } else if let data = data {
                box.value = .success(data)
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()

        guard case .success(let pageData) = box.value,
              let rawHTML = String(data: pageData, encoding: .utf8) ?? String(data: pageData, encoding: .ascii) else {
            let errorMsg: String
            if case .failure(let err) = box.value {
                errorMsg = err.localizedDescription
            } else {
                errorMsg = "Failed to decode page content"
            }
            return jsonResult(["error": "Fetch failed: \(errorMsg)", "url": urlStr])
        }

        // Strip scripts and styles first
        var cleaned = rawHTML
            .replacingOccurrences(of: #"<script[^>]*>[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<style[^>]*>[\s\S]*?</style>"#, with: "", options: .regularExpression)

        // Strip remaining HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode basic HTML entities
        cleaned = cleaned
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")

        // Collapse multiple whitespace/newlines into single spaces
        cleaned = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Truncate to 8000 characters
        let truncated = cleaned.count > 8000
        if truncated {
            cleaned = String(cleaned.prefix(8000))
        }

        return jsonResult([
            "url": urlStr,
            "content": cleaned,
            "length": cleaned.count,
            "truncated": truncated
        ])
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
