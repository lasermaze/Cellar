import Foundation

struct AIService {

    // MARK: - Provider Detection

    /// Detect which AI provider is configured via environment variables.
    /// Prefers Anthropic (Claude) if both keys are present.
    static func detectProvider() -> AIProvider {
        let env = ProcessInfo.processInfo.environment
        if let key = env["ANTHROPIC_API_KEY"], !key.isEmpty {
            return .anthropic(apiKey: key)
        }
        if let key = env["OPENAI_API_KEY"], !key.isEmpty {
            return .openai(apiKey: key)
        }
        return .unavailable
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
            model: "claude-haiku-4-5",
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

    /// Map AI fix_type + args to WineFix enum. Validates winetricks verbs against known-safe list.
    private static func parseWineFix(fixType: String, arg1: String, arg2: String) -> WineFix? {
        // Valid winetricks verbs — prevents hallucinated verb names
        let validWinetricksVerbs: Set<String> = [
            "dotnet48", "d3dx9", "d3dx10", "d3dx11_43",
            "d3dcompiler_47", "vcrun2019", "xinput"
        ]

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
}
