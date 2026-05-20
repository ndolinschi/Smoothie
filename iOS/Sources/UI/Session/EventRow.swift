import SwiftUI

/// Legacy sentinel-prefix from P17 soft mode switching. Kept so events
/// still buffered from older builds render correctly; new events use
/// the safer `metadata["divider"]` flag (P24.b B5) which can't be
/// hijacked by an agent that happens to echo this literal string.
fileprivate let dividerSentinel = "__SMOOTHIE_DIVIDER__::"

struct EventRow: View {
    let event: SmoothieEventWire
    @State private var expanded = false

    /// Resolve a divider label from either the new metadata flag or the
    /// legacy sentinel prefix. Metadata wins when both are set.
    private var dividerLabel: String? {
        if let s = event.metadata?["divider"]?.stringValue, !s.isEmpty {
            return s
        }
        if event.content.hasPrefix(dividerSentinel) {
            return String(event.content.dropFirst(dividerSentinel.count))
        }
        return nil
    }

    var body: some View {
        if let label = dividerLabel {
            dividerRow(label: label)
        } else {
            typedBody
        }
    }

    private func dividerRow(label: String) -> some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(SmoothieColor.strokeSoft)
                .frame(height: 0.5)
            Text("(\(label))")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(SmoothieColor.textTertiary)
                .fixedSize()
            Rectangle()
                .fill(SmoothieColor.strokeSoft)
                .frame(height: 0.5)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var typedBody: some View {
        switch event.type {
        case .message:
            MarkdownText(content: event.content)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thinking:
            if !event.content.isEmpty {
                thinkingRow
            }
        case .toolUse:
            toolRow(icon: "wrench.adjustable", tint: .white.opacity(0.75))
        case .toolResult:
            Text(event.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(expanded ? nil : 4)
                .onTapGesture { expanded.toggle() }
        case .fileEdit:
            toolRow(icon: "doc.text.fill", tint: .green.opacity(0.85))
        case .waiting:
            EmptyView()
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text(event.content.isEmpty ? "Done" : event.content)
            }
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.55))
        case .error, .limitReached:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(event.content)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SmoothieColor.statusErr.opacity(0.12), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SmoothieColor.statusErr.opacity(0.35), lineWidth: 0.5)
            )
        }
    }

    /// Collapsed reasoning chip ("thinking ▾"). Tap to reveal the italic
    /// monologue — hidden by default so Claude's internal stream-of-
    /// consciousness doesn't dominate the chat. Each thinking event keeps
    /// its own expansion state.
    private var thinkingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .semibold))
                    Text("thinking")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(SmoothieColor.bgCard, in: .capsule)
                .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            if expanded {
                Text(event.content)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(.white.opacity(0.55))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Chip + optional expandable detail for `.toolUse` and `.fileEdit`.
    /// The chip is always tappable; if the event has structured input
    /// metadata (Bash's `command`, Edit's `old_string`, etc.), tapping
    /// reveals a key/value detail block below.
    private func toolRow(icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if !inputFields.isEmpty { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                    Text(event.content)
                        .font(.system(size: 12, design: .monospaced))
                    if !inputFields.isEmpty {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(SmoothieColor.bgCard, in: .capsule)
                .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
            }
            .buttonStyle(.plain)

            if expanded, !inputFields.isEmpty {
                ToolInputView(fields: inputFields)
            }
        }
    }

    /// Ordered list of (key, value) pairs extracted from
    /// `metadata.input`. Empty if the event has no input — in which case
    /// the chip stays non-expandable.
    private var inputFields: [(String, String)] {
        guard let metadata = event.metadata,
              let input = metadata["input"]
        else { return [] }
        guard case .object(let inputObj) = input.value else { return [] }
        let priority = [
            "command", "description",
            "file_path", "path",
            "pattern", "glob",
            "old_string", "new_string",
            "content",
            "url",
            "prompt",
        ]
        var seen: Set<String> = []
        var ordered: [(String, String)] = []
        for key in priority {
            if let v = inputObj[key] {
                ordered.append((key, anyCodableString(v)))
                seen.insert(key)
            }
        }
        for key in inputObj.keys.sorted() where !seen.contains(key) {
            if let v = inputObj[key] {
                ordered.append((key, anyCodableString(v)))
            }
        }
        return ordered
    }

    private func anyCodableString(_ v: AnyCodable) -> String {
        switch v.value {
        case .null:           return "null"
        case .bool(let b):    return b ? "true" : "false"
        case .int(let i):     return String(i)
        case .double(let d):  return String(d)
        case .string(let s):  return s
        case .array(let arr):
            return "[" + arr.map { anyCodableString($0) }.joined(separator: ", ") + "]"
        case .object(let obj):
            return "{" + obj.map { "\($0.key): \(anyCodableString($0.value))" }.joined(separator: ", ") + "}"
        }
    }
}

/// Renders the structured input args of a tool call. Mono-font, scrollable
/// for very long fields (e.g. Edit's `old_string`). Sits below the chip
/// when the user taps to expand.
private struct ToolInputView: View {
    let fields: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                VStack(alignment: .leading, spacing: 3) {
                    Text(field.0.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(SmoothieColor.textTertiary)
                    Text(field.1)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerSm))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }
}
