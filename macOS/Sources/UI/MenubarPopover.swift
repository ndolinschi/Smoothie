import SwiftUI
import Shared

struct MenubarPopover: View {
    @Environment(SmoothieHTTPServer.self) private var server
    @Environment(PairingService.self) private var pairing
    @State private var showingFullQR = false
    @State private var copiedField: CopiedField?
    /// Periodically-refreshed list of active sessions on the daemon.
    /// Surfaced as a compact list in the menubar so the user can see at
    /// a glance what's running on their Mac without picking up the phone.
    @State private var activeSessions: [SessionDescriptor] = []
    @State private var refreshTask: Task<Void, Never>?

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
            sessionsSection
            Divider()
            pairingSection
            Divider()
            actions
        }
        .padding(SmoothieMetrics.space14)
        .frame(width: SmoothieMetrics.popoverWidth)
        .task {
            // Refresh the sessions list on every popover open and then
            // every 2s while the popover is mounted. SwiftUI tears down
            // the `.task` automatically when the view goes away so the
            // poll stops on close — no leak risk.
            while !Task.isCancelled {
                await refreshSessions()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func refreshSessions() async {
        do {
            let list = try await server.manager.list()
            await MainActor.run { activeSessions = list }
        } catch {
            await MainActor.run { activeSessions = [] }
        }
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
                Text("Tailscale not detected — phone must be on the same LAN, or switch the Network selector to Remote.")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textSecondary)
            }
        }
    }

    /// P28 — Network mode selector. Two-segment Picker that maps to
    /// cloudflared on/off:
    ///   • Local  — phone must reach this Mac directly (LAN / Tailscale).
    ///              cloudflared is stopped.
    ///   • Remote — phone can reach this Mac from anywhere via a
    ///              Cloudflare tunnel. cloudflared is started.
    /// Replaces the prior PUBLIC TUNNEL toggle so the mental model is
    /// "where is your phone right now?" instead of "do you want a
    /// tunnel?".
    @ViewBuilder
    private var tunnelSection: some View {
        VStack(alignment: .leading, spacing: SmoothieMetrics.space6) {
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("NETWORK")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SmoothieColor.textTertiary)
                Spacer()
            }
            Picker("", selection: networkModeBinding) {
                Text("Local").tag(NetworkMode.local)
                Text("Remote").tag(NetworkMode.remote)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // Both tabs stay tappable. If cloudflared isn't installed,
            // flipping to Remote yields a .failed status via
            // CloudflaredHost.start(); the install hint surfaces in
            // tunnelStatusBody below.
            tunnelStatusBody
        }
    }

    private enum NetworkMode: Hashable {
        case local, remote
    }

    /// `.local` only when cloudflared is fully `.off`; `.remote` for
    /// `.starting`, `.running`, **and** `.failed` — a failed start
    /// reflects the user's last expressed intent (they tapped Remote),
    /// so we keep the picker on Remote and surface the failure in
    /// `tunnelStatusBody`. P28.a — previously `.failed` mapped to
    /// `.local`, which silently undid the user's choice and made the
    /// "couldn't start" hint feel disconnected from what they'd just
    /// tapped.
    private var networkModeBinding: Binding<NetworkMode> {
        Binding(
            get: {
                switch pairing.cloudflared.status {
                case .starting, .running, .failed: return .remote
                case .off:                         return .local
                }
            },
            set: { mode in
                switch mode {
                case .remote: pairing.cloudflared.start()
                case .local:  pairing.cloudflared.stop()
                }
            }
        )
    }

    @ViewBuilder
    private var tunnelStatusBody: some View {
        switch pairing.cloudflared.status {
        case .off:
            // Local mode. Phone has to reach the daemon directly — show
            // the install hint only when the user might want to switch
            // to Remote later.
            VStack(alignment: .leading, spacing: SmoothieMetrics.space2) {
                Text("Local — phone must be on the same network (LAN or Tailscale).")
                    .font(.system(size: 10))
                    .foregroundStyle(SmoothieColor.textSecondary)
                if !pairing.cloudflared.isInstalled {
                    Text("Remote needs `cloudflared` — run `brew install cloudflared`.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
            }
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
                    Text("Remote — anyone with the QR can connect from anywhere.")
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
            HStack(spacing: SmoothieMetrics.space6) {
                Image(systemName: "qrcode")
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Text("PAIRING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
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

    @ViewBuilder
    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("ACTIVE SESSIONS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("\(activeSessions.count)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if activeSessions.isEmpty {
                Text("No sessions running. Start one from your phone.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 4) {
                    ForEach(activeSessions.prefix(5), id: \.id) { descriptor in
                        sessionRow(descriptor)
                    }
                    if activeSessions.count > 5 {
                        Text("+ \(activeSessions.count - 5) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func sessionRow(_ d: SessionDescriptor) -> some View {
        HStack(spacing: 8) {
            providerBadge(d.cli)
            VStack(alignment: .leading, spacing: 1) {
                Text(d.projectName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let model = d.model {
                    Text(model)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            stateDot(d.state)
                .help(stateLabel(d.state))
            Menu {
                Button("Open in Terminal") {
                    Task { await handoffSession(d) }
                }
                Divider()
                Button("Kill session", role: .destructive) {
                    Task { await killSession(d) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }

    @ViewBuilder
    private func providerBadge(_ cli: CLIType) -> some View {
        let (letter, color) = providerVisual(cli)
        Text(letter)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color, in: .rect(cornerRadius: 4))
    }

    private func providerVisual(_ cli: CLIType) -> (String, Color) {
        switch cli.name.lowercased() {
        case "claude_code": return ("C", Color(red: 0.55, green: 0.55, blue: 0.55))
        case "gemini":      return ("G", Color(red: 0.40, green: 0.55, blue: 0.75))
        case "open_code":   return ("O", Color(red: 0.50, green: 0.50, blue: 0.60))
        case "antigravity": return ("A", Color(red: 0.50, green: 0.40, blue: 0.70))
        default:            return ("?", Color.gray)
        }
    }

    private func stateDot(_ state: SessionState) -> some View {
        let color: Color = {
            switch state.name.lowercased() {
            case "starting", "thinking": return .blue
            case "waiting":              return .green
            case "done":                 return .gray
            case "error", "limit_reached": return .red
            default:                     return .gray
            }
        }()
        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .shadow(color: color.opacity(0.45), radius: 3)
    }

    private func stateLabel(_ state: SessionState) -> String {
        switch state.name.lowercased() {
        case "starting":     return "Starting"
        case "thinking":     return "Thinking"
        case "waiting":      return "Waiting for input"
        case "done":         return "Finished"
        case "error":        return "Error"
        case "limit_reached": return "Rate-limited"
        default:             return state.name
        }
    }

    private func killSession(_ d: SessionDescriptor) async {
        _ = await server.processes.terminate(id: d.id)
        await refreshSessions()
    }

    private func handoffSession(_ d: SessionDescriptor) async {
        // Reuse the existing terminal handoff path — opens Terminal.app
        // at the project root so the user can pick up where the agent
        // left off in a real shell. Best-effort: swallow the throws so
        // a missing osascript / blocked AppleScript doesn't crash the
        // popover. `clear` lands the user at a fresh prompt without
        // re-running the agent.
        try? TerminalHandoff.openInTerminal(cwd: d.projectPath, command: "clear")
        await refreshSessions()
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
