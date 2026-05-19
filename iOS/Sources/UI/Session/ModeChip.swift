import SwiftUI

/// REF-1 / REF-5 bottom-row leading chip: glyph in mode-color + label. Tap
/// opens the ModeSheet so the user can switch between Code and Plan.
struct ModeChip: View {
    let mode: String?
    let onTap: () -> Void

    private var resolved: (icon: String, color: Color, label: String) {
        switch (mode ?? "default").lowercased() {
        case "plan":          return ("doc.text", SmoothieColor.modePlan, "Plan")
        case "auto_edit":     return ("scribble", SmoothieColor.modeCode, "Auto-edit")
        case "yolo":          return ("bolt.fill", SmoothieColor.statusErr, "Yolo")
        default:              return ("chevron.left.forwardslash.chevron.right", SmoothieColor.modeCode, "Code")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: resolved.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(resolved.color)
                Text(resolved.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
