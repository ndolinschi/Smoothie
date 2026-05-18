import SwiftUI

struct ConnectView: View {
    @Environment(ServerStore.self) private var server
    @State private var input: String = ""
    @State private var isConnecting = false
    @State private var errorText: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 60)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Smoothie")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Connect to your Mac")
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.55))
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Tailscale address")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.45))

                        TextField("100.64.0.10:7749", text: $input)
                            .focused($inputFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.URL)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .foregroundStyle(.white)
                            .font(.system(.body, design: .monospaced))
                            .glassSurface(cornerRadius: Theme.Radius.input)
                            .onSubmit(connect)

                        if let errorText {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 11))
                                Text(errorText)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Theme.error)
                        }
                    }
                }

                Button(action: connect) {
                    HStack(spacing: 10) {
                        if isConnecting {
                            ProgressView().controlSize(.small).tint(.black)
                        }
                        Text(isConnecting ? "Connecting…" : "Connect")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(.white, in: .rect(cornerRadius: Theme.Radius.button))
                }
                .disabled(isConnecting || trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.35 : 1)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.35))
                    Text("Both your Mac and iPhone need Tailscale running on the same tailnet.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.bottom, 30)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var trimmed: String { input.trimmingCharacters(in: .whitespaces) }

    private func connect() {
        guard let url = API.normalize(input) else {
            errorText = "That doesn't look like a valid address."
            return
        }
        isConnecting = true
        errorText = nil
        Task {
            await server.setServerURL(url)
            isConnecting = false
            if server.health == nil {
                errorText = server.lastError ?? "Couldn't reach the server."
                await server.setServerURL(nil)
            }
        }
    }
}

#Preview {
    ZStack {
        BackdropView()
        ConnectView()
            .environment(ServerStore())
    }
    .preferredColorScheme(.dark)
}
