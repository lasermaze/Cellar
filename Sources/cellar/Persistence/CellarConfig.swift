import Foundation

/// User configuration loaded from ~/.cellar/config.json or environment.
/// Priority: CELLAR_BUDGET env var > config.json > default ($5.00).
struct CellarConfig: Codable {
    var budgetCeiling: Double
    var aiProvider: String?  // "claude" | "deepseek" | nil (auto-detect)

    enum CodingKeys: String, CodingKey {
        case budgetCeiling = "budget"
        case aiProvider = "ai_provider"
    }

    static let defaultBudgetCeiling: Double = 15.00

    /// Load configuration with priority: env var > config file > default.
    static func load() -> CellarConfig {
        // 1. CELLAR_BUDGET env var overrides everything
        if let envVal = ProcessInfo.processInfo.environment["CELLAR_BUDGET"],
           let val = Double(envVal), val > 0 {
            return CellarConfig(budgetCeiling: val, aiProvider: nil)
        }
        // 2. Read ~/.cellar/config.json
        let configURL = CellarPaths.configFile
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(CellarConfig.self, from: data) {
            return config
        }
        // 3. Default
        return CellarConfig(budgetCeiling: defaultBudgetCeiling, aiProvider: nil)
    }
}
