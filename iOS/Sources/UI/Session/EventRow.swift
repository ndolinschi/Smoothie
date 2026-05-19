import SwiftUI

/// Locally-injected event content prefix used by SessionLiveStore to render
/// in-stream dividers (P17 soft mode switching). Keeping it in the content
/// field avoids extending the wire schema; EventRow checks for this prefix
/// before falling through to the type switch.
fileprivate let dividerSentinel = "__SMOOTHIE_DIVIDER__::"

struct EventRow: View {
    let event: SmoothieEventWire

    var body: some View {
        if event.content.hasPrefix(dividerSentinel) {
            dividerRow
        } else {
            typedBody
        }
    }

    private var dividerRow: some View {
        let label = String(event.content.dropFirst(dividerSentinel.count))
        return HStack(spacing: 10) {
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

    private var typedBody: some View {
        Group {
            switch event.type {
            case .message:
                MarkdownText(content: event.content)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .thinking:
                if !event.content.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 3)
                        Text(event.content)
                            .font(.system(size: 13))
                            .italic()
                            .foregroundStyle(.white.opacity(0.55))
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            case .toolUse:
                HStack(spacing: 6) {
                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 11))
                    Text(event.content)
                        .font(.system(size: 12, design: .monospaced))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(in: .capsule)
            case .toolResult:
                Text(event.content)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(4)
            case .fileEdit:
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 11))
                    Text(event.content)
                        .font(.system(size: 12, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.green.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(in: .capsule)
            case .waiting:
                EmptyView()       // never a row — bottom status pill shows this
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
                .glassEffect(in: .rect(cornerRadius: 12))
            }
        }
    }
}
