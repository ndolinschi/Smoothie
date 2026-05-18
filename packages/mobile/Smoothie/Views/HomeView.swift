import SwiftUI

struct HomeView: View {
    @Environment(ServerStore.self) private var server
    @Environment(CustomProjectsStore.self) private var customProjects
    @State private var projects: [ProjectDTO] = []
    @State private var sessions: [SessionDTO] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var presentingNew = false
    @State private var presentingSettings = false
    @State private var presentingBrowser = false
    @State private var selectedSession: SessionDTO?
    @State private var pendingProject: ProjectDTO?

    var combinedProjects: [ProjectDTO] {
        let custom = customProjects.asProjects()
        let remote = projects.filter { remote in
            !custom.contains { $0.path == remote.path }
        }
        return custom + remote
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !sessions.isEmpty {
                        sectionHeader("Active sessions")
                        ForEach(sessions) { session in
                            SessionRow(session: session) {
                                selectedSession = session
                            }
                        }
                    }

                    HStack {
                        sectionHeader(sessions.isEmpty ? "Projects" : "Start a new session")
                        Spacer()
                        Button {
                            presentingBrowser = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Add")
                                    .font(.system(size: 12, weight: .semibold))
                                    .tracking(0.3)
                            }
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .glassPill()
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }

                    if loading {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle")
                                    .font(.system(size: 13))
                                Text("Couldn't load")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Theme.error)
                            Text(loadError)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassSurface(cornerRadius: Theme.Radius.card, emphasis: .error)
                    } else {
                        ForEach(combinedProjects) { project in
                            ProjectRow(
                                project: project,
                                isCustom: customProjects.contains(project.path)
                            ) {
                                pendingProject = project
                                presentingNew = true
                            } onRemove: {
                                customProjects.remove(project.path)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("Smoothie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        presentingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Smoothie")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        pendingProject = nil
                        presentingNew = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { s in
                SessionView(session: s)
            }
            .sheet(isPresented: $presentingNew) {
                NewSessionView(preselectedProject: pendingProject) { newSession in
                    pendingProject = nil
                    presentingNew = false
                    Task { await refresh() }
                    selectedSession = newSession
                }
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
            .sheet(isPresented: $presentingSettings) {
                SettingsView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.clear)
            }
            .sheet(isPresented: $presentingBrowser) {
                BrowserSheet { path in
                    customProjects.add(path)
                    Task { await refresh() }
                }
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 12)
            .padding(.leading, 6)
    }

    private func refresh() async {
        guard let api = server.api else { return }
        loading = true
        loadError = nil
        do {
            async let p = api.projects()
            async let s = api.sessions()
            projects = try await p
            sessions = try await s
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

private struct SessionRow: View {
    let session: SessionDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 6, height: 6)
                    Text(session.projectName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusBadge(state: session.state)
                }
                Text("\(session.cli.label)  ·  \(session.projectPath)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Theme.Radius.card, emphasis: session.state == .waiting ? .subtle : .none)
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectRow: View {
    let project: ProjectDTO
    let isCustom: Bool
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: project.isGit ? "circlebadge.2" : "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(project.isGit ? 0.75 : 0.45))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        if isCustom {
                            Text("pinned")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(0.3)
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .glassPill()
                        }
                    }
                    Text(project.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isCustom {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove from list", systemImage: "minus.circle")
                }
            }
        }
    }
}
