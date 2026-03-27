import Foundation

// MARK: - AI Provider

enum AIProvider {
    case anthropic(apiKey: String)
    case openai(apiKey: String)
    case unavailable
}

// MARK: - AI Service Error

enum AIServiceError: Error {
    case httpError(statusCode: Int)
    case decodingError(String)
    case unavailable
    case allRetriesFailed
}

// MARK: - AI Diagnosis

struct AIDiagnosis {
    let explanation: String
    let suggestedFix: WineFix?
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
