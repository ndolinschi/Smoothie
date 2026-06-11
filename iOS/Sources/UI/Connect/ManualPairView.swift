import SwiftUI

struct ManualPairView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @State private var host: String = ""
    @State private var port: String = "7749"
    @State private var token: String = ""
    /// Extracted from a pasted smoothie:// URL; defaults to http for LAN/Tailscale.
    /// When https (Cloudflare tunnel), the port field is hidden — tunnels always
    /// terminate at 443 and the user shouldn't have to enter it.
    @State private var scheme: String = "http"
    @State private var verifying = false
    @State private var errorText: String?

    private var isHTTPS: Bool { scheme == "https" }

    private var effectivePort: Int {
        isHTTPS ? 443 : (Int(port) ?? 7749)
    }

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isHTTPS || Int(port) != nil) &&
        token.trimmingCharacters(in: .whitespaces).count >= 16
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(label: "Host", text: $host,
                              placeholder: "100.64.0.10  or paste smoothie:// URL",
                              keyboard: .URL)

                        // Port is meaningless for HTTPS tunnels — always 443.
                        if !isHTTPS {
                            field(label: "Port", text: $port,
                                  placeholder: "7749", keyboard: .numberPad)
                        } else {
                            schemeHint
                        }

                        field(label: "Token", text: $token,
                              placeholder: "base64url from menu bar",
                              keyboard: .asciiCapable)
                            .onChange(of: host)  { _, _ in absorbPastedURLIfPresent() }
                            .onChange(of: token) { _, _ in absorbPastedURLIfPresent() }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(SmoothieColor.statusErr)
                                .padding(.horizontal, 4)
                        }

                        Button(action: connect) {
                            HStack(spacing: 8) {
                                if verifying {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(canSubmit ? SmoothieColor.onAccent : SmoothieColor.textSecondary)
                                }
                                Text(verifying ? "Verifying…" : "Connect")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(canSubmit ? SmoothieColor.onAccent : SmoothieColor.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSubmit ? SmoothieColor.accent : SmoothieColor.bgGlyph,
                                        in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit || verifying)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Enter manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            }
        }
    }

    /// Shown instead of the port field when a Cloudflare HTTPS URL was detected.
    private var schemeHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(SmoothieColor.statusDone)
            Text("HTTPS — Cloudflare tunnel, port 443 (automatic)")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.statusDone.opacity(0.4), lineWidth: 1)
        )
    }

    private func field(label: String, text: Binding<String>, placeholder: String,
                       keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SmoothieColor.textTertiary)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
                .overlay(
                    RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                        .strokeBorder(SmoothieColor.stroke, lineWidth: 1)
                )
        }
    }

    private func connect() {
        let trimHost = host.trimmingCharacters(in: .whitespaces)
        let p = effectivePort
        // Validate the URL using the actual scheme so https tunnel hosts pass.
        guard !trimHost.isEmpty,
              URL(string: "\(scheme)://\(trimHost):\(p)") != nil else {
            errorText = "Host looks wrong."
            return
        }
        let trimToken = token.trimmingCharacters(in: .whitespaces)
        guard trimToken.count >= 16 else {
            errorText = "Token looks too short."
            return
        }
        verifying = true
        errorText = nil
        Task {
            let ok = await pairing.tryPair(host: trimHost, port: p, token: trimToken,
                                           scheme: scheme)
            verifying = false
            if ok {
                dismiss()
            } else {
                errorText = pairing.lastError ?? "Couldn't reach the server."
            }
        }
    }

    /// Detect when the user has pasted a URL into the host or token field and
    /// auto-fill all fields. Handles two formats:
    ///
    /// 1. `smoothie://pair?host=…&port=…&token=…&scheme=…` — full pairing URL
    ///    copied from the Mac menu bar. Fills everything including scheme.
    ///
    /// 2. `https://xxx.trycloudflare.com` or any `http(s)://` URL — Cloudflare
    ///    (or other) tunnel URL pasted directly into the Host field. Strips the
    ///    scheme prefix, sets scheme + port automatically. Without this, the
    ///    scheme ends up inside the host string and URLComponents builds a broken
    ///    URL like `http://https:7749` that silently times out.
    private func absorbPastedURLIfPresent() {
        for candidate in [host, token] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()

            // Case 1: smoothie:// pairing URL
            if lower.hasPrefix("smoothie://") {
                guard let comps = URLComponents(string: trimmed),
                      comps.host == "pair" else { continue }
                let items = comps.queryItems ?? []
                if let h = items.first(where: { $0.name == "host" })?.value, !h.isEmpty { host = h }
                if let p = items.first(where: { $0.name == "port" })?.value, !p.isEmpty { port = p }
                if let t = items.first(where: { $0.name == "token" })?.value, !t.isEmpty { token = t }
                if let s = items.first(where: { $0.name == "scheme" })?.value,
                   s == "http" || s == "https" { scheme = s }
                return
            }

            // Case 2: plain https:// or http:// URL (e.g. Cloudflare tunnel URL)
            if lower.hasPrefix("https://") || lower.hasPrefix("http://") {
                guard let comps = URLComponents(string: trimmed),
                      let h = comps.host, !h.isEmpty else { continue }
                host = h
                scheme = comps.scheme == "https" ? "https" : "http"
                if scheme == "https" {
                    port = "443"      // always use the standard HTTPS port
                } else if let p = comps.port {
                    port = String(p)
                }
                return
            }
        }
    }
}
