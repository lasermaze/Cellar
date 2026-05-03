import Foundation

// MARK: - AgentToolName

/// Typed enum for every agent tool name.
///
/// String-backed so `AgentToolName(rawValue: wireName)` resolves a wire string to a typed case.
/// `CaseIterable` so `AgentToolName.allCases.map { $0.definition }` derives the tool definitions
/// array sent to the LLM — replacing the hand-authored `toolDefinitions` array in AgentTools.
///
/// Each case carries metadata (description, JSON schema, optional pending-action closure) in a
/// private static table so all three concerns stay co-located per tool.
enum AgentToolName: String, CaseIterable {
    case inspectGame       = "inspect_game"
    case readLog           = "read_log"
    case readRegistry      = "read_registry"
    case askUser           = "ask_user"
    case setEnvironment    = "set_environment"
    case setRegistry       = "set_registry"
    case installWinetricks = "install_winetricks"
    case placeDll          = "place_dll"
    case launchGame        = "launch_game"
    case saveRecipe        = "save_recipe"
    case writeGameFile     = "write_game_file"
    case readGameFile      = "read_game_file"
    case querySuccessdb    = "query_successdb"
    case saveSuccess       = "save_success"
    case traceLaunch       = "trace_launch"
    case checkFileAccess   = "check_file_access"
    case verifyDllOverride = "verify_dll_override"
    case searchWeb         = "search_web"
    case fetchPage         = "fetch_page"
    case listWindows       = "list_windows"
    case queryCompatibility = "query_compatibility"
    case queryWiki         = "query_wiki"
    case saveFailure       = "save_failure"
    case updateWiki        = "update_wiki"
}

// MARK: - ToolMetadata

private struct ToolMetadata: @unchecked Sendable {
    let description: String
    let inputSchema: JSONValue
    /// Optional closure that formats a pending-action description from the tool's input.
    /// `nil` for tools that do not track pending actions.
    let pendingAction: (@Sendable (JSONValue) -> String?)?
}

// MARK: - Metadata Table + Accessors

extension AgentToolName {

    /// Look up the JSON schema for a tool from the versioned policy resource.
    /// Falls back to a minimally valid empty-object schema if the tool is absent from the JSON
    /// (which signals a missing entry in tool_schemas.json — should be treated as a build bug).
    private static func schema(for tool: AgentToolName) -> JSONValue {
        PolicyResources.shared.toolSchemas[tool.rawValue]
            ?? .object(["type": .string("object"), "properties": .object([:]), "required": .array([])])
    }

