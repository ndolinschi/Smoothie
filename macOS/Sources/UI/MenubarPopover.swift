import SwiftUI

struct MenubarPopover: View {
    @Environment(SmoothieHTTPServer.self) private var server
    @Environment(PairingService.self) private var pairing
    @State private var showingFullQR = false
    @State private var copiedField: CopiedField?

    private enum CopiedField: String {
        case host, token, url
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space12) {
            header
            Divider()
            statusSection
            Divider()
            tunnelSection
            Divider()
            pairingSection
            Divider()
            actions
        }
        .padding(SmoothieMetrics.space14)
        .frame(width: SmoothieMetrics.popoverWidth)
    }

    private var header: some View {
        HStack(spacing: SmoothieMetrics.space8) {
            Image(systemName: "waveform.path")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.accent)
            Text("Smoothie")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Spacer()
            Text("v0.2.0")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(SmoothieColor.textTertiary)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch server.status {
        case .running(let host, let port):
            statusRow(color: SmoothieColor.statusDone, label: "Running", detail: "\(host):\(port)")
        case .starting:
            statusRow(color: SmoothieColor.statusWaiting, label: "Starting…", detail: "")
        case .failed(let msg):
            statusRow(color: SmoothieColor.statusErr, label: "Failed", detail: msg)
        case .stopped:
            statusRow(color: SmoothieColor.statusIdle, label: "Stopped", detail: "")
        }
        if !pairing.hostIsTailscale && !pairing.isPublicTunnelActive {
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.statusWaiting)
                Text("Tailscale not detected — phone must be on the same LAN, or turn on the public tunnel below.")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var tunnelSection: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space6) {
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("PUBLIC TUNNEL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SmoothieColor.textTertiary)
                Spacer()
                Toggle("", isOn: tunnelBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .disabled(!pairing.cloudflared.isInstalled)
            }
            tunnelStatusBody
        }
    }

    private var tunnelBinding: Binding<Bool> {
        Binding(
            get: { pairing.isPublicTunnelActive || isTunnelStarting },
            set: { on in
                if on { pairing.cloudflared.start() }
                else  { pairing.cloudflared.stop() }
            }
        )
    }

    private var isTunnelStarting: Bool {
        if case .starting = pairing.cloudflared.status { return true }
        return false
    }

    @ViewBuilder
    private var tunnelStatusBody: some View {
        if !pairing.cloudflared.isInstalled {
            VStack(alignment: .leading, spacing: SmoothieMetrics.space2) {
                Text("`cloudflared` is not installed.")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("Run `brew install cloudflared` and reopen this popover.")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
        } else {
            switch pairing.cloudflared.status {
            case .off:
                Text("Off — phone must reach this Mac directly (LAN or Tailscale).")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textSecondary)
            case .starting:
                HStack(spacing: SmoothieMetrics.space6) {
                    ProgressView().controlSize(.mini)
                    Text("Asking Cloudflare for a URL…")
                        .font(.system(size: 10))
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            case .running(let url):
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: SmoothieMetrics.space4) {
                        Circle().fill(SmoothieColor.statusDone).frame(width: 6, height: 6)
                        Text("Public — anyone with the QR can connect from anywhere.")
                            .font(.system(size: 10))
                            .foregroundStyle(SmoothieColor.textSecondary)
                    }
                    Text(url.absoluteString)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            case .failed(let msg):
                HStack(spacing: SmoothieMetrics.space6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SmoothieColor.statusErr)
                    Text(msg)
                        .font(.system(size: 10))
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            }
        }
    }

    private func statusRow(color: Color, label: String, detail: String) -> some View {
        HStack(spacing: SmoothieMetrics.space8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.6), radius: 3)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SmoothieColor.textPrimary)
            Spacer()
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var pairingSection: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space8) {
            Text("PAIRING")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SmoothieColor.textTertiary)
            HStack(alignment: .top, spacing: SmoothieMetrics.space12) {
                if let img = pairing.qrImage(pixelSize: 160) {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: 88, height: 88)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerSm))
                }
                VStack(alignment: .leading, spacing: SmoothieMetrics.space6) {
                    Text("Scan from iPhone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(SmoothieColor.textPrimary)
                    Text("or enter manually:")
                        .font(.system(size: 11))
                        .foregroundStyle(SmoothieColor.textSecondary)
                    copyableRow(
                        label: "host",
                        value: pairingHostDisplay,
                        field: .host,
                        action: {
                            copy(pairingHostDisplay, as: .host)
                        }
                    )
                    copyableRow(
                        label: "token",
                        value: maskedToken,
                        field: .token,
                        action: {
                            copy(pairing.token, as: .token)
                        }
                    )
                    Button("Show full QR") { showingFullQR = true }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                        .tint(SmoothieColor.accent)
                }
                Spacer()
            }
        }
        .sheet(isPresented: $showingFullQR) {
            PairingFullView(showing: $showingFullQR)
                .environment(pairing)
        }
    }

    /// What to show next to "host:" in the pairing card. Falls back to the
    /// local LAN/Tailscale `host:port`; uses the Cloudflare public URL when
    /// the tunnel toggle is on.
    private var pairingHostDisplay: String {
        if case .running(let url) = pairing.cloudflared.status {
            return url.absoluteString
        }
        return "\(pairing.host):\(pairing.port)"
    }

    private var maskedToken: String {
        let t = pairing.token
        guard t.count > 12 else { return t }
        return "\(t.prefix(6))…\(t.suffix(6))"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space6) {
            actionButton(
                label: copiedField == .token ? "✓ Token copied" : "Copy token",
                systemImage: "key.fill",
                tint: copiedField == .token ? SmoothieColor.statusDone : SmoothieColor.textPrimary
            ) {
                copy(pairing.token, as: .token)
            }

            actionButton(
                label: copiedField == .url ? "✓ Pairing URL copied" : "Copy pairing URL",
                systemImage: "link",
                tint: copiedField == .url ? SmoothieColor.statusDone : SmoothieColor.textPrimary
            ) {
                copy(pairing.qrPayloadURL, as: .url)
            }

            actionButton(
                label: "Re-pair (rotate token)",
                systemImage: "arrow.triangle.2.circlepath",
                tint: SmoothieColor.accent
            ) {
                pairing.rotate()
                server.restart()
            }

            Divider().padding(.vertical, SmoothieMetrics.space2)

            actionButton(
                label: "Quit Smoothie",
                systemImage: "power",
                tint: SmoothieColor.statusErr
            ) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }

    // MARK: - Helpers

    private func copyableRow(
        label: String,
        value: String,
        field: CopiedField,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: SmoothieMetrics.space4) {
            Text("\(label):")
                .font(.system(size: 10))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: SmoothieMetrics.space4)
            Button(action: action) {
                Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(copiedField == field ? SmoothieColor.statusDone : SmoothieColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Copy \(label)")
        }
    }

    private func actionButton(
        label: String,
        systemImage: String,
        tint: Color = SmoothieColor.textPrimary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copy(_ value: String, as field: CopiedField) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        copiedField = field
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copiedField == field { copiedField = nil }
        }
    }
}

