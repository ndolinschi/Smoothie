import SwiftUI

struct HomeView: View {
    @Environment(ServerStore.self) private var server
    @State private var projects: [ProjectDTO] = []
    @State private var sessions: [SessionDTO] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var presentingNew = false
    @State private var presentingSettings = false
    @State private var selectedSession: SessionDTO?
    @State private var pendingProject: ProjectDTO?

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

                    sectionHeader(sessions.isEmpty ? "Projects" : "Start a new session")

                    if loading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if let loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 13))
                                Text("Couldn't load")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Theme.error)
                            Text(loadError)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .glassSurface(cornerRadius: Theme.Radius.card, tint: Theme.error)
                    } else {
                        ForEach(projects) { project in
                            ProjectRow(project: project) {
                                pendingProject = project
                                presentingNew = true
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
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        presentingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        pendingProject = nil
                        presentingNew = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.accent)
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
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.4))
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
                    Image(systemName: "circle.dotted.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(session.state.tint)
                    Text(session.projectName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    StatusBadge(state: session.state)
                }
                Text("\(session.cli.label)  ·  \(session.projectPath)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Theme.Radius.card, tint: session.state.tint)
        }
        .buttonStyle(.plain)
    }
}

private struct ProjectRow: View {
    let project: ProjectDTO
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: project.isGit ? "point.3.connected.trianglepath.dotted" : "folder.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(project.isGit ? Theme.accent : .white.opacity(0.5))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text(project.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(cornerRadius: Theme.Radius.card)
        }
        .buttonStyle(.plain)
    }
}
