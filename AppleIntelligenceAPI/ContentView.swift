import SwiftUI
import Combine
#if os(macOS)
import SystemConfiguration
#endif

@MainActor
class ServerViewModel: ObservableObject {
    @Published var configuration: ServerConfiguration
    @Published var hostInput: String
    @Published var portInput: String
    @Published var isModelAvailable: Bool = false
    @Published var modelUnavailableReason: String?
    @Published var isCheckingModel: Bool = false

    private let serverManager = VaporServerManager()
    var isRunning: Bool { serverManager.isRunning }
    var lastError: String? { serverManager.lastError }
    var serverURL: String { configuration.url }
    var openaiBaseURL: String { configuration.openaiBaseURL }
    var chatCompletionsEndpoint: String { configuration.chatCompletionsEndpoint }
    var modelName: String { configuration.mode.displayName }

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
        self.hostInput = configuration.host
        self.portInput = String(configuration.port)
        Task { await checkModelAvailability() }
    }

    func checkModelAvailability() async {
        isCheckingModel = true
        let result = await aiManager.isModelAvailable()
        isModelAvailable = result.available
        modelUnavailableReason = result.reason
        isCheckingModel = false
    }

    func startServer() async {
        await checkModelAvailability()
        guard isModelAvailable else { return }
        updateConfiguration()
        await serverManager.startServer(configuration: configuration)
    }

    func stopServer() async {
        await serverManager.stopServer()
    }

    private func updateConfiguration() {
        let trimmedHost = hostInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHost.isEmpty { configuration.host = trimmedHost }
        if let port = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)),
           port > 0 && port <= 65535 {
            configuration.port = port
        }
    }

    func resetToDefaults() {
        configuration = ServerConfiguration(
            host: configuration.mode == .base ? "127.0.0.1" : configuration.host,
            port: configuration.mode.defaultPort,
            mode: configuration.mode
        )
        hostInput = configuration.host
        portInput = String(configuration.port)
    }

    func copyToClipboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

@MainActor
class SingleServerViewModel: ObservableObject {
    @Published var serverViewModel: ServerViewModel

    init() {
        let config = ServerConfiguration(
            host: "127.0.0.1",
            port: 11435,
            mode: .base
        )
        serverViewModel = ServerViewModel(configuration: config)
    }
}

struct ContentView: View {
    @StateObject private var singleServerVM = SingleServerViewModel()
    @State private var isStarting: Bool = false
    @State private var isStopping: Bool = false
    @State private var selectedModel: AvailableModel? = nil
    @State private var showChat: Bool = false
    @State private var showDocumentation: Bool = false

    var availableModels: [AvailableModel] {
        guard singleServerVM.serverViewModel.isRunning else { return [] }
        let port = singleServerVM.serverViewModel.configuration.port
        return ServerMode.allCases.map { mode in
            AvailableModel(id: mode.modelName, mode: mode, port: port)
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            VStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Apple On-Device Intelligence API")
                    .font(.title)
                    .fontWeight(.bold)

                VStack(spacing: 10) {
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.circle.fill")
                                .foregroundColor(.blue)
                            Text("apple/ai")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "desktopcomputer")
                                .foregroundColor(.green)
                            Text(getDeviceName())
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }

                    Text("OpenAI API Compatible • Local Apple Intelligence Server")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.green)
                                .font(.caption2)
                            Text("Private")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                                .font(.caption2)
                            Text("Fast")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .foregroundColor(.purple)
                                .font(.caption2)
                            Text("On-Device")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            SimpleServerPanel(
                viewModel: singleServerVM.serverViewModel,
                isStarting: isStarting,
                isStopping: isStopping,
                onStart: {
                    isStarting = true
                    Task {
                        await singleServerVM.serverViewModel.startServer()
                        isStarting = false
                    }
                },
                onStop: {
                    isStopping = true
                    Task {
                        await singleServerVM.serverViewModel.stopServer()
                        isStopping = false
                    }
                }
            )

