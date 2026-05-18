import SwiftUI

/// Folder browser that lets the user drill into any directory inside the
/// server's allowed roots and pin it as a project.
struct BrowserSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server

    @State private var stack: [String] = []           // navigation stack, last is current
    @State private var current: BrowseResponse?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                BackdropView()

                VStack(spacing: 0) {
                    pathBar
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
                    } else if let response = current {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                if response.entries.isEmpty {
                                    Text("Empty folder.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.4))
                                        .padding(.vertical, 40)
                                } else {
                                    ForEach(response.entries) { row($0) }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, response.current != nil ? 100 : 24)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }

                if let path = current?.current {
                    VStack {
                        Spacer()
                        useButton(path: path)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if stack.count > 1 || current?.parent != nil {
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .task { await load(path: nil) }
    }

    private var titleText: String {
        if let path = current?.current {
            return (path as NSString).lastPathComponent
        }
        return "Add project"
    }

    private var pathBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
            Text(current?.current ?? "Choose a folder")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: Theme.Radius.row)
    }

    private func row(_ entry: BrowseEntry) -> some View {
        Button {
            Task { await load(path: entry.path) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isGit ? "circlebadge.2" : "folder")
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
            .glassSurface(cornerRadius: Theme.Radius.row)
        }
        .buttonStyle(.plain)
    }

    private func useButton(path: String) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)

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
                    onAdd(path)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                        Text("Add")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.white, in: .rect(cornerRadius: Theme.Radius.button))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    private func navigateUp() {
        if let parent = current?.parent {
            Task { await load(path: parent) }
        } else {
            stack = []
            Task { await load(path: nil) }
        }
    }

    private func load(path: String?) async {
        guard let api = server.api else { return }
        loading = true
        loadError = nil
        do {
            let response = try await api.browse(path: path)
            current = response
            if let p = path {
                if stack.last != p { stack.append(p) }
            } else {
                stack = []
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}
