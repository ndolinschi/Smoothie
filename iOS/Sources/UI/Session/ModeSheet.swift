import SwiftUI

/// REF-2 mode-picker bottom sheet. Rows are driven by the active CLI's
/// `availableModes`. Picking a new mode triggers the existing restart-with-
/// mode flow so the CLI is relaunched with the new flag.
struct ModeSheet: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let onPick: (String) -> Void
    let onDismiss: () -> Void

    /// Built-in mode set rendered even when the provider has no
    /// per-CLI modes (e.g. Claude). Each mode maps to a descriptive
    /// subtitle the reference uses verbatim.
    private static let claudeModes: [Entry] = [
        Entry(id: "default", title: "Code", subtitle: "Claude writes and edits code directly",
              glyph: "chevron.left.forwardslash.chevron.right", glyphColor: SmoothieColor.modeCode,
              glyphBackground: Color(hex: 0x1F1F2E)),
        Entry(id: "plan", title: "Plan", subtitle: "Claude explores code and presents a plan before making edits",
              glyph: "doc.text", glyphColor: SmoothieColor.modePlan,
              glyphBackground: Color(hex: 0x1F2A3E))
    ]

    struct Entry: Identifiable, Hashable {
        let id: String
        let title: String
        let subtitle: String
        let glyph: String
        let glyphColor: Color
        let glyphBackground: Color
    }

    private var entries: [Entry] {
        // For Claude (no per-CLI modes), surface the canonical Code/Plan pair.
        if (features?.availableModes.isEmpty ?? true) { return Self.claudeModes }
        return (features?.availableModes ?? []).map { raw in
            switch raw.lowercased() {
            case "plan":      return Entry(id: raw, title: "Plan", subtitle: "Explore, then propose changes",
                                            glyph: "doc.text", glyphColor: SmoothieColor.modePlan,
                                            glyphBackground: Color(hex: 0x1F2A3E))
            case "auto_edit": return Entry(id: raw, title: "Auto-edit", subtitle: "Apply changes without confirmation",
                                            glyph: "scribble", glyphColor: SmoothieColor.modeCode,
                                            glyphBackground: Color(hex: 0x1F1F2E))
            case "yolo":      return Entry(id: raw, title: "Yolo", subtitle: "Skip every safety prompt — be careful",
                                            glyph: "bolt.fill", glyphColor: SmoothieColor.statusErr,
                                            glyphBackground: Color(hex: 0x2E1717))
            default:          return Entry(id: raw, title: raw.capitalized,
                                            subtitle: "Provider mode",
                                            glyph: "circle", glyphColor: SmoothieColor.textPrimary,
                                            glyphBackground: SmoothieColor.bgGlyph)
            }
        }
    }

    var body: some View {
        SmoothieBottomSheet(title: "Select mode", onDismiss: onDismiss) {
            ForEach(entries) { entry in
                SheetRow(
                    glyph: entry.glyph,
                    glyphColor: entry.glyphColor,
                    glyphBackground: entry.glyphBackground,
                    title: entry.title,
                    subtitle: entry.subtitle,
                    isSelected: (session.mode ?? "default").lowercased() == entry.id.lowercased()
                ) {
                    onPick(entry.id)
                    onDismiss()
                }
            }
        }
    }
}
