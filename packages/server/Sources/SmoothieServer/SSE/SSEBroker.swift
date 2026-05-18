import Foundation

/// Formats `SmoothieEvent`s for the Server-Sent Events wire protocol.
/// Each event becomes a `event: <type>\ndata: <jsonline>\n\n` frame.
enum SSEFormatter {
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        return enc
    }()

    static func frame(_ event: SmoothieEvent) -> Data {
        var out = Data()
        out.append("event: \(event.type.rawValue)\n".data(using: .utf8) ?? Data())
        if let json = try? encoder.encode(event),
           let body = String(data: json, encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ") {
            out.append("data: \(body)\n\n".data(using: .utf8) ?? Data())
        } else {
            out.append("data: {}\n\n".data(using: .utf8) ?? Data())
        }
        return out
    }

    static func heartbeat() -> Data {
        Data(": keep-alive\n\n".utf8)
    }

    static func errorFrame(_ message: String) -> Data {
        var out = Data()
        out.append("event: error\n".data(using: .utf8) ?? Data())
        let escaped = message.replacingOccurrences(of: "\n", with: " ")
        out.append("data: {\"error\":\"\(escaped)\"}\n\n".data(using: .utf8) ?? Data())
        return out
    }
}
