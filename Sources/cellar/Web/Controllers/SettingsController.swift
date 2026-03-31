@preconcurrency import Vapor
import Foundation

enum SettingsController {
    static func register(_ app: Application) throws {
        let settings = app.grouped("settings")

        // GET /settings — render settings page
        settings.get { req async throws -> View in
            let env = loadEnvFile()
            let anthropicKey = env["ANTHROPIC_API_KEY"] ?? ""
            let openaiKey = env["OPENAI_API_KEY"] ?? ""
            let deepseekKey = env["DEEPSEEK_API_KEY"] ?? ""
            let aiProvider = env["AI_PROVIDER"] ?? ""
            let config = CellarConfig.load()
            let contributeMemory = config.contributeMemory ?? false
            let successCount = SuccessDatabase.loadAll().count
            return try await req.view.render("settings", SettingsContext(
                title: "Settings",
                anthropicKey: maskKey(anthropicKey),
                openaiKey: maskKey(openaiKey),
                deepseekKey: maskKey(deepseekKey),
                hasAnthropicKey: !anthropicKey.isEmpty,
                hasOpenaiKey: !openaiKey.isEmpty,
                hasDeepseekKey: !deepseekKey.isEmpty,
                aiProvider: aiProvider,
                contributeMemory: contributeMemory,
                successCount: successCount,
                syncResult: ""
            ))
        }

        // POST /settings/config — update config.json fields
        settings.post("config") { req async throws -> Response in
            let input = try req.content.decode(ConfigInput.self)
            var config = CellarConfig.load()
            if let contribute = input.contributeMemory {
                config.contributeMemory = contribute
            }
            try CellarConfig.save(config)
            return req.redirect(to: "/settings")
        }

        // POST /settings/sync — sync success records to collective memory
        settings.post("sync") { req async throws -> Response in
            let status = DependencyChecker().checkAll()
            guard let wineURL = status.wine else {
                throw Abort(.preconditionFailed, reason: "Wine is not installed")
            }

            let result = CollectiveMemoryWriteService.syncAll(wineURL: wineURL)

            let env = loadEnvFile()
            let anthropicKey = env["ANTHROPIC_API_KEY"] ?? ""
            let openaiKey = env["OPENAI_API_KEY"] ?? ""
            let deepseekKey = env["DEEPSEEK_API_KEY"] ?? ""
            let aiProvider = env["AI_PROVIDER"] ?? ""
            let config = CellarConfig.load()
            let contributeMemory = config.contributeMemory ?? false
            let successCount = SuccessDatabase.loadAll().count

            var message = ""
            if result.synced > 0 { message += "Synced \(result.synced) record(s)." }
            if result.failed > 0 { message += " Failed: \(result.failed)." }
            if result.synced == 0 && result.failed == 0 { message = "All records already synced." }

            return try await req.view.render("settings", SettingsContext(
                title: "Settings",
                anthropicKey: maskKey(anthropicKey),
                openaiKey: maskKey(openaiKey),
                deepseekKey: maskKey(deepseekKey),
                hasAnthropicKey: !anthropicKey.isEmpty,
                hasOpenaiKey: !openaiKey.isEmpty,
                hasDeepseekKey: !deepseekKey.isEmpty,
                aiProvider: aiProvider,
                contributeMemory: contributeMemory,
                successCount: successCount,
                syncResult: message
            )).encodeResponse(for: req)
        }

        // POST /settings/keys — update API keys
        settings.post("keys") { req async throws -> Response in
            let input = try req.content.decode(KeysInput.self)
            var env = loadEnvFile()

            // Only update if the field isn't the masked placeholder
            if let key = input.anthropicKey, !key.isEmpty, !key.contains("••••") {
                env["ANTHROPIC_API_KEY"] = key
            } else if input.anthropicKey?.isEmpty == true {
                env.removeValue(forKey: "ANTHROPIC_API_KEY")
            }

            if let key = input.openaiKey, !key.isEmpty, !key.contains("••••") {
                env["OPENAI_API_KEY"] = key
            } else if input.openaiKey?.isEmpty == true {
                env.removeValue(forKey: "OPENAI_API_KEY")
            }

            if let key = input.deepseekKey, !key.isEmpty, !key.contains("••••") {
                env["DEEPSEEK_API_KEY"] = key
            } else if input.deepseekKey?.isEmpty == true {
                env.removeValue(forKey: "DEEPSEEK_API_KEY")
            }

            if let providerValue = input.aiProvider {
                if providerValue.isEmpty {
                    env.removeValue(forKey: "AI_PROVIDER")  // auto-detect mode
                } else {
                    env["AI_PROVIDER"] = providerValue
                }
            }

            try writeEnvFile(env)
            return req.redirect(to: "/settings")
        }
    }

    // MARK: - .env File Handling

    private static func loadEnvFile() -> [String: String] {
        let envFile = CellarPaths.base.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envFile, encoding: .utf8) else {
            return [:]
        }
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private static func writeEnvFile(_ env: [String: String]) throws {
        let envFile = CellarPaths.base.appendingPathComponent(".env")
        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: CellarPaths.base,
            withIntermediateDirectories: true
        )
        let lines = env.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: envFile, atomically: true, encoding: .utf8)
    }

    private static func maskKey(_ key: String) -> String {
        guard key.count > 8 else { return key.isEmpty ? "" : "••••" }
        let prefix = String(key.prefix(4))
        let suffix = String(key.suffix(4))
        return "\(prefix)••••••••\(suffix)"
    }

    // MARK: - View Models

    struct SettingsContext: Content {
        let title: String
        let anthropicKey: String
        let openaiKey: String
        let deepseekKey: String
        let hasAnthropicKey: Bool
        let hasOpenaiKey: Bool
        let hasDeepseekKey: Bool
        let aiProvider: String  // current value: "claude", "deepseek", or "" (auto-detect)
        let contributeMemory: Bool
        let successCount: Int
        let syncResult: String
    }

    struct KeysInput: Content {
        let anthropicKey: String?
        let openaiKey: String?
        let deepseekKey: String?
        let aiProvider: String?
    }

    struct ConfigInput: Content {
        let contributeMemory: Bool?
    }
}
