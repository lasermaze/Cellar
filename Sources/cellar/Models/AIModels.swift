import Foundation

// MARK: - AI Provider

enum AIProvider {
    case anthropic(apiKey: String)
    case openai(apiKey: String)
    case unavailable
}

// MARK: - AI Service Error

enum AIServiceError: Error, LocalizedError {
    case httpError(statusCode: Int)
    case decodingError(String)
    case unavailable
    case allRetriesFailed

    var errorDescription: String? {
        switch self {
        case .httpError(let statusCode):
            return "HTTP \(statusCode)"
        case .decodingError(let detail):
            return "Failed to parse AI response: \(detail)"
        case .unavailable:
            return "AI service unavailable (no API key set)"
        case .allRetriesFailed:
            return "All AI retry attempts failed"
        }
    }
}

// MARK: - AI Diagnosis

struct AIDiagnosis {
    let explanation: String
    let suggestedFix: WineFix?
}

// MARK: - AI Variant

/// An AI-generated launch variant with parsed WineFix actions (not Codable — used only at runtime).
struct AIVariant {
    let description: String
    let environment: [String: String]
    let actions: [WineFix]   // parsed from AI response actions array
}

// MARK: - AI Variant Result

struct AIVariantResult {
    let variants: [AIVariant]
    let reasoning: String
}

// MARK: - AI Result

enum AIResult<T> {
    case success(T)
    case unavailable
    case failed(String)
}

// MARK: - Anthropic Request/Response

struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

struct AnthropicResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    var firstText: String? {
        content.first(where: { $0.type == "text" })?.text
    }
}

// MARK: - OpenAI Request/Response

struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let responseFormat: ResponseFormat?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct ResponseFormat: Encodable {
        let type: String
    }
}

struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
        struct Message: Decodable {
            let content: String
        }
    }

    var firstContent: String? {
        choices.first?.message.content
    }
}

// MARK: - Tool-Use API Types (Agent Loop)

// MARK: JSONValue

/// Recursive JSON value enum for encoding/decoding arbitrary JSON structures.
/// Used for tool input/output in the agent loop.
indirect enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // CRITICAL: try Bool BEFORE Double — otherwise true/false decode as 1.0/0.0
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSONValue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

extension JSONValue {
    var asString: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var asBool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }

    var asNumber: Double? {
        if case .number(let v) = self { return v }
        return nil
    }

    var asObject: [String: JSONValue]? {
        if case .object(let v) = self { return v }
        return nil
    }

    var asArray: [JSONValue]? {
        if case .array(let v) = self { return v }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }
}

// MARK: ToolContentBlock

/// Tagged union for Anthropic API content blocks in tool-use requests/responses.
/// Named ToolContentBlock to avoid collision with AnthropicResponse.ContentBlock.
enum ToolContentBlock: Codable {
    case text(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case toolResult(toolUseId: String, content: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "tool_use":
            let id = try container.decode(String.self, forKey: .id)
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decode(JSONValue.self, forKey: .input)
            self = .toolUse(id: id, name: name, input: input)
        case "tool_result":
            let toolUseId = try container.decode(String.self, forKey: .toolUseId)
            let content = try container.decode(String.self, forKey: .content)
            let isError = (try? container.decode(Bool.self, forKey: .isError)) ?? false
            self = .toolResult(toolUseId: toolUseId, content: content, isError: isError)
        default:
            // Unknown block type — treat as empty text to avoid crashing
            self = .text("")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .toolUse(let id, let name, let input):
            try container.encode("tool_use", forKey: .type)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(input, forKey: .input)
        case .toolResult(let toolUseId, let content, let isError):
            try container.encode("tool_result", forKey: .type)
            try container.encode(toolUseId, forKey: .toolUseId)
            try container.encode(content, forKey: .content)
            // Only encode is_error if true (Anthropic API convention)
            if isError {
                try container.encode(isError, forKey: .isError)
            }
        }
    }
}

// MARK: MessageContent

/// Flexible content type for Anthropic messages — either a plain string or an array of content blocks.
enum MessageContent: Codable {
    case text(String)
    case blocks([ToolContentBlock])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let blocks = try? container.decode([ToolContentBlock].self) {
            self = .blocks(blocks)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode MessageContent")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .blocks(let blocks):
            try container.encode(blocks)
        }
    }
}

// MARK: ToolDefinition

/// Describes a tool available to the AI agent.
struct ToolDefinition: Encodable {
    let name: String
    let description: String
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }
}

// MARK: AnthropicToolRequest

/// Anthropic API request with tool definitions (for agent loop).
struct AnthropicToolRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [Message]
    let tools: [ToolDefinition]?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case tools
    }

    struct Message: Encodable {
        let role: String
        let content: MessageContent
    }
}

// MARK: AnthropicToolResponse

/// Anthropic API response containing tool-use or text content blocks.
struct AnthropicToolResponse: Decodable {
    let content: [ToolContentBlock]
    let stopReason: String

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
