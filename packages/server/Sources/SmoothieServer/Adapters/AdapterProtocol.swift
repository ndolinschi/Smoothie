import Foundation

/// Uniform interface every CLI adapter exposes once started. Each concrete
/// adapter owns its own transport (PTY, HTTP, ACP …) but speaks the same
/// shape to the rest of the server.
protocol AgentAdapter: AnyObject, Sendable {
    var cli: CLIType { get }
    var events: AsyncStream<SmoothieEvent> { get }
    func currentState() -> SessionState
    func send(_ content: String) async throws
    func terminate() async
}

/// Construction-time inputs.
struct AdapterStartConfig: Sendable {
    let projectPath: String
    let systemPromptText: String?
}

/// Helpers shared by adapters.
enum AdapterUtils {
    /// Strip ANSI CSI escape sequences (used when reading from a PTY).
    static func stripANSI(_ s: String) -> String {
        var out = String()
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "\u{1B}", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "[" {
                // Skip CSI ... letter
                var j = s.index(i, offsetBy: 2)
                while j < s.endIndex {
                    let cc = s[j]
                    if cc.isLetter { j = s.index(after: j); break }
                    j = s.index(after: j)
                }
                i = j
            } else {
                out.append(c)
                i = s.index(after: i)
            }
        }
        return out
    }
}
