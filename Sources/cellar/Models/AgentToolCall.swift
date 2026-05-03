import Foundation

// MARK: - AgentToolCall

/// Provider-neutral representation of a single tool invocation emitted by the model.
/// Adapters translate this <-> wire protocol (Anthropic tool_use blocks / OpenAI tool_calls).
/// The `id` is opaque: it carries `tool_use_id` (Anthropic) or `tool_call_id` (OpenAI-compat).
struct AgentToolCall: Sendable, Equatable {
    let id: String
    let name: String
    let input: JSONValue
}
