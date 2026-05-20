import SwiftUI

/// REF-1 styled overflow menu opened from the composer's `+` button. We can't
/// attach photos to a CLI agent, so we keep the design language and swap the
/// content to file / mention / feature pickers.
struct AttachSheet: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let onTakePhoto: () -> Void
    let onChoosePhoto: () -> Void
    let onMentionFile: () -> Void
    let onAttachFile: () -> Void
    let onOpenSkills: () -> Void
    let onOpenModels: () -> Void
    let onOpenMCP: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SmoothieBottomSheet(title: "Add to message", onDismiss: onDismiss) {
            SheetRow(
                glyph: "camera",
                glyphColor: SmoothieColor.accent,
                glyphBackground: SmoothieColor.accentSoft,
                title: "Take Photo",
                subtitle: "Use the camera and attach the capture"
            ) {
                onTakePhoto()
                onDismiss()
            }
            SheetRow(
                glyph: "photo",
                glyphColor: Color(hex: 0xFBBF24),
                glyphBackground: Color(hex: 0x2A2415),
                title: "Choose Photo",
                subtitle: "Pick an image from your library"
            ) {
                onChoosePhoto()
                onDismiss()
            }
            SheetRow(
                glyph: "at",
                glyphColor: SmoothieColor.modeCode,
                glyphBackground: Color(hex: 0x1F1F2E),
                title: "Mention file",
                subtitle: "Insert @path with the file contents attached"
            ) {
                onMentionFile()
                onDismiss()
            }
            SheetRow(
                glyph: "paperclip",
                glyphColor: SmoothieColor.modePlan,
                glyphBackground: Color(hex: 0x1F2A3E),
                title: "Attach a file",
                subtitle: "Pick a text file from Files"
            ) {
                onAttachFile()
                onDismiss()
            }

            if let f = features, !f.slashCommands.isEmpty {
                SheetRow(
                    glyph: "wand.and.stars",
                    glyphColor: Color(hex: 0xFBBF24),
                    glyphBackground: Color(hex: 0x2A2415),
                    title: "Commands",
                    subtitle: "Insert a slash command at the cursor"
                ) {
                    onOpenSkills()
                    onDismiss()
                }
            }

            if let f = features, f.supportsModelPicker {
                SheetRow(
                    glyph: "cube",
                    glyphColor: SmoothieColor.statusDone,
                    glyphBackground: Color(hex: 0x152A22),
                    title: "Models",
                    subtitle: "Switch model — restarts the session"
                ) {
                    onOpenModels()
                    onDismiss()
                }
            }

            SheetRow(
                glyph: "server.rack",
                glyphColor: SmoothieColor.textSecondary,
                glyphBackground: SmoothieColor.bgGlyph,
                title: "MCP servers",
                subtitle: "Connectors land in v1.5"
            ) {
                onOpenMCP()
                onDismiss()
            }
        }
    }
}
