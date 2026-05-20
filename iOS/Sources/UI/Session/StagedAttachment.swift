import Foundation
import UIKit

/// One attachment the user has staged for the next message — either a text
/// file (prepended as a fenced block in the body) or an image (sent
/// out-of-band as base64 in the request payload so ClaudeAdapter can wrap
/// it in a content-block on the wire).
enum StagedAttachment: Identifiable, Hashable {
    case file(StagedFile)
    case image(StagedImage)

    var id: UUID {
        switch self {
        case .file(let f):  return f.id
        case .image(let i): return i.id
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

extension Array where Element == StagedAttachment {
    /// Files become a fenced block prepended to the user text. Images are
    /// returned alongside as a separate list — they ride on the wire as
    /// JSON-base64 in the message envelope, not in the text body.
    func composedMessage(with userText: String) -> String {
        let files = compactMap { entry -> StagedFile? in
            if case .file(let f) = entry { return f }
            return nil
        }
        guard !files.isEmpty else { return userText }
        var lines: [String] = []
        lines.append("--- attached files ---")
        for att in files {
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

    /// Just the image attachments, in order. APIClient sends these as a
    /// parallel `images` array in the JSON body.
    var images: [StagedImage] {
        compactMap { entry -> StagedImage? in
            if case .image(let i) = entry { return i }
            return nil
        }
    }
}
