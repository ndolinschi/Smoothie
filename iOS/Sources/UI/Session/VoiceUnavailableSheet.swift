import SwiftUI

/// Bottom-sheet replacement for the prior `.alert("Voice unavailable")`.
/// Surfaces in REF-2 styling so the user gets the same visual language across
/// every modal in the app. Body adapts to the underlying failure reason.
struct VoiceUnavailableSheet: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        SmoothieBottomSheet(title: "Voice unavailable", onDismiss: onDismiss) {
            VStack(spacing: 18) {
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 72, height: 72)
                    .background(SmoothieColor.bgGlyph, in: .circle)
                    .padding(.top, 8)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 24)
                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(SmoothieColor.accent, in: .capsule)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
        }
    }
}
