import SwiftUI

/// REF-1 / REF-3 starter row: a `Suggestions` label followed by a vertical
/// stack of pills. Bracketed words in each suggestion render as coral
/// inline-code pills inside the pill body.
struct SuggestionsBar: View {
    let session: SessionDescriptorWire
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space8) {
            Text("Suggestions")
                .font(.system(size: 13))
                .foregroundStyle(SmoothieColor.textSecondary)
                .padding(.leading, SmoothieMetrics.space4)
            VStack(spacing: SmoothieMetrics.space8) {
                ForEach(SmoothieSuggestions.starters(for: session.cli), id: \.self) { s in
                    Button {
                        onPick(SmoothieSuggestions.plainText(s))
                    } label: {
                        suggestionPill(s)
                    }
                    .buttonStyle(.smoothiePress)
                }
            }
        }
    }

    private func suggestionPill(_ source: String) -> some View {
        let segments = SmoothieSuggestions.segments(of: source)
        return HStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    switch seg {
                    case .text(let t):
                        Text(t)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SmoothieColor.chipLabel)
                    case .code(let c):
                        Text(c)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SmoothieColor.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(SmoothieColor.accentSoft, in: .rect(cornerRadius: 4))
                    }
                }
            }
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SmoothieMetrics.space16)
        .padding(.vertical, SmoothieMetrics.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SmoothieColor.chipBg, in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                .strokeBorder(SmoothieColor.chipStroke, lineWidth: 0.5)
        )
    }
}
