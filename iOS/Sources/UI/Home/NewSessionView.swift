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
                // Flat bgPrimary — the previous radial gradient was a
                // pre-P16 Liquid-Glass remnant that no longer matches
                // any other surface in the app.
                SmoothieColor.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let preselectedPath {
                            section("PROJECT") {
                                projectCard(path: preselectedPath)
                            }
                        }

                        section("CLI") {
                            if loading && adapters.isEmpty {
                                ProgressView().tint(SmoothieColor.textTertiary).padding(8)
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
                            .foregroundStyle(SmoothieColor.statusErr)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SmoothieColor.statusErr.opacity(0.12), in: .rect(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(SmoothieColor.statusErr.opacity(0.35), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(SmoothieColor.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: start) {
                        HStack(spacing: 6) {
                            if starting {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(SmoothieColor.onAccent)
                            }
                            Text(starting ? "Starting…" : "Start")
                                .fontWeight(.semibold)
                        }
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
        return adapters.first { $0.cli == selectedCLI }?.installed ?? false
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(SmoothieColor.textTertiary).padding(.leading, 6)
            content()
        }
    }

    private func projectCard(path: String) -> some View {
        let name = (path as NSString).lastPathComponent
        return HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(SmoothieColor.textSecondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .font(.system(size: 15, weight: .semibold))
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private func cliRow(_ a: AdapterInfoWire) -> some View {
        let isSelected = selectedCLI == a.cli
        let installed = a.installed
        let selectable = installed
        return Button {
            if selectable { selectedCLI = a.cli }
        } label: {
            HStack(spacing: 12) {
                ProviderIcon(cli: a.cli, size: 18)
                    .opacity(selectable ? 1 : 0.35)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.cli.displayName)
                        .foregroundStyle(selectable ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                        .font(.system(size: 15, weight: .medium))
                    Text(rowSubtitle(installed: installed, version: a.version))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
                Spacer()
                if isSelected, selectable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SmoothieColor.linkBlue)
                }
            }
            .padding(14)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? SmoothieColor.linkBlue.opacity(0.6) : SmoothieColor.strokeSoft,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
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
            // Antigravity is hidden from the picker for now — the agy
            // one-shot host works but isn't ready for end users. The
            // CLIWire case stays so existing Antigravity sessions still
            // render correctly elsewhere in the app.
            adapters = try await api.adapters().filter { $0.cli != .antigravity }
            // Default to the first installed adapter so the user lands
            // on a selectable row instead of an empty selection state.
            if let firstInstalled = adapters.first(where: { $0.installed }) {
                selectedCLI = firstInstalled.cli
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
