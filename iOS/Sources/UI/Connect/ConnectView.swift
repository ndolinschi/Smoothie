import SwiftUI

struct ConnectView: View {
    @Environment(PairingStore.self) private var pairing
    @State private var presentingScanner = false
    @State private var presentingManual = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // Subtle radial vignette for visual depth under glass elements
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 80)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Smoothie")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Pair with your Mac to start.")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.6))
                }

                if let error = pairing.lastError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(error)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .padding(12)
                    .glassEffect(in: .rect(cornerRadius: 14))
                }

                VStack(spacing: 12) {
                    Button {
                        presentingScanner = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Scan QR code")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("from the Smoothie menu bar on your Mac")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 22, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .foregroundStyle(.black)

                    Button {
                        presentingManual = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enter host manually")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("type the host, port and token")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "keyboard")
                                .font(.system(size: 20, weight: .medium))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Pairing uses a 32-byte token stored on-device. No cloud.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
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
                .presentationDetents([.medium])
                .presentationBackground(.clear)
        }
    }
}

private struct ScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @State private var lastSeen: String?
    @State private var accepted = false

    var body: some View {
        ZStack {
            QRScannerView { text in
                guard !accepted else { return }
                lastSeen = text
                if pairing.saveFromURL(text) {
                    accepted = true
                    Task {
                        let ok = await pairing.verify()
                        if ok {
                            dismiss()
                        } else {
                            accepted = false
                        }
                    }
                }
            }
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                }
                .padding()
                Spacer()
                VStack(spacing: 4) {
                    Text("Scan the QR from the Mac menu bar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let last = lastSeen, pairing.lastError != nil {
                        Text(pairing.lastError ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    } else if accepted {
                        Text("Got it — verifying…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    } else {
                        Text("Tap “Show full QR” in the Mac popover for a bigger code.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .glassEffect(in: .rect(cornerRadius: 16))
                .padding(.bottom, 32)
            }
        }
    }
}
