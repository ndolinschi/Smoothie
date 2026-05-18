import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server
    var preselectedProject: ProjectDTO?
    var onCreated: (SessionDTO) -> Void

    @State private var projects: [ProjectDTO] = []
    @State private var selectedProject: ProjectDTO?
    @State private var selectedCLI: CLIType = .opencode
    @State private var supportedCLIs: [AdapterInfo] = []
    @State private var loading = true
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BackdropView()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        section("Project") {
                            if loading && projects.isEmpty {
                                ProgressView()
                                    .tint(.white.opacity(0.5))
                                    .controlSize(.small)
                                    .padding(8)
                            } else {
                                VStack(spacing: 8) {
                                    ForEach(projects) { p in projectRow(p) }
                                }
                            }
                        }

                        section("CLI") {
                            VStack(spacing: 8) {
                                ForEach(supportedCLIs) { adapter in cliRow(adapter) }
                            }
                        }

                        if let errorText {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                Text(errorText)
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(Theme.error)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassSurface(cornerRadius: Theme.Radius.row, emphasis: .error)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.65))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: start) {
                        Text(creating ? "Starting…" : "Start")
                            .fontWeight(.semibold)
                            .foregroundStyle(canStart ? .white : .white.opacity(0.3))
                    }
                    .disabled(!canStart || creating)
                }
            }
        }
        .task { await load() }
    }

    private var canStart: Bool {
        selectedProject != nil &&
        (supportedCLIs.first { $0.cli == selectedCLI }?.supported ?? false)
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

    private func projectRow(_ p: ProjectDTO) -> some View {
        let isSelected = selectedProject?.path == p.path
        return Button {
            selectedProject = p
        } label: {
            HStack(spacing: 12) {
                Image(systemName: p.isGit ? "circlebadge.2" : "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(p.isGit ? 0.75 : 0.45))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .medium))
                    Text(p.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: Theme.Radius.row, emphasis: isSelected ? .subtle : .none)
        }
        .buttonStyle(.plain)
    }

    private func cliRow(_ adapter: AdapterInfo) -> some View {
        let isSelected = selectedCLI == adapter.cli
        let available = adapter.installed && adapter.supported
        return Button {
            if available { selectedCLI = adapter.cli }
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
                    Text(statusText(for: adapter))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                }
                Spacer()
                if isSelected, available {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(14)
            .glassSurface(cornerRadius: Theme.Radius.row, emphasis: isSelected && available ? .subtle : .none)
            .opacity(available ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private func cliIcon(_ cli: CLIType) -> String {
        switch cli {
        case .opencode: return "terminal"
        case .claude:   return "sparkle"
        case .gemini:   return "diamond"
        case .codex:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    private func statusText(for a: AdapterInfo) -> String {
        if !a.installed { return "not installed" }
        if !a.supported { return "coming soon" }
        return a.version.map { "v\($0)" } ?? "ready"
    }

    private func load() async {
        guard let api = server.api else { return }
        loading = true
        do {
            async let p = api.projects()
            async let a = api.adapters()
            projects = try await p
            supportedCLIs = try await a
            if let first = supportedCLIs.first(where: { $0.installed && $0.supported }) {
                selectedCLI = first.cli
            }
            if selectedProject == nil {
                selectedProject = preselectedProject ?? projects.first
            }
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func start() {
        guard let api = server.api, let project = selectedProject else { return }
        creating = true
        errorText = nil
        Task {
            do {
                let session = try await api.createSession(projectPath: project.path, cli: selectedCLI)
                creating = false
                dismiss()
                onCreated(session)
            } catch {
                creating = false
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
