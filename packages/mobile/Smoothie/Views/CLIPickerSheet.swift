import SwiftUI

/// Sheet for switching the CLI driving the current session. Selecting a new CLI
/// restarts the session in-place (kills the current process, spawns a new one
/// in the same project).
struct CLIPickerSheet: View {
    let currentCLI: CLIType
    let onPick: (CLIType) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server

    @State private var adapters: [AdapterInfo] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                BackdropView()

                ScrollView {
                    VStack(spacing: 8) {
                        if loading {
                            ProgressView()
                                .tint(.white.opacity(0.5))
                                .padding(40)
                        } else {
                            ForEach(adapters) { row($0) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Switch CLI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .task { await load() }
    }

    private func row(_ adapter: AdapterInfo) -> some View {
        let isCurrent = adapter.cli == currentCLI
        let available = adapter.installed && adapter.supported

        return Button {
            guard available, !isCurrent else { return }
            onPick(adapter.cli)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cliIcon(adapter.cli))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(available ? 0.75 : 0.25))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(adapter.cli.label)
                        .foregroundStyle(available ? .white : .white.opacity(0.4))
                        .font(.system(size: 15, weight: .medium))
                    Text(statusText(adapter))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                if isCurrent {
                    Text("current")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassPill()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .glassSurface(cornerRadius: Theme.Radius.row, emphasis: isCurrent ? .subtle : .none)
            .opacity(available ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!available || isCurrent)
    }

    private func cliIcon(_ cli: CLIType) -> String {
        switch cli {
        case .opencode: return "terminal"
        case .claude:   return "sparkle"
        case .gemini:   return "diamond"
        case .codex:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func statusText(_ a: AdapterInfo) -> String {
        if !a.installed { return "not installed" }
        if !a.supported { return "coming soon" }
        return a.version.map { "v\($0)" } ?? "ready"
    }

    private func load() async {
        guard let api = server.api else { return }
        loading = true
        adapters = (try? await api.adapters()) ?? []
        loading = false
    }
}
