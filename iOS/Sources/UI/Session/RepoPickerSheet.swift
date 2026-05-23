import SwiftUI

/// Bottom-sheet repository picker (P25.f). Surfaces every project the user
/// has touched (via RecentsStore), with the current session's project
/// checkmarked. Tapping a different project dismisses the session view and
/// stamps the picked path so HomeView surfaces it.
///
/// Search-bar filtering matches on the resolved `owner/repo` label, the
/// raw path's last component, and the full path — so users can find a
/// repo by typing any of "smoothie", "ndolinschi/Smoothie", or
/// "~/Code/smoothie".
struct RepoPickerSheet: View {
    let currentPath: String
    let recentPaths: [String]
    let onPick: (String) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""

    private var allPaths: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in [currentPath] + recentPaths where seen.insert(p).inserted {
            out.append(p)
        }
        return out
    }

    private var filtered: [String] {
        guard !query.isEmpty else { return allPaths }
        let q = query.lowercased()
        return allPaths.filter { path in
            let basename = (path as NSString).lastPathComponent.lowercased()
            return basename.contains(q) || path.lowercased().contains(q)
        }
    }

    var body: some View {
        SmoothieBottomSheet(title: "Choose repository", onDismiss: onDismiss) {
            VStack(spacing: SmoothieMetrics.space12) {
                searchField
                if filtered.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: SmoothieMetrics.space6) {
                        ForEach(filtered, id: \.self) { path in
                            row(for: path)
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: SmoothieMetrics.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SmoothieColor.textTertiary)
            TextField("Search repositories", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
        }
        .padding(.horizontal, SmoothieMetrics.rowPaddingH)
        .padding(.vertical, 11)
        .background(SmoothieColor.surface2, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private func row(for path: String) -> some View {
        let isCurrent = path == currentPath
        let basename = (path as NSString).lastPathComponent
        let owner = ownerSegment(for: path)
        let title = owner.map { "\($0)/\(basename)" } ?? basename
        return Button {
            onPick(path)
        } label: {
            HStack(spacing: SmoothieMetrics.space12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(SmoothieColor.surface2, in: .rect(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: SmoothieMetrics.space8)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(SmoothieColor.accent)
                }
            }
            .padding(SmoothieMetrics.space12)
            .background(SmoothieColor.surface1, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                    .strokeBorder(
                        isCurrent ? SmoothieColor.accent.opacity(0.5) : SmoothieColor.strokeSoft,
                        lineWidth: isCurrent ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: SmoothieMetrics.space8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("No repositories match.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text("Pair a Mac or start a session in another project to add it here.")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, SmoothieMetrics.space24)
        }
        .padding(.vertical, SmoothieMetrics.space24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
                )
                .foregroundStyle(SmoothieColor.strokeDashed)
        )
    }

    private func ownerSegment(for path: String) -> String? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Users" else { return nil }
        return String(parts[1])
    }
}
