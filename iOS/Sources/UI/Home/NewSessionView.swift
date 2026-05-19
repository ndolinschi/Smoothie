import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    let preselectedProject: ProjectWire?
    let onCreated: (SessionDescriptorWire) -> Void

    @State private var projects: [ProjectWire] = []
    @State private var adapters: [AdapterInfoWire] = []
    @State private var selectedProject: ProjectWire?
    @State private var selectedCLI: CLIWire = .claudeCode
    @State private var loading = true
    @State private var loadError: String?
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("PROJECT") {
                            if loading && projects.isEmpty {
                                ProgressView().tint(.white.opacity(0.5)).padding(8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(projects) { p in projectRow(p) }
                                }
                            }
                        }

                        section("CLI") {
                            VStack(spacing: 8) {
                                ForEach(adapters) { a in cliRow(a) }
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
        selectedProject != nil &&
        (adapters.first { $0.cli == selectedCLI }?.installed ?? false)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.4)).padding(.leading, 6)
            content()
        }
    }

    private func projectRow(_ p: ProjectWire) -> some View {
        let isSelected = selectedProject?.path == p.path
        return Button {
            selectedProject = p
        } label: {
            HStack(spacing: 12) {
                Image(systemName: p.isGit ? "point.3.connected.trianglepath.dotted" : "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(p.isGit ? 0.75 : 0.45))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).foregroundStyle(.white).font(.system(size: 15, weight: .medium))
                    Text(p.path).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3)).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func cliRow(_ a: AdapterInfoWire) -> some View {
        let isSelected = selectedCLI == a.cli
        let installed = a.installed
        return Button {
            if installed { selectedCLI = a.cli }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: cliIcon(a.cli))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(installed ? 0.75 : 0.3))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.cli.displayName).foregroundStyle(installed ? .white : .white.opacity(0.4))
                        .font(.system(size: 15, weight: .medium))
                    Text(installed ? (a.version.map { "v\($0)" } ?? "ready") : "not installed")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
                Spacer()
                if isSelected, installed {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
                }
            }
            .padding(14)
            .glassEffect(in: .rect(cornerRadius: 14))
            .opacity(installed ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!installed)
    }

    private func cliIcon(_ cli: CLIWire) -> String {
        switch cli {
        case .claudeCode: return "sparkle"
        case .gemini:     return "diamond"
        case .openCode:   return "terminal"
        }
    }

    private func load() async {
        let api = APIClient(store: pairing)
        loading = true
        do {
            async let p = api.projects()
            async let a = api.adapters()
            projects = try await p
            adapters = try await a
            if selectedProject == nil { selectedProject = preselectedProject ?? projects.first }
            if let first = adapters.first(where: { $0.installed }) {
                selectedCLI = first.cli
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func start() {
        guard let project = selectedProject else { return }
        let api = APIClient(store: pairing)
        starting = true
        Task {
            do {
                let req = CreateSessionRequestWire(projectPath: project.path, cli: selectedCLI)
                let session = try await api.createSession(req)
                starting = false
                dismiss()
                onCreated(session)
            } catch {
                starting = false
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
