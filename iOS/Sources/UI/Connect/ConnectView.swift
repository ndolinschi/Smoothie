import SwiftUI

struct ConnectView: View {
    @Environment(PairingStore.self) private var pairing
    @State private var presentingScanner = false
    @State private var presentingManual = false

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 80)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Smoothie")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(SmoothieColor.textPrimary)
                    Text(pairing.pairings.isEmpty
                         ? "Pair with your Mac to start."
                         : "Pair another Mac to add it to the list.")
                        .font(.system(size: 17))
                        .foregroundStyle(SmoothieColor.textSecondary)
                }

                if let error = pairing.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(SmoothieColor.statusErr)
                    .padding(12)
                    .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
                }

                VStack(spacing: 10) {
                    pairingButton(
                        title: "Scan QR code",
                        subtitle: "from the Smoothie menu bar on your Mac",
                        systemName: "qrcode.viewfinder",
                        prominent: true
                    ) { presentingScanner = true }

                    pairingButton(
                        title: "Enter host manually",
                        subtitle: "type the host, port and token",
                        systemName: "keyboard",
                        prominent: false
                    ) { presentingManual = true }
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(SmoothieColor.textTertiary)
                    Text("Pairing uses a 32-byte token stored on-device. No cloud.")
                        .font(.system(size: 11))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .fullScreenCover(isPresented: $presentingScanner) {
            ScannerSheet()
        }
        .sheet(isPresented: $presentingManual) {
            ManualPairView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
    }

    private func pairingButton(
        title: String,
        subtitle: String,
        systemName: String,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(prominent ? SmoothieColor.onAccent : SmoothieColor.textPrimary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(prominent ? SmoothieColor.onAccent : SmoothieColor.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(prominent ? SmoothieColor.onAccent.opacity(0.75) : SmoothieColor.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(prominent ? SmoothieColor.accent : SmoothieColor.bgCard,
                        in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                    .strokeBorder(prominent ? Color.clear : SmoothieColor.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @State private var lastSeen: String?
    @State private var accepted = false
    @State private var failed = false
    /// Set when AVCapture reports the user has denied or restricted
    /// camera access. We render an actionable card with an Open Settings
    /// link instead of a black screen.
    @State private var permissionDenied = false

    var body: some View {
        ZStack {
            if permissionDenied {
                permissionDeniedCard
            } else {
                QRScannerView(
                    onScan: { text in
                        guard !accepted else { return }
                        lastSeen = text
                        accepted = true
                        Task {
                            let ok = await pairing.tryPairFromURL(text)
                            if ok {
                                dismiss()
                            } else {
                                accepted = false
                                failed = true
                            }
                        }
                    },
                    onPermissionDenied: {
                        permissionDenied = true
                    }
                )
                .ignoresSafeArea()

                VStack {
                    HStack {
                        Spacer()
                        closeButton
                    }
                    .padding()
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Scan the QR from the Mac menu bar")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if failed, let err = pairing.lastError {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundStyle(SmoothieColor.statusErr)
                                .multilineTextAlignment(.center)
                        } else if accepted {
                            Text("Got it — verifying…")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text("Tap \u{201C}Show full QR\u{201D} in the Mac popover for a bigger code.")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(SmoothieColor.bgCard.opacity(0.85), in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(SmoothieColor.bgGlyph, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var permissionDeniedCard: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(SmoothieColor.accent)
                    Spacer()
                    closeButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Camera access required")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                    Text("Scanning the QR from the Mac needs the camera. Open Settings → Smoothie and turn Camera on, or enter the pairing details manually.")
                        .font(.system(size: 14))
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Open Settings")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SmoothieColor.accent, in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
                        .foregroundStyle(SmoothieColor.onAccent)
                    }
                    .buttonStyle(.plain)
                    Button {
                        dismiss()
                    } label: {
                        Text("Use manual entry")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
                            .overlay(
                                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                                    .strokeBorder(SmoothieColor.stroke, lineWidth: 1)
                            )
                            .foregroundStyle(SmoothieColor.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 60)
            .padding(.bottom, 30)
        }
    }
}
