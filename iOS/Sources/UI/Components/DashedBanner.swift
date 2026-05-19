import SwiftUI

/// Dashed-border card used for the home-screen orientation banner. Mirrors
/// REF-4's "Take your desktop sessions on the go" callout.
struct DashedBanner<Trailing: View>: View {
    let title: String
    let message: String
    let linkText: String?
    let onLink: (() -> Void)?
    let onDismiss: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        message: String,
        linkText: String? = nil,
        onLink: (() -> Void)? = nil,
        onDismiss: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.message = message
        self.linkText = linkText
        self.onLink = onLink
        self.onDismiss = onDismiss
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .lineLimit(3)
                if let linkText, let onLink {
                    Button(action: onLink) {
                        Text(linkText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SmoothieColor.textPrimary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            trailing()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.02))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.strokeDashed,
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd))
    }
}
