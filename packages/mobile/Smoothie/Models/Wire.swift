import Foundation
import SwiftUI

// Wire types — these mirror the server's Codable structs in Sources/SmoothieServer/Models.swift.
// Kept manually in sync.

enum CLIType: String, Codable, Sendable, CaseIterable, Identifiable {
    case opencode, claude, gemini, codex
    var id: String { rawValue }

    var label: String {
        switch self {
        case .opencode: return "OpenCode"
        case .claude:   return "Claude Code"
        case .gemini:   return "Gemini"
        case .codex:    return "Codex"
        }
    }
}

enum EventType: String, Codable, Sendable {
    case message, thinking, tool_use, file_edit, waiting, done, error
}

enum SessionState: String, Codable, Sendable {
    case starting, thinking, waiting, done, error

    var tint: Color {
        switch self {
        case .starting: return Theme.textMuted
        case .thinking: return Theme.thinking
        case .waiting:  return Theme.waiting
        case .done:     return Theme.textMuted
        case .error:    return Theme.error
        }
    }
}

struct SmoothieEvent: Codable, Sendable, Identifiable {
    let type: EventType
    let content: String
    let metadata: [String: AnyCodable]?
    let timestamp: Double

    var id: String { "\(timestamp)-\(type.rawValue)" }

    var filePath: String? { metadata?["path"]?.value as? String }
    var toolName: String? { metadata?["name"]?.value as? String }
}

struct SessionDTO: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let projectPath: String
    let projectName: String
    let cli: CLIType
    let state: SessionState
    let createdAt: Double
}

struct ProjectDTO: Codable, Sendable, Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isGit: Bool
}

struct AdapterInfo: Codable, Sendable, Identifiable {
    var id: String { cli.rawValue }
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

/// Type-erased JSON value. Mirrors the server's `AnyCodable` for `metadata` fields.
struct AnyCodable: Codable, Sendable {
    let value: any Sendable

    init(_ value: any Sendable) { self.value = value }

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self.value = NSNull(); return }
        if let v = try? c.decode(Bool.self)            { self.value = v; return }
        if let v = try? c.decode(Int.self)             { self.value = v; return }
        if let v = try? c.decode(Double.self)          { self.value = v; return }
        if let v = try? c.decode(String.self)          { self.value = v; return }
        if let v = try? c.decode([AnyCodable].self)    { self.value = v; return }
        if let v = try? c.decode([String: AnyCodable].self) { self.value = v; return }
        self.value = NSNull()
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull:                          try c.encodeNil()
        case let v as Bool:                      try c.encode(v)
        case let v as Int:                       try c.encode(v)
        case let v as Double:                    try c.encode(v)
        case let v as String:                    try c.encode(v)
        case let v as [AnyCodable]:              try c.encode(v)
        case let v as [String: AnyCodable]:      try c.encode(v)
        default:                                 try c.encodeNil()
        }
    }
}
