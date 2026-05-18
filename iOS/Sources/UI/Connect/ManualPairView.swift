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
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field(label: "Host", text: $host, placeholder: "100.64.0.10", keyboard: .URL)
                        field(label: "Port", text: $port, placeholder: "7749", keyboard: .numberPad)
                        field(label: "Token", text: $token, placeholder: "base64url from menu bar", keyboard: .asciiCapable)

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                                .padding(.horizontal, 4)
                        }

                        Button {
                            connect()
                        } label: {
                            HStack(spacing: 8) {
                                if verifying { ProgressView().controlSize(.small).tint(.black) }
                                Text(verifying ? "Verifying…" : "Connect")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.black)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .disabled(!canSubmit || verifying)
                        .opacity(canSubmit ? 1 : 0.5)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Enter manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func field(label: String, text: Binding<String>, placeholder: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.45))
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
    }

    private func connect() {
        let trimHost = host.trimmingCharacters(in: .whitespaces)
        guard let p = Int(port), let _ = URL(string: "http://\(trimHost):\(p)") else {
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
        pairing.save(host: trimHost, port: p, token: trimToken)
        Task {
            let ok = await pairing.verify()
            verifying = false
            if ok {
                dismiss()
            } else {
                errorText = pairing.lastError ?? "Couldn't reach the server."
                pairing.clear()
            }
        }
    }
}
