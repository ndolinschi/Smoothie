import SwiftUI
import UIKit

/// P29 §6 — Terminal-styled card used on ConnectView (and reusable on
/// any future install / onboarding surface). Renders a fake macOS
/// window-chrome bar (red / yellow / green traffic lights + a
/// "Terminal" label) over a body of monospaced commands with token
/// coloring: `$` prompt is muted, the command itself is primary text,
/// arguments are green, flags are purple.
///
/// A "Copy" button bottom-right copies the first command to the
/// clipboard. The card stays inside the flat-dark-coral language —
/// `bgCard` + soft stroke + 14pt corner — so it sits next to the
/// other dashboard surfaces without introducing material/glass.
struct TerminalCard: View {
    /// Each line in the terminal body. Lines without a `$` prefix are
    /// rendered as raw output (no colorization).
    struct Line: Identifiable {
        enum Kind { case command, output }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    let title: String
    let lines: [Line]
    /// The command string copied to the clipboard when the user taps
    /// the trailing copy button. Defaults to the first command line
    /// (stripped of its leading `$ `) when not provided.
    let copyValue: String?

    @State private var copied: Bool = false

    init(title: String = "Terminal", lines: [Line], copyValue: String? = nil) {
        self.title = title
        self.lines = lines
        self.copyValue = copyValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            chromeBar
            Rectangle()
                .fill(SmoothieColor.strokeSoft)
                .frame(height: 0.5)
            body(for: lines)
        }
        .background(SmoothieColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    // MARK: - Chrome bar

    private var chromeBar: some View {
        ZStack {
            HStack(spacing: 6) {
                trafficLight(.red)
                trafficLight(.yellow)
                trafficLight(.green)
                Spacer()
            }
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(SmoothieColor.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private enum TrafficLight { case red, yellow, green }

    private func trafficLight(_ kind: TrafficLight) -> some View {
        let fill: Color = {
            switch kind {
            case .red:    return Color(red: 0.99, green: 0.36, blue: 0.36)
            case .yellow: return Color(red: 0.99, green: 0.74, blue: 0.18)
            case .green:  return Color(red: 0.18, green: 0.79, blue: 0.40)
            }
        }()
        return Circle()
            .fill(fill)
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5))
    }

    // MARK: - Body

    private func body(for lines: [Line]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                lineView(line)
            }
            if copyValue != nil || !lines.filter({ $0.kind == .command }).isEmpty {
                HStack {
                    Spacer()
                    copyButton
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func lineView(_ line: Line) -> some View {
        switch line.kind {
        case .command:
            Text(highlight(command: line.text))
                .font(.system(size: 13, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        case .output:
            Text(line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SmoothieColor.textSecondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var copyButton: some View {
        Button(action: copy) {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(copied ? "Copied" : "Copy")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(copied ? SmoothieColor.statusDone : SmoothieColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(SmoothieColor.bgChip, in: .capsule)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tokenisation

    /// Render a `$ command --flag arg /path` line as an AttributedString
    /// with restrained syntax colors. Order:
    ///   `$`           → tertiary text
    ///   first token   → primary text (the command)
    ///   `--flag`      → modePlan (purple)
    ///   `/path` / `~` → glyphAmber (amber)
    ///   anything else → statusDone (green)
    private func highlight(command line: String) -> AttributedString {
        var attr = AttributedString("")
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return attr }

        // Strip a leading "$ " so we can color the prompt independently.
        let hasPrompt = trimmed.hasPrefix("$")
        let body = hasPrompt ? trimmed.drop(while: { $0 == "$" }).trimmingCharacters(in: .whitespaces) : trimmed

        if hasPrompt {
            var prompt = AttributedString("$ ")
            prompt.foregroundColor = SmoothieColor.textTertiary
            attr += prompt
        }

        let tokens = body.split(separator: " ").map(String.init)
        var firstWord = true
        for (index, token) in tokens.enumerated() {
            var piece = AttributedString(token)
            // First token may be a two-word command ("brew install"); we
            // treat "brew" and "install" both as command tokens by
            // checking the running index against `1` too when the first
            // token is a known multi-word command prefix.
            let isCommandToken = firstWord || (index == 1 && isKnownMultiWordPrefix(tokens.first ?? ""))
            if isCommandToken {
                piece.foregroundColor = SmoothieColor.textPrimary
                if firstWord { firstWord = false }
            } else if token.hasPrefix("--") || token.hasPrefix("-") {
                piece.foregroundColor = SmoothieColor.modePlan
            } else if token.hasPrefix("/") || token.hasPrefix("~") {
                piece.foregroundColor = SmoothieColor.glyphAmber
            } else {
                piece.foregroundColor = SmoothieColor.statusDone
            }
            attr += piece
            if index < tokens.count - 1 {
                attr += AttributedString(" ")
            }
        }
        return attr
    }

    private func isKnownMultiWordPrefix(_ word: String) -> Bool {
        ["brew", "npm", "yarn", "pnpm", "gem", "pip", "pip3", "cargo", "go"].contains(word)
    }

    // MARK: - Clipboard

    private func copy() {
        let toCopy: String = copyValue ?? lines
            .first(where: { $0.kind == .command })
            .map { $0.text.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("$") ? String($0.dropFirst().trimmingCharacters(in: .whitespaces)) : $0 }
            ?? ""
        guard !toCopy.isEmpty else { return }
        UIPasteboard.general.string = toCopy
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}
