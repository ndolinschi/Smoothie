import SwiftUI

/// Composer-level chip surfacing the current model with a tier dot +
/// chevron. Tap opens the model picker. Promoted in Phase 3 of the
/// Cursor redesign so model switching no longer requires drilling into
/// the AttachSheet `+` menu — matches the Cursor-mobile composer's
/// pattern of having the model affordance always visible above the
/// keyboard.
struct ModelChip: View {
    let cli: CLIWire
    let model: String?
    let onTap: () -> Void

    private var tier: ModelCatalog.Tier {
        ModelCatalog.tier(cli: cli, model: model)
    }

    private var label: String {
        ModelCatalog.displayLabel(cli: cli, model: model)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tier.dotColor)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(SmoothieColor.bgChip, in: .capsule)
            .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ModelChip(cli: .claudeCode, model: "sonnet", onTap: {})
        ModelChip(cli: .claudeCode, model: "haiku", onTap: {})
        ModelChip(cli: .claudeCode, model: "opus", onTap: {})
        ModelChip(cli: .gemini, model: "gemini-3-flash-preview", onTap: {})
        ModelChip(cli: .openCode, model: "anthropic/claude-sonnet-4-5", onTap: {})
        ModelChip(cli: .antigravity, model: nil, onTap: {})
    }
    .padding()
    .background(SmoothieColor.bgPrimary)
    .preferredColorScheme(.dark)
}
#endif
