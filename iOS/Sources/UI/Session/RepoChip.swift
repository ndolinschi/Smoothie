import SwiftUI

/// REF-1 project chip rendered to the right of the + button. Uses a folder
/// glyph for plain directories and a Git symbol when the underlying project
/// is a git checkout. The label is the path's last component.
struct RepoChip: View {
    let projectPath: String
    let isGit: Bool
    /// Optional `owner/repo` override (e.g. parsed from `.git/config`'s
    /// remote URL on the macOS side). When nil, we derive a label of the
    /// form `<mac-user>/<folder>` which matches the visual shape of the
    /// reference's GitHub repo chip even for purely-local projects.
    let label: String?
    /// True when this chip represents the currently-active session's
    /// project — gets an accent stroke + bold label so the row reads
    /// "you are here" at a glance (P25.e).
    let isActive: Bool

    init(projectPath: String, isGit: Bool, label: String? = nil, isActive: Bool = true) {
        self.projectPath = projectPath
        self.isGit = isGit
        self.label = label
        self.isActive = isActive
    }

    private var resolvedLabel: String {
        if let label, !label.isEmpty { return label }
        let basename = (projectPath as NSString).lastPathComponent
        let owner = ownerSegment()
        if let owner, !owner.isEmpty {
            return "\(owner)/\(basename)"
        }
        return basename.isEmpty ? projectPath : basename
    }

    /// Pulls the macOS user name out of a `/Users/<name>/…` path so the
    /// chip looks like `<name>/<folder>` without needing a server round
    /// trip to read git config. RepoLabelResolver will refine this later
    /// for actual git remotes.
    private func ownerSegment() -> String? {
        let parts = projectPath.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Users" else { return nil }
        return String(parts[1])
    }

    var body: some View {
        HStack(spacing: SmoothieMetrics.space6) {
            Image(systemName: isGit ? "point.3.connected.trianglepath.dotted" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? SmoothieColor.textPrimary : SmoothieColor.textSecondary)
            Text(resolvedLabel)
                .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, SmoothieMetrics.space8)
        .padding(.horizontal, SmoothieMetrics.space12)
        .background(SmoothieColor.chipBg, in: .capsule)
        .overlay(
            Capsule().strokeBorder(
                isActive ? SmoothieColor.accent.opacity(0.7) : SmoothieColor.chipStroke,
                lineWidth: isActive ? 1 : 0.5
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isActive ? "Active repository: \(resolvedLabel)" : "Repository: \(resolvedLabel)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
