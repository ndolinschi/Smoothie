import Foundation

/// On-disk shape of the latest session state shared between the host app and
/// the widget extension via App Group container. Kept intentionally tiny so
/// the WidgetKit timeline budget never has to parse anything substantial.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public enum WireState: String, Codable, Sendable {
        case none, starting, thinking, waiting, done, error, limitReached
    }

    public enum WireCLI: String, Codable, Sendable {
        case claudeCode = "claude_code"
        case gemini
        case openCode = "open_code"
    }

    public let sessionId: String?
    public let projectName: String?
    public let cli: WireCLI?
    public let state: WireState
    public let lastEventAt: Date

    public init(
        sessionId: String?,
        projectName: String?,
        cli: WireCLI?,
        state: WireState,
        lastEventAt: Date
    ) {
        self.sessionId = sessionId
        self.projectName = projectName
        self.cli = cli
        self.state = state
        self.lastEventAt = lastEventAt
    }

    public static let placeholder = WidgetSnapshot(
        sessionId: nil,
        projectName: nil,
        cli: nil,
        state: .none,
        lastEventAt: .distantPast
    )
}