            if singleServerVM.serverViewModel.isRunning {
                HStack(spacing: 20) {
                    Button(action: {
                        showChat = true
                    }) {
                        Label("Open Chat", systemImage: "message.fill")
                    }
                    .buttonStyle(CapsuleControlButtonStyle(background: Color.blue.opacity(0.18), foreground: .blue))

                    Button(action: {
                        showDocumentation = true
                    }) {
                        Label("Documentation", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(CapsuleControlButtonStyle(background: Color.orange.opacity(0.18), foreground: .orange))
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(maxWidth: 600)
        .frame(minWidth: 600, maxWidth: .infinity, minHeight: 600, idealHeight: 750, maxHeight: .infinity)
        .navigationTitle("")
        .sheet(isPresented: $showChat) {
            VStack {
                HStack {
                    Text("Chat")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Done") {
                        showChat = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()

                ChatPanel(
                    availableModels: availableModels,
                    selectedModel: $selectedModel
                )
            }
            .frame(minWidth: 600, minHeight: 600)
        }
        .sheet(isPresented: $showDocumentation) {
            VStack {
                HStack {
                    Text("Documentation")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Button("Done") {
                        showDocumentation = false
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()

                DocumentationView(viewModel: singleServerVM.serverViewModel)
            }
            .frame(minWidth: 600, minHeight: 600)
        }
    }

    private func getDeviceName() -> String {
        #if os(macOS)
        if let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? {
            return computerName
        }
        if let localHostName = SCDynamicStoreCopyLocalHostName(nil) as String? {
            return localHostName.replacingOccurrences(of: ".local", with: "")
        }
        return ProcessInfo.processInfo.hostName
        #else
        return UIDevice.current.name
        #endif
    }
}

struct SimpleServerPanel: View {
    @ObservedObject var viewModel: ServerViewModel
    var isStarting: Bool
    var isStopping: Bool
    var onStart: () -> Void
    var onStop: () -> Void

    private var statusColor: Color { viewModel.isRunning ? .green : .red }
    private var statusIcon: String { viewModel.isRunning ? "checkmark.circle.fill" : "pause.circle.fill" }

    private var availabilityColor: Color {
        if viewModel.isCheckingModel { return .blue }
        return viewModel.isModelAvailable ? .green : .orange
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        statusIndicator
                        Spacer()
                        portIndicator
                    }
                    intelligenceIndicator
                }
                if let reason = viewModel.modelUnavailableReason, !viewModel.isModelAvailable {
                    ErrorMessage(text: reason, color: .orange)
                }
                if let error = viewModel.lastError {
                    ErrorMessage(text: "Error: \(error)", color: .red)
                }
                HStack {
                    Spacer()
                    HStack(spacing: 14) {
                        if viewModel.isRunning {
                            Button(action: onStop) {
                                Label("Stop Server", systemImage: "stop.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(CapsuleControlButtonStyle(background: Color.red.opacity(0.18), foreground: .red))
                            .disabled(isStopping)
                        } else {
                            Button(action: onStart) {
                                Label(viewModel.isModelAvailable ? "Start Server" : "Model Not Available", systemImage: "play.fill")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(CapsuleControlButtonStyle(
                                background: (viewModel.isModelAvailable && !viewModel.isCheckingModel) ? Color.green.opacity(0.18) : Color.gray.opacity(0.18),
                                foreground: (viewModel.isModelAvailable && !viewModel.isCheckingModel) ? .green : .gray
                            ))
                            .disabled(isStarting || !viewModel.isModelAvailable || viewModel.isCheckingModel)
                        }

                        if isStarting || isStopping {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .scaleEffect(0.9)
                        }
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
        .padding(.vertical, 8)
    }

    private var statusIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIcon)
                .font(.title3)
                .foregroundColor(statusColor)
                .frame(width: 24, height: 24)
            Text(viewModel.isRunning ? "Server Running" : "Server Stopped")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(viewModel.isRunning ? statusColor.opacity(0.1) : Color.gray.opacity(0.08))
        )
    }

    private var portIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isRunning ? Color.green : Color.gray.opacity(0.6))
                .frame(width: 10, height: 10)
            Text(verbatim: "\(viewModel.configuration.port)")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(viewModel.isRunning ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
        )
    }

    private var intelligenceIndicator: some View {
        HStack(spacing: 12) {
            if viewModel.isCheckingModel {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(availabilityColor)
                    .scaleEffect(0.8)
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: viewModel.isModelAvailable ? "sparkles" : "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundColor(availabilityColor)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.isModelAvailable ? "Apple Intelligence Available" : (viewModel.isCheckingModel ? "Checking Apple Intelligence" : "Apple Intelligence Unavailable"))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                if viewModel.isCheckingModel {
                    Text("Verifying local models...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(viewModel.isModelAvailable ? "Models ready for completions" : "Installation required")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(availabilityColor.opacity(0.08))
        )
    }
}

struct ErrorMessage: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

struct CapsuleControlButtonStyle: ButtonStyle {
    var background: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        CapsuleButton(configuration: configuration, background: background, foreground: foreground)
    }

    private struct CapsuleButton: View {
        let configuration: Configuration
        let background: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(background.opacity(configuration.isPressed ? 0.7 : 1))
                )
                .foregroundColor(foreground.opacity(isEnabled ? 1 : 0.4))
                .opacity(isEnabled ? 1 : 0.6)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
        }
    }
}

struct DocumentationView: View {
    @ObservedObject var viewModel: ServerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if viewModel.isRunning {
                GroupBox("API Endpoints") {
                    VStack(alignment: .leading, spacing: 16) {
                        APIEndpointRow(
                            title: "Base URL",
                            subtitle: "OpenAI clients",
                            url: viewModel.openaiBaseURL,
                            onCopy: { viewModel.copyToClipboard(viewModel.openaiBaseURL) }
                        )
                        APIEndpointRow(
                            title: "Chat Completions",
                            subtitle: "POST endpoint",
                            url: viewModel.chatCompletionsEndpoint,
                            onCopy: { viewModel.copyToClipboard(viewModel.chatCompletionsEndpoint) }
                        )
                    }
                    .padding(16)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Available Models")
                        .font(.headline)
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Circle().fill(.blue).frame(width: 8, height: 8)
                            Text("apple-fm-base").fontWeight(.semibold).foregroundColor(.blue)
                            Text("Balanced responses for general use.").font(.caption).foregroundColor(.secondary)
                        }
                        HStack(spacing: 10) {
                            Circle().fill(.green).frame(width: 8, height: 8)
                            Text("apple-fm-deterministic").fontWeight(.semibold).foregroundColor(.green)
                            Text("Predictable and consistent text generation.").font(.caption).foregroundColor(.secondary)
                        }
                        HStack(spacing: 10) {
                            Circle().fill(.purple).frame(width: 8, height: 8)
                            Text("apple-fm-creative").fontWeight(.semibold).foregroundColor(.purple)
                            Text("Enhanced creativity for imaginative content.").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 4)
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Quick Start")
                        .font(.headline)
                        .fontWeight(.semibold)
                    let pythonCode = """
# Python OpenAI client
from openai import OpenAI
client = OpenAI(base_url="\(viewModel.openaiBaseURL)", api_key="tanu1337")
response = client.chat.completions.create(model="apple-fm-base", messages=[{"role": "user", "content": "ping"}])
print(response.choices[0].message.content)
"""
                    CodeBlock(
                        code: pythonCode,
                        onCopy: { viewModel.copyToClipboard(pythonCode) }
                    )
                }
            } else {
                Text("Start the server to see documentation")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .padding(20)
    }
}

struct APIEndpointRow: View {
    let title: String
    let subtitle: String
    let url: String
    let onCopy: () -> Void

    @State private var showCopied = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            HStack(spacing: 12) {
                Text(url)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                Button(showCopied ? "Copied" : "Copy") {
                    onCopy()
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showCopied = false
                    }
                }
                .buttonStyle(.borderless)
                .foregroundColor(showCopied ? .green : .primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct CodeBlock: View {
    let code: String
    let onCopy: () -> Void

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 12) {
            HStack {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Button(showCopied ? "Copied" : "Copy Code") {
                onCopy()
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    showCopied = false
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(showCopied ? .green : .primary)
            .padding(.trailing, 4)
        }
    }
}
