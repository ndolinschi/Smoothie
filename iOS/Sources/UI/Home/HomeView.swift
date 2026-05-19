import SwiftUI

enum HomeFilter: Hashable {
    case all, completed

    var title: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        }
    }
}

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
    @State private var filter: HomeFilter = .all
    @AppStorage("smoothie.homeTipDismissed") private var tipDismissed: Bool = false

    private var allCount: Int { sessions.count }
    private var completedCount: Int {
        sessions.filter { $0.state.isCompleted }.count
    }
    private var filteredSessions: [SessionDescriptorWire] {
        switch filter {
        case .all: return sessions
        case .completed: return sessions.filter { $0.state.isCompleted }
        }
    }

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
                        if !tipDismissed {
                            tipBanner
                        }

                        if !sessions.isEmpty {
                            sessionsHeader
                            ForEach(filteredSessions) { s in
                                Button {
                                    selectedSession = s
                                } label: {
                                    sessionRow(s)
                                }
                                .buttonStyle(.plain)
                            }
                            if filteredSessions.isEmpty {
                                Text(filter == .completed
                                     ? "No completed sessions yet."
                                     : "Nothing here yet.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 18)
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
                                        recents.touch(path)
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
                let liveProjects = sessions.filter { !$0.state.isCompleted }.map(\.projectPath)
                FolderPickerSheet(activeProjects: liveProjects) { path in
                    pendingPath = path
                    presentingPicker = false
                    // Give the sheet a tick to dismiss before presenting the next one.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        presentingNew = true
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationDragIndicator(.visible)
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

    /// Header for the Sessions section: title on the left, segmented All /
    /// Completed capsule on the right. Live counts on each chip.
    private var sessionsHeader: some View {
        HStack(spacing: 8) {
            Text("SESSIONS")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.35))
            Spacer()
            HStack(spacing: 0) {
                filterChip(.all, count: allCount)
                filterChip(.completed, count: completedCount)
            }
            .padding(2)
            .glassEffect(in: .capsule)
        }
        .padding(.top, 4)
        .padding(.leading, 6)
        .padding(.trailing, 2)
    }

    private func filterChip(_ f: HomeFilter, count: Int) -> some View {
        Button {
            filter = f
        } label: {
            HStack(spacing: 5) {
                Text(f.title)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .opacity(0.65)
            }
            .foregroundStyle(filter == f ? .black : .white.opacity(0.7))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                filter == f ? Color.white : Color.clear,
                in: .capsule
            )
        }
        .buttonStyle(.plain)
    }

    /// Dismissible orientation banner shown until the user taps the X. The flag
    /// persists across launches via @AppStorage.
    private var tipBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 13))
                .foregroundStyle(.yellow.opacity(0.85))
            Text("Tip: pull down to refresh · long-press a session to remove it.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)
            Spacer(minLength: 6)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { tipDismissed = true }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    /// Task-list style row for an active or completed session — circular
    /// provider icon, project name + relative time, trailing status badge.
    private func sessionRow(_ s: SessionDescriptorWire) -> some View {
        HStack(spacing: 12) {
            ProviderIcon(cli: s.cli, size: 22)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.06), in: .circle)
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(s.projectName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(rowSublabel(for: s))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusBadge(state: s.state)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                Task { await deleteSession(s) }
            } label: {
                Label("Remove", systemImage: "minus.circle")
            }
        }
    }

    private func rowSublabel(for s: SessionDescriptorWire) -> String {
        let created = Date(timeIntervalSince1970: TimeInterval(s.createdAt) / 1000.0)
        let agePart = "Started " + created.relative
        if let model = s.model, !model.isEmpty {
            return "\(s.cli.friendlyModelName(model)) · \(agePart)"
        }
        return "\(s.cli.displayName) · \(agePart)"
    }

    private func deleteSession(_ s: SessionDescriptorWire) async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: s.id)
        await refresh()
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
