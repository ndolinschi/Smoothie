import SwiftUI

/// REF-2 styled bottom sheet listing every paired Mac. Tapping a row makes
/// that Mac the active server. A trailing "Pair another Mac" row exits the
/// sheet and asks the host to present ConnectView in "add another" mode.
struct PairingsSheet: View {
    @Environment(PairingStore.self) private var pairing
    let onAddPairing: () -> Void
    let onDismiss: () -> Void

    @State private var confirmingRemoval: PairingStore.Pairing?

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
                        // Always allow removing — even the last paired
                        // Mac. The audit flagged that gating on `count
                        // > 1` left users stuck if they wanted to fully
                        // start over (e.g. selling the iPhone). Routing
                        // already falls back to ConnectView when
                        // `pairing.current == nil`, so the sheet
                        // naturally closes and the pairing flow opens.
                        Button(role: .destructive) {
                            confirmingRemoval = mac
                        } label: {
                            Label(
                                pairing.pairings.count == 1
                                    ? "Disconnect this Mac"
                                    : "Remove this Mac",
                                systemImage: "trash"
                            )
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
        .confirmationDialog(
            confirmingRemoval.map { "Disconnect \($0.label)?" } ?? "Disconnect",
            isPresented: Binding(
                get: { confirmingRemoval != nil },
                set: { if !$0 { confirmingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingRemoval
        ) { mac in
            Button("Disconnect", role: .destructive) {
                pairing.remove(id: mac.id)
                // If that was the only Mac, the routing in SmoothieApp
                // flips to ConnectView automatically. Close the sheet
                // either way.
                onDismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { mac in
            Text("Removes the bearer token from this iPhone. Sessions running on \(mac.label) keep running — re-pair to reconnect.")
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
