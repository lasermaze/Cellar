import Foundation

struct AIService {

    // MARK: - Provider Detection

    /// Detect which AI provider is configured via environment variables or ~/.cellar/.env file.
    /// Prefers Anthropic (Claude) if both keys are present.
    static func detectProvider() -> AIProvider {
        let env = loadEnvironment()
        if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            return .anthropic(apiKey: key)
        }
        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            return .openai(apiKey: key)
        }
        return .unavailable
    }

    /// Load environment: process env vars take precedence, then fall back to ~/.cellar/.env file.
    private static func loadEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let envFile = CellarPaths.base.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else {
            return env
        }
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            // Process env takes precedence — only set if not already present
            if env[key] == nil {
                env[key] = value
            }
        }
        return env
    }

    // MARK: - HTTP

    /// Make a synchronous HTTP request using DispatchSemaphore to bridge async URLSession.
    /// Uses URLSession.shared (background delegate queue) to avoid semaphore deadlock.
    private static func callAPI(request: URLRequest) throws -> Data {
        // Use a class box for Swift 6 Sendable compliance — avoids captured-var mutation warning
        final class ResultBox: @unchecked Sendable {
            var value: Result<Data, Error> = .failure(AIServiceError.allRetriesFailed)
        }
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                box.value = .failure(error)
            } else if let data = data {
                let httpResponse = response as? HTTPURLResponse
                if let code = httpResponse?.statusCode, code >= 400 {
                    box.value = .failure(AIServiceError.httpError(statusCode: code))
                } else {
                    box.value = .success(data)
                }
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return try box.value.get()
    }

    // MARK: - Retry

    /// Retry a throwing closure up to maxAttempts times with a 1-second delay between attempts.
    private static func withRetry<T>(maxAttempts: Int = 3, work: () throws -> T) throws -> T {
        var lastError: Error = AIServiceError.allRetriesFailed
        for attempt in 1...maxAttempts {
            do {
                return try work()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: 1.0)
                }
            }
        }
        throw lastError
    }

    // MARK: - Diagnose

    /// Diagnose a Wine failure using AI. Returns a plain-English explanation and optional WineFix.
    /// Returns .unavailable if no API key is configured.
    /// Returns .failed if all retry attempts are exhausted.
    static func diagnose(stderr: String, gameId: String) -> AIResult<AIDiagnosis> {
        let provider = detectProvider()
        if case .unavailable = provider {
            return .unavailable
        }
        return _diagnose(stderr: stderr, gameId: gameId, provider: provider)
    }

    private static func _diagnose(stderr: String, gameId: String, provider: AIProvider) -> AIResult<AIDiagnosis> {
        // Truncate stderr to last 8000 characters (avoid context window overflow)
        let truncatedStderr = String(stderr.suffix(8000))

        let systemPrompt = """
        You are a Wine compatibility expert helping diagnose why a Windows game failed to run on macOS via Wine.

        Analyze the Wine stderr output and return a JSON object with exactly these keys:
        - "explanation": A 2-3 sentence plain English description of what Wine tried to do, why it failed, and what the user can do. Do not use technical jargon or raw error codes.
        - "fix_type": One of: "installWinetricks", "setEnvVar", "setDLLOverride", "none"
        - "fix_arg1": First argument for the fix (winetricks verb, env var name, or DLL name). Empty string if fix_type is "none".
        - "fix_arg2": Second argument for the fix (env var value, or DLL mode like "n,b"). Empty string if fix_type is "none" or "installWinetricks".

        Valid winetricks verbs (only use these exact values): dotnet48, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, vcrun2019, xinput

        Return ONLY the JSON object, no additional text or markdown.

        Example response:
        {"explanation": "Wine could not find a required DirectX 9 component. The game needs d3dx9.dll to render graphics. Installing the DirectX 9 runtime via winetricks should resolve this.", "fix_type": "installWinetricks", "fix_arg1": "d3dx9", "fix_arg2": ""}
        """

        let userMessage = "Game ID: \(gameId)\n\nWine stderr output:\n\(truncatedStderr)"

        do {
            let responseText = try withRetry {
                let data = try makeAPICall(
                    provider: provider,
                    systemPrompt: systemPrompt,
                    userMessage: userMessage
                )
                return data
            }

            return parseDiagnosisResponse(responseText)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func parseDiagnosisResponse(_ text: String) -> AIResult<AIDiagnosis> {
        // Extract JSON from response (strip any surrounding markdown code blocks)
        let cleanedText = extractJSON(from: text)

        guard let data = cleanedText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
            return .failed("Could not parse AI response as JSON")
        }

        guard let explanation = json["explanation"], !explanation.isEmpty else {
            return .failed("AI response missing 'explanation' field")
        }

        let fixType = json["fix_type"] ?? "none"
        let fixArg1 = json["fix_arg1"] ?? ""
        let fixArg2 = json["fix_arg2"] ?? ""

        let suggestedFix = parseWineFix(fixType: fixType, arg1: fixArg1, arg2: fixArg2)

        return .success(AIDiagnosis(explanation: explanation, suggestedFix: suggestedFix))
    }

    // MARK: - Generate Recipe

    /// Generate a Wine recipe for a game using AI. Returns a Recipe struct.
    /// Returns .unavailable if no API key is configured.
    /// Returns .failed if all retry attempts are exhausted or parsing fails.
    static func generateRecipe(gameName: String, gameId: String, installedFiles: [URL]) -> AIResult<Recipe> {
        let provider = detectProvider()
        if case .unavailable = provider {
            return .unavailable
        }
        return _generateRecipe(gameName: gameName, gameId: gameId, installedFiles: installedFiles, provider: provider)
    }

    private static func _generateRecipe(
        gameName: String,
        gameId: String,
        installedFiles: [URL],
        provider: AIProvider
    ) -> AIResult<Recipe> {
        // Filter and cap file list: .exe, .dll (game dir only), .ini, .cfg
        let relevantExtensions = Set(["exe", "dll", "ini", "cfg"])
        let filteredFiles = installedFiles
            .filter { relevantExtensions.contains($0.pathExtension.lowercased()) }
            .prefix(50)
            .map { $0.lastPathComponent }

        let fileList = filteredFiles.joined(separator: "\n")

        let systemPrompt = """
        You are a Wine compatibility expert. Generate a Wine recipe JSON for a Windows game.

        The recipe must be a JSON object with these exact keys (snake_case):
        - "id": string — game identifier (use: \(gameId))
        - "name": string — human-readable game name
        - "version": string — recipe version (use "1.0.0")
        - "source": string — where game files came from (e.g., "gog", "steam", "cd")
        - "executable": string — relative path to the game EXE within the bottle's drive_c (e.g., "GOG Games/GameName/game.exe")
        - "wine_tested_with": string or null — Wine version (use null)
        - "environment": object — Wine environment variables as key-value pairs
        - "registry": array — Wine registry entries, each with "description" (string) and "reg_content" (string in .reg format)
        - "launch_args": array of strings — command-line arguments to pass to the game
        - "notes": string or null — any important compatibility notes
        - "setup_deps": array of strings or null — winetricks verbs needed (e.g., ["vcrun2019"])
        - "install_dir": string or null — expected install directory inside drive_c
        - "retry_variants": array or null — alternative env configs, each with "description" and "environment"

        Valid winetricks verbs: dotnet48, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, vcrun2019, xinput

        Example recipe structure (Cossacks: European Wars):
        {
          "id": "cossacks-european-wars",
          "name": "Cossacks: European Wars",
          "version": "1.0.0",
          "source": "gog",
          "executable": "GOG Games/Cossacks - European Wars/Cossacks.exe",
          "wine_tested_with": null,
          "environment": {"WINEDLLOVERRIDES": "mscoree=n,b", "WINEFSYNC": "1"},
          "registry": [],
          "launch_args": [],
          "notes": "Classic RTS from 2001. Requires wined3d for DirectX 8 rendering.",
          "setup_deps": ["d3dx9"],
          "install_dir": "GOG Games/Cossacks - European Wars",
          "retry_variants": [
            {"description": "Legacy OpenGL mode", "environment": {"MESA_GL_VERSION_OVERRIDE": "3.3"}}
          ]
        }

        Return ONLY the JSON object, no additional text or markdown.
        """

        let userMessage = """
        Game name: \(gameName)
        Game ID: \(gameId)

        Installed files found in the bottle:
        \(fileList.isEmpty ? "(no files detected)" : fileList)

        Generate a Wine recipe for this game.
        """

        do {
            let responseText = try withRetry {
                try makeAPICall(provider: provider, systemPrompt: systemPrompt, userMessage: userMessage)
            }

            return parseRecipeResponse(responseText)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func parseRecipeResponse(_ text: String) -> AIResult<Recipe> {
        let cleanedText = extractJSON(from: text)

        guard let data = cleanedText.data(using: .utf8) else {
            return .failed("Could not convert AI response to data")
        }

        do {
            let decoder = JSONDecoder()
            let recipe = try decoder.decode(Recipe.self, from: data)
            guard !recipe.executable.isEmpty else {
                return .failed("AI-generated recipe has empty 'executable' field")
            }
            return .success(recipe)
        } catch {
            return .failed("Could not decode AI-generated recipe: \(error.localizedDescription)")
        }
    }

    // MARK: - Generate Variants

    /// Generate alternative recipe variants using AI after bundled variants are exhausted.
    /// escalationLevel controls which action types are permitted:
    ///   Level 1: env vars and WINEDLLOVERRIDES only
    ///   Level 2: adds winetricks verbs and DLL overrides
    ///   Level 3: adds place_dll and set_registry actions
    /// Returns .unavailable if no API key is configured.
    static func generateVariants(
        gameId: String,
        gameName: String,
        currentEnvironment: [String: String],
        attemptHistory: [(description: String, envDiff: [String: String], errorSummary: String)],
        escalationLevel: Int = 1
    ) -> AIResult<AIVariantResult> {
        let provider = detectProvider()
        if case .unavailable = provider {
            return .unavailable
        }
        return _generateVariants(
            gameId: gameId, gameName: gameName,
            currentEnvironment: currentEnvironment,
            attemptHistory: attemptHistory,
            escalationLevel: escalationLevel,
            provider: provider
        )
    }

    private static func _generateVariants(
        gameId: String,
        gameName: String,
        currentEnvironment: [String: String],
        attemptHistory: [(description: String, envDiff: [String: String], errorSummary: String)],
        escalationLevel: Int,
        provider: AIProvider
    ) -> AIResult<AIVariantResult> {
        let systemPrompt = buildVariantSystemPrompt(level: escalationLevel)

        // Build user message with game context and attempt history
        var lines: [String] = []
        lines.append("Game ID: \(gameId)")
        lines.append("Game name: \(gameName)")
        lines.append("")
        lines.append("Current base environment:")
        if currentEnvironment.isEmpty {
            lines.append("(none)")
        } else {
            for (key, value) in currentEnvironment.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key)=\(value)")
            }
        }
        lines.append("")
        lines.append("Prior attempts:")
        if attemptHistory.isEmpty {
            lines.append("(none)")
        } else {
            for (index, attempt) in attemptHistory.enumerated() {
                lines.append("Attempt \(index + 1): \(attempt.description)")
                if !attempt.envDiff.isEmpty {
                    let envStr = attempt.envDiff.sorted(by: { $0.key < $1.key })
                        .map { "\($0.key)=\($0.value)" }
                        .joined(separator: ", ")
                    lines.append("  Env diff: \(envStr)")
                }
                // Cap error summary at 500 chars to prevent prompt token explosion
                let cappedError = String(attempt.errorSummary.prefix(500))
                lines.append("  Error: \(cappedError)")
            }
        }
        lines.append("")
        lines.append("Generate up to 3 alternative configurations to try.")
        let userMessage = lines.joined(separator: "\n")

        do {
            let responseText = try withRetry {
                try makeAPICall(provider: provider, systemPrompt: systemPrompt, userMessage: userMessage)
            }

            return parseVariantsResponse(responseText)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Build the system prompt for variant generation based on escalation level.
    /// Level 1: env vars and WINEDLLOVERRIDES only (conservative).
    /// Level 2: adds winetricks + DLL overrides.
    /// Level 3: adds place_dll and set_registry (most powerful).
    private static func buildVariantSystemPrompt(level: Int) -> String {
        let base = """
        You are a Wine compatibility expert generating alternative launch configurations for a Windows game running on macOS via Wine.

        Return a JSON object with exactly these keys:
        - "reasoning": string — 1-2 sentences explaining your analysis of what might be causing the failure
        - "variants": array of up to 3 objects, each with:
          - "description": string — brief label for this variant
          - "environment": object — string key-value pairs of Wine environment variables to set
          - "actions": array of typed action objects (may be empty)

        Each variant should try a meaningfully different approach, not minor tweaks of the same idea.

        Common Wine environment variables to consider:
        WINEDLLOVERRIDES, MESA_GL_VERSION_OVERRIDE, MESA_GLSL_VERSION_OVERRIDE, WINED3D_DISABLE_CSMT,
        STAGING_SHARED_MEMORY, WINE_LARGE_ADDRESS_AWARE, WINEDEBUG, __GL_THREADED_OPTIMIZATIONS,
        DXVK_HUD, WINEFSYNC, WINEESYNC, WINE_CPU_TOPOLOGY

        Return ONLY the JSON object, no additional text or markdown.
        """

        switch level {
        case 1:
            return base + """


        IMPORTANT: At this level you MUST use environment variables and WINEDLLOVERRIDES ONLY.
        Do NOT suggest registry edits. Do NOT suggest winetricks installs. Do NOT suggest DLL downloads.
        All action arrays must be empty [].

        Action format (all empty at this level):
        {"type": "set_env", "key": "...", "value": "..."}
        """
        case 2:
            return base + """


        You may also suggest these additional action types:
        - "install_winetricks" actions with a verb name (e.g., "d3dx9", "vcrun2019", "dsound")
        - "set_dll_override" actions with DLL name and mode

        Return actions as an array of typed objects:
        {"type": "set_env", "key": "...", "value": "..."}
        {"type": "set_dll_override", "dll": "...", "mode": "..."}
        {"type": "install_winetricks", "verb": "..."}

        Valid winetricks verbs (only use these): dotnet48, dotnet40, dotnet35, vcrun2019, vcrun2015, vcrun2013, vcrun2010, vcrun2008, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, dinput8, dinput, quartz, wmp9, wmp10, dsound, xinput, physx, xact, xactengine3_7
        """
        default: // level 3+
            return base + """


        You may suggest all action types including powerful low-level fixes:
        - "place_dll" actions to download and install DLL replacements (e.g., cnc-ddraw for DirectDraw games)
        - "set_registry" actions for Wine registry modifications
        - "set_dll_override" actions for WINEDLLOVERRIDES tweaks
        - "install_winetricks" actions for runtime dependencies

        Known DLL replacements available for auto-download:
        - cnc-ddraw: DirectDraw replacement for classic 2D games (fixes "DirectDraw Init Failed" errors)

        Return actions as typed objects:
        {"type": "set_env", "key": "...", "value": "..."}
        {"type": "set_dll_override", "dll": "...", "mode": "..."}
        {"type": "install_winetricks", "verb": "..."}
        {"type": "place_dll", "dll": "cnc-ddraw", "target": "game_dir"}
        {"type": "set_registry", "key": "HKCU\\\\Software\\\\...", "value_name": "...", "data": "dword:00000001"}

        Valid winetricks verbs (only use these): dotnet48, dotnet40, dotnet35, vcrun2019, vcrun2015, vcrun2013, vcrun2010, vcrun2008, d3dx9, d3dx10, d3dx11_43, d3dcompiler_47, dinput8, dinput, quartz, wmp9, wmp10, dsound, xinput, physx, xact, xactengine3_7
        """
        }
    }

    private static func parseVariantsResponse(_ text: String) -> AIResult<AIVariantResult> {
        let cleanedText = extractJSON(from: text)

        guard let data = cleanedText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .failed("Could not parse AI variants response as JSON")
        }

        let reasoning = json["reasoning"] as? String ?? ""

        guard let variantsArray = json["variants"] as? [[String: Any]], !variantsArray.isEmpty else {
            return .failed("AI variants response missing or empty 'variants' array")
        }

        let variants: [AIVariant] = variantsArray.prefix(3).compactMap { dict in
            guard let description = dict["description"] as? String,
                  let envRaw = dict["environment"] as? [String: Any]
            else { return nil }
            // Cast environment values to String
            var environment: [String: String] = [:]
            for (key, value) in envRaw {
                environment[key] = "\(value)"
            }
            // Parse actions array if present
            var parsedActions: [WineFix] = []
            if let actionsArray = dict["actions"] as? [[String: Any]] {
                parsedActions = actionsArray.compactMap { actionDict in
                    // Cast all values to String for parseWineFix(from:)
                    var stringDict: [String: String] = [:]
                    for (k, v) in actionDict { stringDict[k] = "\(v)" }
                    return parseWineFix(from: stringDict)
                }
            }
            return AIVariant(description: description, environment: environment, actions: parsedActions)
        }

        guard !variants.isEmpty else {
            return .failed("AI variants response contained no valid variant objects")
        }

        return .success(AIVariantResult(variants: variants, reasoning: reasoning))
    }

    // MARK: - Agent Loop

    /// Run the agentic Wine expert loop for a game launch session.
    ///
    /// Requires an Anthropic API key — OpenAI is not supported for the agent loop
    /// because the tool-use API differs significantly.
    ///
    /// Returns:
    ///   - .unavailable if no Anthropic key is configured (or OpenAI-only)
    ///   - .success(summary) when the agent loop completes
    ///   - .failed(message) if an error is thrown during the session
    static func runAgentLoop(
        gameId: String,
        entry: GameEntry,
        executablePath: String,
        wineURL: URL,
        bottleURL: URL,
        wineProcess: WineProcess
    ) -> AIResult<String> {
        let provider = detectProvider()
        guard case .anthropic(let apiKey) = provider else {
            // OpenAI or unavailable — agent loop is Anthropic-only
            return .unavailable
        }

        let systemPrompt = """
        You are a Wine compatibility expert for macOS. Your job is to get a Windows game running via Wine on macOS.

        ## Three-Phase Workflow: Research -> Diagnose -> Adapt

        You can move between phases non-linearly based on evidence.

        ### Phase 1: Research (before first launch)
        1. Call query_successdb to check for known-working configs for this game or similar games
        2. Call inspect_game to understand the game: exe type, PE imports, bottle type, data files, existing config
        3. If no success record found, call search_web to find Wine compatibility info
        4. If search_web returns promising URLs, call fetch_page to read them
        5. Synthesize research into an initial configuration plan

        ### Phase 2: Diagnose (before configuring)
        1. Call trace_launch to see which DLLs Wine actually loads — this is cheap (3-5 seconds)
        2. Call check_file_access if the game uses relative paths or data files
        3. After placing DLLs or setting overrides, call verify_dll_override to confirm they took effect
        4. Budget: up to 3 diagnostic traces before first real launch, 2 between failed real launches

        ### Phase 3: Adapt (configure and launch)
        1. Based on research and diagnosis, configure environment (set_environment), registry (set_registry), DLLs (place_dll), config files (write_game_file)
        2. Call launch_game for a real launch attempt
        3. After launch, call ask_user to check if the game worked
        4. If yes: call save_success with full details including pitfalls and resolution narrative
        5. If no: read_log, diagnose, loop back to Phase 2 for more investigation

        ## macOS + Wine Domain Knowledge
        - NEVER suggest virtual desktop mode (winemac.drv does not support it on macOS)
        - wow64 bottles have drive_c/windows/syswow64 — 32-bit system DLLs (like ddraw.dll from cnc-ddraw) must go in syswow64, NOT system32
        - cnc-ddraw REQUIRES ddraw.ini with renderer=opengl on macOS (macOS has no D3D9)
        - The game's working directory MUST be the EXE's parent directory (many games use relative paths)
        - PE imports (from inspect_game) show the game's actual DLL dependencies — use this to plan configuration
        - DLL override modes: n=native, b=builtin, n,b=prefer native fall back to builtin
        - WINE_CPU_TOPOLOGY=1:0 helps old single-threaded games
        - WINEDEBUG=-all suppresses debug noise for performance
        - If a game exits immediately (< 2 seconds), it likely has a missing dependency or configuration issue
        - Diagnostic methodology: ALWAYS trace before configuring, verify after placing DLLs

        ## Available Tools (18 total)
        Research: query_successdb, search_web, fetch_page
        Diagnostic: inspect_game, trace_launch, verify_dll_override, check_file_access, read_log, read_registry
        Action: set_environment, set_registry, install_winetricks, place_dll, write_game_file, launch_game
        User: ask_user
        Persistence: save_success, save_recipe

        ## Constraints
        - Maximum 8 real launch attempts — be strategic, use diagnostics first
        - Diagnostic launches (trace_launch) are free — use them liberally
        - Only install winetricks verbs from the allowed list
        - Only place DLLs from the known DLL registry
        - All operations are sandboxed to the game's bottle and ~/.cellar/

        ## Communication
        - Explain your reasoning as you go — what you found in research, what the trace revealed, why you're trying a specific fix
        - If you exhaust attempts, write a detailed summary including pitfalls discovered
        """

        let tools = AgentTools(
            gameId: gameId,
            entry: entry,
            executablePath: executablePath,
            bottleURL: bottleURL,
            wineURL: wineURL,
            wineProcess: wineProcess
        )

        let agentLoop = AgentLoop(
            apiKey: apiKey,
            tools: AgentTools.toolDefinitions,
            systemPrompt: systemPrompt,
            model: "claude-sonnet-4-20250514",
            maxIterations: 20,
            maxTokens: 16384
        )

        let initialMessage = "Launch the game '\(entry.name)' (ID: \(gameId)). The executable is at: \(executablePath). Follow the Research-Diagnose-Adapt workflow: start by querying the success database, then inspect the game."

        let result = agentLoop.run(
            initialMessage: initialMessage,
            toolExecutor: { name, input in tools.execute(toolName: name, input: input) }
        )

        if result.completed {
            return .success(result.finalText)
        } else {
            return .failed(result.finalText.isEmpty ? "Agent loop did not complete (used \(result.iterationsUsed) iterations)" : result.finalText)
        }
    }

    // MARK: - One-Time Tip

    /// Show the AI setup tip once if no API key is configured.
    /// Uses a sentinel file to prevent repeated display.
    static func showAITipIfNeeded() {
        let sentinel = CellarPaths.aiTipSentinel
        guard !FileManager.default.fileExists(atPath: sentinel.path) else { return }

        print("Tip: Set ANTHROPIC_API_KEY or OPENAI_API_KEY for AI-powered diagnosis and recipe generation.")

        // Create sentinel file atomically — harmless race condition on concurrent first runs
        let data = Data()
        try? data.write(to: sentinel, options: .withoutOverwriting)
    }

    // MARK: - Private Helpers

    /// Make an API call to the configured provider. Returns raw response text.
    private static func makeAPICall(
        provider: AIProvider,
        systemPrompt: String,
        userMessage: String
    ) throws -> String {
        switch provider {
        case .anthropic(let apiKey):
            return try callAnthropic(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .openai(let apiKey):
            return try callOpenAI(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .unavailable:
            throw AIServiceError.unavailable
        }
    }

    private static func callAnthropic(apiKey: String, systemPrompt: String, userMessage: String) throws -> String {
        let requestBody = AnthropicRequest(
            model: "claude-opus-4-6",
            maxTokens: 1024,
            system: systemPrompt,
            messages: [AnthropicRequest.Message(role: "user", content: userMessage)]
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let responseData = try callAPI(request: request)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: responseData)

        guard let text = response.firstText else {
            throw AIServiceError.decodingError("Anthropic response had no text content")
        }
        return text
    }

    private static func callOpenAI(apiKey: String, systemPrompt: String, userMessage: String) throws -> String {
        let requestBody = OpenAIRequest(
            model: "gpt-4o-mini",
            messages: [
                OpenAIRequest.Message(role: "system", content: systemPrompt),
                OpenAIRequest.Message(role: "user", content: userMessage)
            ],
            responseFormat: OpenAIRequest.ResponseFormat(type: "json_object")
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let responseData = try callAPI(request: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)

        guard let content = response.firstContent else {
            throw AIServiceError.decodingError("OpenAI response had no content")
        }
        return content
    }

    /// Extract JSON object from text, stripping markdown code blocks if present.
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences: ```json ... ``` or ``` ... ```
        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: "\n")
            let stripped = lines.dropFirst().dropLast().joined(separator: "\n")
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Find first { and last } to extract bare JSON
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    /// Expanded winetricks verb allowlist — prevents AI hallucinating invalid verbs.
    private static let validWinetricksVerbs: Set<String> = [
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

    /// Map AI fix_type + args to WineFix enum. Validates winetricks verbs against known-safe list.
    /// Used by diagnose() response parser (flat key format).
    private static func parseWineFix(fixType: String, arg1: String, arg2: String) -> WineFix? {
        switch fixType {
        case "installWinetricks":
            guard validWinetricksVerbs.contains(arg1) else { return nil }
            return .installWinetricks(arg1)
        case "setEnvVar":
            guard !arg1.isEmpty else { return nil }
            return .setEnvVar(arg1, arg2)
        case "setDLLOverride":
            guard !arg1.isEmpty else { return nil }
            return .setDLLOverride(arg1, arg2.isEmpty ? "n,b" : arg2)
        default:
            return nil
        }
    }

    /// Parse a typed action dict (from AI variants actions array) into a WineFix.
    /// Dict keys depend on type: type, key/value (set_env), dll/mode (set_dll_override),
    /// verb (install_winetricks), dll/target (place_dll), key/value_name/data (set_registry).
    static func parseWineFix(from dict: [String: String]) -> WineFix? {
        guard let type = dict["type"] else { return nil }
        switch type {
        case "set_env":
            guard let key = dict["key"], !key.isEmpty,
                  let value = dict["value"]
            else { return nil }
            return .setEnvVar(key, value)
        case "set_dll_override":
            guard let dll = dict["dll"], !dll.isEmpty else { return nil }
            let mode = dict["mode"] ?? "n,b"
            return .setDLLOverride(dll, mode.isEmpty ? "n,b" : mode)
        case "install_winetricks":
            guard let verb = dict["verb"], !verb.isEmpty else { return nil }
            guard validWinetricksVerbs.contains(verb) else {
                print("Warning: AI suggested winetricks verb '\(verb)' which is not in our known list — skipping.")
                return nil
            }
            return .installWinetricks(verb)
        case "place_dll":
            guard let dllName = dict["dll"], !dllName.isEmpty else { return nil }
            let target: DLLPlacementTarget
            switch dict["target"] {
            case "system32": target = .system32
            case "syswow64": target = .syswow64
            default: target = .gameDir
            }
            return .placeDLL(dllName, target)
        case "set_registry":
            guard let key = dict["key"], !key.isEmpty,
                  let valueName = dict["value_name"] ?? dict["valueName"],
                  let data = dict["data"]
            else { return nil }
            return .setRegistry(key, valueName, data)
        default:
            return nil
        }
    }
}
