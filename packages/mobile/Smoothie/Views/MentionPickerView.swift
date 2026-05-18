import SwiftUI

/// File picker that lists files in a project. Used both for "@-mention" context
/// and the regular attach-file flow.
struct MentionPickerView: View {
    let projectPath: String
    let onPick: (FileEntry, FileContent) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server

    @State private var files: [FileEntry] = []
    @State private var query: String = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var fetchingPath: String?
    @FocusState private var searchFocused: Bool

    var filtered: [FileEntry] {
        guard !query.isEmpty else { return files }
        let q = query.lowercased()
        return files.filter { $0.path.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BackdropView()

                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    if loading {
                        Spacer()
                        ProgressView().tint(.white.opacity(0.5))
                        Spacer()
                    } else if let loadError {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.error)
                            Text(loadError)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.55))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                    } else if filtered.isEmpty {
                        Spacer()
                        Text(query.isEmpty ? "No files found." : "No matches.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 4) {
                                ForEach(filtered) { file in
                                    fileRow(file)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Attach file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .task { await load() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))
            TextField("Search files in project", text: $query)
                .focused($searchFocused)
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
        .glassSurface(cornerRadius: Theme.Radius.input)
    }

    private func fileRow(_ file: FileEntry) -> some View {
        let isFetching = fetchingPath == file.fullPath
        return Button {
            Task { await pick(file) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: file.path))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(URL(fileURLWithPath: file.path).lastPathComponent)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                Spacer()
                if isFetching {
                    ProgressView().controlSize(.small).tint(.white.opacity(0.5))
                } else {
                    Text(formatSize(file.size))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .glassSurface(cornerRadius: Theme.Radius.row)
        }
        .buttonStyle(.plain)
        .disabled(fetchingPath != nil)
    }

    private func iconName(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "ts", "tsx", "js", "jsx", "py", "rb", "go", "rs", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.text"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.0fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / 1024 / 1024)
    }

    private func load() async {
        guard let api = server.api else { return }
        loading = true
        loadError = nil
        do {
            files = try await api.projectFiles(path: projectPath)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func pick(_ file: FileEntry) async {
        guard let api = server.api else { return }
        fetchingPath = file.fullPath
        defer { fetchingPath = nil }
        do {
            let content = try await api.fileContent(path: file.fullPath)
            onPick(file, content)
            dismiss()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
