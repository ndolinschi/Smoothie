import SwiftUI

/// P29 §3 — Inline diff panel rendered for every `.fileEdit` event in
/// the agent stream. Replaces the prior treatment which rendered each
/// fileEdit as a generic `ToolCallCard` with no diff content.
///
/// The panel shows file path + +added/−removed counts + the first N
/// diff rows. When the diff is taller than the visible cap, a footer
/// invites the user to "Show all changes" — tapping opens the
/// existing `DiffSheet` for the full review surface.
///
/// Reuses `DiffEntry` + `DiffLineRowView` from `DiffSheet.swift` (both
/// already module-visible), so no parallel diff parser exists.
struct FileChangesPanel: View {
    let event: SmoothieEventWire
    /// Invoked when the user taps the panel header or the "Show all
    /// changes" footer. The host (SessionView) opens its existing
    /// DiffSheet so the comment workflow keeps working.
    var onShowAll: () -> Void = {}

    /// Maximum diff rows rendered inline before the "Show all" footer
    /// takes over. Picked so the panel stays compact in the stream;
    /// users wanting the full diff tap into the sheet.
    private let inlineRowCap: Int = 12

    @State private var expanded: Bool = true

    private var entry: DiffEntry? { DiffEntry(event: event) }

    var body: some View {
        if let entry {
            panel(for: entry)
        } else {
            // Couldn't parse the event into a DiffEntry — fall back to a
            // minimal placeholder so the stream still shows something.
            placeholder
        }
    }

    private func panel(for entry: DiffEntry) -> some View {
        let rows = entry.diffRows()
        let added = rows.filter { $0.kind == .addition }.count
        let removed = rows.filter { $0.kind == .deletion }.count
        let visibleRows = expanded ? Array(rows.prefix(inlineRowCap)) : []
        let overflow = max(0, rows.count - inlineRowCap)

        return VStack(alignment: .leading, spacing: 0) {
            header(entry: entry, added: added, removed: removed)
            if expanded, !visibleRows.isEmpty {
                Rectangle()
                    .fill(SmoothieColor.strokeSoft)
                    .frame(height: 0.5)
                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                        DiffLineRowView(row: row, language: entry.languageHint)
                    }
                }
                if overflow > 0 || rows.count > inlineRowCap {
                    showAllFooter(overflow: overflow)
                }
            }
        }
        .background(SmoothieColor.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd, style: .continuous)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private func header(entry: DiffEntry, added: Int, removed: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: entry.glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(entry.glyphTint)
                Text(entry.toolLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(entry.glyphTint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(entry.glyphTint.opacity(0.15), in: .capsule)
                Text(displayPath(entry.path))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 8)
                if added > 0 {
                    Text("+\(added)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.statusDone)
                }
                if removed > 0 {
                    Text("−\(removed)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(SmoothieColor.statusErr)
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            .padding(.horizontal, SmoothieMetrics.toolCardPaddingH)
            .padding(.vertical, SmoothieMetrics.toolCardPaddingV)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func showAllFooter(overflow: Int) -> some View {
        Button(action: onShowAll) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .semibold))
                if overflow > 0 {
                    Text("Show all changes (\(overflow) more line\(overflow == 1 ? "" : "s"))")
                        .font(.system(size: 12, weight: .semibold))
                } else {
                    Text("Open full diff")
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(SmoothieColor.textSecondary)
            .padding(.horizontal, SmoothieMetrics.toolCardPaddingH)
            .padding(.vertical, 8)
            .background(SmoothieColor.bgChip)
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("File change")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SmoothieColor.textSecondary)
            Spacer()
        }
        .padding(SmoothieMetrics.toolCardPaddingH)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    /// Truncate the leading path components so the file name stays
    /// visible. SwiftUI's `.truncationMode(.head)` would hide the file
    /// name on long absolute paths.
    private func displayPath(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 3 else { return path }
        return "…/" + parts.suffix(3).joined(separator: "/")
    }
}
