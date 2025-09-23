import Foundation
import SwiftUI
import Combine

public struct ChatEntry: Identifiable, Equatable {
    public enum Role: String {
        case user, assistant, system
    }
    public let id = UUID()
    public let role: Role
    public var content: String
}

private struct ChatMessagePayload: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionsRequest: Codable {
    let model: String
    let messages: [ChatMessagePayload]
    let temperature: Double?
    let top_p: Double?
    let stream: Bool?
}

private struct ChatChoiceMessage: Codable {
    let role: String
    let content: String
}

private struct ChatChoice: Codable {
    let index: Int
    let finish_reason: String?
    let message: ChatChoiceMessage
}

struct ChatUsage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

private struct ChatCompletionsResponse: Codable {
    let object: String?
    let id: String?
    let created: Int?
    let model: String?
    let choices: [ChatChoice]
    let usage: ChatUsage?
    let system_fingerprint: String?
}

private struct OpenAIErrorResponse: Codable {
    let error: OpenAIErrorDetail
}

private struct OpenAIErrorDetail: Codable {
    let message: String
    let type: String
    let code: String?
}

@MainActor
final class ChatPanelViewModel: ObservableObject {
    @Published var entries: [ChatEntry] = []
    @Published var input: String = ""
    @Published var isSending: Bool = false
    @Published var lastError: String?
    @Published var lastUsage: ChatUsage?
    @Published var lastResponseTime: TimeInterval?
    @Published var lastSystemFingerprint: String?
    @Published var lastResponseId: String?
    @Published var lastResponseModel: String?

    @Published var temperature: Double = 1.0
    @Published var topP: Double = 0.7

    func send(via availableModel: AvailableModel?, host: String = "127.0.0.1") async {
        lastError = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let target = availableModel else {
            lastError = "No model selected. Start a server and pick a model."
            return
        }

        entries.append(ChatEntry(role: .user, content: trimmed))
        input = ""
        isSending = true
        defer { isSending = false }

        let modelName = target.mode.modelName
        let messagesPayload: [ChatMessagePayload] = entries.map {
            ChatMessagePayload(role: $0.role.rawValue, content: $0.content)
        }

        let requestBody = ChatCompletionsRequest(
            model: modelName,
            messages: messagesPayload,
            temperature: temperature,
            top_p: topP,
            stream: false
        )

        do {
            let url = URL(string: "http://\(host):\(target.port)/v1/chat/completions")!
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.httpBody = try JSONEncoder().encode(requestBody)

            let startTime = Date()
            let (data, resp) = try await URLSession.shared.data(for: req)
            let responseTime = Date().timeIntervalSince(startTime)
            guard let http = resp as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard (200...299).contains(http.statusCode) else {
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "ChatHTTPError",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(errorResponse.error.message)"]
                    )
                } else {
                    let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                    throw NSError(
                        domain: "ChatHTTPError",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(body)"]
                    )
                }
            }

            let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            guard let first = decoded.choices.first else {
                throw NSError(
                    domain: "ChatDecode",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No choices in response."]
                )
            }

            entries.append(ChatEntry(role: .assistant, content: first.message.content))

            lastResponseTime = responseTime
            lastSystemFingerprint = decoded.system_fingerprint
            lastResponseId = decoded.id
            lastResponseModel = decoded.model
            if let serverUsage = decoded.usage {
                lastUsage = serverUsage
            } else {
                let promptTokens = estimateTokens(for: messagesPayload)
                let completionTokens = estimateTokens(for: first.message.content)
                lastUsage = ChatUsage(
                    prompt_tokens: promptTokens,
                    completion_tokens: completionTokens,
                    total_tokens: promptTokens + completionTokens
                )
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clear() {
        entries.removeAll()
        lastError = nil
        lastUsage = nil
        lastResponseTime = nil
        lastSystemFingerprint = nil
        lastResponseId = nil
        lastResponseModel = nil
    }

    private func estimateTokens(for messages: [ChatMessagePayload]) -> Int {
        let totalText = messages.map { $0.content }.joined(separator: " ")
        return estimateTokens(for: totalText)
    }

    private func estimateTokens(for text: String) -> Int {

        let wordCount = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.count

        let charBasedTokens = Double(text.count) / 4.0
        let wordBasedTokens = Double(wordCount) / 0.75

        return Int(max(charBasedTokens, wordBasedTokens))
    }
}

public struct ChatPanel: View {
    public let availableModels: [AvailableModel]
    @Binding public var selectedModel: AvailableModel?

    @State private var selectedModelID: String?
    @StateObject private var viewModel = ChatPanelViewModel()
    @FocusState private var inputFocused: Bool
    @State private var scrollToBottomToken = UUID()

