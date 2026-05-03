import Foundation

// MARK: - ModelProvider

/// Provider discriminant without associated values — used inside ModelDescriptor.
/// Distinct from AIProvider (which carries an API key as associated value and is used
/// for live provider selection). ModelProvider is the catalog identifier only.
enum ModelProvider: String, Sendable, Equatable {
    case anthropic
    case deepseek
    case kimi
}

// MARK: - ModelDescriptor

/// Static description of a single model: its identity, provider, pricing, and output limit.
/// Lean by design — no displayLabel, no contextWindow, no supportsToolUse flag.
struct ModelDescriptor: Sendable {
    let id: String
    let provider: ModelProvider
    let inputPricePerToken: Double
    let outputPricePerToken: Double
    let maxOutputTokens: Int
}

// MARK: - ModelCatalog

/// Single source of truth for all supported models and their pricing.
///
/// Pricing values (USD per token) originally sourced from the per-provider modelPricing dict.
/// Verify against provider pricing pages before each release.
/// deepseek-reasoner intentionally absent — it does not support function calling (Phase 18).
enum ModelCatalog {

    static let all: [ModelDescriptor] = [
        // MARK: Anthropic — Claude models
        ModelDescriptor(
            id: "claude-sonnet-4-6",
            provider: .anthropic,
            inputPricePerToken: 3.0 / 1_000_000,
            outputPricePerToken: 15.0 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "claude-opus-4-6",
            provider: .anthropic,
            inputPricePerToken: 15.0 / 1_000_000,
            outputPricePerToken: 75.0 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "claude-opus-4-5",
            provider: .anthropic,
            inputPricePerToken: 15.0 / 1_000_000,
            outputPricePerToken: 75.0 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "claude-haiku-3-5",
            provider: .anthropic,
            inputPricePerToken: 0.8 / 1_000_000,
            outputPricePerToken: 4.0 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "claude-haiku-4-5-20251001",
            provider: .anthropic,
            inputPricePerToken: 0.8 / 1_000_000,
            outputPricePerToken: 4.0 / 1_000_000,
            maxOutputTokens: 8192
        ),

        // MARK: Deepseek
        // deepseek-reasoner intentionally absent — no function-calling support (Phase 18)
        ModelDescriptor(
            id: "deepseek-chat",
            provider: .deepseek,
            inputPricePerToken: 0.27 / 1_000_000,
            outputPricePerToken: 1.10 / 1_000_000,
            maxOutputTokens: 8192
        ),

        // MARK: Kimi (Moonshot AI)
        ModelDescriptor(
            id: "moonshot-v1-8k",
            provider: .kimi,
            inputPricePerToken: 0.20 / 1_000_000,
            outputPricePerToken: 2.00 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "moonshot-v1-32k",
            provider: .kimi,
            inputPricePerToken: 1.00 / 1_000_000,
            outputPricePerToken: 3.00 / 1_000_000,
            maxOutputTokens: 8192
        ),
        ModelDescriptor(
            id: "moonshot-v1-128k",
            provider: .kimi,
            inputPricePerToken: 2.00 / 1_000_000,
            outputPricePerToken: 5.00 / 1_000_000,
            maxOutputTokens: 8192
        ),
    ]

    /// Strict resolver: returns the descriptor for a known model ID or throws.
    /// Never silently falls back to (0.0, 0.0) pricing.
    static func descriptor(for id: String) throws -> ModelDescriptor {
        guard let d = all.first(where: { $0.id == id }) else {
            throw ModelCatalogError.unknownModel(id)
        }
        return d
    }
}

// MARK: - ModelCatalogError

enum ModelCatalogError: Error, LocalizedError {
    case unknownModel(String)

    var errorDescription: String? {
        switch self {
        case .unknownModel(let id):
            return "Unknown model '\(id)'. Check your AI model setting."
        }
    }
}
