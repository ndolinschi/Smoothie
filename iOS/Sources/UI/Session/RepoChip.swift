import SwiftUI

/// REF-1 project chip rendered to the right of the + button. Uses a folder
/// glyph for plain directories and a Git symbol when the underlying project
/// is a git checkout. The label is the path's last component.
struct RepoChip: View {
    let projectPath: String
    let isGit: Bool

    private var label: String {
        let trimmed = (projectPath as NSString).lastPathComponent
        return trimmed.isEmpty ? projectPath : trimmed
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isGit ? "point.3.connected.trianglepath.dotted" : "folder.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text(label)
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
