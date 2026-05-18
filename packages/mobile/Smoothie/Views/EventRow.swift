import SwiftUI

struct EventRow: View {
    let event: SmoothieEvent

    var body: some View {
        if shouldHide { EmptyView() }
        else {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)
                    Text(prefix)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                }

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var shouldHide: Bool {
        (event.type == .thinking || event.type == .waiting) && event.content.isEmpty
    }

    private var prefix: String {
        switch event.type {
        case .message:   return "•"
        case .thinking:  return "·"
        case .tool_use:  return "▸"
        case .file_edit: return "✎"
        case .waiting:   return "◇"
        case .done:      return "◆"
        case .error:     return "✕"
        }
    }

    private var color: Color {
        switch event.type {
        case .message:   return .white
        case .thinking:  return .white.opacity(0.5)
        case .tool_use:  return .white.opacity(0.85)
        case .file_edit: return .white.opacity(0.85)
        case .waiting:   return .white
        case .done:      return .white.opacity(0.5)
        case .error:     return Theme.error
        }
    }

    @ViewBuilder
    private var content: some View {
        switch event.type {
        case .message:
            MarkdownText(content: event.content)
        case .file_edit:
            Text(event.filePath ?? event.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassPill()
                .lineLimit(2)
        case .tool_use:
            Text(event.toolName ?? event.content)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassPill()
        default:
            Text(event.content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}
