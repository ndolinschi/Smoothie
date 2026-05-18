import SwiftUI

struct MenubarPopover: View {
    @Environment(SmoothieHTTPServer.self) private var server
    @Environment(PairingService.self) private var pairing
    @State private var showingFullQR = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            statusSection
            Divider()
            pairingSection
            Divider()
            actions
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Smoothie")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Text("v0.2.0")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch server.status {
        case .running(let host, let port):
            statusRow(color: .green, label: "Running", detail: "\(host):\(port)")
        case .starting:
            statusRow(color: .yellow, label: "Starting…", detail: "")
        case .failed(let msg):
            statusRow(color: .red, label: "Failed", detail: msg)
        case .stopped:
            statusRow(color: .gray, label: "Stopped", detail: "")
        }
        if !pairing.hostIsTailscale {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Tailscale not detected — only 127.0.0.1 will be reachable.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusRow(color: Color, label: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PAIRING")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            HStack(alignment: .top, spacing: 12) {
                if let img = pairing.qrImage(pixelSize: 160) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 88, height: 88)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan from iPhone")
                        .font(.system(size: 12, weight: .medium))
                    Text("or enter manually:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("\(pairing.host):\(pairing.port)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                    HStack(spacing: 4) {
                        Text("token:")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        Text(maskedToken)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Button("Show full QR") { showingFullQR = true }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showingFullQR) {
            PairingFullView(showing: $showingFullQR)
                .environment(pairing)
        }
    }

    private var maskedToken: String {
        let t = pairing.token
        guard t.count > 12 else { return t }
        return "\(t.prefix(6))…\(t.suffix(6))"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Copy pairing URL") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(pairing.qrPayloadURL, forType: .string)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button("Re-pair (rotate token)") {
                pairing.rotate()
                server.restart()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.orange)

            Divider().padding(.vertical, 2)

            Button("Quit Smoothie") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.red)
            .keyboardShortcut("q")
        }
    }
}

struct PairingFullView: View {
    @Environment(PairingService.self) private var pairing
    @Binding var showing: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text("Pair Smoothie")
                .font(.system(size: 18, weight: .semibold))
            if let img = pairing.qrImage(pixelSize: 320) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 320, height: 320)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(spacing: 4) {
                Text("Scan with the iPhone Smoothie app")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Or enter manually:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("\(pairing.host):\(pairing.port)")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Text("token: \(pairing.token)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                Button("Copy URL") {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(pairing.qrPayloadURL, forType: .string)
                }
                Button("Done") { showing = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
