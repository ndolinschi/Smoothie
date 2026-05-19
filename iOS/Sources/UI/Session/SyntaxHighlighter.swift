import SwiftUI
import UIKit

/// Minimal regex-driven code highlighter for mobile chat. Targets the common
/// languages an agent emits in fenced code blocks: Swift / Kotlin / Java,
/// JavaScript / TypeScript, Python, Bash, Go, Rust, JSON, YAML, plus diff
/// fragments. Skips real lexers — strings, comments, numbers, and a per-
/// language keyword set is enough to make the snippets readable on a phone
/// without pulling in a heavy dependency.
enum SyntaxHighlighter {
    /// One Dark-ish palette mapped to UIKit colors so NSAttributedString
    /// can apply ranges directly.
    enum Theme {
        static let plain    = UIColor(white: 0.92, alpha: 1)
        static let keyword  = UIColor(red: 0.78, green: 0.52, blue: 0.81, alpha: 1) // pinky-purple
        static let string   = UIColor(red: 0.81, green: 0.57, blue: 0.47, alpha: 1) // orange-ish
        static let comment  = UIColor(red: 0.45, green: 0.60, blue: 0.36, alpha: 1) // muted green
        static let number   = UIColor(red: 0.71, green: 0.81, blue: 0.66, alpha: 1) // light green
        static let type     = UIColor(red: 0.31, green: 0.81, blue: 0.69, alpha: 1) // teal
        static let constant = UIColor(red: 0.34, green: 0.65, blue: 0.92, alpha: 1) // blue
        static let diffAdd  = UIColor(red: 0.20, green: 0.83, blue: 0.60, alpha: 1)
        static let diffDel  = UIColor(red: 0.94, green: 0.40, blue: 0.40, alpha: 1)
    }

    static func highlight(_ code: String, language: String?) -> AttributedString {
        let lang = (language ?? "").lowercased()
        let ns = NSMutableAttributedString(
            string: code,
            attributes: [.foregroundColor: Theme.plain]
        )

        // Diff has its own line-prefix rules — handle and bail early.
        if lang == "diff" || lang == "patch" {
            applyDiff(ns: ns, source: code)
            return AttributedString(ns)
        }

        // Order matters: keyword/number stamp colour, then strings/comments
        // overwrite (strings + comments contain keywords too, and should win).
        applyKeywords(ns: ns, source: code, lang: lang)
        applyNumbers(ns: ns, source: code)
        applyStrings(ns: ns, source: code, lang: lang)
        applyComments(ns: ns, source: code, lang: lang)
        return AttributedString(ns)
    }

    // MARK: - Languages

    /// Keyword bag per language. Order of an enum keeps the matcher honest —
    /// we use word-boundary `\b` so partial matches don't paint other tokens.
    private static let keywords: [String: [String]] = [
        // Swift / Kotlin (very overlapping; Java too)
        "swift": SWIFT_KW,
        "kotlin": KOTLIN_KW,
        "java": KOTLIN_KW,
        // JavaScript / TypeScript family
        "javascript": JS_KW,
        "js":         JS_KW,
        "jsx":        JS_KW,
        "typescript": TS_KW,
        "ts":         TS_KW,
        "tsx":        TS_KW,
        // Python
        "python":     PY_KW,
        "py":         PY_KW,
        // Bash family
        "bash":       SH_KW,
        "sh":         SH_KW,
        "shell":      SH_KW,
        "zsh":        SH_KW,
        // Go / Rust / Ruby
        "go":         GO_KW,
        "rust":       RUST_KW,
        "rs":         RUST_KW,
        "ruby":       RUBY_KW,
        "rb":         RUBY_KW,
    ]

