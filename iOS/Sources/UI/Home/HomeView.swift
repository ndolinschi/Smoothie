import SwiftUI

struct HomeView: View {
    @Environment(PairingStore.self) private var pairing
    @Environment(RecentsStore.self) private var recents
    @State private var sessions: [SessionDescriptorWire] = []
    @State private var adapters: [AdapterInfoWire] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var presentingPicker = false
    @State private var presentingNew = false
    @State private var pendingPath: String?
    @State private var selectedSession: SessionDescriptorWire?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.white.opacity(0.04), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
                .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if !sessions.isEmpty {
                            sectionHeader("ACTIVE SESSIONS")
                            ForEach(sessions) { s in
                                Button {
                                    selectedSession = s
                                } label: {
                                    sessionCard(s)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        sectionHeader(sessions.isEmpty ? "NEW SESSION" : "START ANOTHER")

                        if loading {
                            ProgressView().tint(.white.opacity(0.5))
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if let loadError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(loadError).font(.system(size: 13))
                            }
                            .foregroundStyle(.red.opacity(0.85))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(in: .rect(cornerRadius: 14))
                        } else {
                            Button {
                                presentingPicker = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 20))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Start a new session")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(.black)
                                        Text(installedSummary())
                                            .font(.system(size: 12))
                                            .foregroundStyle(.black.opacity(0.55))
                                    }
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.white)
                            .foregroundStyle(.black)

                            if !recents.paths.isEmpty {
                                sectionHeader("RECENT PROJECTS")
                                ForEach(recents.paths, id: \.self) { path in
                                    Button {
                                        pendingPath = path
                                        presentingNew = true
                                    } label: {
                                        recentCard(path: path)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            recents.remove(path)
                                        } label: {
                                            Label("Remove", systemImage: "minus.circle")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Smoothie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Smoothie")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Disconnect", role: .destructive) { pairing.clear() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { s in
                SessionView(session: s)
            }
            .sheet(isPresented: $presentingPicker) {
                FolderPickerSheet { path in
                    pendingPath = path
                    presentingPicker = false
                    // Give the sheet a tick to dismiss before presenting the next one.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        presentingNew = true
                    }
                }
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
            .sheet(isPresented: $presentingNew) {
                NewSessionView(preselectedPath: pendingPath) { new in
                    presentingNew = false
                    pendingPath = nil
                    Task { await refresh() }
                    selectedSession = new
                }
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 12)
            .padding(.leading, 6)
    }

    private func sessionCard(_ s: SessionDescriptorWire) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderIcon(cli: s.cli, size: 16)
                Text(s.projectName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                StatusBadge(state: s.state)
            }
            Text("\(s.cli.displayName)\(s.model.map { "  ·  \($0)" } ?? "")  ·  \(s.projectPath)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 16))
    }

    private func recentCard(path: String) -> some View {
        let name = (path as NSString).lastPathComponent
        let isHome = path == NSHomeDirectory()
        return HStack(spacing: 10) {
            Image(systemName: isHome ? "house" : "folder")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(isHome ? "Home" : name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func installedSummary() -> String {
        let installed = adapters.filter { $0.installed }
        if installed.isEmpty { return "no CLIs installed" }
        return installed.map { $0.cli.displayName }.joined(separator: " · ")
    }

    private func refresh() async {
        let api = APIClient(store: pairing)
        loading = true
        loadError = nil
        do {
            async let s = api.sessions()
            async let a = api.adapters()
            sessions = try await s
            adapters = try await a
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}
