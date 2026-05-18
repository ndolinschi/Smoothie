import SwiftUI
import UniformTypeIdentifiers

struct MessageInput: View {
    let state: SessionState
    let cli: CLIType
    let projectPath: String
    let onSend: (_ content: String, _ attachments: [StagedAttachment]) async -> Void
    var onSwitchCLI: () -> Void = {}
    var disabled: Bool = false

    @State private var text: String = ""
    @State private var sending = false
    @State private var attachments: [StagedAttachment] = []
    @State private var showMentionPicker = false
    @State private var showFileImporter = false
    @State private var importError: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !sending && !disabled && (!trimmed.isEmpty || !attachments.isEmpty) }

    var body: some View {
        VStack(spacing: 8) {
            chipsRow
            composerRow
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .fill(state == .waiting ? Color.white.opacity(0.35) : Color.white.opacity(0.06))
                .frame(height: 0.5),
            alignment: .top
        )
        .onChange(of: state) { _, newState in
            if newState == .waiting { focused = true }
        }
        .sheet(isPresented: $showMentionPicker) {
            MentionPickerView(projectPath: projectPath) { entry, content in
                stage(entry: entry, content: content, fromMention: true)
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.text, .sourceCode, .plainText, .json, .yaml, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            handleImporter(result: result)
        }
        .alert("Couldn't attach file", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Subviews

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                modelChip
                ForEach(attachments) { att in
                    attachmentChip(att)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var modelChip: some View {
        Button(action: onSwitchCLI) {
            HStack(spacing: 6) {
                Image(systemName: cliIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(cli.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassPill()
        }
        .buttonStyle(.plain)
    }

    private func attachmentChip(_ att: StagedAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .semibold))
            Text(att.name)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            if att.truncated {
                Text("(trimmed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Button {
                attachments.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.leading, 2)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassPill(emphasized: true)
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            plusMenu

            TextField(
                state == .waiting ? "agent is waiting for you…" : "send a message",
                text: $text,
                axis: .vertical
            )
            .focused($focused)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .glassSurface(cornerRadius: Theme.Radius.input, emphasis: state == .waiting ? .subtle : .none)
            .disabled(disabled)

            sendButton
        }
    }

    private var plusMenu: some View {
        Menu {
            Button {
                showMentionPicker = true
            } label: {
                Label("Mention file (@)", systemImage: "at")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("Attach file", systemImage: "paperclip")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .background {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.glassStroke, lineWidth: 0.5)
                )
        }
        .disabled(disabled)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: sending ? "ellipsis" : "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canSend ? .black : .white.opacity(0.4))
                .frame(width: 44, height: 44)
                .background {
                    ZStack {
                        if canSend {
                            Color.white
                        } else {
                            Color.white.opacity(0.06)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(canSend ? Color.clear : Theme.glassStroke, lineWidth: 0.5)
                )
        }
        .disabled(!canSend)
    }

    private var cliIcon: String {
        switch cli {
        case .opencode: return "terminal"
        case .claude:   return "sparkle"
        case .gemini:   return "diamond"
        case .codex:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    // MARK: - Actions

    private func stage(entry: FileEntry, content: FileContent, fromMention: Bool) {
        let name = (entry.path as NSString).lastPathComponent
        let att = StagedAttachment(
            name: name,
            relativePath: entry.path,
            content: content.content,
            truncated: content.truncated
        )
        if !attachments.contains(where: { $0.relativePath == att.relativePath }) {
            attachments.append(att)
        }
        if fromMention {
            // Insert "@<relative path>" at the end of the current text
            let trimmedText = text
            if trimmedText.isEmpty {
                text = "@\(entry.path) "
            } else if trimmedText.hasSuffix(" ") || trimmedText.hasSuffix("\n") {
                text = trimmedText + "@\(entry.path) "
            } else {
                text = trimmedText + " @\(entry.path) "
            }
        }
    }

    private func handleImporter(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let raw = try Data(contentsOf: url)
                let maxBytes = 100 * 1024
                let truncated = raw.count > maxBytes
                let slice = truncated ? raw.prefix(maxBytes) : raw
                guard let text = String(data: slice, encoding: .utf8) else {
                    importError = "Not a text file."
                    return
                }
                let att = StagedAttachment(
                    name: url.lastPathComponent,
                    relativePath: url.lastPathComponent,
                    content: text,
                    truncated: truncated
                )
                attachments.append(att)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func send() {
        guard canSend else { return }
        sending = true
        let userText = trimmed
        let staged = attachments
        Task {
            await onSend(userText, staged)
            text = ""
            attachments = []
            sending = false
        }
    }
}
