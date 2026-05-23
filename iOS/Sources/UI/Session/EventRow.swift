import SwiftUI

/// Legacy sentinel-prefix from P17 soft mode switching. Kept so events
/// still buffered from older builds render correctly; new events use
/// the safer `metadata["divider"]` flag (P24.b B5) which can't be
/// hijacked by an agent that happens to echo this literal string.
fileprivate let dividerSentinel = "__SMOOTHIE_DIVIDER__::"

struct EventRow: View {
    let event: SmoothieEventWire
    @State private var expanded = false

    var body: some View {
        if let label = Self.dividerLabel(for: event) {
            dividerRow(label: label)
        } else {
            typedBody
        }
    }

    /// Resolve a divider label from either the new metadata flag or the
    /// legacy sentinel prefix. Static so `AgentStreamItem.collapse` can
    /// guard against absorbing a divider into an adjacent tool run.
    static func dividerLabel(for event: SmoothieEventWire) -> String? {
        if let s = event.metadata?["divider"]?.stringValue, !s.isEmpty {
            return s
        }
        if event.content.hasPrefix(dividerSentinel) {
            return String(event.content.dropFirst(dividerSentinel.count))
        }
        return nil
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
        case .toolUse, .fileEdit:
            // Tool invocations are grouped into a `ToolCallCard` by
            // `AgentStreamItem.collapse` before reaching this row. The
            // case stays as a defensive `EmptyView` in case a future
            // call site renders an `EventRow` outside the agent stream.
            EmptyView()
        case .toolResult:
            // Most `.toolResult` events are absorbed into a `ToolCallCard`
            // by the collapse step; this fallback only fires for standalone
            // results (e.g. a daemon-emitted result without a paired
            // tool_use) and divider events handled above.
            Text(event.content)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(expanded ? nil : 4)
                .onTapGesture { expanded.toggle() }
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
                    .foregroundStyle(SmoothieColor.statusErr)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(SmoothieColor.statusErr.opacity(0.12), in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SmoothieColor.statusErr.opacity(0.35), lineWidth: 0.5)
            )
        case .contextUpdate:
            // Side-channel event consumed by SessionLiveStore — never
            // belongs in the visible stream.
            EmptyView()
        case .unknown:
            // Forward-compat: a newer daemon emitted an event type this
            // build doesn't know. Render nothing rather than crashing;
            // the next known event will rejoin the visible stream.
            EmptyView()
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

    /// Ordered list of `(key, value)` pairs extracted from `metadata.input`.
    /// Used by `ToolCallCard` (via `AgentStream`) to populate the card
    /// body. Returns an empty array if the event has no structured input
    /// or the input isn't a JSON object. `hidingKeys` lets callers drop
    /// fields already surfaced elsewhere — e.g. AgentStream hides
    /// `subagent_type` for Task tool calls because the value is already
    /// rendered as a header badge on the card.
    static func inputFields(
        from event: SmoothieEventWire,
        hidingKeys: Set<String> = []
    ) -> [(String, String)] {
        guard let metadata = event.metadata,
              let input = metadata["input"]
        else { return [] }
        guard case .object(let inputObj) = input.value else { return [] }
        // `prompt` is now near the top so Task tool invocations surface
        // the subagent's instructions before any auxiliary fields.
        let priority = [
            "prompt",
            "command", "description",
            "file_path", "path",
            "pattern", "glob",
            "old_string", "new_string",
            "content",
            "url",
        ]
        var seen: Set<String> = hidingKeys
        var ordered: [(String, String)] = []
        for key in priority where !seen.contains(key) {
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

    /// Pull the subagent kind out of a Task tool's metadata so
    /// `ToolCallCard` can render it as a header chip. Claude's
    /// stream-json wraps the value under `metadata.input.subagent_type`.
    /// Returns nil when the field is missing or empty — caller falls
    /// back to the bare "Task" name in that case.
    static func subagentType(from event: SmoothieEventWire) -> String? {
        guard let metadata = event.metadata,
              let input = metadata["input"]
        else { return nil }
        guard case .object(let inputObj) = input.value else { return nil }
        guard let raw = inputObj["subagent_type"] else { return nil }
        if case .string(let s) = raw.value, !s.isEmpty {
            return s
        }
        return nil
    }

    private static func anyCodableString(_ v: AnyCodable) -> String {
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