struct PairingFullView: View {
    @Environment(PairingService.self) private var pairing
    @Binding var showing: Bool
    @State private var copied: String?

    private var pairingHostDisplayForFull: String {
        if case .running(let url) = pairing.cloudflared.status {
            return url.absoluteString
        }
        return "\(pairing.host):\(pairing.port)"
    }

    var body: some View {
        VStack(spacing: SmoothieMetrics.space14) {
            Text("Pair Smoothie")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            if let img = pairing.qrImage(pixelSize: 320) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 320, height: 320)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg))
            }
            VStack(spacing: SmoothieMetrics.space6) {
                Text("Scan with the iPhone Smoothie app")
                    .font(.system(size: 12))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("Or enter manually:")
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textTertiary)
                Text(pairingHostDisplayForFull)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, SmoothieMetrics.space12)
                Text("token: \(pairing.token)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, SmoothieMetrics.space12)
            }
            HStack(spacing: SmoothieMetrics.space8) {
                Button {
                    copyToPasteboard(pairing.token, label: "token")
                } label: {
                    Label(copied == "token" ? "✓ Copied" : "Copy token",
                          systemImage: "key.fill")
                }
                Button {
                    copyToPasteboard(pairing.qrPayloadURL, label: "url")
                } label: {
                    Label(copied == "url" ? "✓ Copied" : "Copy URL",
                          systemImage: "link")
                }
                Button("Done") { showing = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(SmoothieMetrics.space20)
        .frame(width: 380)
    }

    private func copyToPasteboard(_ value: String, label: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        copied = label
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copied == label { copied = nil }
        }
    }
}
