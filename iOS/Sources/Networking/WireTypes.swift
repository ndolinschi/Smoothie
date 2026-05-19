import Foundation

/// Swift-native Decodable mirrors of the JSON the macOS HTTP server emits.
/// Kept separate from `Shared` framework types because Kotlin's K/N exports
/// aren't Codable from Swift's perspective.

enum CLIWire: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode = "claude_code"
    case gemini
    case openCode = "open_code"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .gemini:     return "Gemini"
        case .openCode:   return "OpenCode"
        }
    }

    /// Server expects the same lowercased token the Kotlin enum's `.name`
    /// produces (`claude_code`, `gemini`, `codex`, `open_code`).
    var wireValue: String { rawValue }
}

enum SessionStateWire: String, Codable, Sendable {
    case starting, thinking, waiting, done, error
    case limitReached = "limit_reached"
}

enum EventTypeWire: String, Codable, Sendable {
    case message, thinking
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case fileEdit = "file_edit"
    case waiting, done, error
    case limitReached = "limit_reached"
}

struct SmoothieEventWire: Codable, Sendable, Identifiable {
    let type: EventTypeWire
    let content: String
    let metadata: [String: AnyCodable]?
    let timestamp: Int64

    var id: String { "\(timestamp)-\(type.rawValue)-\(content.prefix(40))" }
}

struct SessionDescriptorWire: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let projectPath: String
    let projectName: String
    let cli: CLIWire
    let model: String?
    let reasoningEffort: String?
    let mode: String?
    let state: SessionStateWire
    let createdAt: Int64
}

struct SlashCommandWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let description: String
    var id: String { name }
}

struct ProviderFeaturesWire: Codable, Sendable, Hashable {
    let supportsModelPicker: Bool
    let supportsReasoningEffort: Bool
    let supportsModes: Bool
    let defaultModel: String?
    let availableModels: [String]
    let availableReasoningEfforts: [String]
    let availableModes: [String]
    let slashCommands: [SlashCommandWire]
}

struct AdapterInfoWire: Codable, Sendable, Identifiable {
    let cli: CLIWire
    let installed: Bool
    let version: String?
    let features: ProviderFeaturesWire?

    var id: String { cli.rawValue }
}

struct CreateSessionRequestWire: Codable, Sendable {
    let projectPath: String
    let cli: CLIWire
    let model: String?
    let reasoningEffort: String?
    let mode: String?

    init(projectPath: String, cli: CLIWire, model: String? = nil, reasoningEffort: String? = nil, mode: String? = nil) {
        self.projectPath = projectPath
        self.cli = cli
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.mode = mode
    }
}

struct ProjectWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let path: String
    let isGit: Bool
    var id: String { path }
}

/// Type-erased JSON value for `metadata`. Decode-only.
struct AnyCodable: Codable, Sendable, Hashable {
    enum Value: Hashable, Sendable {
        case null
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case array([AnyCodable])
        case object([String: AnyCodable])
    }

    let value: Value

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = .null; return }
        if let v = try? c.decode(Bool.self) { value = .bool(v); return }
        if let v = try? c.decode(Int.self) { value = .int(v); return }
        if let v = try? c.decode(Double.self) { value = .double(v); return }
        if let v = try? c.decode(String.self) { value = .string(v); return }
        if let v = try? c.decode([AnyCodable].self) { value = .array(v); return }
        if let v = try? c.decode([String: AnyCodable].self) { value = .object(v); return }
        value = .null
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case .null:           try c.encodeNil()
        case .bool(let v):    try c.encode(v)
        case .int(let v):     try c.encode(v)
        case .double(let v):  try c.encode(v)
        case .string(let v):  try c.encode(v)
        case .array(let v):   try c.encode(v)
        case .object(let v):  try c.encode(v)
        }
    }

    var stringValue: String? {
        if case .string(let s) = value { return s }
        return nil
    }
}
