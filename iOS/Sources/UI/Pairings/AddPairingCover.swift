import SwiftUI

/// Minimal wrapper that presents ConnectView when adding another Mac. The
/// cover auto-dismisses when the pairing list count changes, so a successful
/// pair returns the user straight to HomeView with the new Mac active.
///
/// Extracted from HomeView.swift in P24.d D2 — it had no dependency on
/// HomeView state and lived at the bottom of an already-long file. The
/// type is `internal` so HomeView (in the same module) can still
/// instantiate it.
struct AddPairingCover: View {
    @Environment(PairingStore.self) private var pairing
    @State private var initialCount: Int = 0
    let onDismiss: () -> Void

    var body: some View {
        ConnectView()
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(SmoothieColor.bgGlyph, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            .onAppear { initialCount = pairing.pairings.count }
            .onChange(of: pairing.pairings.count) { _, new in
                if new > initialCount { onDismiss() }
            }
    }
}
