import Combine
import Foundation
import FoundationModels
import Vapor
import NIO

let globalEventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

@MainActor
class VaporServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var lastError: String?

    private var app: Application?
    private var serverTask: Task<Void, Never>?
    private var mode: ServerMode = .base
    private static var loggingBootstrapped = false

    func startServer(configuration: ServerConfiguration) async {
        guard !isRunning else { return }
        do {
            self.mode = configuration.mode
            var env = try Environment.detect()
            if !Self.loggingBootstrapped {
                try LoggingSystem.bootstrap(from: &env)
                Self.loggingBootstrapped = true
            }
            let app = try await Application.make(env, .shared(globalEventLoopGroup))
            self.app = app
            app.environment.arguments = [app.environment.arguments[0]]
            configureRoutes(app, mode: mode)
            app.http.server.configuration.hostname = configuration.host
            app.http.server.configuration.port = configuration.port
            serverTask = Task {
                do {
                    try await app.execute()
                } catch {
                    await MainActor.run {
                        self.lastError = error.localizedDescription
                        self.isRunning = false
                    }
                }
            }
            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stopServer() async {
        guard isRunning else { return }
        serverTask?.cancel()
        serverTask = nil
        if let app = app {
            try? await app.asyncShutdown()
            self.app = nil
        }
        isRunning = false
    }

    private func configureRoutes(_ app: Application, mode: ServerMode) {
        app.get("health") { req async -> HTTPStatus in .ok }
        app.get("status") { req async throws -> ServerStatus in
            let (available, reason) = await aiManager.isModelAvailable()
            let supportedLanguages = await aiManager.getSupportedLanguages()
            return ServerStatus(
                modelAvailable: available,
                reason: reason ?? "Model is available",
                supportedLanguages: supportedLanguages,
                serverVersion: "1.0.0",
                appleIntelligenceCompatible: true
            )
        }
        let v1 = app.grouped("v1")
        v1.get("models") { req async throws -> ModelsResponse in
            let (available, _) = await aiManager.isModelAvailable()
            var models: [ModelInfo] = []
            if available {
                models.append(contentsOf: [
                    ModelInfo(
                        id: "apple-fm-base",
                        object: "model",
                        created: Int(Date().timeIntervalSince1970),
                        ownedBy: "apple-on-device-openai"
                    ),
                    ModelInfo(
                        id: "apple-fm-deterministic",
                        object: "model",
                        created: Int(Date().timeIntervalSince1970),
                        ownedBy: "apple-on-device-openai"
                    ),
                    ModelInfo(
                        id: "apple-fm-creative",
                        object: "model",
                        created: Int(Date().timeIntervalSince1970),
                        ownedBy: "apple-on-device-openai"
                    )
                ])
            }
            return ModelsResponse(object: "list", data: models)
        }
        v1.post("chat", "completions") { req async throws -> Response in
            let chatRequest = try req.content.decode(ChatCompletionRequest.self)
            guard !chatRequest.messages.isEmpty else {
                throw Abort(.badRequest, reason: "No messages provided")
            }
            let requestedModel = chatRequest.model ?? "apple-fm-base"
            let temp = chatRequest.temperature ?? 0.7
            let topP = chatRequest.topP ?? 0.95
            func fixedCall(_ temp: Double, _ topP: Double, modelName: String) async throws -> Response {
                let response = try await aiManager.generateResponse(
                    for: chatRequest.messages,
                    temperature: temp,
                    maxTokens: chatRequest.maxTokens
                )
                let chatResponse = ChatCompletionResponse(
                    id: "chatcmpl-\(UUID().uuidString)",
                    object: "chat.completion",
                    created: Int(Date().timeIntervalSince1970),
                    model: modelName,
                    choices: [
                        ChatCompletionChoice(
                            index: 0,
                            message: ChatMessage(role: "assistant", content: response, name: nil),
                            delta: nil,
                            finishReason: "stop"
                        )
                    ]
                )
                let jsonData = try JSONEncoder().encode(chatResponse)
                let res = Response()
                res.headers.contentType = .json
                res.body = .init(data: jsonData)
                return res
            }
            switch requestedModel {
            case "apple-fm-deterministic":
                return try await fixedCall(0.1, 0.0, modelName: "apple-fm-deterministic")
            case "apple-fm-creative":
                return try await fixedCall(0.9, 0.9, modelName: "apple-fm-creative")
            case "apple-fm-base":
                fallthrough
            default:
                if temp < 0.2 || topP < 0.2 {
                    return try await fixedCall(0.1, 0.0, modelName: "apple-fm-deterministic")
                } else if temp >= 0.8 || topP >= 0.8 {
                    return try await fixedCall(0.9, 0.9, modelName: "apple-fm-creative")
                } else {
                    return try await fixedCall(temp, topP, modelName: "apple-fm-base")
                }
            }
        }
    }

    deinit {
        Task { [app] in
            try? await app?.asyncShutdown()
            try? await globalEventLoopGroup.shutdownGracefully()
        }
    }
}
