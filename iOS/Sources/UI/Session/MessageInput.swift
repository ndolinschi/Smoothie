import SwiftUI
import UniformTypeIdentifiers

/// Composer footer of a session: above-the-input chips (current model +
/// staged attachments), the "+" ComposerMenu, the text field, and a
/// glass-prominent send button. All Liquid Glass.
struct MessageInput: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    /// Every adapter info row from /adapters — enables in-chat provider
    /// switching ("open in OpenCode") via the model chip menu.
    let allAdapters: [AdapterInfoWire]
    /// True while the session has no events yet — surfaces the starter
    /// suggestion bar. SessionView derives this from `store.events.isEmpty`.
    let isFreshSession: Bool
    let onSend: (String, [StagedAttachment]) async -> Void
    let onSwitchModel: (String) -> Void
    let onSwitchEffort: (String) -> Void
    let onSwitchMode: (String) -> Void
    let onSwitchProvider: (CLIWire) -> Void

    @State private var text: String = ""
    @State private var sending = false
    @State private var attachments: [StagedAttachment] = []
    @State private var showingMention = false
    @State private var showingImporter = false
    @State private var importError: String?
    @State private var voice = VoiceDictator()
    @State private var voiceError: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !sending && (!trimmed.isEmpty || !attachments.isEmpty) }
    private var showSuggestions: Bool {
        isFreshSession && trimmed.isEmpty && attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if showSuggestions {
                SuggestionsBar(session: session) { snippet in
                    insertAtCursor(snippet)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            chipsRow
            composerRow
        }
        .animation(.easeOut(duration: 0.18), value: showSuggestions)
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
        .alert("Voice unavailable", isPresented: Binding(
            get: { voiceError != nil },
            set: { if !$0 { voiceError = nil } }
        )) {
            Button("OK", role: .cancel) { voiceError = nil }
        } message: {
            Text(voiceError ?? "")
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
            // Section 1 — model picker for the CURRENT provider.
            if let f = features, !f.availableModels.isEmpty {
                Section(session.cli.displayName + " models") {
                    ForEach(f.availableModels, id: \.self) { m in
                        Button {
                            onSwitchModel(m)
                        } label: {
                            let friendly = session.cli.friendlyModelName(m)
                            if (session.model ?? f.defaultModel) == m {
                                Label(friendly, systemImage: "checkmark")
                            } else {
                                Text(friendly)
                            }
                        }
                    }
                }
            }
            // Section 2 — reasoning effort if supported.
            if let f = features, f.supportsReasoningEffort, !f.availableReasoningEfforts.isEmpty {
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
            // Section 3 — switch provider entirely ("Open in OpenCode" etc.).
            let otherInstalled = allAdapters.filter { $0.installed && $0.cli != session.cli }
            if !otherInstalled.isEmpty {
                Section("Open in another provider") {
                    ForEach(otherInstalled) { adapter in
                        Button {
                            onSwitchProvider(adapter.cli)
                        } label: {
                            Label("Open in \(adapter.cli.displayName)", systemImage: "arrow.right.circle")
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
        let raw = session.model ?? features?.defaultModel ?? session.cli.displayName
        let friendly = session.cli.friendlyModelName(raw)
        if let effort = session.reasoningEffort, !effort.isEmpty {
            return "\(friendly) · \(effort)"
        }
        return friendly
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

    @ViewBuilder
    private var composerRow: some View {
        if voice.isListening {
            voiceComposerRow
        } else {
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
                    "Plan, Build, / for commands, @ for context",
                    text: $text,
                    axis: .vertical
                )
                .focused($focused)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .glassEffect(in: .rect(cornerRadius: 14))

                trailingActionButton
            }
        }
    }

    /// Full-width glass capsule shown in place of the standard composer while
    /// dictation is running. Sparkle icon on the left, waveform driven by
    /// `voice.level` in the centre, stop button on the right.
    private var voiceComposerRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 28, height: 28)

                VoiceWaveform(level: voice.level)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)

                Button {
                    voice.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(.white, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 22))

            if !voice.draft.isEmpty {
                Text(voice.draft)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 14)
            }
        }
    }

    /// Voice icon when nothing is typed; arrow-up send when there is. Smaller
    /// than the v1 button to match the Cursor-style composer reference.
    @ViewBuilder
    private var trailingActionButton: some View {
        if canSend {
            Button(action: send) {
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(.white, in: .circle)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                Task { await toggleVoice() }
            } label: {
                Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(voice.isListening ? .black : .white)
                    .frame(width: 36, height: 36)
                    .background {
                        if voice.isListening {
                            Circle().fill(.white)
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.75)
                        }
                    }
                    .glassEffect(in: .circle)
            }
            .buttonStyle(.plain)
            .symbolEffect(.variableColor.iterative, isActive: voice.isListening)
        }
    }

    private func toggleVoice() async {
        if voice.isListening {
            voice.stop()
            return
        }
        await voice.start(initial: text) { transcribed in
            text = transcribed
        }
        if case .unavailable(let msg) = voice.state {
            voiceError = msg
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