    public init(
        availableModels: [AvailableModel],
        selectedModel: Binding<AvailableModel?>
    ) {
        self.availableModels = availableModels
        self._selectedModel = selectedModel
        let initialModelID: String?
        if let currentModel = selectedModel.wrappedValue {
            initialModelID = currentModel.id
        } else if let baseModel = availableModels.first(where: { $0.mode.modelName == "apple-fm-base" }) {
            initialModelID = baseModel.id
        } else {
            initialModelID = availableModels.first?.id
        }
        self._selectedModelID = State(initialValue: initialModelID)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transcript
            composer
        }
        .onChange(of: availableModels) { _, newList in
            if let id = selectedModelID, !newList.contains(where: { $0.id == id }) {
                selectedModelID = nil
            }
            if let id = selectedModelID {
                selectedModel = newList.first(where: { $0.id == id })
            } else {
                if let baseModel = newList.first(where: { $0.mode.modelName == "apple-fm-base" }) {
                    selectedModelID = baseModel.id
                    selectedModel = baseModel
                } else if let firstModel = newList.first {
                    selectedModelID = firstModel.id
                    selectedModel = firstModel
                } else {
                    selectedModel = nil
                }
            }
        }
        .onChange(of: selectedModel) { _, newModel in
            let newID = newModel?.id
            if selectedModelID != newID {
                selectedModelID = newID
            }
        }
        .onChange(of: selectedModelID) { _, newID in
            if let id = newID {
                selectedModel = availableModels.first(where: { $0.id == id })
            } else {
                selectedModel = nil
            }
        }
        .onChange(of: viewModel.entries) { _, _ in
            scrollToBottomToken = UUID()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 0)
    }

    private var header: some View {
        HStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Chat")
                        .font(.title3)
                        .fontWeight(.semibold)
                    if !availableModels.isEmpty {
                        Text("\(availableModels.count) model\(availableModels.count == 1 ? "" : "s") available")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 12) {
                    if availableModels.isEmpty {
                        HStack(spacing: 8) {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text("Server Offline")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    } else {
                        Menu {
                            ForEach(availableModels) { model in
                                Button(action: {
                                    selectedModelID = model.id
                                }) {
                                    HStack {
                                        Text(model.mode.displayName)
                                        Spacer()
                                        if selectedModelID == model.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(selectedModel != nil ? Color.green : Color.orange).frame(width: 8, height: 8)
                                Text(selectedModel?.mode.displayName ?? "Select Model")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.gray.opacity(0.02))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.2)),
            alignment: .bottom
        )
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(viewModel.entries) { entry in
                        MessageBubble(entry: entry)
                            .id(entry.id)
                    }
                    Color.clear.frame(height: 1).id(scrollToBottomToken)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .onChange(of: scrollToBottomToken) { _, token in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo(token, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var composer: some View {
        VStack(spacing: 12) {
            if let err = viewModel.lastError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Spacer()
                    Button("Dismiss") { viewModel.lastError = nil }
                        .font(.caption)
                }
                .padding(12)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let usage = viewModel.lastUsage {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text("Prompt: \(usage.prompt_tokens)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "text.bubble")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Text("Completion: \(usage.completion_tokens)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "sum")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text("Total: \(usage.total_tokens)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    if let responseTime = viewModel.lastResponseTime {
                        HStack(spacing: 16) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text("Time: \(String(format: "%.2f", responseTime))s")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                            if responseTime > 0 {
                                let tokensPerSecond = Double(usage.completion_tokens) / responseTime
                                HStack(spacing: 4) {
                                    Image(systemName: "speedometer")
                                        .font(.caption)
                                        .foregroundStyle(.mint)
                                    Text("\(String(format: "%.1f", tokensPerSecond)) tok/s")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }

                    if let fingerprint = viewModel.lastSystemFingerprint {
                        HStack(spacing: 4) {
                            Image(systemName: "fingerprint")
                                .font(.caption)
                                .foregroundStyle(.gray)
                            Text("System: \(fingerprint)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("temperature: \(String(format: "%.2f", viewModel.temperature))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Slider(value: $viewModel.temperature, in: 0.1...1, step: 0.05)
                            .tint(.blue)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("top_p: \(String(format: "%.2f", viewModel.topP))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Slider(value: $viewModel.topP, in: 0.1...1, step: 0.05)
                            .tint(.purple)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.bottom, 8)
            HStack(alignment: .center, spacing: 12) {
                TextField("Type your message…", text: $viewModel.input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .lineLimit(1...6)
                    .onSubmit { Task { await viewModel.send(via: selectedModel) } }
                HStack(spacing: 8) {
                    Button {
                        viewModel.clear()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(CircularControlButtonStyle(background: Color.red.opacity(0.18), foreground: .red))
                    .disabled(viewModel.entries.isEmpty)
                    Button {
                        Task { await viewModel.send(via: selectedModel) }
                    } label: {
                        Image(systemName: viewModel.isSending ? "clock.fill" : "paperplane.fill")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(CircularControlButtonStyle(background: Color.blue.opacity(0.18), foreground: .blue))
                    .disabled(viewModel.isSending ||
                              viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              selectedModel == nil)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }
}

private struct MessageBubble: View {
    let entry: ChatEntry
    var isUser: Bool { entry.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: isUser ? "person.fill" : "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isUser ? .blue : .purple)
                    Text(isUser ? "You" : "Assistant")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                Text(entry.content)
                    .textSelection(.enabled)
                    .font(.system(.body, design: .default))
                    .lineSpacing(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isUser ? Color.blue.opacity(0.10) : Color.gray.opacity(0.08))
            )
            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 16)
    }
}

struct CircularControlButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        CircularButton(configuration: configuration, background: background, foreground: foreground)
    }

    private struct CircularButton: View {
        let configuration: Configuration
        let background: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(background.opacity(configuration.isPressed ? 0.7 : 1))
                )
                .foregroundColor(foreground.opacity(isEnabled ? 1 : 0.4))
                .opacity(isEnabled ? 1 : 0.6)
                .scaleEffect(configuration.isPressed ? 0.95 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}
