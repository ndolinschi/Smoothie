import Foundation
import Shared

/// Helper for the iPhone → Mac Terminal handoff path. Builds the per-CLI
/// resume command and invokes osascript to open Terminal.app focused on
/// the project's working directory.
///
/// Per-provider semantics:
/// - Claude: `claude --resume <providerSessionId>` (resumes the exact
///   conversation logged at ~/.claude/projects/<encoded-path>/<id>.jsonl).
/// - Gemini: `gemini --resume <providerSessionId>`.
/// - OpenCode: bare `opencode` — opencode's session lives inside the
///   `opencode serve` process the daemon just killed, so the Terminal
///   user gets a fresh chat in the same project. We surface this on the
///   iOS side so the user knows OpenCode handoff isn't conversation-
///   resumed.
/// - Antigravity: `agy -c` — agy threads conversations per cwd, no
///   per-id resume in `-p` output. The user picks up the most recent
///   conversation in this directory.
@MainActor
enum TerminalHandoff {
    enum Error: LocalizedError {
        case osascriptFailed(Int32, String)

        var errorDescription: String? {
            switch self {
            case .osascriptFailed(let code, let stderr):
                let detail = stderr.isEmpty ? "" : "\n\(stderr)"
                return "Couldn't open Terminal (osascript exit \(code))\(detail)"
            }
        }
    }

    static func resumeCommand(cli: CLIType, providerSessionId: String?) -> String {
        switch cli {
        case .claudeCode:
            if let id = providerSessionId, !id.isEmpty {
                return "claude --resume \(shellQuote(id))"
            }
            return "claude"
        case .gemini:
            if let id = providerSessionId, !id.isEmpty {
                return "gemini --resume \(shellQuote(id))"
            }
            return "gemini"
        case .openCode:
            // OpenCode has no resume on the CLI surface — its session
            // record lives inside `opencode serve`, which the daemon
            // killed during handoff. The Terminal user gets a fresh
            // session in the same cwd; document this in the iOS prompt.
            return "opencode"
        case .antigravity:
            return "agy -c"
        default:
            return cli.executableName
        }
    }

    static func openInTerminal(cwd: String, command: String) throws {
        // AppleScript double-quoted strings need backslash-escaping for
        // backslashes and quotes. We then wrap the whole script in
        // single-quoted argv for osascript -e so the shell doesn't
        // re-interpret the inner quotes.
        let inner = "cd \(shellQuote(cwd)) && \(command)"
        let escaped = inner
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let stderr = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = stderr
        try proc.run()
        proc.waitUntilExit()

        if proc.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8) ?? ""
            throw Error.osascriptFailed(proc.terminationStatus, errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// POSIX single-quote shell escape — wraps the value in `'…'` and
    /// escapes any embedded single quotes. Safer than `"…"` for paths
    /// with spaces, $variables, or backticks.
    private static func shellQuote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
