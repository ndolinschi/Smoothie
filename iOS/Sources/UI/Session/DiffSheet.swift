import SwiftUI

/// Reviewable diff of every `.fileEdit` event the session has produced.
/// Each entry shows the file path, the before/after strings (for Edit) or
/// the written content (for Write), plus a single comment field. On send,
/// non-empty comments are bundled into a structured feedback message and
/// posted back to the agent — comments behave like attachments scoped to
/// a single file change.
struct DiffSheet: View {
    let events: [SmoothieEventWire]
    let onSend: (String) async -> Void
    let onDismiss: () -> Void

    @State private var comments: [String: String] = [:]
    @State private var sending = false

    private var entries: [DiffEntry] {
        events.compactMap { e in
            guard e.type == .fileEdit else { return nil }
            return DiffEntry(event: e)
        }
    }

    private var totalComments: Int {
        comments.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        SmoothieBottomSheet(title: "Diff · \(entries.count) file\(entries.count == 1 ? "" : "s")", onDismiss: onDismiss) {
            if entries.isEmpty {
                Text("No file edits in this session yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                ForEach(entries) { entry in
                    DiffEntryView(
                        entry: entry,
                        comment: Binding(
                            get: { comments[entry.id] ?? "" },
                            set: { comments[entry.id] = $0 }
                        )
                    )
                }
                sendBar
            }
        }
    }

    private var sendBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("\(totalComments) comment\(totalComments == 1 ? "" : "s") ready to send")
                    .font(.system(size: 12))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Spacer()
            }
            Button {
                Task { await sendComments() }
            } label: {
                HStack(spacing: 8) {
                    if sending {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(sending ? "Sending…" : "Send feedback to Claude")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    SmoothieColor.accent.opacity(totalComments > 0 ? 1 : 0.35),
                    in: .rect(cornerRadius: SmoothieMetrics.cornerLg)
                )
            }
            .buttonStyle(.plain)
            .disabled(totalComments == 0 || sending)
        }
        .padding(.top, 12)
    }

    private func sendComments() async {
        sending = true
        let lines = entries.compactMap { entry -> String? in
            let c = (comments[entry.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !c.isEmpty else { return nil }
            return "\(entry.toolLabel) \(entry.path)\n  → \(c)"
        }
        let body = """
        I've reviewed the file changes and have inline feedback:

        \(lines.joined(separator: "\n\n"))

        Please address these comments.
        """
        await onSend(body)
        sending = false
        onDismiss()
    }
}

/// Per-row presentation of a single `.fileEdit` event.
private struct DiffEntryView: View {
    let entry: DiffEntry
    @Binding var comment: String
    @State private var expanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                changesBlock
                commentField
            }
        }
        .padding(12)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private var header: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.glyphTint)
                Text(entry.toolLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.glyphTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.glyphTint.opacity(0.15), in: .capsule)
                Text(entry.path)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Unified line-by-line view: every removed line of `old_string` is a
    /// red `-` row, every added line of `new_string` (or `content` for
    /// Write) is a green `+` row. No extra container per side — just one
    /// list of lines with a gutter, matching the diff idiom users expect.
    @ViewBuilder
    private var changesBlock: some View {
        let rows = entry.diffRows()
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    DiffLineRowView(row: row, language: entry.languageHint)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm)
                    .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
            )
        }
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textTertiary)
                Text("Add a comment on this change")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            TextField("", text: $comment, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 13))
                .foregroundStyle(SmoothieColor.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SmoothieColor.bgChip, in: .rect(cornerRadius: SmoothieMetrics.cornerSm))
                .overlay(
                    RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm)
                        .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                )
        }
    }
}

/// Decoded view of a single `.fileEdit` event.
struct DiffEntry: Identifiable {
    let id: String
    let toolName: String
    let path: String
    let before: String?
    let after: String?
    let writeContent: String?

    init?(event: SmoothieEventWire) {
        guard event.type == .fileEdit else { return nil }
        self.id = event.id

        // Tool name comes from the event content for Claude's fileEdit
        // mapping (set in K/N ClaudeAdapter line 159).
        self.toolName = event.content

        // Pull structured input out of metadata; if absent, surface the
        // path only — better than nothing.
        let input: [String: AnyCodable]? = {
            guard let metadata = event.metadata,
                  case .object(let obj) = metadata["input"]?.value else { return nil }
            return obj
        }()

        if let p = input?["file_path"]?.value.asString ?? input?["path"]?.value.asString {
            self.path = p
        } else if let m = event.metadata, case .string(let s) = m["path"]?.value {
            self.path = s
        } else {
            return nil
        }

        switch event.content {
        case "Edit":
            self.before = input?["old_string"]?.value.asString
            self.after = input?["new_string"]?.value.asString
            self.writeContent = nil
        case "Write":
            self.before = nil
            self.after = nil
            self.writeContent = input?["content"]?.value.asString
        case "MultiEdit":
            // Aggregate the first edit's old/new for a quick preview.
            if case .array(let edits) = input?["edits"]?.value, let first = edits.first,
               case .object(let firstObj) = first.value {
                self.before = firstObj["old_string"]?.value.asString
                self.after = firstObj["new_string"]?.value.asString
            } else {
                self.before = nil; self.after = nil
            }
            self.writeContent = nil
        default:
            self.before = input?["old_string"]?.value.asString
            self.after = input?["new_string"]?.value.asString
            self.writeContent = input?["content"]?.value.asString
        }
    }