    // swiftlint:disable:next function_body_length
    private static let metadata: [AgentToolName: ToolMetadata] = [

        // 1. inspect_game
        .inspectGame: ToolMetadata(
            description: "Inspect the game setup: executable type (PE32/PE32+), game directory files, bottle state, installed DLLs in system32, and bundled recipe info. Call this first to understand what you're working with.",
            inputSchema: schema(for: .inspectGame),
            pendingAction: nil
        ),

        // 2. read_log
        .readLog: ToolMetadata(
            description: "Read the Wine stderr log from the most recent game launch. Returns the last 8000 characters of the log file. Use this after launch_game to diagnose errors.",
            inputSchema: schema(for: .readLog),
            pendingAction: nil
        ),

        // 3. read_registry
        .readRegistry: ToolMetadata(
            description: "Read Wine registry values directly from user.reg or system.reg. Use key paths like 'HKCU\\\\Software\\\\Wine\\\\DllOverrides'. Returns all values in the matching section, or a specific value if value_name is provided.",
            inputSchema: schema(for: .readRegistry),
            pendingAction: nil
        ),

        // 4. ask_user
        .askUser: ToolMetadata(
            description: "Ask the user a question and return their answer. Use for decisions that require user input — e.g. confirming a potentially destructive action, or gathering info about their game version. Keep questions concise.",
            inputSchema: schema(for: .askUser),
            pendingAction: nil
        ),

        // 5. set_environment
        .setEnvironment: ToolMetadata(
            description: "Set a Wine environment variable for the next launch_game call. Variables accumulate across multiple calls. Common variables: WINEDLLOVERRIDES, WINEFSYNC, WINEESYNC, MESA_GL_VERSION_OVERRIDE, WINEDEBUG.",
            inputSchema: schema(for: .setEnvironment),
            pendingAction: { input in
                guard let key = input["key"]?.asString, let value = input["value"]?.asString else { return nil }
                return "set_environment(\(key)=\(value))"
            }
        ),

        // 6. set_registry
        .setRegistry: ToolMetadata(
            description: "Write a value to the Wine registry via wine regedit. Use for persistent game configuration. Data format: 'dword:00000001', '\"string value\"', 'hex:...'.",
            inputSchema: schema(for: .setRegistry),
            pendingAction: { input in
                guard let keyPath = input["key_path"]?.asString, let name = input["value_name"]?.asString else { return nil }
                return "set_registry(\(keyPath), \(name))"
            }
        ),

        // 7. install_winetricks
        .installWinetricks: ToolMetadata(
            description: "Install a winetricks verb into the game's Wine bottle. Only verbs from the known-safe allowlist are permitted. Use for runtime dependencies like vcrun2019, d3dx9, dotnet48.",
            inputSchema: schema(for: .installWinetricks),
            pendingAction: { input in
                guard let verb = input["verb"]?.asString else { return nil }
                return "install_winetricks(\(verb))"
            }
        ),

        // 8. place_dll
        .placeDll: ToolMetadata(
            description: "Download and place a DLL replacement from the known registry. Targets: game_dir (next to EXE), system32 (Wine System32), syswow64 (Wine SysWOW64 for 32-bit system DLLs in wow64 bottles). If target is omitted, auto-detects based on bottle type and DLL metadata. Auto-applies required WINEDLLOVERRIDES and writes companion config files.",
            inputSchema: schema(for: .placeDll),
            pendingAction: { input in
                guard let dllName = input["dll_name"]?.asString else { return nil }
                return "place_dll(\(dllName))"
            }
        ),

        // 9. launch_game
        .launchGame: ToolMetadata(
            description: "Launch the game with Wine using the currently accumulated environment variables. Runs pre-flight checks (exe exists, DLL files present), returns exit code, elapsed time, stderr tail, detected errors, and loaded DLL summary. Maximum 8 real launches per session. Diagnostic launches (diagnostic=true) do NOT count toward the limit.",
            inputSchema: schema(for: .launchGame),
            pendingAction: nil
        ),

        // 10. save_recipe
        .saveRecipe: ToolMetadata(
            description: "Save the current working configuration as a user recipe file for future launches. Call this when the game launches successfully. The recipe captures the accumulated environment variables.",
            inputSchema: schema(for: .saveRecipe),
            pendingAction: nil
        ),

        // 11. write_game_file
        .writeGameFile: ToolMetadata(
            description: "Write a config or data file into the game directory. Use for files like ddraw.ini, mode.dat, or custom config files the game needs. Paths are relative to the game executable's directory. Windows backslash paths are auto-converted. WARNING: This OVERWRITES the entire file. If modifying an existing config file (e.g. .ini), use check_file_access to verify it exists first, then read it via inspect_game or read_log context. Never write a partial version of an existing config — include ALL original sections/keys plus your changes. A backup is created automatically (.cellar-backup).",
            inputSchema: schema(for: .writeGameFile),
            pendingAction: { input in
                guard let path = input["relative_path"]?.asString else { return nil }
                return "write_game_file(\(path))"
            }
        ),

        // 11b. read_game_file
        .readGameFile: ToolMetadata(
            description: "Read a file from the game directory. Use this BEFORE write_game_file to see the current contents of config files (.ini, .cfg, etc.) so you can make targeted edits without losing existing settings. Returns the file contents (up to 16000 chars). Paths are relative to the game executable's directory.",
            inputSchema: schema(for: .readGameFile),
            pendingAction: nil
        ),

        // 12. trace_launch
        .traceLaunch: ToolMetadata(
            description: "Run a short diagnostic Wine launch with debug channels enabled. The game is killed after timeout_seconds. Returns structured DLL load analysis (which DLLs loaded, from where, native vs builtin), any dialog/msgbox text detected, and errors. Use this BEFORE configuring — trace first, then fix. Does NOT count toward the launch limit.",
            inputSchema: schema(for: .traceLaunch),
            pendingAction: nil
        ),

        // 13. check_file_access
        .checkFileAccess: ToolMetadata(
            description: "Check if the game can find files it needs by verifying file existence relative to the game executable's directory. Use to diagnose 'file not found' errors caused by wrong working directory.",
            inputSchema: schema(for: .checkFileAccess),
            pendingAction: nil
        ),

        // 14. verify_dll_override
        .verifyDllOverride: ToolMetadata(
            description: "Verify that a DLL override is actually working by comparing the configured override (env/registry) with what Wine actually loaded (via a short trace). Explains discrepancies like 'native DLL exists in game_dir but Wine loaded builtin from syswow64'.",
            inputSchema: schema(for: .verifyDllOverride),
            pendingAction: nil
        ),

        // 15. query_successdb
        .querySuccessdb: ToolMetadata(
            description: "Query the local success database for known-working game configurations. Query by game_id (exact), tags (overlap), engine (substring), graphics_api (substring), symptom (fuzzy keyword match against pitfalls), or similar_games (composite multi-signal similarity search). Call this BEFORE web research — local knowledge is faster and more reliable.",
            inputSchema: schema(for: .querySuccessdb),
            pendingAction: nil
        ),

        // 16. save_success
        .saveSuccess: ToolMetadata(
            description: "Record a working configuration after the game launches successfully. REQUIRED: resolution_narrative — concrete prose explaining what you tried, what worked, what didn't, and what you'd try next time. NOT a generic confirmation. Example: \"Set WINEDLLOVERRIDES=ddraw=n,b after dxvk failed; installed dotnet48 to fix vgui2 crash; confirmed menu and first level run at 60fps.\" This narrative becomes the session log future agents read. Generic strings like \"game works\" are rejected by the wiki.",
            inputSchema: schema(for: .saveSuccess),
            pendingAction: nil
        ),

        // 17. search_web
        .searchWeb: ToolMetadata(
            description: "Search the web for game-specific Wine compatibility info. Targets WineHQ, ProtonDB, PCGamingWiki, and forums. Results are cached per game for 7 days. Returns structured snippets, not full pages — use fetch_page to read a specific URL. Call this after checking query_successdb.",
            inputSchema: schema(for: .searchWeb),
            pendingAction: nil
        ),

        // 18. fetch_page
        .fetchPage: ToolMetadata(
            description: "Fetch a URL and extract structured content using SwiftSoup HTML parsing. Returns text_content (up to 8000 chars) plus extracted_fixes containing Wine-specific fix data (env vars, DLL overrides, registry entries, winetricks verbs, INI changes) when detected. Use after search_web to read promising result pages. Specialized parsers for WineHQ AppDB and PCGamingWiki; generic parser for other sites.",
            inputSchema: schema(for: .fetchPage),
            pendingAction: nil
        ),

        // 19. list_windows
        .listWindows: ToolMetadata(
            description: "Query the macOS window list for Wine processes. Returns window sizes, owner process names, and titles (titles require Screen Recording permission). Use after launch_game to check if the game is showing a dialog (small window) or running normally (large window). If Screen Recording permission is denied, returns bounds and owner only with instructions to grant permission.",
            inputSchema: schema(for: .listWindows),
            pendingAction: nil
        ),

        // 20. query_compatibility
        .queryCompatibility: ToolMetadata(
            description: "Query Lutris and ProtonDB community databases for Wine compatibility data on a game. Returns environment variables, DLL overrides, winetricks verbs, registry edits from Lutris installer scripts, and ProtonDB tier rating. Use this for on-demand lookups if compatibility data wasn't in the initial context or you need to check a different game name.",
            inputSchema: schema(for: .queryCompatibility),
            pendingAction: nil
        ),

        // 21. query_wiki
        .queryWiki: ToolMetadata(
            description: "Search the compiled knowledge wiki for Wine compatibility patterns, engine-specific fixes, common symptom solutions, and environment notes. Returns synthesized knowledge pages. Use this when you encounter a specific symptom or engine and want to check accumulated knowledge before trying web research.",
            inputSchema: schema(for: .queryWiki),
            pendingAction: nil
        ),

        // 22. save_failure
        .saveFailure: ToolMetadata(
            description: "Record that you've given up on this session and what you learned. Use this when you cannot find a working configuration after substantive troubleshooting. The entry is added to the shared wiki so future agents skip the dead-ends you already proved don't work. REQUIRED: narrative (what you tried and why it didn't work) and blocking_symptom (the specific failure mode that stopped you). This is more valuable than silently giving up — failure data is rare and high-signal.",
            inputSchema: schema(for: .saveFailure),
            pendingAction: nil
        ),

        // 23. update_wiki
        .updateWiki: ToolMetadata(
            description: "Capture a mid-session observation worth preserving for future agents. Use this for non-obvious findings that you might forget by session end. Examples: 'v-sync off triples cutscene fps on this engine', 'menu music skips when MF dlls present, fine without them', 'native d3d9.dll causes crash on alt-tab specifically'. The note is automatically attached to the session log entry written at session end. Be specific and concrete.",
            inputSchema: schema(for: .updateWiki),
            pendingAction: nil
        )
    ]

    // MARK: - Public Accessors

    /// Build a `ToolDefinition` from this case's metadata. Force-unwrap is safe because the
    /// metadata table is complete (enforced by the debug-init assertion below).
    var definition: ToolDefinition {
        let m = Self.metadata[self]!
        return ToolDefinition(name: rawValue, description: m.description, inputSchema: m.inputSchema)
    }

    /// Return a formatted pending-action description if this tool tracks one.
    /// Returns `nil` for tools that do not update `pendingActions`.
    func pendingActionDescription(for input: JSONValue) -> String? {
        Self.metadata[self]?.pendingAction?(input)
    }

    // MARK: - Debug Completeness Assertion

    #if DEBUG
    /// Verifies every AgentToolName case has a metadata entry.
    /// Catches dictionary gaps that the compiler cannot enforce on a [Enum: Value] literal.
    /// Called from `definition` on every access in DEBUG builds so a missing entry is caught
    /// the first time any tool is resolved, not just at app launch.
    static func assertMetadataComplete() {
        for tool in AgentToolName.allCases {
            assert(
                metadata[tool] != nil,
                "AgentToolName.metadata is missing entry for .\(tool) (\"\(tool.rawValue)\"). Add it to the metadata table."
            )
        }
    }
    #endif
}
