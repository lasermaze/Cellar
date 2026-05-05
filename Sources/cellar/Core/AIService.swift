import Foundation

struct AIService {

    // MARK: - Available Models per Provider

    struct ModelOption: Codable {
        let id: String
        let label: String
    }

    /// Fallback models when API fetch fails. Derived from ModelCatalog — single source of truth.
    /// First entry per provider is the default. Provider key strings match modelEndpoints keys.
    static var fallbackModels: [String: [ModelOption]] {
        var result: [String: [ModelOption]] = ["claude": [], "deepseek": [], "kimi": []]
        for descriptor in ModelCatalog.all {
            switch descriptor.provider {
            case .anthropic:
                result["claude"]!.append(ModelOption(id: descriptor.id, label: descriptor.id))
            case .deepseek:
                result["deepseek"]!.append(ModelOption(id: descriptor.id, label: descriptor.id))
            case .kimi:
                result["kimi"]!.append(ModelOption(id: descriptor.id, label: descriptor.id))
            }
        }
        return result
    }

    /// Provider API endpoints for listing models.
    private static let modelEndpoints: [String: (url: String, keyEnv: String)] = [
        "claude": ("https://api.anthropic.com/v1/models", "ANTHROPIC_API_KEY"),
        "deepseek": ("https://api.deepseek.com/v1/models", "DEEPSEEK_API_KEY"),
        "kimi": ("https://api.moonshot.ai/v1/models", "KIMI_API_KEY"),
    ]

    /// Fetch available models from provider APIs. Falls back to hardcoded list per provider on failure.
    /// Only fetches for providers that have a configured API key.
    static func fetchAvailableModels() async -> [String: [ModelOption]] {
        let env = loadEnvironment()
        var result: [String: [ModelOption]] = [:]

        for (provider, endpoint) in modelEndpoints {
            guard let apiKey = env[endpoint.keyEnv], !apiKey.isEmpty else {
                // No key — use fallback
                result[provider] = fallbackModels[provider] ?? []
                continue
            }

            do {
                var request = URLRequest(url: URL(string: endpoint.url)!)
                request.timeoutInterval = 5
                if provider == "claude" {
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                } else {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    result[provider] = fallbackModels[provider] ?? []
                    continue
                }

                let models = parseModelsResponse(data: data, provider: provider)
                result[provider] = models.isEmpty ? (fallbackModels[provider] ?? []) : models
            } catch {
                result[provider] = fallbackModels[provider] ?? []
            }
        }

        return result
    }

    /// Parse the /models response. Anthropic has a different format than OpenAI-compatible providers.
    private static func parseModelsResponse(data: Data, provider: String) -> [ModelOption] {
        struct OpenAIModelsResponse: Decodable {
            let data: [OpenAIModel]
            struct OpenAIModel: Decodable {
                let id: String
            }
        }
        struct AnthropicModelsResponse: Decodable {
            let data: [AnthropicModel]
            struct AnthropicModel: Decodable {
                let id: String
                let displayName: String?
                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                }
            }
        }

