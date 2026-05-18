import Foundation

enum CodexAdapter {
    static func make(config: AdapterStartConfig) async throws -> any AgentAdapter {
        throw AdapterError.notImplemented(.codex)
    }
}
