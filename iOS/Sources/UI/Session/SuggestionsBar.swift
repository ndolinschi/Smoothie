import SwiftUI

/// Above-the-composer starter row. Three suggestion pills on the left, then a
/// scroll into the connected-project chip and the active-provider chip. Only
/// rendered on a brand-new session (no events received yet, no staged
/// attachments, empty text field).
struct SuggestionsBar: View {
    let session: SessionDescriptorWire
    let onPick: (String) -> Void

    private var projectLabel: String {
        (session.projectPath as NSString).lastPathComponent
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SmoothieSuggestions.starters(for: session.cli), id: \.self) { s in
                    Button {
                        onPick(s)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.55))
                            Text(s)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(in: .capsule)
                    }
                    .buttonStyle(.plain)
                }

                Divider()
                    .frame(height: 14)
                    .overlay(Color.white.opacity(0.12))
                    .padding(.horizontal, 2)

                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                    Text(projectLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(in: .capsule)

                HStack(spacing: 4) {
                    ProviderIcon(cli: session.cli, size: 11)
                    Text(session.cli.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(in: .capsule)
            }
            .padding(.horizontal, 4)
        }
    }
}