    private static let SWIFT_KW = [
        "func", "let", "var", "if", "else", "guard", "return", "for", "in", "while",
        "switch", "case", "default", "break", "continue", "do", "try", "catch", "throw",
        "throws", "rethrows", "async", "await", "import", "class", "struct", "enum",
        "protocol", "extension", "actor", "init", "deinit", "self", "Self", "nil",
        "true", "false", "private", "public", "internal", "fileprivate", "open",
        "static", "final", "lazy", "weak", "unowned", "where", "as", "is", "some", "any",
        "@MainActor", "@Observable", "@State", "@Binding", "@Environment",
    ]
    private static let KOTLIN_KW = [
        "fun", "val", "var", "if", "else", "when", "return", "for", "in", "while",
        "break", "continue", "do", "try", "catch", "finally", "throw", "throws",
        "suspend", "import", "class", "object", "interface", "data", "enum", "sealed",
        "abstract", "open", "override", "init", "constructor", "this", "super", "null",
        "true", "false", "private", "public", "internal", "protected", "companion",
        "lateinit", "lazy", "by", "where", "as", "is", "out", "in", "vararg",
    ]
    private static let JS_KW = [
        "function", "const", "let", "var", "if", "else", "return", "for", "while",
        "switch", "case", "default", "break", "continue", "do", "try", "catch",
        "finally", "throw", "async", "await", "import", "export", "from", "class",
        "extends", "new", "this", "super", "null", "undefined", "true", "false",
        "typeof", "instanceof", "in", "of", "yield", "delete", "void",
    ]
    private static let TS_KW = JS_KW + [
        "interface", "type", "enum", "namespace", "declare", "readonly", "implements",
        "public", "private", "protected", "abstract", "static", "as", "is", "keyof",
    ]
    private static let PY_KW = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from",
        "as", "pass", "break", "continue", "try", "except", "finally", "raise", "with",
        "yield", "async", "await", "lambda", "global", "nonlocal", "and", "or", "not",
        "is", "in", "True", "False", "None", "self", "cls",
    ]
    private static let SH_KW = [
        "if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until",
        "case", "esac", "function", "return", "export", "local", "readonly", "set",
        "unset", "echo", "printf", "read", "cd", "exit", "trap", "source", "alias",
    ]
    private static let GO_KW = [
        "func", "var", "const", "if", "else", "for", "range", "return", "break",
        "continue", "switch", "case", "default", "fallthrough", "go", "defer", "chan",
        "select", "import", "package", "type", "struct", "interface", "map", "nil",
        "true", "false", "new", "make", "iota",
    ]
    private static let RUST_KW = [
        "fn", "let", "mut", "if", "else", "match", "for", "in", "while", "loop",
        "return", "break", "continue", "use", "pub", "mod", "crate", "self", "Self",
        "struct", "enum", "trait", "impl", "type", "const", "static", "ref", "where",
        "as", "async", "await", "move", "dyn", "unsafe", "true", "false",
    ]
    private static let RUBY_KW = [
        "def", "class", "module", "if", "elsif", "else", "unless", "end", "do", "while",
        "until", "for", "in", "return", "begin", "rescue", "ensure", "raise", "yield",
        "require", "include", "extend", "self", "nil", "true", "false", "and", "or", "not",
    ]

    private static func applyKeywords(ns: NSMutableAttributedString, source: String, lang: String) {
        guard let words = keywords[lang], !words.isEmpty else { return }
        // Escape & join into a single alternation for a single regex pass.
        let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
        let pattern = "(?<![A-Za-z0-9_])(" + escaped.joined(separator: "|") + ")(?![A-Za-z0-9_])"
        applyRegex(pattern, color: Theme.keyword, ns: ns, source: source)
    }

    // MARK: - Tokens

    private static func applyNumbers(ns: NSMutableAttributedString, source: String) {
        // Integers, decimals, hex, binary literals.
        applyRegex(
            #"(?<![A-Za-z_])(?:0[xX][0-9A-Fa-f_]+|0[bB][01_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)"#,
            color: Theme.number, ns: ns, source: source
        )
    }

    private static func applyStrings(ns: NSMutableAttributedString, source: String, lang: String) {
        // Double-quoted with embedded \" escape.
        applyRegex(#""(?:[^"\\\n]|\\.)*""#, color: Theme.string, ns: ns, source: source)
        // Single-quoted (JS char / Python / shell single-quoted).
        applyRegex(#"'(?:[^'\\\n]|\\.)*'"#, color: Theme.string, ns: ns, source: source)
        // Backtick template strings (JS / Kotlin) — single line only; safer.
        if lang.hasPrefix("ts") || lang.hasPrefix("js") || lang == "kotlin" {
            applyRegex(#"`(?:[^`\\\n]|\\.)*`"#, color: Theme.string, ns: ns, source: source)
        }
    }

    private static func applyComments(ns: NSMutableAttributedString, source: String, lang: String) {
        // Block comments /* ... */ — handles multi-line by using dotMatchesLineSeparators.
        if shouldUseBlockComment(lang: lang) {
            applyRegex(#"/\*[\s\S]*?\*/"#, color: Theme.comment, ns: ns, source: source)
        }
        // Line comments. Choose prefix(es) per language.
        let prefixes = lineCommentPrefixes(for: lang)
        for prefix in prefixes {
            let escaped = NSRegularExpression.escapedPattern(for: prefix)
            applyRegex("\(escaped)[^\\n]*", color: Theme.comment, ns: ns, source: source)
        }
    }

    private static func shouldUseBlockComment(lang: String) -> Bool {
        switch lang {
        case "python", "py", "bash", "sh", "shell", "zsh", "yaml", "yml", "ruby", "rb":
            return false
        default:
            return true
        }
    }

    private static func lineCommentPrefixes(for lang: String) -> [String] {
        switch lang {
        case "python", "py", "bash", "sh", "shell", "zsh", "ruby", "rb", "yaml", "yml":
            return ["#"]
        case "sql":
            return ["--"]
        case "":
            return []
        default:
            return ["//"]
        }
    }

    // MARK: - Diff

    private static func applyDiff(ns: NSMutableAttributedString, source: String) {
        var lineStart = source.startIndex
        while lineStart < source.endIndex {
            let lineEnd = source[lineStart...].firstIndex(of: "\n") ?? source.endIndex
            let line = source[lineStart..<lineEnd]
            let nsRange = NSRange(lineStart..<lineEnd, in: source)
            if let first = line.first {
                switch first {
                case "+":
                    if !line.hasPrefix("+++") {
                        ns.addAttribute(.foregroundColor, value: Theme.diffAdd, range: nsRange)
                    }
                case "-":
                    if !line.hasPrefix("---") {
                        ns.addAttribute(.foregroundColor, value: Theme.diffDel, range: nsRange)
                    }
                case "@":
                    ns.addAttribute(.foregroundColor, value: Theme.constant, range: nsRange)
                default:
                    break
                }
            }
            if lineEnd == source.endIndex { break }
            lineStart = source.index(after: lineEnd)
        }
    }

    // MARK: - Regex helper

    private static func applyRegex(
        _ pattern: String,
        color: UIColor,
        ns: NSMutableAttributedString,
        source: String
    ) {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators]
        ) else { return }
        let full = NSRange(source.startIndex..<source.endIndex, in: source)
        regex.enumerateMatches(in: source, options: [], range: full) { match, _, _ in
            guard let r = match?.range else { return }
            if r.length == 0 { return }
            ns.addAttribute(.foregroundColor, value: color, range: r)
        }
    }
}
