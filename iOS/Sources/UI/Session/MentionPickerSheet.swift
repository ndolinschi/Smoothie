import SwiftUI

/// @-mention picker. Modelled after Cursor's mobile picker: a root list
/// of context categories (Branch / Browser / MCP / Files & Folders /
/// Past Chats) that drills into a category-specific picker when tapped.
/// v1 ships Files & Folders as the only active category — the rest are
/// disabled placeholders so the visual surface looks complete even
/// before the daemon-side wiring lands.
///
/// `onPick(FileEntryWire, FileContentWire)` is the existing callback —
/// invoked when the user taps a file in the Files & Folders sub-picker.
/// New categories that need different payloads (e.g. Past Chats) will
/// add their own callbacks alongside without breaking this one.
struct MentionPickerSheet: View {
    let session: SessionDescriptorWire
    let onPick: (FileEntryWire, FileContentWire) -> Void
    /// Called when the user picks a past session from the Past Chats
    /// sub-picker. The MessageInput parent stages it as a `.chat`
    /// attachment so it folds into the next outgoing turn alongside
    /// any files / images.
    let onPickChat: (StagedChat) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing
    @Environment(SessionMetaStore.self) private var sessionMeta
    @State private var showingBranch = false
    @State private var showingMCP = false
    @State private var showingPastChats = false

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add context")
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(SmoothieColor.textTertiary)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)

                    VStack(spacing: 6) {
                        NavigationLink {
                            FilesAndFoldersPicker(projectPath: session.projectPath, onPick: { entry, content in
                                onPick(entry, content)
                                dismiss()
                            })
                        } label: {
                            categoryRow(
                                icon: "folder.fill",
                                title: "Files & Folders",
                                subtitle: "Attach a file from the project tree",
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingBranch = true
                        } label: {
                            categoryRow(
                                icon: "point.3.connected.trianglepath.dotted",
                                title: "Branch",
                                subtitle: "Switch the project's git branch",
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingMCP = true
                        } label: {
                            categoryRow(
                                icon: "server.rack",
                                title: "MCP Servers",
                                subtitle: "Toggle connectors for this session",
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            showingPastChats = true
                        } label: {
                            categoryRow(
                                icon: "bubble.left.and.bubble.right.fill",
                                title: "Past Chats",
                                subtitle: "Reference a previous session as context",
                                enabled: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)

                    Spacer()
                }
            }
            .navigationTitle("Mention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            }
            .sheet(isPresented: $showingBranch) {
                BranchPickerSheet(
                    session: session,
                    pairing: pairing,
                    onSwitched: { _ in
                        showingBranch = false
                        dismiss()
                    },
                    onDismiss: { showingBranch = false }
                )
                .presentationDetents([.large])
                .presentationBackground(.clear)
                .smoothieThemed()
            }
            .sheet(isPresented: $showingMCP) {
                MCPPickerSheet(
                    session: session,
                    pairing: pairing,
                    onDismiss: {
                        showingMCP = false
                        dismiss()
                    }
                )
                .presentationDetents([.large])
                .presentationBackground(.clear)
                .smoothieThemed()
            }
            .sheet(isPresented: $showingPastChats) {
                PastChatsPickerSheet(
                    currentSession: session,
                    pairing: pairing,
                    sessionMeta: sessionMeta,
                    onPicked: { chat in
                        onPickChat(chat)
                        showingPastChats = false
                        dismiss()
                    },
                    onDismiss: { showingPastChats = false }
                )
                .presentationDetents([.large])
                .presentationBackground(.clear)
                .smoothieThemed()
            }
        }
    }

    private func categoryRow(
        icon: String,
        title: String,
        subtitle: String,
        enabled: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                .frame(width: SmoothieMetrics.glyphTile, height: SmoothieMetrics.glyphTile)
                .background(SmoothieColor.bgGlyph, in: .rect(cornerRadius: SmoothieMetrics.cornerChip))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(enabled ? SmoothieColor.textPrimary : SmoothieColor.textSecondary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if enabled {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
        .opacity(enabled ? 1.0 : 0.55)
    }
}

/// Files & Folders sub-picker. Lists project files via `/projects/files`,
/// returns the absolute file content plus the relative path so callers
/// can both stage the file and insert "@<relative path>" into the input.
/// Lives as a pushed view in the MentionPickerSheet's NavigationStack.
struct FilesAndFoldersPicker: View {
    let projectPath: String
    let onPick: (FileEntryWire, FileContentWire) -> Void

    @Environment(PairingStore.self) private var pairing

    @State private var files: [FileEntryWire] = []
    @State private var query: String = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var fetching: String?

    private var filtered: [FileEntryWire] {
        if query.isEmpty { return files }
        let q = query.lowercased()
        return files.filter { $0.path.lowercased().contains(q) }
    }

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(SmoothieColor.textTertiary)
                    TextField("Search files in project", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .font(.system(.body, design: .monospaced))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                if loading {
                    ProgressView().tint(SmoothieColor.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle").foregroundStyle(SmoothieColor.statusErr)
                        Text(loadError).font(.system(size: 13)).foregroundStyle(SmoothieColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    Text(query.isEmpty ? "No files found." : "No matches.")
                        .font(.system(size: 13))
                        .foregroundStyle(SmoothieColor.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filtered) { file in row(file) }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Files & Folders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    private func row(_ file: FileEntryWire) -> some View {
        let isFetching = fetching == file.fullPath
        return Button {
            Task { await pick(file) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: file.path))
                    .font(.system(size: 13))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
                if isFetching {
                    ProgressView().controlSize(.small).tint(SmoothieColor.textTertiary)
                } else {
                    Text(formatSize(file.size))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .smoothieCard(cornerRadius: SmoothieMetrics.cornerRow)
        }
        .buttonStyle(.plain)
        .disabled(fetching != nil)
    }

    private func iconName(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":                                                  return "swift"
        case "kt", "kts":                                              return "k.circle"
        case "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "c", "cpp", "h":
                                                                       return "chevron.left.forwardslash.chevron.right"
        case "md", "txt":                                              return "doc.text"
        case "json", "yml", "yaml", "toml":                            return "curlybraces"
        default:                                                       return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.0fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / 1024 / 1024)
    }

    private func load() async {
        let api = pairing.api
        loading = true
        loadError = nil
        do {
            files = try await api.projectFiles(path: projectPath)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func pick(_ file: FileEntryWire) async {
        let api = pairing.api
        fetching = file.fullPath
        defer { fetching = nil }
        do {
            let content = try await api.fileContent(path: file.fullPath)
            onPick(file, content)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
