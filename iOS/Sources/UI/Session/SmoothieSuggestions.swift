import Foundation

/// Provider-keyed starter prompts surfaced above the composer on a fresh
/// session. Three per CLI keeps the row scannable and matches the reference
/// composer screenshot.
enum SmoothieSuggestions {
    static func starters(for cli: CLIWire) -> [String] {
        switch cli {
        case .claudeCode:
            return [
                "Explain this repo",
                "Find a bug",
                "Write tests",
            ]
        case .gemini:
            return [
                "Plan a refactor",
                "Summarise the diff",
                "Write docs",
            ]
        case .openCode:
            return [
                "Continue last task",
                "Run the test suite",
                "Show project status",
            ]
        }
    }
}
