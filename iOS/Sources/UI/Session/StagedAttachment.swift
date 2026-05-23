import Foundation
import UIKit

/// One attachment the user has staged for the next message — either a
/// text file (prepended as a fenced block), an image (sent out-of-band
/// as base64), or a past chat transcript (folded into the body like a
/// file, but flagged distinctly so the agent treats it as reference
/// context rather than a code artefact).
enum StagedAttachment: Identifiable, Hashable {
    case file(StagedFile)
    case image(StagedImage)
    case chat(StagedChat)

    var id: UUID {
        switch self {
        case .file(let f):  return f.id
        case .image(let i): return i.id
        case .chat(let c):  return c.id
        }
    }
}

struct StagedFile: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let relativePath: String     // for "@<path>" mention syntax
    let content: String
    let truncated: Bool
}

struct StagedImage: Identifiable, Hashable {
    let id = UUID()
    let name: String             // for display only (e.g. "IMG_1234.jpg")
    let mimeType: String         // image/jpeg | image/png
    let base64: String           // raw image bytes encoded as base64
    let thumbnail: UIImage       // small preview rendered in the composer
}

/// A past chat transcript referenced via the @-mention "Past Chats"
/// category. `title` is the session's project name (or custom title);
/// `transcript` is the assembled markdown the daemon returned from
/// `GET /sessions/:id/transcript`.
struct StagedChat: Identifiable, Hashable, Sendable {
    let id = UUID()
    let sessionId: String
    let title: String
    let transcript: String
}

extension Array where Element == StagedAttachment {
    /// Files become a fenced block prepended to the user text. Images are
    /// returned alongside as a separate list — they ride on the wire as
    /// JSON-base64 in the message envelope, not in the text body. Past
    /// chats land in their own fenced section so the agent can see them
    /// as reference context distinct from code attachments.
    func composedMessage(with userText: String) -> String {
        let files = compactMap { entry -> StagedFile? in
            if case .file(let f) = entry { return f }
            return nil
        }
        let chats = compactMap { entry -> StagedChat? in
            if case .chat(let c) = entry { return c }
            return nil
        }
        guard !files.isEmpty || !chats.isEmpty else { return userText }
        var lines: [String] = []
        if !files.isEmpty {
            lines.append("--- attached files ---")
            for att in files {
                lines.append("file: \(att.relativePath)\(att.truncated ? " (truncated)" : "")")
                lines.append("```")
                lines.append(att.content)
                lines.append("```")
            }
            lines.append("--- end attached files ---")
        }
        if !chats.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("--- referenced past chats ---")
            for chat in chats {
                lines.append("past chat: \(chat.title)")
                lines.append("```markdown")
                lines.append(chat.transcript)
                lines.append("```")
            }
            lines.append("--- end referenced past chats ---")
        }
        if !userText.isEmpty {
            lines.append("")
            lines.append(userText)
        }
        return lines.joined(separator: "\n")
    }

    /// Just the image attachments, in order. APIClient sends these as a
    /// parallel `images` array in the JSON body.
    var images: [StagedImage] {
        compactMap { entry -> StagedImage? in
            if case .image(let i) = entry { return i }
            return nil
        }
    }
}
