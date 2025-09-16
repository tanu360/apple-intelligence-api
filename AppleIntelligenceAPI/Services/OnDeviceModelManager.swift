import Foundation
import FoundationModels
import Vapor

actor OnDeviceModelManager {
    private let model: SystemLanguageModel

    init() {
        self.model = SystemLanguageModel.default
    }

    func isModelAvailable() -> (available: Bool, reason: String?) {
        let availability = model.availability
        switch availability {
        case .available:
            return (true, nil)
        case .unavailable(let reason):
            let reasonString: String
            switch reason {
            case .deviceNotEligible:
                reasonString =
                    "Device not eligible for Apple Intelligence. Supported devices: iPhone 15 Pro/Pro Max or newer, iPad with M1 chip or newer, Mac with Apple Silicon"
            case .appleIntelligenceNotEnabled:
                reasonString =
                    "Apple Intelligence not enabled. Enable it in Settings > Apple Intelligence & Siri"
            case .modelNotReady:
                reasonString =
                    "AI model not ready. Models are downloaded automatically based on network status, battery level, and system load. Please wait and try again later."
            @unknown default:
                reasonString = "Unknown availability issue"
            }
            return (false, reasonString)
        @unknown default:
            return (false, "Unknown availability status")
        }
    }

    func getSupportedLanguages() -> [String] {
        let languages = model.supportedLanguages
        return languages.compactMap { language -> String? in
            let locale = Locale(identifier: language.maximalIdentifier)
            if let displayName = locale.localizedString(forIdentifier: language.maximalIdentifier) {
                return displayName
            }
            return language.languageCode?.identifier
        }.sorted()
    }

    func convertMessagesToTranscript(_ messages: [ChatMessage]) -> [Transcript.Entry] {
        var entries: [Transcript.Entry] = []
        for message in messages {
            let textSegment = Transcript.TextSegment(content: message.content)
            switch message.role.lowercased() {
            case "system":
                let instructions = Transcript.Instructions(
                    segments: [.text(textSegment)],
                    toolDefinitions: []
                )
                entries.append(.instructions(instructions))
            case "user":
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))
            case "assistant":
                let response = Transcript.Response(
                    assetIDs: [],
                    segments: [.text(textSegment)]
                )
                entries.append(.response(response))
            default:
                let prompt = Transcript.Prompt(
                    segments: [.text(textSegment)]
                )
                entries.append(.prompt(prompt))
            }
        }
        return entries
    }

    func generateResponse(
        for messages: [ChatMessage], temperature: Double? = nil, maxTokens: Int? = nil
    ) async throws -> String {
        let (available, reason) = isModelAvailable()
        guard available else {
            throw Abort(
                .serviceUnavailable, reason: reason ?? "Apple Intelligence model is not available")
        }
        guard !messages.isEmpty else {
            throw Abort(.badRequest, reason: "No messages provided")
        }
        let lastMessage = messages.last!
        let currentPrompt = lastMessage.content
        let previousMessages = messages.count > 1 ? Array(messages.dropLast()) : []
        let transcriptEntries = convertMessagesToTranscript(previousMessages)
        let transcript = Transcript(entries: transcriptEntries)
        let session = LanguageModelSession(transcript: transcript)
        do {
            var options = GenerationOptions()
            if let temp = temperature {
                options = GenerationOptions(temperature: temp, maximumResponseTokens: maxTokens)
            } else if let maxTokens = maxTokens {
                options = GenerationOptions(maximumResponseTokens: maxTokens)
            }
            let response = try await session.respond(
                to: currentPrompt,
                options: options
            )
            let content = response.content
            return content
        } catch {
            throw Abort(
                .internalServerError,
                reason: "Error generating response: \(error.localizedDescription)")
        }
    }

    func generateResponse(for prompt: String, temperature: Double? = nil, maxTokens: Int? = nil)
        async throws -> String
    {
        let messages = [ChatMessage(role: "user", content: prompt)]
        return try await generateResponse(
            for: messages, temperature: temperature, maxTokens: maxTokens)
    }
}

let aiManager = OnDeviceModelManager()