        if provider == "claude" {
            guard let parsed = try? JSONDecoder().decode(AnthropicModelsResponse.self, from: data) else { return [] }
            return parsed.data
                .sorted { $0.id > $1.id }  // newest first
                .map { ModelOption(id: $0.id, label: $0.displayName ?? $0.id) }
        } else {
            guard let parsed = try? JSONDecoder().decode(OpenAIModelsResponse.self, from: data) else { return [] }
            return parsed.data
                .sorted { $0.id < $1.id }
                .map { ModelOption(id: $0.id, label: $0.id) }
        }
    }

    /// Resolve the model to use for a given provider key.
    /// Priority: config.json ai_model > AI_MODEL env var > provider default.
    static func resolveModel(for providerKey: String) -> String {
        let config = CellarConfig.load()
        let env = loadEnvironment()

        // Check config or env for explicit model
        if let model = config.aiModel ?? env["AI_MODEL"], !model.isEmpty {
            return model
        }

        // Default: first model for this provider
        return fallbackModels[providerKey]?.first?.id ?? "claude-sonnet-4-6"
    }

    // MARK: - Provider Detection

    /// Detect which AI provider is configured via environment variables or ~/.cellar/.env file.
    /// Respects AI_PROVIDER config/env var. Auto-detects from available keys if not set.
    static func detectProvider() -> AIProvider {
        let env = loadEnvironment()
        let configProvider = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]

        switch configProvider?.lowercased() {
        case "deepseek":
            if let key = env["DEEPSEEK_API_KEY"], !key.isEmpty { return .deepseek(apiKey: key) }
            return .unavailable  // Deepseek requested but no key
        case "claude", "anthropic":
            if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty { return .anthropic(apiKey: key) }
            return .unavailable  // Claude requested but no key
        case "kimi", "moonshot":
            if let key = env["KIMI_API_KEY"], !key.isEmpty { return .kimi(apiKey: key) }
            return .unavailable  // Kimi requested but no key
        default:
            // Auto-detect: check which keys are present
            let hasAnthropic = env["ANTHROPIC_API_KEY"].map { !$0.isEmpty } ?? false
            let hasDeepseek = env["DEEPSEEK_API_KEY"].map { !$0.isEmpty } ?? false
            let hasKimi = env["KIMI_API_KEY"].map { !$0.isEmpty } ?? false
            if hasAnthropic { return .anthropic(apiKey: env["ANTHROPIC_API_KEY"]!) }
            if hasDeepseek { return .deepseek(apiKey: env["DEEPSEEK_API_KEY"]!) }
            if hasKimi { return .kimi(apiKey: env["KIMI_API_KEY"]!) }
            // Legacy: check OpenAI key
            if let key = env["OPENAI_API_KEY"], !key.isEmpty { return .openai(apiKey: key) }
            return .unavailable
        }
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

    /// Async HTTP call using URLSession.data(for:).
    private static func callAPI(request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.allRetriesFailed
        }
        if http.statusCode >= 400 {
            throw AIServiceError.httpError(statusCode: http.statusCode)
        }
        return data
    }

    // MARK: - Retry

    /// Retry a throwing closure up to maxAttempts times with a 1-second delay between attempts.
    private static func withRetry<T>(maxAttempts: Int = 3, work: () async throws -> T) async throws -> T {
        var lastError: Error = AIServiceError.allRetriesFailed
        for attempt in 1...maxAttempts {
            do {
                return try await work()
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }
        throw lastError
    }

    // MARK: - Diagnose

    /// Diagnose a Wine failure using AI. Returns a plain-English explanation and optional WineFix.
    /// Returns .unavailable if no API key is configured.
    /// Returns .failed if all retry attempts are exhausted.
    static func diagnose(stderr: String, gameId: String) async -> AIResult<AIDiagnosis> {
        let provider = detectProvider()
        if case .unavailable = provider {
            let env = loadEnvironment()
            let requested = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]
            if requested?.lowercased() == "deepseek" {
                return .failed("Deepseek API key not configured. Set DEEPSEEK_API_KEY in ~/.cellar/.env or environment.")
            } else if requested?.lowercased() == "kimi" || requested?.lowercased() == "moonshot" {
                return .failed("Kimi API key not configured. Set KIMI_API_KEY in ~/.cellar/.env or environment.")
            } else if requested != nil {
                return .failed("Anthropic API key not configured. Set ANTHROPIC_API_KEY in ~/.cellar/.env or environment.")
            }
            return .unavailable
        }
        return await _diagnose(stderr: stderr, gameId: gameId, provider: provider)
    }

    private static func _diagnose(stderr: String, gameId: String, provider: AIProvider) async -> AIResult<AIDiagnosis> {
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
            let responseText = try await withRetry {
                let data = try await makeAPICall(
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
    static func generateRecipe(gameName: String, gameId: String, installedFiles: [URL]) async -> AIResult<Recipe> {
        let provider = detectProvider()
        if case .unavailable = provider {
            let env = loadEnvironment()
            let requested = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]
            if requested?.lowercased() == "deepseek" {
                return .failed("Deepseek API key not configured. Set DEEPSEEK_API_KEY in ~/.cellar/.env or environment.")
            } else if requested?.lowercased() == "kimi" || requested?.lowercased() == "moonshot" {
                return .failed("Kimi API key not configured. Set KIMI_API_KEY in ~/.cellar/.env or environment.")
            } else if requested != nil {
                return .failed("Anthropic API key not configured. Set ANTHROPIC_API_KEY in ~/.cellar/.env or environment.")
            }
            return .unavailable
        }
        return await _generateRecipe(gameName: gameName, gameId: gameId, installedFiles: installedFiles, provider: provider)
    }

    private static func _generateRecipe(
        gameName: String,
        gameId: String,
        installedFiles: [URL],
        provider: AIProvider
    ) async -> AIResult<Recipe> {
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
            let responseText = try await withRetry {
                try await makeAPICall(provider: provider, systemPrompt: systemPrompt, userMessage: userMessage)
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
    ) async -> AIResult<AIVariantResult> {
        let provider = detectProvider()
        if case .unavailable = provider {
            let env = loadEnvironment()
            let requested = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]
            if requested?.lowercased() == "deepseek" {
                return .failed("Deepseek API key not configured. Set DEEPSEEK_API_KEY in ~/.cellar/.env or environment.")
            } else if requested?.lowercased() == "kimi" || requested?.lowercased() == "moonshot" {
                return .failed("Kimi API key not configured. Set KIMI_API_KEY in ~/.cellar/.env or environment.")
            } else if requested != nil {
                return .failed("Anthropic API key not configured. Set ANTHROPIC_API_KEY in ~/.cellar/.env or environment.")
            }
            return .unavailable
        }
        return await _generateVariants(
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
    ) async -> AIResult<AIVariantResult> {
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
            let responseText = try await withRetry {
                try await makeAPICall(provider: provider, systemPrompt: systemPrompt, userMessage: userMessage)
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
    /// Supports Anthropic (Claude) and Deepseek providers. OpenAI is not supported for the
    /// agent loop because the tool-use API differs significantly.
    ///
    /// Returns:
    ///   - .unavailable if no supported key is configured (or OpenAI-only)
    ///   - .success(summary) when the agent loop completes
    ///   - .failed(message) if an error is thrown during the session
    static func runAgentLoop(
        gameId: String,
        entry: GameEntry,
        executablePath: String,
        wineURL: URL,
        bottleURL: URL,
        wineProcess: WineProcess,
        onOutput: (@Sendable (AgentEvent) -> Void)? = nil,
        askUserHandler: (@Sendable (_ question: String, _ options: [String]?) -> String)? = nil,
        onToolsCreated: ((AgentTools, AgentControl) -> Void)? = nil
    ) async -> AIResult<String> {
        // Validate provider before building prompts
        let provider = detectProvider()
        switch provider {
        case .unavailable:
            let env = loadEnvironment()
            let requested = CellarConfig.load().aiProvider ?? env["AI_PROVIDER"]
            if requested?.lowercased() == "deepseek" {
                return .failed("Deepseek API key not configured. Set DEEPSEEK_API_KEY in ~/.cellar/.env or environment.")
            } else if requested?.lowercased() == "kimi" || requested?.lowercased() == "moonshot" {
                return .failed("Kimi API key not configured. Set KIMI_API_KEY in ~/.cellar/.env or environment.")
            } else if requested != nil {
                return .failed("Anthropic API key not configured. Set ANTHROPIC_API_KEY in ~/.cellar/.env or environment.")
            }
            return .unavailable
        case .openai:
            return .unavailable
        default:
            break
        }

        // Register KnowledgeStoreRemote once at session start (idempotent guard).
        if KnowledgeStoreContainer.shared is NoOpKnowledgeStore {
            KnowledgeStoreContainer.shared = KnowledgeStoreRemote()
        }

        let systemPrompt = PolicyResources.shared.systemPrompt

        let tools = AgentTools(config: SessionConfiguration(
            gameId: gameId,
            entry: entry,
            executablePath: executablePath,
            bottleURL: bottleURL,
            wineURL: wineURL,
            wineProcess: wineProcess
        ))
        if let handler = askUserHandler {
            tools.askUserHandler = handler
        }

        // Create thread-safe control channel
        let control = AgentControl()
        tools.control = control

        // Notify caller (LaunchController uses this to register with ActiveAgents)
        onToolsCreated?(tools, control)

        let config = CellarConfig.load()

        // Resolve model descriptor from catalog at session boundary.
        // Unknown model IDs surface a clear error here — no silent (0.0, 0.0) fallback.
        let providerKey: String
        switch provider {
        case .anthropic: providerKey = "claude"
        case .deepseek:  providerKey = "deepseek"
        case .kimi:      providerKey = "kimi"
        default:         return .unavailable
        }
        let resolvedModelID = resolveModel(for: providerKey)
        let descriptor: ModelDescriptor
        do {
            descriptor = try ModelCatalog.descriptor(for: resolvedModelID)
        } catch let error as ModelCatalogError {
            onOutput?(.error(error.localizedDescription))
            return .failed(error.localizedDescription)
        } catch {
            onOutput?(.error(error.localizedDescription))
            return .failed(error.localizedDescription)
        }

        // Create provider with fully built systemPrompt and resolved descriptor.
        // Single AgentProvider construction replaces three-way switch — provider routing is
        // done inside AgentProvider.init via descriptor.provider (ModelProvider enum).
        let apiKey: String
        switch provider {
        case .anthropic(let key): apiKey = key
        case .deepseek(let key):  apiKey = key
        case .kimi(let key):      apiKey = key
        default:                  return .unavailable
        }
        let agentProvider = AgentProvider(
            descriptor: descriptor,
            apiKey: apiKey,
            tools: AgentTools.toolDefinitions,
            systemPrompt: systemPrompt
        )

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

        // Fetch community compatibility data from Lutris + ProtonDB (silent skip on any failure)
        let compatContext = await CompatibilityService.fetchReport(for: entry.name)

        // Prefer event log resume over SessionHandoff (richer context — tool history, env changes, launch outcomes)
        let eventLogResume: String?
        if let previousLog = AgentEventLog.findMostRecent(gameId: gameId) {
            eventLogResume = previousLog.summarizeForResume()
        } else {
            eventLogResume = nil
        }

        // Check for handoff from a previous incomplete session (fallback when no event log)
        let previousSession = SessionHandoff.read(gameId: gameId)
        if previousSession != nil {
            SessionHandoff.delete(gameId: gameId)
        }

        let launchInstruction = "Launch the game '\(entry.name)' (ID: \(gameId)). The executable is at: \(executablePath). Follow the Research-Diagnose-Adapt workflow: start by querying the success database and wiki, then inspect the game. Move quickly to a real launch_game call — research and at most one trace_launch before your first real launch."

        var contextParts: [String] = []
        // Rewired: unified read path through KnowledgeStoreContainer.shared (Plan 04)
        let knowledgeEnv = EnvironmentFingerprint.current(
            wineVersion: CollectiveMemoryService.detectWineVersionInternal(wineURL: wineURL) ?? "",
            wineFlavor: CollectiveMemoryService.detectWineFlavorInternal(wineURL: wineURL)
        )
        if let knowledgeContext = await KnowledgeStoreContainer.shared.fetchContext(for: entry.name, environment: knowledgeEnv) {
            contextParts.append(knowledgeContext)
        }
        if let compatReport = compatContext {
            contextParts.append(compatReport.formatForAgent())
        }
        if let eventLogResume = eventLogResume {
            contextParts.append(eventLogResume)
        } else if let previousSession = previousSession {
            contextParts.append(previousSession.formatForAgent())
        }
        if eventLogResume == nil && previousSession == nil,
           let diagRecord = DiagnosticRecord.readLatest(gameId: gameId) {
            contextParts.append(diagRecord.formatForAgent())
        }
        contextParts.append(launchInstruction)
        let initialMessage = contextParts.joined(separator: "\n\n")

        let sessionStartTime = Date()
        // Purge stale draft files older than 7 days (bounded cost, best-effort)
        SessionDraftBuffer.purgeOldDrafts()
        let result = await agentLoop.run(
            initialMessage: initialMessage,
            toolExecutor: { name, input in await tools.execute(toolName: name, input: input) },
            control: control,
            middlewareContext: mwContext
        )

        // ── POST-LOOP SAVE (the critical fix — BUG-01) ──
        // Runs with await. No fire-and-forget. No race condition.
        // Save on: user clicked confirm, OR user clicked confirm late (after loop exited with .completed)
        var didSave = false
        let shouldSave: Bool
        if case .userConfirmed = result.stopReason {
            shouldSave = true
        } else if control.userForceConfirmed {
            // User clicked "Game Works" after the agent naturally completed
            shouldSave = true
        } else {
            shouldSave = false
        }

        if shouldSave {
            let saveInput: JSONValue = .object([
                "game_name": .string(entry.name)
                // resolution_narrative intentionally omitted: the agent's own save_success call (if any)
                // owns this field. Post-loop save is a safety net for user-confirmed completions.
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
        let isCompleted: Bool
        if case .completed = result.stopReason { isCompleted = true } else { isCompleted = false }
        let isSuccess = isCompleted || didSave
        if isSuccess {
            if didSave {
                await handleContributionIfNeeded(
                    tools: tools, gameName: entry.name,
                    wineURL: wineURL, isWebContext: askUserHandler != nil
                )
                // Rewired: write success knowledge through KnowledgeStoreContainer.shared (Plan 04)
                if let record = SuccessDatabase.load(gameId: gameId) {
                    // Game page (was WikiService.ingest)
                    if let gamePage = WikiService.buildIngestedGamePage(record: record) {
                        await KnowledgeStoreContainer.shared.write(.gamePage(gamePage))
                    }
                    // Session log (was WikiService.postSessionLog)
                    let sessionEntry = SessionLogEntry(
                        path: WikiService.sessionLogFilename(record: record),
                        body: WikiService.formatSuccessSessionBody(
                            record: record,
                            duration: Date().timeIntervalSince(sessionStartTime),
                            wineURL: wineURL,
                            midSessionNotes: tools.draftBuffer.notes
                        ),
                        commitMessage: "session: success for \(record.gameName)"
                    )
                    await KnowledgeStoreContainer.shared.write(.sessionLog(sessionEntry))
                    // Clear the on-disk draft after successful session log write
                    tools.draftBuffer.clearDraft()
                    // Config (was CollectiveMemoryWriteService.push — called by handleContributionIfNeeded above)
                    // Note: contribution push is handled via handleContributionIfNeeded; this is the unified store path
                }
            }
            SessionHandoff.delete(gameId: gameId)
            // Clean up event log on successful session (no stale logs accumulating)
            if let oldLog = AgentEventLog.findMostRecent(gameId: gameId) {
                try? FileManager.default.removeItem(at: oldLog.url)
            }
            return .success(result.finalText)
        } else if case .userAborted = result.stopReason {
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

            // Phase 41: deposit failure session log if substantive material exists
            let trimmedFinal = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasMaterial =
                !tools.pendingActions.isEmpty ||
                !tools.lastAppliedActions.isEmpty ||
                tools.launchCount > 0 ||
                tools.hasSubstantiveFailure ||
                trimmedFinal.count >= 80
            if hasMaterial {
                let actions = Array(Set(tools.pendingActions + tools.lastAppliedActions))
                // Rewired: failure session log through KnowledgeStoreContainer.shared (Plan 04)
                let failureEntry = SessionLogEntry(
                    path: WikiService.failureSessionLogFilename(gameId: gameId),
                    body: WikiService.formatFailureSessionBody(
                        gameId: gameId,
                        gameName: entry.name,
                        narrative: trimmedFinal,
                        actionsAttempted: actions,
                        launchCount: tools.launchCount,
                        duration: Date().timeIntervalSince(sessionStartTime),
                        wineURL: wineURL,
                        stopReason: stopReasonStr,
                        midSessionNotes: tools.draftBuffer.notes
                    ),
                    commitMessage: "session: failure for \(entry.name)"
                )
                await KnowledgeStoreContainer.shared.write(.sessionLog(failureEntry))
                // Failure path: keep the draft on disk for inspection. Do NOT clearDraft().
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
    }

    // MARK: - Internal Test Seam (Plan 04)

    /// Fetch knowledge context for a game using the active KnowledgeStoreContainer.shared.
    /// Extracted as an `internal` helper to enable integration tests without running the full agent loop.
    internal static func fetchKnowledgeContext(gameName: String, wineURL: URL) async -> String? {
        let env = EnvironmentFingerprint.current(
            wineVersion: CollectiveMemoryService.detectWineVersionInternal(wineURL: wineURL) ?? "",
            wineFlavor: CollectiveMemoryService.detectWineFlavorInternal(wineURL: wineURL)
        )
        return await KnowledgeStoreContainer.shared.fetchContext(for: gameName, environment: env)
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

    // MARK: - Collective Memory Contribution

    /// Handle opt-in prompt and push to collective memory after a successful agent session.
    ///
    /// - For CLI (no askUserHandler): shows a yes/no prompt on first push opportunity.
    /// - For web (askUserHandler provided): skips the readLine prompt; pushes if already opted in.
    /// - Saves the user's preference to CellarConfig.
    private static func handleContributionIfNeeded(
        tools: AgentTools,
        gameName: String,
        wineURL: URL,
        isWebContext: Bool
    ) async {
        // Called only when post-loop save completed successfully

        var config = CellarConfig.load()

        if config.contributeMemory == nil {
            // Never asked — show prompt for CLI only (web uses settings toggle)
            if !isWebContext {
                print("\nShare this working config with the Cellar community?")
                print("Other users will benefit when setting up this game. [y/N]: ", terminator: "")
                fflush(stdout)
                let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
                let opted = (input == "y" || input == "yes")
                config.contributeMemory = opted
                try? CellarConfig.save(config)
                if !opted { return }
            } else {
                // Web context: auto-opt-in on first success; user can disable in Settings
                config.contributeMemory = true
                try? CellarConfig.save(config)
            }
        }

        guard config.contributeMemory == true else { return }

        // Load the just-saved SuccessRecord and push
        // Rewired: config write through KnowledgeStoreContainer.shared (Plan 04)
        guard let record = SuccessDatabase.load(gameId: tools.config.gameId) else { return }
        if let cfgEntry = CollectiveMemoryWriteService.buildConfigEntry(record: record, gameName: gameName, wineURL: wineURL) {
            await KnowledgeStoreContainer.shared.write(.config(cfgEntry))
        }
    }

    // MARK: - Private Helpers

    /// Make an API call to the configured provider. Returns raw response text.
    private static func makeAPICall(
        provider: AIProvider,
        systemPrompt: String,
        userMessage: String
    ) async throws -> String {
        switch provider {
        case .anthropic(let apiKey):
            return try await callAnthropic(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .openai(let apiKey):
            return try await callOpenAI(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .deepseek(let apiKey):
            return try await callDeepseek(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .kimi(let apiKey):
            return try await callKimi(apiKey: apiKey, systemPrompt: systemPrompt, userMessage: userMessage)
        case .unavailable:
            throw AIServiceError.unavailable
        }
    }

    private static func callKimi(apiKey: String, systemPrompt: String, userMessage: String) async throws -> String {
        let requestBody = OpenAIRequest(
            model: resolveModel(for: "kimi"),
            messages: [
                OpenAIRequest.Message(role: "system", content: systemPrompt),
                OpenAIRequest.Message(role: "user", content: userMessage)
            ],
            responseFormat: OpenAIRequest.ResponseFormat(type: "json_object")
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: URL(string: "https://api.moonshot.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let responseData = try await callAPI(request: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)

        guard let content = response.firstContent else {
            throw AIServiceError.decodingError("Kimi response had no content")
        }
        return content
    }

    private static func callDeepseek(apiKey: String, systemPrompt: String, userMessage: String) async throws -> String {
        let requestBody = OpenAIRequest(
            model: resolveModel(for: "deepseek"),
            messages: [
                OpenAIRequest.Message(role: "system", content: systemPrompt),
                OpenAIRequest.Message(role: "user", content: userMessage)
            ],
            responseFormat: OpenAIRequest.ResponseFormat(type: "json_object")
        )

        let encoder = JSONEncoder()
        let bodyData = try encoder.encode(requestBody)

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = bodyData

        let responseData = try await callAPI(request: request)
        let response = try JSONDecoder().decode(OpenAIResponse.self, from: responseData)

        guard let content = response.firstContent else {
            throw AIServiceError.decodingError("Deepseek response had no content")
        }
        return content
    }

    private static func callAnthropic(apiKey: String, systemPrompt: String, userMessage: String) async throws -> String {
        let requestBody = AnthropicRequest(
            model: resolveModel(for: "claude"),
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

        let responseData = try await callAPI(request: request)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: responseData)

        guard let text = response.firstText else {
            throw AIServiceError.decodingError("Anthropic response had no text content")
        }
        return text
    }

    private static func callOpenAI(apiKey: String, systemPrompt: String, userMessage: String) async throws -> String {
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

        let responseData = try await callAPI(request: request)
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
