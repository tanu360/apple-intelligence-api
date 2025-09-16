import Foundation

public enum ServerMode: String, CaseIterable, Identifiable, Codable, Hashable {
    case base = "Base"
    case deterministic = "Deterministic"
    case creative = "Creative"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .base: return "Apple FM Base"
        case .deterministic: return "Apple FM Deterministic"
        case .creative: return "Apple FM Creative"
        }
    }

    public var modelName: String {
        switch self {
        case .base: return "apple-fm-base"
        case .deterministic: return "apple-fm-deterministic"
        case .creative: return "apple-fm-creative"
        }
    }

    public var defaultPort: Int {
        11435
    }
}

public struct ServerConfiguration: Identifiable, Equatable, Codable, Hashable {
    public var host: String
    public var port: Int
    public var mode: ServerMode

    public var id: String { "\(host):\(port):\(mode.rawValue)" }

    public var url: String { "http://\(host):\(port)" }
    public var openaiBaseURL: String { url }
    public var chatCompletionsEndpoint: String { "\(url)/v1/chat/completions" }
}

public struct AvailableModel: Identifiable, Hashable {
    public let id: String
    public let mode: ServerMode
    public let port: Int

    public var label: String {
        mode.displayName
    }

    public static func == (lhs: AvailableModel, rhs: AvailableModel) -> Bool {
        lhs.id == rhs.id && lhs.mode == rhs.mode && lhs.port == rhs.port
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(mode)
        hasher.combine(port)
    }
}
