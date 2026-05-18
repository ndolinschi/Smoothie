import SwiftUI

struct HomeView: View {
    @Environment(PairingStore.self) private var pairing
    @State private var whoamiResponse: String = "—"
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.white.opacity(0.05), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Paired")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if let p = pairing.current {
                        Text("\(p.host):\(p.port)")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.top, 60)

                VStack(alignment: .leading, spacing: 10) {
                    Text("AUTH PING (/whoami)")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(whoamiResponse)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassEffect(in: .rect(cornerRadius: 14))
                }
                .padding(.horizontal, 20)

                Button {
                    Task { await pingWhoami() }
                } label: {
                    HStack(spacing: 8) {
                        if loading { ProgressView().controlSize(.small).tint(.black) }
                        Text(loading ? "Pinging…" : "Ping /whoami")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .padding(.horizontal, 20)

                Spacer()

                Button(role: .destructive) {
                    pairing.clear()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                        Text("Disconnect")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.55))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.glass)
                .padding(.bottom, 24)
            }
        }
        .task { await pingWhoami() }
    }

    private func pingWhoami() async {
        loading = true
        let api = APIClient(store: pairing)
        do {
            let data = try await api.get("/whoami")
            whoamiResponse = String(data: data, encoding: .utf8) ?? "(non-utf8)"
        } catch {
            whoamiResponse = "✕ \((error as? LocalizedError)?.errorDescription ?? "\(error)")"
        }
        loading = false
    }
}
