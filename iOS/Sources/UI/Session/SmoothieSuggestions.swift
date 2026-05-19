import Foundation

/// Provider-keyed starter prompts surfaced above the composer on a fresh
/// session. Words wrapped in `[brackets]` are rendered as coral inline-code
/// pills inside SuggestionsBar so phrases like `[CLAUDE.md]` or `[TODO]` pop
/// against the dark pill background (REF-1 inline-code styling).
enum SmoothieSuggestions {
    static func starters(for cli: CLIWire) -> [String] {
        switch cli {
        case .claudeCode:
            return [
                "Create or update my [CLAUDE.md] file",
                "Search for a [TODO] comment and fix it",
                "Recommend areas to improve our [tests]",
            ]
        case .gemini:
            return [
                "Plan a refactor of the [main] module",
                "Summarise the diff for the current branch",
                "Write docs for the public API",
            ]
        case .openCode:
            return [
                "Continue the last task in this repo",
                "Run the [test] suite and report failures",
                "Show me the current project [status]",
            ]
        }
    }

    /// Parses a starter string like `"Search for a [TODO] comment"` into
    /// alternating plain-text and inline-code spans.
    static func segments(of source: String) -> [Segment] {
        var out: [Segment] = []
        var remaining = Substring(source)
        while let openRange = remaining.range(of: "[") {
            let prefix = remaining[..<openRange.lowerBound]
            if !prefix.isEmpty { out.append(.text(String(prefix))) }
            let afterOpen = remaining[openRange.upperBound...]
            guard let closeRange = afterOpen.range(of: "]") else {
                out.append(.text(String(remaining[openRange.lowerBound...])))
                return out
            }
            let code = afterOpen[..<closeRange.lowerBound]
            out.append(.code(String(code)))
            remaining = afterOpen[closeRange.upperBound...]
        }
        if !remaining.isEmpty { out.append(.text(String(remaining))) }
        return out
    }

    enum Segment: Hashable {
        case text(String)
        case code(String)
    }

    /// Strip the bracket syntax so the suggestion fills the text field with a
    /// plain string when tapped.
    static func plainText(_ source: String) -> String {
        source.replacingOccurrences(of: "[", with: "")
              .replacingOccurrences(of: "]", with: "")
    }
}
