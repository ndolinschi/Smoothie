import SwiftUI
import UniformTypeIdentifiers

/// REF-1 / REF-3 / REF-5 composer. Vertical stack: Suggestions (fresh
/// session only) → attachment chips (when staged) → + button + project chip
/// row → rounded text field → mode chip + quick actions + coral send.
struct MessageInput: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let allAdapters: [AdapterInfoWire]
    let isFreshSession: Bool
    let onSend: (String, [StagedAttachment]) async -> Void
    let onSwitchModel: (String) -> Void
    let onSwitchEffort: (String) -> Void
    let onSwitchMode: (String) -> Void
    let onSwitchProvider: (CLIWire) -> Void
    /// Opens the mode picker (owned by SessionView so the action-chips row
    /// can share the same sheet anchor).
    let onTapMode: () -> Void

    @State private var text: String = ""
    @State private var sending = false
    @State private var attachments: [StagedAttachment] = []
    @State private var showingMention = false
    @State private var showingImporter = false
    @State private var showingAttach = false
    @State private var showingSkills = false
    @State private var showingModels = false
    @State private var showingMCP = false
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
        VStack(alignment: .leading, spacing: 10) {
            if showSuggestions {
                SuggestionsBar(session: session) { snippet in
                    insertAtCursor(snippet)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !attachments.isEmpty {
                attachmentsRow
            }

            if voice.isListening {
                voiceComposerRow
            } else {
                textField
                actionsRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(SmoothieColor.bgPrimary)
        .overlay(
            Rectangle()
                .fill(session.state == .waiting ? SmoothieColor.statusWaiting.opacity(0.55) : SmoothieColor.strokeSoft)
                .frame(height: 0.5),
            alignment: .top
        )
        .animation(.easeOut(duration: 0.18), value: showSuggestions)
        .animation(.easeInOut(duration: 0.18), value: voice.isListening)
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
        .sheet(isPresented: $showingAttach) {
            AttachSheet(
                session: session,
                features: features,
                onMentionFile: { showingMention = true },
                onAttachFile:  { showingImporter = true },
                onOpenSkills:  { showingSkills = true },
                onOpenModels:  { showingModels = true },
                onOpenMCP:     { showingMCP = true },
                onDismiss:     { showingAttach = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingSkills) {
            if let f = features {
                SlashCommandSheet(commands: f.slashCommands, onPick: { insertAtCursor($0) })
                    .presentationDetents([.medium])
                    .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingModels) {
            if let f = features {
                ModelPickerSheet(
                    currentModel: session.model,
                    currentEffort: session.reasoningEffort,
                    features: f,
                    onPickModel: { onSwitchModel($0) },
                    onPickEffort: { onSwitchEffort($0) }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingMCP) {
            MCPComingSoonSheet()
                .presentationDetents([.medium])
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
        .sheet(isPresented: Binding(
            get: { voiceError != nil },
            set: { if !$0 { voiceError = nil } }
        )) {
            VoiceUnavailableSheet(message: voiceError ?? "") {
                voiceError = nil
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
    }

    // MARK: - Rows

    private var textField: some View {
        TextField(
            isFreshSession ? "Code" : "Add feedback…",
            text: $text,
            axis: .vertical
        )
        .focused($focused)
        .lineLimit(1...5)
        .font(.system(size: 15))
        .foregroundStyle(SmoothieColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                .strokeBorder(SmoothieColor.stroke, lineWidth: 1)
        )
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                showingAttach = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().strokeBorder(SmoothieColor.stroke, lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            ModeChip(mode: session.mode) {
                onTapMode()
            }
            Spacer()
            Button {
                showingImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task { await toggleVoice() }
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            sendButton
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: sending ? "ellipsis" : "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: SmoothieMetrics.sendButton, height: SmoothieMetrics.sendButton)
                .background(SmoothieColor.accent.opacity(canSend ? 1.0 : 0.35), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    private var attachmentsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments) { att in
                    attachmentChip(att)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func attachmentChip(_ att: StagedAttachment) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text(att.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
            if att.truncated {
                Text("(trimmed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            Button {
                attachments.removeAll { $0.id == att.id }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .padding(.leading, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }

    /// Full-width glass capsule shown in place of the standard composer while
    /// dictation is running. Replaces both `projectRow` and `textField` and
    /// the `actionsRow` while listening.
    private var voiceComposerRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SmoothieColor.accent)
                    .frame(width: 28, height: 28)
                VoiceWaveform(level: voice.level, color: SmoothieColor.accent)
                    .frame(height: 28)
                    .frame(maxWidth: .infinity)
                Button {
                    voice.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: SmoothieMetrics.sendButton, height: SmoothieMetrics.sendButton)
                        .background(SmoothieColor.accent, in: .circle)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerLg))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                    .strokeBorder(SmoothieColor.stroke, lineWidth: 1)
            )
            if !voice.draft.isEmpty {
                Text(voice.draft)
                    .font(.system(size: 12))
                    .foregroundStyle(SmoothieColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Actions

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
