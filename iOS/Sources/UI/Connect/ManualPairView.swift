import SwiftUI

struct ManualPairView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @State private var host: String = ""
    @State private var port: String = "7749"
    @State private var token: String = ""
    @State private var verifying = false
    @State private var errorText: String?

    private var canSubmit: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(port) != nil &&
        token.trimmingCharacters(in: .whitespaces).count >= 16
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(label: "Host", text: $host, placeholder: "100.64.0.10 (or paste smoothie:// URL)", keyboard: .URL)
                        field(label: "Port", text: $port, placeholder: "7749", keyboard: .numberPad)
                        field(label: "Token", text: $token, placeholder: "base64url from menu bar", keyboard: .asciiCapable)
                            .onChange(of: host) { _, _ in absorbPastedURLIfPresent() }
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
                                        .tint(canSubmit ? SmoothieColor.onAccent : .white)
                                }
                                Text(verifying ? "Verifying…" : "Connect")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(canSubmit ? SmoothieColor.onAccent : .white.opacity(0.6))
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

    private func field(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType) -> some View {
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
        guard let p = Int(port), URL(string: "http://\(trimHost):\(p)") != nil else {
            errorText = "Host or port looks wrong."
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
            let ok = await pairing.tryPair(host: trimHost, port: p, token: trimToken)
            verifying = false
            if ok {
                dismiss()
            } else {
                errorText = pairing.lastError ?? "Couldn't reach the server."
            }
        }
    }

    /// Detect when the user has pasted a full `smoothie://pair?…` URL
    /// into either the host or the token field and auto-fill the three
    /// fields from its query params. Way friendlier than asking the
    /// user to manually split the URL.
    private func absorbPastedURLIfPresent() {
        for candidate in [host, token] {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("smoothie://") else { continue }
            guard let comps = URLComponents(string: trimmed),
                  comps.host == "pair" else { continue }
            let items = comps.queryItems ?? []
            let pastedHost = items.first(where: { $0.name == "host" })?.value
            let pastedPort = items.first(where: { $0.name == "port" })?.value
            let pastedToken = items.first(where: { $0.name == "token" })?.value
            if let h = pastedHost, !h.isEmpty { host = h }
            if let p = pastedPort, !p.isEmpty { port = p }
            if let t = pastedToken, !t.isEmpty { token = t }
            return
        }
    }
}
