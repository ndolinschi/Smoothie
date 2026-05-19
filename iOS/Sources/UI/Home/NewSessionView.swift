import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    let preselectedPath: String?
    let onCreated: (SessionDescriptorWire) -> Void

    @State private var adapters: [AdapterInfoWire] = []
    @State private var selectedCLI: CLIWire = .claudeCode
    @State private var loading = true
    @State private var loadError: String?
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    center: .top, startRadius: 0, endRadius: 500
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let preselectedPath {
                            section("PROJECT") {
                                projectCard(path: preselectedPath)
                            }
                        }

                        section("CLI") {
                            if loading && adapters.isEmpty {
                                ProgressView().tint(.white.opacity(0.5)).padding(8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(adapters) { a in cliRow(a) }
                                }
                            }
                        }

                        if let loadError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(loadError).font(.system(size: 13))
                            }
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(in: .rect(cornerRadius: 12))
                        }
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: start) {
                        Text(starting ? "Starting…" : "Start")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canStart || starting)
                    .foregroundStyle(canStart ? .white : .white.opacity(0.3))
                }
            }
        }
        .task { await load() }
    }

    private var canStart: Bool {
        guard preselectedPath != nil else { return false }
        guard isSupported(selectedCLI) else { return false }
        return adapters.first { $0.cli == selectedCLI }?.installed ?? false
    }

    /// Client-side allowlist of CLIs that actually drive an end-to-end
    /// session through ProcessRegistry today. All three providers are
    /// supported as of P18 — Claude via ProcessHost, Gemini via
    /// GeminiOneshotHost with --resume, and OpenCode via OpenCodeServeHost
    /// over the local `opencode serve` HTTP server.
    private func isSupported(_ cli: CLIWire) -> Bool { true }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.4)).padding(.leading, 6)
            content()
        }
    }

    private func projectCard(path: String) -> some View {
        let name = (path as NSString).lastPathComponent
        return HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.75))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func cliRow(_ a: AdapterInfoWire) -> some View {
        let isSelected = selectedCLI == a.cli
        let installed = a.installed
        let selectable = installed && isSupported(a.cli)
        return Button {
            if selectable { selectedCLI = a.cli }
        } label: {
            HStack(spacing: 12) {
                ProviderIcon(cli: a.cli, size: 18)
                    .opacity(selectable ? 1 : 0.35)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.cli.displayName)
                        .foregroundStyle(selectable ? .white : .white.opacity(0.4))
                        .font(.system(size: 15, weight: .medium))
                    Text(rowSubtitle(installed: installed, version: a.version))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Spacer()
                if isSelected, selectable {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
            .opacity(selectable ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
    }

    private func rowSubtitle(installed: Bool, version: String?) -> String {
        if !installed { return "not installed" }
        return version.map { "v\($0)" } ?? "ready"
    }

    private func load() async {
        let api = APIClient(store: pairing)
        loading = true
        do {
            adapters = try await api.adapters()
            // Prefer a supported, installed CLI; fall back to any installed.
            if let supportedInstalled = adapters.first(where: { $0.installed && isSupported($0.cli) }) {
                selectedCLI = supportedInstalled.cli
            } else if let first = adapters.first(where: { $0.installed }) {
                selectedCLI = first.cli
            }
        } catch {
            if isCancellation(error) {
                loading = false
                return
            }
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func start() {
        guard let path = preselectedPath else { return }
        let api = APIClient(store: pairing)
        starting = true
        Task {
            do {
                let req = CreateSessionRequestWire(projectPath: path, cli: selectedCLI)
                let session = try await api.createSession(req)
                starting = false
                dismiss()
                onCreated(session)
            } catch {
                starting = false
                if isCancellation(error) { return }
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
