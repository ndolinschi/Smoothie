import Foundation

/// One file the user has staged for the next message. Sent prepended as a
/// fenced block so any text-based agent receives it.
struct StagedAttachment: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let relativePath: String     // for "@<path>" mention syntax
    let content: String
    let truncated: Bool
}

extension Array where Element == StagedAttachment {
    /// Prepend the staged files to a message body as a fenced section so the
    /// agent receives them inline. Returns the original text if there are no
    /// attachments.
    func composedMessage(with userText: String) -> String {
        guard !isEmpty else { return userText }
        var lines: [String] = []
        lines.append("--- attached files ---")
        for att in self {
            lines.append("file: \(att.relativePath)\(att.truncated ? " (truncated)" : "")")
            lines.append("```")
            lines.append(att.content)
            lines.append("```")
        }
        lines.append("--- end attached files ---")
        if !userText.isEmpty {
            lines.append("")
            lines.append(userText)
        }
        return lines.joined(separator: "\n")
    }
}
