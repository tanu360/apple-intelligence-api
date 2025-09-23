import Foundation
import FoundationModels
import Vapor

struct ChatCompletionRequest: Content, Sendable {
    let model: String?
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let n: Int?
    let stream: Bool?
    let stop: [String]?
    let presencePenalty: Double?
    let frequencyPenalty: Double?
    let logitBias: [String: Double]?
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case n
        case stream
        case stop
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case logitBias = "logit_bias"
        case user
    }
}

struct ChatMessage: Content, Sendable {
    let role: String
    let content: String
    let name: String?

    init(role: String, content: String, name: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
    }
}

struct ChatCompletionResponse: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionChoice]
    let usage: UsageInfo
    let systemFingerprint: String
    
    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
        case systemFingerprint = "system_fingerprint"
    }
}

struct UsageInfo: Content, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
    
    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct ChatCompletionChoice: Content, Sendable {
    let index: Int
    let message: ChatMessage?
    let delta: ChatMessage?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case delta
        case finishReason = "finish_reason"
    }
}

struct ModelsResponse: Content, Sendable {
    let object: String
    let data: [ModelInfo]
}

struct ModelInfo: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

struct ServerStatus: Content, Sendable {
    let modelAvailable: Bool
    let reason: String
    let supportedLanguages: [String]
    let serverVersion: String
    let appleIntelligenceCompatible: Bool

    enum CodingKeys: String, CodingKey {
        case modelAvailable = "model_available"
        case reason
        case supportedLanguages = "supported_languages"
        case serverVersion = "server_version"
        case appleIntelligenceCompatible = "apple_intelligence_compatible"
    }
}

struct ErrorResponse: Content, Sendable {
    let error: ErrorDetail
}

struct ErrorDetail: Content, Sendable {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

struct ChatCompletionStreamResponse: Content, Sendable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatCompletionStreamChoice]
}

struct ChatCompletionStreamChoice: Content, Sendable {
    let index: Int
    let delta: ChatCompletionDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }
}

struct ChatCompletionDelta: Content, Sendable {
    let role: String?
    let content: String?
}
