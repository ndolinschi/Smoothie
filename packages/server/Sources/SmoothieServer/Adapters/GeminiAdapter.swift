import Foundation

enum GeminiAdapter {
    static func make(config: AdapterStartConfig) async throws -> any AgentAdapter {
        throw AdapterError.notImplemented(.gemini)
    }
}
