import Foundation

// MARK: - AgentLoopProviderResponse

/// The normalized response returned by any ProviderAdapter implementation.
/// Abstracts away Anthropic and OpenAI/Deepseek response format differences.
struct AgentLoopProviderResponse {
    enum StopReason {
        case endTurn
        case toolUse
        case maxTokens
        case other(String)
    }

    let textBlocks: [String]
    let toolCalls: [AgentToolCall]
    let stopReason: StopReason
    let inputTokens: Int
    let outputTokens: Int
}

// MARK: - Shared HTTP Helper

/// Async HTTP call using URLSession.data(for:).
/// Used by AnthropicAdapter, DeepseekAdapter, and KimiAdapter.
func agentCallAPI(request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw AgentLoopError.noResponse
    }
    if http.statusCode >= 400 {
        let body = String(data: data, encoding: .utf8) ?? "(binary)"
        throw AgentLoopError.httpError(statusCode: http.statusCode, body: body)
    }
    return data
}

// MARK: - ProviderAdapter Protocol

/// Internal protocol implemented by exactly three adapter classes.
/// Not visible outside Core/ — AgentLoop sees only the concrete AgentProvider struct.
///
/// Adapters are class-bound (AnyObject) to avoid protocol-existential copy-on-mutation
/// when stored as `any ProviderAdapter` inside the value-type AgentProvider struct.
/// With class-bound adapters the struct's delegating methods are non-mutating —
/// the reference is constant; the referent's message state mutates internally.
protocol ProviderAdapter: AnyObject {
    func appendUserMessage(_ text: String)
    func appendAssistantResponse(_ response: AgentLoopProviderResponse)
    func appendToolResults(_ results: [(id: String, content: String, isError: Bool)])
    func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) async throws -> AgentLoopProviderResponse
}

// MARK: - AgentProvider

/// Single concrete provider type that AgentLoop holds.
/// Encapsulates per-provider wire-protocol quirks behind three adapter classes.
/// AgentLoop never sees raw API message types — they stay inside each adapter.
struct AgentProvider {

    // MARK: Properties

    private let adapter: any ProviderAdapter
    let descriptor: ModelDescriptor

    // MARK: Init

    /// Dispatch on descriptor.provider to instantiate the right adapter.
    init(descriptor: ModelDescriptor, apiKey: String, tools: [ToolDefinition], systemPrompt: String) {
        self.descriptor = descriptor
        switch descriptor.provider {
        case .anthropic:
            adapter = AnthropicAdapter(descriptor: descriptor, apiKey: apiKey, tools: tools, systemPrompt: systemPrompt)
        case .deepseek:
            adapter = DeepseekAdapter(descriptor: descriptor, apiKey: apiKey, tools: tools, systemPrompt: systemPrompt)
        case .kimi:
            adapter = KimiAdapter(descriptor: descriptor, apiKey: apiKey, tools: tools, systemPrompt: systemPrompt)
        }
    }

    // MARK: Computed from Descriptor

    var modelName: String { descriptor.id }
    var maxOutputTokensLimit: Int { descriptor.maxOutputTokens }

    func pricingPerToken() -> (input: Double, output: Double) {
        (descriptor.inputPricePerToken, descriptor.outputPricePerToken)
    }

    // MARK: Adapter Delegation
    // Non-mutating: adapter is a class reference — it mutates its own message state internally.

    func appendUserMessage(_ text: String) {
        adapter.appendUserMessage(text)
    }

    func appendAssistantResponse(_ response: AgentLoopProviderResponse) {
        adapter.appendAssistantResponse(response)
    }

    func appendToolResults(_ results: [(id: String, content: String, isError: Bool)]) {
        adapter.appendToolResults(results)
    }

    func callWithRetry(maxTokens: Int, emit: (AgentEvent) -> Void) async throws -> AgentLoopProviderResponse {
        try await adapter.callWithRetry(maxTokens: maxTokens, emit: emit)
    }
}
