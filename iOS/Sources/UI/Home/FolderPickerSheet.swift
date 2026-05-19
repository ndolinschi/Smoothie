import SwiftUI

/// Cursor-style "Run Smoothie anywhere…" picker. Top: search field over a
/// merged Recents list. Below: a Browse Mac entry that drills into the live
/// `/browse` navigator on the macOS host. Floating glass bar at the bottom
/// commits the choice.
///
/// Caller receives a single absolute path string when the user picks.
struct FolderPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @Environment(RecentsStore.self) private var recents
    let activeProjects: [String]
    let onPick: (String) -> Void

    init(activeProjects: [String] = [], onPick: @escaping (String) -> Void) {
        self.activeProjects = activeProjects
        self.onPick = onPick
    }

    @State private var mode: Mode = .root
    @State private var query: String = ""

    @State private var browseResponse: BrowseResponseWire?
    @State private var loading = false
    @State private var loadError: String?
    @State private var topProjects: [ProjectWire] = []

    enum Mode: Equatable {
        case root
        case browsing(path: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                RadialGradient(
                    colors: [Color.white.opacity(0.05), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 500
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    contentForCurrentMode
                }

                if case .browsing(let path) = mode {
                    VStack {
                        Spacer()
                        useThisFolderBar(path: path)
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .browsing = mode {
                        Button {
                            navigateUp()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "chevron.left")
                                Text("Up")
                            }
                            .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .task { await loadInitial() }
    }

    private var navTitle: String {
        switch mode {
        case .root: return "Run Smoothie anywhere…"
        case .browsing(let path): return (path as NSString).lastPathComponent
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))
            TextField(searchPlaceholder, text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .font(.system(.body, design: .monospaced))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private var searchPlaceholder: String {
        switch mode {
        case .root: return "Run Smoothie anywhere…"
        case .browsing: return "Filter folders"
        }
    }

    @ViewBuilder
    private var contentForCurrentMode: some View {
        switch mode {
        case .root: rootContent
        case .browsing: browseContent
        }
    }

    // MARK: - Root mode

    private var rootContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if !filteredRecents.isEmpty {
                    sectionHeader("Recents")
                    ForEach(filteredRecents, id: \.self) { path in
                        recentRow(path: path)
                    }
                }
                if !filteredTopProjects.isEmpty {
                    sectionHeader("Open a folder")
                    ForEach(filteredTopProjects) { project in
                        projectRow(project)
                    }
                }
                sectionHeader("Browse")
                browseMacRow
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
    }

    private var filteredRecents: [String] {
        let q = query.lowercased()
        guard !q.isEmpty else { return recents.paths }
        return recents.paths.filter { $0.lowercased().contains(q) }
    }

    private var filteredTopProjects: [ProjectWire] {
        let q = query.lowercased()
        let unique = topProjects.filter { p in !recents.paths.contains(p.path) }
        guard !q.isEmpty else { return unique }
        return unique.filter { $0.name.lowercased().contains(q) || $0.path.lowercased().contains(q) }
    }

    private func recentRow(path: String) -> some View {
        let isHome = path == NSHomeDirectory()
        let name = (path as NSString).lastPathComponent
        return splitRow(
            icon: isHome ? "house" : "folder",
            iconAlpha: 0.6,
            title: isHome ? "Home" : name,
            sublabel: sublabel(for: path, isGit: nil),
            isActive: activeProjects.contains(path),
            onCommit: { choose(path) },
            onDrill: { Task { await navigate(to: path) } }
        )
        .contextMenu {
            Button(role: .destructive) {
                recents.remove(path)
            } label: {
                Label("Remove from recents", systemImage: "minus.circle")
            }
        }
    }

    private func projectRow(_ project: ProjectWire) -> some View {
        splitRow(
            icon: project.isGit ? "point.3.connected.trianglepath.dotted" : "folder",
            iconAlpha: project.isGit ? 0.85 : 0.55,
            title: project.name,
            sublabel: sublabel(for: project.path, isGit: project.isGit),
            isActive: activeProjects.contains(project.path),
            onCommit: { choose(project.path) },
            onDrill: { Task { await navigate(to: project.path) } }
        )
    }

    /// Two-tap-target glass row: body commits the folder, trailing chevron
    /// drills in. Mirrors the reference's repository-chooser layout.
    private func splitRow(
        icon: String,
        iconAlpha: Double,
        title: String,
        sublabel: String,
        isActive: Bool,
        onCommit: @escaping () -> Void,
        onDrill: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 0) {
            Button(action: onCommit) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.white.opacity(iconAlpha))
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(sublabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if isActive {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.leading, 12)
                .padding(.vertical, 10)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 0.5, height: 28)

            Button(action: onDrill) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .glassEffect(in: .rect(cornerRadius: 12))
    }

    /// "Opened 2h ago" if the path is in Recents; else "git" / "no-git" derived
    /// from the wire metadata when available; else the absolute path truncated.
    private func sublabel(for path: String, isGit: Bool?) -> String {
        if let date = recents.lastOpened(path) {
            return "Opened " + date.relative
        }
        if let isGit { return isGit ? "git" : "no-git" }
        return path
    }

    private var browseMacRow: some View {
        Button {
            Task { await enterBrowseFromRoot() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "macbook")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Browse Mac…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    Text("Drill into any subfolder")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Browse mode

    private var browseContent: some View {
        Group {
            if loading {
                ProgressView().tint(.white.opacity(0.5)).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                    Text(error).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                }
                .padding()
            } else if let response = browseResponse {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        if filteredBrowseEntries(response).isEmpty {
                            Text(query.isEmpty ? "Empty folder." : "No matches.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.vertical, 40)
                        } else {
                            ForEach(filteredBrowseEntries(response), id: \.path) { entry in
                                browseEntryRow(entry)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)   // leave space for the floating bar
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func filteredBrowseEntries(_ r: BrowseResponseWire) -> [BrowseEntryWire] {
        let q = query.lowercased()
        guard !q.isEmpty else { return r.entries }
        return r.entries.filter { $0.name.lowercased().contains(q) }
    }

    private func browseEntryRow(_ entry: BrowseEntryWire) -> some View {
        Button {
            Task { await navigate(to: entry.path) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isGit ? "point.3.connected.trianglepath.dotted" : "folder")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(entry.isGit ? 0.85 : 0.55))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.name)
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    Text(entry.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func useThisFolderBar(path: String) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Use this folder")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                Button {
                    choose(path)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                        Text("Pick")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 14)
            .padding(.leading, 6)
            .padding(.bottom, 2)
    }

    // MARK: - Actions

    private func choose(_ path: String) {
        recents.touch(path)
        onPick(path)
        dismiss()
    }

    private func loadInitial() async {
        let api = APIClient(store: pairing)
        do {
            topProjects = try await api.projects()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func enterBrowseFromRoot() async {
        let api = APIClient(store: pairing)
        loading = true
        loadError = nil
        do {
            let resp = try await api.browse(path: nil)
            browseResponse = resp
            // If exactly one root, auto-drill into it; otherwise show the list of roots.
            if resp.entries.count == 1, let only = resp.entries.first {
                await navigate(to: only.path)
            } else {
                mode = .browsing(path: "")
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func navigate(to path: String) async {
        let api = APIClient(store: pairing)
        loading = true
        loadError = nil
        do {
            let resp = try await api.browse(path: path)
            browseResponse = resp
            mode = .browsing(path: path)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func navigateUp() {
        guard case .browsing = mode else { return }
        if let parent = browseResponse?.parent {
            Task { await navigate(to: parent) }
        } else {
            // Back to the root selector view
            browseResponse = nil
            mode = .root
        }
    }
}
