import SwiftUI

/// File picker for @-mentions. Lists project files via `/projects/files`,
/// returns the absolute file content plus the relative path so callers can
/// both stage the file and insert "@<relative path>" into the input.
struct MentionPickerSheet: View {
    let projectPath: String
    let onPick: (FileEntryWire, FileContentWire) -> Void

    @Environment(\.dismiss) private var dismiss
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
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.white.opacity(0.45))
                        TextField("Search files in project", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(.white)
                            .font(.system(.body, design: .monospaced))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .glassEffect(in: .rect(cornerRadius: 14))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                    if loading {
                        ProgressView().tint(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let loadError {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
                            Text(loadError).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filtered.isEmpty {
                        Text(query.isEmpty ? "No files found." : "No matches.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
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
            .navigationTitle("Mention file")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(.white.opacity(0.7))
                }
            }
        }
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
                        .truncationMode(.head)
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
            .padding(.vertical, 9)
            .glassEffect(in: .rect(cornerRadius: 12))
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
        let api = APIClient(store: pairing)
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
        let api = APIClient(store: pairing)
        fetching = file.fullPath
        defer { fetching = nil }
        do {
            let content = try await api.fileContent(path: file.fullPath)
            onPick(file, content)
            dismiss()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
