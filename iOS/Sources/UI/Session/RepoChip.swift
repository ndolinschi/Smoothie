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

    init(projectPath: String, isGit: Bool, label: String? = nil) {
        self.projectPath = projectPath
        self.isGit = isGit
        self.label = label
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
        HStack(spacing: 6) {
            Image(systemName: isGit ? "point.3.connected.trianglepath.dotted" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text(resolvedLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(
            Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }
}
