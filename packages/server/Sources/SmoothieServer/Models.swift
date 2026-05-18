import Foundation

enum CLIType: String, Codable, Sendable, CaseIterable {
    case opencode
    case claude
    case gemini
    case codex
}

enum EventType: String, Codable, Sendable {
    case message
    case thinking
    case tool_use
    case file_edit
    case waiting
    case done
    case error
}

enum SessionState: String, Codable, Sendable {
    case starting
    case thinking
    case waiting
    case done
    case error
}

struct SmoothieEvent: Codable, Sendable {
    let type: EventType
    let content: String
    let metadata: [String: AnyCodable]?
    let timestamp: Double

    init(type: EventType, content: String, metadata: [String: AnyCodable]? = nil, timestamp: Double = Date().timeIntervalSince1970) {
        self.type = type
        self.content = content
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

struct SessionDTO: Codable, Sendable {
    let id: String
    let projectPath: String
    let projectName: String
    let cli: CLIType
    let state: SessionState
    let createdAt: Double
}

struct ProjectDTO: Codable, Sendable {
    let name: String
    let path: String
    let isGit: Bool
}

struct AdapterInfo: Codable, Sendable {
    let cli: CLIType
    let installed: Bool
    let version: String?
    let supported: Bool
}

struct HealthResponse: Codable, Sendable {
    let version: String
    let uptime: Double
    let bindAddress: String
    let adapters: [AdapterInfo]
}

struct CreateSessionRequest: Codable, Sendable {
    let projectPath: String
    let cli: CLIType
}

struct SendMessageRequest: Codable, Sendable {
    let content: String
}

/// Type-erased JSON value for `metadata` fields. Supports the JSON primitive types,
/// arrays, and objects. Encodes to JSON faithfully via JSONSerialization-compatible
/// values.
struct AnyCodable: Codable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral {
    let value: any Sendable

    init(_ value: any Sendable) { self.value = value }
    init(stringLiteral value: String) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init(booleanLiteral value: Bool) { self.value = value }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = NSNull(); return }
        if let v = try? c.decode(Bool.self) { self.value = v; return }
        if let v = try? c.decode(Int.self) { self.value = v; return }
        if let v = try? c.decode(Double.self) { self.value = v; return }
        if let v = try? c.decode(String.self) { self.value = v; return }
        if let v = try? c.decode([AnyCodable].self) { self.value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { self.value = v; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let v as Bool: try c.encode(v)
        case let v as Int: try c.encode(v)
        case let v as Double: try c.encode(v)
        case let v as String: try c.encode(v)
        case let v as [AnyCodable]: try c.encode(v)
        case let v as [String: AnyCodable]: try c.encode(v)
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}

enum AdapterError: Error, Sendable, CustomStringConvertible {
    case notImplemented(CLIType)
    case launchFailed(String)
    case protocolError(String)
    case io(String)

    var description: String {
        switch self {
        case .notImplemented(let cli): return "Adapter for \(cli.rawValue) is not implemented yet."
        case .launchFailed(let msg): return "Failed to launch agent: \(msg)"
        case .protocolError(let msg): return "Agent protocol error: \(msg)"
        case .io(let msg): return "I/O error: \(msg)"
        }
    }
}
