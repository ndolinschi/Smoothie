import SwiftUI
import UniformTypeIdentifiers

/// Composer footer of a session: above-the-input chips (current model +
/// staged attachments), the "+" ComposerMenu, the text field, and a
/// glass-prominent send button. All Liquid Glass.
struct MessageInput: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let onSend: (String, [StagedAttachment]) async -> Void
    let onSwitchModel: (String) -> Void
    let onSwitchEffort: (String) -> Void
    let onSwitchMode: (String) -> Void

    @State private var text: String = ""
    @State private var sending = false
    @State private var attachments: [StagedAttachment] = []
    @State private var showingMention = false
    @State private var showingImporter = false
    @State private var importError: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !sending && (!trimmed.isEmpty || !attachments.isEmpty) }

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
                .fill(session.state == .waiting ? Color.orange.opacity(0.5) : Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .top
        )
        .onChange(of: session.state) { _, new in
            if new == .waiting { focused = true }
        }
        .sheet(isPresented: $showingMention) {
            MentionPickerSheet(projectPath: session.projectPath) { entry, content in
                stage(file: entry, content: content, asMention: true)
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.text, .sourceCode, .plainText, .json, .yaml, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result: result)
        }
        .alert("Couldn't attach", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

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
        Menu {
            if let f = features {
                if !f.availableModels.isEmpty {
                    Section("Models") {
                        ForEach(f.availableModels, id: \.self) { m in
                            Button {
                                onSwitchModel(m)
                            } label: {
                                if (session.model ?? f.defaultModel) == m {
                                    Label(m, systemImage: "checkmark")
                                } else {
                                    Text(m)
                                }
                            }
                        }
                    }
                }
                if f.supportsReasoningEffort, !f.availableReasoningEfforts.isEmpty {
                    Section("Reasoning effort") {
                        ForEach(f.availableReasoningEfforts, id: \.self) { e in
                            Button {
                                onSwitchEffort(e)
                            } label: {
                                if session.reasoningEffort == e {
                                    Label(e, systemImage: "checkmark")
                                } else {
                                    Text(e)
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                ProviderIcon(cli: session.cli, size: 12)
                Text(modelLabel)
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(in: .capsule)
        }
    }

    private var modelLabel: String {
        let model = session.model ?? features?.defaultModel ?? session.cli.displayName
        if let effort = session.reasoningEffort, !effort.isEmpty {
            return "\(model) · \(effort)"
        }
        return model
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
        .glassEffect(in: .capsule)
    }

    private var composerRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ComposerMenu(
                session: session,
                features: features,
                onInsertSlash: { cmd in insertAtCursor(cmd) },
                onAttachFile: { showingImporter = true },
                onMentionFile: { showingMention = true },
                onRestartWithModel: { onSwitchModel($0) },
                onRestartWithEffort: { onSwitchEffort($0) },
                onRestartWithMode: { onSwitchMode($0) }
            )

            TextField(
                session.state == .waiting ? "agent is waiting for you…" : "send a message",
                text: $text,
                axis: .vertical
            )
            .focused($focused)
            .lineLimit(1...5)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(.white)
            .glassEffect(in: .rect(cornerRadius: 14))

            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canSend ? .black : .white.opacity(0.4))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .disabled(!canSend)
        }
    }

    // MARK: - Actions

    private func send() {
        let value = trimmed
        let staged = attachments
        guard !value.isEmpty || !staged.isEmpty else { return }
        sending = true
        Task {
            await onSend(value, staged)
            text = ""
            attachments = []
            sending = false
        }
    }

    private func insertAtCursor(_ snippet: String) {
        // Simple append. SwiftUI TextField doesn't expose a cursor position;
        // we put a leading space if needed.
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += snippet + " "
        } else {
            text += " " + snippet + " "
        }
        focused = true
    }

    private func stage(file entry: FileEntryWire, content: FileContentWire, asMention: Bool) {
        let att = StagedAttachment(
            name: (entry.path as NSString).lastPathComponent,
            relativePath: entry.path,
            content: content.content,
            truncated: content.truncated
        )
        if !attachments.contains(where: { $0.relativePath == att.relativePath }) {
            attachments.append(att)
        }
        if asMention {
            insertAtCursor("@\(entry.path)")
        }
    }

    private func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let raw = try Data(contentsOf: url)
                let maxBytes = 100 * 1024
                let truncated = raw.count > maxBytes
                let slice = truncated ? raw.prefix(maxBytes) : raw
                guard let body = String(data: slice, encoding: .utf8) else {
                    importError = "Not a text file."
                    return
                }
                let att = StagedAttachment(
                    name: url.lastPathComponent,
                    relativePath: url.lastPathComponent,
                    content: body,
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
}
