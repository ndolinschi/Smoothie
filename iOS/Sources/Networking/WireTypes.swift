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

    /// Pretty model name shown in the composer — the wire `id` (sent as
    /// `--model` to the CLI) is usually an alias like `sonnet` that's
    /// useless to the user. Maps known aliases to the marketing name.
    func friendlyModelName(_ id: String) -> String {
        switch self {
        case .claudeCode:
            switch id.lowercased() {
            case "sonnet":  return "Claude Sonnet 4.6"
            case "haiku":   return "Claude Haiku 4.5"
            case "opus":    return "Claude Opus 4.7"
            default:        return id
            }
        case .gemini:
            switch id.lowercased() {
            case "auto-gemini-3":         return "Gemini 3 · auto"
            case "gemini-3-flash-preview": return "Gemini 3 Flash"
            case "gemini-3.1-flash-lite":  return "Gemini 3.1 Flash Lite"
            default:                       return id
            }
        case .openCode:
            return id
        }
    }
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

struct BrowseEntryWire: Codable, Sendable, Identifiable, Hashable {
    let name: String
    let path: String
    let isDirectory: Bool
    let isGit: Bool
    let isAllowed: Bool
    var id: String { path }
}

struct BrowseResponseWire: Codable, Sendable {
    let current: String?
    let parent: String?
    let entries: [BrowseEntryWire]
    let roots: [String]
}

struct FileEntryWire: Codable, Sendable, Identifiable, Hashable {
    let path: String
    let fullPath: String
    let size: Int
    var id: String { fullPath }
}

struct FileContentWire: Codable, Sendable {
    let path: String
    let content: String
    let size: Int
    let truncated: Bool
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
