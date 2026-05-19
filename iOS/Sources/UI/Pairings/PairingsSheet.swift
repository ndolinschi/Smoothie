import SwiftUI

/// REF-2 styled bottom sheet listing every paired Mac. Tapping a row makes
/// that Mac the active server. A trailing "Pair another Mac" row exits the
/// sheet and asks the host to present ConnectView in "add another" mode.
struct PairingsSheet: View {
    @Environment(PairingStore.self) private var pairing
    let onAddPairing: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SmoothieBottomSheet(title: "Paired Macs", onDismiss: onDismiss) {
            if pairing.pairings.isEmpty {
                emptyState
            } else {
                ForEach(pairing.pairings) { mac in
                    SheetRow(
                        glyph: "desktopcomputer",
                        glyphColor: SmoothieColor.textPrimary,
                        glyphBackground: SmoothieColor.bgGlyph,
                        title: mac.label,
                        subtitle: "\(mac.host):\(mac.port)",
                        isSelected: mac.id == pairing.activeId
                    ) {
                        pairing.switchTo(id: mac.id)
                        onDismiss()
                    }
                    .contextMenu {
                        if pairing.pairings.count > 1 {
                            Button(role: .destructive) {
                                pairing.remove(id: mac.id)
                            } label: {
                                Label("Remove this Mac", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            SheetRow(
                glyph: "plus",
                glyphColor: SmoothieColor.accent,
                glyphBackground: SmoothieColor.accentSoft,
                title: "Pair another Mac",
                subtitle: "Scan a QR code or enter a host manually"
            ) {
                onAddPairing()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("No Macs paired yet")
                .font(.system(size: 13))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