    var toolLabel: String { toolName }

    var glyph: String {
        switch toolName {
        case "Write":      return "doc.badge.plus"
        case "MultiEdit":  return "doc.text.below.ecg"
        default:           return "pencil"
        }
    }

    var glyphTint: Color {
        switch toolName {
        case "Write":      return SmoothieColor.statusDone
        case "MultiEdit":  return SmoothieColor.modeCode
        default:           return SmoothieColor.statusWaiting
        }
    }

    /// Filename extension → SyntaxHighlighter language id. Returns nil for
    /// unknown extensions (the highlighter renders as plain text in that
    /// case).
    var languageHint: String? {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":               return "swift"
        case "kt", "kts":           return "kotlin"
        case "java":                return "java"
        case "js", "mjs", "cjs":    return "javascript"
        case "jsx":                 return "jsx"
        case "ts":                  return "typescript"
        case "tsx":                 return "tsx"
        case "py":                  return "python"
        case "sh", "bash", "zsh":   return "bash"
        case "rb":                  return "ruby"
        case "go":                  return "go"
        case "rs":                  return "rust"
        case "json":                return "json"
        case "yml", "yaml":         return "yaml"
        case "sql":                 return "sql"
        case "":                    return nil
        default:                    return ext
        }
    }

    /// Turn the entry's `before` / `after` (Edit / MultiEdit) or
    /// `writeContent` (Write) into a flat list of `DiffLineItem`s ready for
    /// row rendering. No real LCS — Claude's Edit tool already gives us
    /// just the differing region, so every `before` line is a removal and
    /// every `after` / `content` line is an addition.
    func diffRows() -> [DiffLineItem] {
        var rows: [DiffLineItem] = []
        if let before, !before.isEmpty {
            var n = 1
            for line in before.split(separator: "\n", omittingEmptySubsequences: false) {
                rows.append(DiffLineItem(
                    kind: .deletion,
                    oldLineNumber: n,
                    newLineNumber: nil,
                    text: String(line)
                ))
                n += 1
            }
        }
        if let after, !after.isEmpty {
            var n = 1
            for line in after.split(separator: "\n", omittingEmptySubsequences: false) {
                rows.append(DiffLineItem(
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: n,
                    text: String(line)
                ))
                n += 1
            }
        }
        if let writeContent, !writeContent.isEmpty {
            var n = 1
            for line in writeContent.split(separator: "\n", omittingEmptySubsequences: false) {
                rows.append(DiffLineItem(
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: n,
                    text: String(line)
                ))
                n += 1
            }
        }
        return rows
    }
}

/// One renderable line in the unified diff: kind tells us whether to tint
/// the row red / green / leave it neutral; the gutter shows the line number
/// from the matching side and the +/- sign.
struct DiffLineItem {
    enum Kind { case context, addition, deletion }
    let kind: Kind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

/// Single row in the diff list. Gutter left (old line# | new line# | sign),
/// monospaced syntax-highlighted content right, background tinted by kind.
struct DiffLineRowView: View {
    let row: DiffLineItem
    let language: String?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            content
            Spacer(minLength: 0)
        }
        .background(rowBackground)
    }

    private var gutter: some View {
        HStack(spacing: 0) {
            Text(row.oldLineNumber.map(String.init) ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SmoothieColor.textTertiary)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, 2)
            Text(row.newLineNumber.map(String.init) ?? "")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SmoothieColor.textTertiary)
                .frame(width: 24, alignment: .trailing)
                .padding(.trailing, 2)
            Text(signGlyph)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(signTint)
                .frame(width: 14, alignment: .center)
        }
        .padding(.vertical, 1)
        .background(Color.black.opacity(0.15))
    }

    private var content: some View {
        let raw = row.text.isEmpty ? " " : row.text
        return Text(SyntaxHighlighter.highlight(raw, language: language))
            .font(.system(size: 11.5, design: .monospaced))
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .padding(.vertical, 1)
            .textSelection(.enabled)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var signGlyph: String {
        switch row.kind {
        case .addition:  return "+"
        case .deletion:  return "-"
        case .context:   return " "
        }
    }

    private var signTint: Color {
        switch row.kind {
        case .addition:  return SmoothieColor.statusDone
        case .deletion:  return SmoothieColor.statusErr
        case .context:   return .clear
        }
    }

    private var rowBackground: Color {
        switch row.kind {
        case .addition:  return SmoothieColor.statusDone.opacity(0.10)
        case .deletion:  return SmoothieColor.statusErr.opacity(0.12)
        case .context:   return .clear
        }
    }
}

private extension AnyCodable.Value {
    var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }
}
