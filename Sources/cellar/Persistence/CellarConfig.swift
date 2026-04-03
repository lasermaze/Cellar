import Foundation

/// User configuration loaded from ~/.cellar/config.json or environment.
/// Priority: CELLAR_BUDGET env var > config.json > default ($5.00).
struct CellarConfig: Codable {
    var budgetCeiling: Double
    var aiProvider: String?  // "claude" | "deepseek" | "kimi" | nil (auto-detect)
    var aiModel: String?     // e.g. "claude-sonnet-4-6", "deepseek-reasoner", "moonshot-v1-32k"
    /// Opt-in to contribute working configs to collective memory.
    /// nil = not asked yet, true = opted in, false = declined.
    var contributeMemory: Bool?

    enum CodingKeys: String, CodingKey {
        case budgetCeiling = "budget"
        case aiProvider = "ai_provider"
        case aiModel = "ai_model"
        case contributeMemory = "contribute_memory"
    }

    static let defaultBudgetCeiling: Double = 15.00

    /// Load configuration with priority: env var > config file > default.
    static func load() -> CellarConfig {
        // 1. CELLAR_BUDGET env var overrides everything
        if let envVal = ProcessInfo.processInfo.environment["CELLAR_BUDGET"],
           let val = Double(envVal), val > 0 {
            return CellarConfig(budgetCeiling: val, aiProvider: nil, aiModel: nil, contributeMemory: nil)
        }
        // 2. Read ~/.cellar/config.json
        let configURL = CellarPaths.configFile
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(CellarConfig.self, from: data) {
            return config
        }
        // 3. Default
        return CellarConfig(budgetCeiling: defaultBudgetCeiling, aiProvider: nil, aiModel: nil, contributeMemory: nil)
    }

    /// Persist this config to ~/.cellar/config.json atomically.
    static func save(_ config: CellarConfig) throws {
        try FileManager.default.createDirectory(
            at: CellarPaths.base,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: CellarPaths.configFile, options: .atomic)
    }
}
