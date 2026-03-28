import Foundation

// MARK: - AgentTools

/// Container for all 10 agent tool implementations.
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

    /// JSON Schema tool definitions for all 10 agent tools.
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
            description: "Download and place a DLL replacement from the known registry. Currently available: cnc-ddraw (DirectDraw replacement for classic 2D games). Auto-applies required WINEDLLOVERRIDES.",
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
                        "description": .string("Placement target: game_dir (next to EXE, default), system32 (Wine virtual System32), or syswow64 (32-bit system DLLs in wow64 bottles)")
                    ])
                ]),
                "required": .array([.string("dll_name")])
            ])
        ),

        // 9. launch_game — optional extra_winedebug
        ToolDefinition(
            name: "launch_game",
            description: "Launch the game with Wine using the currently accumulated environment variables. Returns exit code, elapsed time, stderr tail, and detected errors. Maximum 8 launches per session.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "extra_winedebug": .object([
                        "type": .string("string"),
                        "description": .string("Optional additional WINEDEBUG channels (e.g. +d3d,+opengl). Merged with existing WINEDEBUG.")
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

        var result: [String: Any] = [
            "exe_type": exeType,
            "game_files": gameFiles,
            "bottle_exists": bottleExists,
            "system32_dlls": system32DLLs
        ]
        if !recipeInfo.isEmpty {
            result["recipe"] = recipeInfo
        } else {
            result["recipe"] = NSNull()
        }
        return jsonResult(result)
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
        let targetParam = input["target"]?.asString ?? "game_dir"

        guard let knownDLL = KnownDLLRegistry.find(name: dllName) else {
            let available = KnownDLLRegistry.registry.map { $0.name }.joined(separator: ", ")
            return jsonResult([
                "error": "DLL '\(dllName)' is not in the known DLL registry. The user should place it manually. Available DLLs: \(available)"
            ])
        }

        // Determine target directory
        let targetDir: URL
        if targetParam == "system32" {
            targetDir = bottleURL
                .appendingPathComponent("drive_c")
                .appendingPathComponent("windows")
                .appendingPathComponent("system32")
        } else if targetParam == "syswow64" {
            targetDir = bottleURL
                .appendingPathComponent("drive_c")
                .appendingPathComponent("windows")
                .appendingPathComponent("syswow64")
        } else {
            targetDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        }

        do {
            print("Downloading \(knownDLL.name) from GitHub...")
            let cachedDLL = try DLLDownloader.downloadAndCache(knownDLL)
            let placedDLL = try DLLDownloader.place(cachedDLL: cachedDLL, into: targetDir)
            print("Placed \(placedDLL.lastPathComponent) in \(targetDir.path)")

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
                "applied_overrides": appliedOverrides
            ])
        } catch {
            return jsonResult(["error": "Failed to download/place \(dllName): \(error.localizedDescription)"])
        }
    }

    // MARK: - Execution Tools

    // MARK: 9. launch_game

    private func launchGame(input: JSONValue) -> String {
        // Enforce max launch limit
        if launchCount >= maxLaunches {
            return jsonResult([
                "error": "Maximum launches (\(maxLaunches)) reached for this session. Save a recipe if you found a working configuration.",
                "launch_number": launchCount
            ])
        }

        launchCount += 1
        let thisLaunchNumber = launchCount

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

        print("\n[Agent launch \(thisLaunchNumber)/\(maxLaunches)] Starting game...")

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
                "launch_number": thisLaunchNumber
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

        let stderrTail = String(result.stderr.suffix(4000))

        return jsonResult([
            "exit_code": Int(result.exitCode),
            "elapsed_seconds": result.elapsed,
            "timed_out": result.timedOut,
            "stderr_tail": stderrTail,
            "detected_errors": errorDicts,
            "log_file": logFile.path,
            "launch_number": thisLaunchNumber
        ])
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
