import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server

    var body: some View {
        NavigationStack {
            ZStack {
                BackdropView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("Server") {
                            VStack(spacing: 0) {
                                row(label: "URL", value: server.serverURL?.absoluteString ?? "—")
                                if let h = server.health {
                                    divider
                                    row(label: "Version", value: h.version)
                                    divider
                                    row(label: "Bind", value: h.bindAddress)
                                    divider
                                    row(label: "Uptime", value: formatUptime(h.uptime))
                                }
                            }
                            .glassSurface(cornerRadius: Theme.Radius.card)
                        }

                        if let h = server.health {
                            section("Adapters") {
                                VStack(spacing: 0) {
                                    ForEach(Array(h.adapters.enumerated()), id: \.element.id) { index, a in
                                        adapterRow(a)
                                        if index < h.adapters.count - 1 { divider }
                                    }
                                }
                                .glassSurface(cornerRadius: Theme.Radius.card)
                            }
                        }

                        Button(role: .destructive) {
                            Task {
                                await server.setServerURL(nil)
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "power")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Disconnect")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(Theme.error)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glassSurface(cornerRadius: Theme.Radius.card, emphasis: .error)
                        }
                        .buttonStyle(.plain)

                        Text("Smoothie v0.1.0")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.25))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 0.5)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.leading, 6)
            content()
        }
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func adapterRow(_ a: AdapterInfo) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(adapterStatusColor(a))
                .frame(width: 6, height: 6)
                .shadow(color: adapterStatusColor(a).opacity(0.4), radius: 3)
            Text(a.cli.label)
                .foregroundStyle(.white)
            Spacer()
            Text(adapterStatusText(a))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func adapterStatusColor(_ a: AdapterInfo) -> Color {
        if !a.installed { return Theme.error }
        if !a.supported { return .white.opacity(0.4) }
        return .white
    }

    private func adapterStatusText(_ a: AdapterInfo) -> String {
        if !a.installed { return "missing" }
        if !a.supported { return "coming soon" }
        return a.version.map { "v\($0)" } ?? "ready"
    }

    private func formatUptime(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total / 60) % 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return String(format: "%ds", s)
    }
}
