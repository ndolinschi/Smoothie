import Foundation
import Shared

/// One image attached to a user turn. The base64 string is the raw JPEG /
/// PNG body, not a data-URL; mime type is one of `image/jpeg`, `image/png`,
/// etc. ClaudeAdapter wraps these into stream-json content blocks; Gemini
/// and OpenCode hosts reject via the default protocol method.
struct ImageAttachment: Sendable {
    let mimeType: String
    let base64: String
}

/// Common surface that any provider's process / transport host needs to
/// expose so ProcessRegistry can hold it in one dictionary. ProcessHost
/// drives Claude over piped stdio; GeminiOneshotHost spawns a fresh
/// `gemini -p` process per turn; OpenCodeServeHost talks HTTP to a long-
/// running `opencode serve` child.
@MainActor
protocol SessionHost: AnyObject {
    var session: Session { get }
    var isRunning: Bool { get }
    func start() throws
    func write(_ content: String) async throws
    /// Send a turn that may include image attachments. Default impl falls
    /// through to `write(_:)` when there are no images, and throws a clear
    /// "not supported" error when images are present — only ProcessHost
    /// (Claude) overrides with real content-block encoding for v0.
    func write(text: String, images: [ImageAttachment]) async throws
    /// Cancel the in-flight turn without killing the session entirely. Each
    /// host best-effort: ProcessHost (Claude) sends SIGINT so the agent can
    /// interrupt cleanly; GeminiOneshotHost terminates the current one-shot
    /// spawn (next write respawns); OpenCodeServeHost POSTs the opencode
    /// `/abort` endpoint and keeps the long-running server up.
    func abort() async
    func terminate()
}

extension SessionHost {
    func write(text: String, images: [ImageAttachment]) async throws {
        if images.isEmpty {
            try await write(text)
        } else {
            throw NSError(domain: "Smoothie", code: 415, userInfo: [
                NSLocalizedDescriptionKey:
                    "Image attachments aren't supported on this provider yet — only Claude can read images today."
            ])
        }
    }
}
