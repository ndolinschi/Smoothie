import SwiftUI

/// Shared shell for every Smoothie bottom sheet (mode picker, attach picker,
/// pairings, voice-unavailable, etc.). Centralises the REF-2 styling:
/// flat dark background, 20pt top corner, drag indicator, header row with
/// leading X button and centred title.
struct SmoothieBottomSheet<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 6) {
                    content()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SmoothieColor.bgSheet.ignoresSafeArea())
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(SmoothieColor.bgGlyph, in: .circle)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}
