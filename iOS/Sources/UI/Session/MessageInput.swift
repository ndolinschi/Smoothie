import SwiftUI
import UniformTypeIdentifiers

/// Composer. Vertical stack: Suggestions (fresh session only) →
/// attachment chips (when staged) → rounded text field → mode chip +
/// paperclip + mic + coral send. The repo chip row that used to sit
/// above the text field was retired — the user didn't want the
/// project name restated; the picker now lives in the toolbar menu.
struct MessageInput: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let isFreshSession: Bool
    /// Current session state. When `.starting`/`.thinking`, the trailing
    /// send button becomes an Abort button instead.
    let sessionState: SessionStateWire
    let onSend: (String, [StagedAttachment]) async -> Void
    let onAbort: () -> Void
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
    @State private var showingMCP = false
    @State private var importError: String?
    @State private var voice = VoiceDictator()
    @State private var voiceError: String?
    @State private var pendingImagePickerSource: ImagePickerSheet.Source?
    /// Set to true the first time the user taps send in this view's
    /// lifetime. Used by `showSuggestions` so the starter chips stay
    /// visible until the user actually sends something — independent
    /// of whatever state events the daemon is pushing in the meantime
    /// (the prior @Observable-based gate had subtle propagation issues
    /// that left suggestions hidden on fresh sessions).
    @State private var hasUserSent = false
    @FocusState private var focused: Bool
    /// Used to stop dictation when the app goes to the background. Without
    /// this, the `AVAudioSession` stays in `.record` mode across launches
    /// and blocks other apps' audio playback until the user manually
    /// toggles the mic off.
    @Environment(\.scenePhase) private var scenePhase
    /// Used by the inline MCP picker sheet — it builds an APIClient
    /// against this store to talk to the daemon.
    @Environment(PairingStore.self) private var pairing

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !sending && !sessionEnded && (!trimmed.isEmpty || !attachments.isEmpty) }
    /// Show the starter chips until either the daemon-side session has
    /// real conversation content (parent passes `isFreshSession = false`)
    /// OR the user has tapped send in this view's lifetime. Earlier
    /// revisions also hid the bar the moment the user started typing
    /// or staged an attachment — the user asked for the chips to
    /// persist until the prompt actually goes out, so those gates were
    /// dropped. Tapping a chip still appends to whatever the user has
    /// typed via `insertAtCursor`.
    private var showSuggestions: Bool {
        isFreshSession && !hasUserSent && !sessionEnded
    }

    /// True when the daemon-side session is no longer accepting input.
    /// Today that's only `.done` — `.error` may still be recoverable via
    /// the connection banner's reconnect, and `.limitReached` is a
    /// rate-limit pause not a hard stop. Driven by the SSE state machine
    /// so a fresh `done` event flowing in mid-session disables sending
    /// without requiring a view rebuild.
    private var sessionEnded: Bool {
        sessionState == .done
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

            if sessionEnded {
                endedSessionFooter
            } else if voice.isListening {
                voiceComposerRow
            } else {
                // Repo chip row was retired in this iteration — the user
                // didn't want the project name re-stated in the composer
                // (it's already visible in the toolbar / Home). To switch
                // repos, pop back to Home and pick a different session.
                textField
                actionsRow
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(SmoothieColor.bgPrimary)
        .overlay(
            // Use the live sessionState (driven by SSE) — session.state is a
            // snapshot of the descriptor at view-mount time and never moves,
            // so reading it here meant the waiting hairline + the auto-focus
            // below never fired in practice. P25: was `statusWaiting` (orange)
            // → switched to `activeBorder` (white@30%) to fit the mono palette
            // without reintroducing a coral/orange leftover.
            Rectangle()
                .fill(sessionState == .waiting ? SmoothieColor.activeBorder : SmoothieColor.strokeSoft)
                .frame(height: 0.5),
            alignment: .top
        )
        .animation(.easeOut(duration: 0.18), value: showSuggestions)
        .animation(.easeInOut(duration: 0.18), value: voice.isListening)
        .animation(.easeInOut(duration: 0.25), value: sessionState)
        .onChange(of: sessionState) { _, new in
            // Auto-focus the composer when the agent is ready — BUT only
            // when there's no sheet already presented. Without the guard,
            // a `.waiting` transition arriving while AttachSheet /
            // ImagePicker / MentionPicker is open steals focus back to
            // the text field and dismisses the iOS keyboard mid-tap.
            // Removed `&& !showingModels` after the merge — model picker
            // moved to SessionView's toolbar (showingModelDropdown /
            // showingModelSheet) so this composer-local state var no
            // longer exists.
            let noSheetUp = !showingAttach
                && !showingImporter
                && !showingMention
                && !showingSkills
                && !showingMCP
                && pendingImagePickerSource == nil
            if new == .waiting && noSheetUp { focused = true }
        }
        .onChange(of: text) { oldText, newText in
            // P27.b — typing `@` at the start of a token auto-opens the
            // mention picker. We require a single-character append at the
            // very end (so paste of a string containing `@` doesn't
            // trigger), AND the character before the `@` must be
            // whitespace or absent (so email addresses like "me@x" don't
            // trigger either). The `@` is stripped before presenting —
            // the picker's selection callback re-inserts `@path` via
            // insertAtCursor, so leaving the user-typed `@` would
            // produce `@@path`.
            //
            // P27.k — explicitly gate on `!voice.isListening` too: voice
            // dictation can transcribe "at" as "@" mid-stream and we
            // don't want the picker stealing focus while the mic is
            // live. IME composition (Chinese / Japanese commits that
            // grow `text` by >1 character at once) implicitly falls
            // through the `count == oldText.count + 1` guard — those
            // users still have the paperclip → Mention File path.
            guard !showingMention, !showingAttach, !showingImporter,
                  !showingSkills, !showingMCP, pendingImagePickerSource == nil,
                  !voice.isListening
            else { return }
            guard newText.count == oldText.count + 1, newText.hasSuffix("@") else { return }
            // Drop the "@" the user just typed; `dropLast()` is grapheme-
            // cluster-aware so this is safe even when the preceding
            // character is a multi-scalar emoji.
            let prefix = newText.dropLast()
            if prefix.isEmpty || prefix.last?.isWhitespace == true {
                text = String(prefix)
                showingMention = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Release the mic + speech recognizer when iOS sends us to
            // the background. Otherwise a long dictation session left
            // running while the user switches apps holds the
            // AVAudioSession in `.record` mode and stops everything
            // else (Music, podcasts, FaceTime) from playing audio.
            if phase == .background && voice.isListening {
                voice.stop()
            }
        }
        .onDisappear {
            // scenePhase never fires when the composer simply leaves the
            // hierarchy (session view dismissed mid-dictation), so release
            // the mic here too — otherwise the audio session stays in
            // `.record` and keeps every other app's audio ducked.
            if voice.isListening {
                voice.stop()
            }
        }
        .sheet(isPresented: $showingMention) {
            MentionPickerSheet(
                session: session,
                onPick: { entry, content in
                    stage(file: entry, content: content, asMention: true)
                },
                onPickChat: { chat in
                    attachments.append(.chat(chat))
                    // Inline the @<title> marker into the text so the
                    // user can still see what context they pulled in.
                    insertAtCursor("@\(chat.title)")
                }
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
            .smoothieThemed()
        }
        .sheet(isPresented: $showingAttach) {
            AttachSheet(
                session: session,
                features: features,
                onTakePhoto:   { pendingImagePickerSource = .camera },
                onChoosePhoto: { pendingImagePickerSource = .library },
                onMentionFile: { showingMention = true },
                onAttachFile:  { showingImporter = true },
                onOpenSkills:  { showingSkills = true },
                onOpenMCP:     { showingMCP = true },
                onDismiss:     { showingAttach = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
            .smoothieThemed()
        }
        .sheet(item: $pendingImagePickerSource) { source in
            ImagePickerSheet(
                source: source,
                onPicked: { staged in
                    attachments.append(.image(staged))
                    pendingImagePickerSource = nil
                },
                onCancel: { pendingImagePickerSource = nil }
            )
            .smoothieThemed()
        }
        .sheet(isPresented: $showingSkills) {
            if let f = features {
                SlashCommandSheet(commands: f.slashCommands, onPick: { insertAtCursor($0) })
                    .presentationDetents([.medium])
                    .presentationBackground(.clear)
                    .smoothieThemed()
            }
        }
        .sheet(isPresented: $showingMCP) {
            MCPPickerSheet(
                session: session,
                pairing: pairing,
                onDismiss: { showingMCP = false }
            )
            .presentationDetents([.large])
            .presentationBackground(.clear)
            .smoothieThemed()
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
            .smoothieThemed()
        }
    }

    // MARK: - Rows

    /// Replaces the composer when the daemon-side session is `.done`
    /// (handed off to Terminal, or ended naturally). Sending into a
    /// dead session silently 404s, so the live text field was misleading
    /// — the user typed, tapped send, nothing happened. The footer
    /// explains the state and directs the user back to Home to start a
    /// fresh session in the same project.
    private var endedSessionFooter: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SmoothieColor.statusDone)
            VStack(alignment: .leading, spacing: 2) {
                Text("Session ended")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                Text("Tap + on Home to start a new session in this project.")
                    .font(.system(size: 12))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private var textField: some View {
        TextField(
            // Keep the merged-in placeholder set — the parallel branch
            // landed on "Ask Claude…" / "Message…" after the earlier
            // sim feedback flagged "Add feedback…" as confusing for a
            // brand-new session. Plays nicer across non-Claude CLIs too.
            isFreshSession ? "Ask Claude…" : "Message…",
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
        // P25.g/h consolidation (origin/main): the leading "+" + the
        // composer-level ModelChip were both removed. Attach is now a
        // single entry via the trailing paperclip → AttachSheet, and
        // model picking lives in the toolbar title dropdown
        // (showingModelDropdown). My earlier composer ModelChip work
        // (p25.b) is superseded — the toolbar dropdown is always
        // visible and shows the friendly model name. ModelChip /
        // ModelCatalog files stay in the repo as building blocks for
        // a future inline-overlay dropdown if we revisit.
        HStack(spacing: SmoothieMetrics.space12) {
            ModeChip(mode: session.mode) {
                onTapMode()
            }
            Spacer()
            // Paperclip opens the full AttachSheet (camera, mention, file,
            // commands, models, MCP). Direct fileImporter access stays
            // reachable from AttachSheet's "Attach a file" row (P25.g).
            Button {
                showingAttach = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Attach or open menu")

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

    private var isThinking: Bool {
        sessionState == .starting || sessionState == .thinking
    }

    /// Either Send (coral arrow.up) or Abort (red stop.fill) depending on
    /// whether the agent is currently working. Same slot so the user never
    /// has to hunt for a separate "stop" affordance.
    @ViewBuilder
    private var sendButton: some View {
        if isThinking {
            Button(action: onAbort) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: SmoothieMetrics.sendButton, height: SmoothieMetrics.sendButton)
                    .background(SmoothieColor.statusErr, in: .circle)
            }
            .buttonStyle(.plain)
        } else {
            Button(action: send) {
                // P27.k — disabled state previously rendered as
                // white@40% on black@35% in light mode (grey-on-grey,
                // failed WCAG). Use a separate, less-translucent bg
                // tint and keep the fg at full onAccent opacity so the
                // glyph stays readable in both modes.
                Image(systemName: sending ? "ellipsis" : "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SmoothieColor.onAccent)
                    .frame(width: SmoothieMetrics.sendButton, height: SmoothieMetrics.sendButton)
                    .background(
                        SmoothieColor.accent.opacity(canSend ? 1.0 : 0.55),
                        in: .circle
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
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

    @ViewBuilder
    private func attachmentChip(_ att: StagedAttachment) -> some View {
        switch att {
        case .file(let f):  fileChip(f)
        case .image(let i): imageChip(i)
        case .chat(let c):  chatChip(c)
        }
    }

    /// Capsule rendered for a `StagedChat` mention. Mirrors the file
    /// chip but uses the conversation glyph + a "past" prefix so the
    /// user can distinguish staged transcripts from staged code files.
    private func chatChip(_ c: StagedChat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SmoothieColor.accent)
            Text("past · \(c.title)")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
            removeButton(id: c.id)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }

    private func fileChip(_ f: StagedFile) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SmoothieColor.textSecondary)
            Text(f.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
            if f.truncated {
                Text("(trimmed)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            removeButton(id: f.id)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }

    private func imageChip(_ i: StagedImage) -> some View {
        HStack(spacing: 6) {
            Image(uiImage: i.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(i.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
            removeButton(id: i.id)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(SmoothieColor.bgCard, in: .capsule)
        .overlay(Capsule().strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5))
    }

    private func removeButton(id: UUID) -> some View {
        Button {
            attachments.removeAll { $0.id == id }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.leading, 2)
        }
        .buttonStyle(.plain)
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
                        .foregroundStyle(SmoothieColor.onAccent)
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
        // Flip the local freshness flag the moment the user commits a
        // message — independent of whatever state the SSE stream is in.
        // The animation on `showSuggestions` smooths the fade-out so the
        // bar doesn't blink off as the message lands.
        hasUserSent = true
        Task {
            await onSend(value, staged)
            text = ""
            attachments = []
            sending = false
        }
    }

    private func insertAtCursor(_ snippet: String) {
        // Slash commands have special semantics — they replace the field.
        // The user picking `/clear` from the sheet expects to send just
        // `/clear`, not `whatever they had typed before` + ` /clear`.
        // If there's an existing leading `/word`, replace that prefix.
        // If the field is otherwise non-empty, replace the whole field
        // (the agent doesn't accept "free text /command" — it's parsed
        // strictly as the first token).
        if snippet.hasPrefix("/") {
            let trimmedField = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedField.hasPrefix("/") {
                // Replace existing /command prefix up to first whitespace.
                let withoutLeading = trimmedField.drop(while: { !$0.isWhitespace })
                text = snippet + String(withoutLeading)
            } else if trimmedField.isEmpty {
                text = snippet + " "
            } else {
                // Existing user text is incompatible with /command —
                // assume the user wants to start over with the command.
                text = snippet + " "
            }
            focused = true
            return
        }

        // Default behaviour for non-slash snippets (e.g. @mention) is
        // insert-at-end with surrounding whitespace.
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += snippet + " "
        } else {
            text += " " + snippet + " "
        }
        focused = true
    }

    private func stage(file entry: FileEntryWire, content: FileContentWire, asMention: Bool) {
        let f = StagedFile(
            name: (entry.path as NSString).lastPathComponent,
            relativePath: entry.path,
            content: content.content,
            truncated: content.truncated
        )
        let pathAlreadyStaged = attachments.contains { existing in
            if case .file(let other) = existing { return other.relativePath == f.relativePath }
            return false
        }
        if !pathAlreadyStaged {
            attachments.append(.file(f))
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
                // 4 MB cap — the server-side message body limit is 16 MB
                // and 100 KB (our previous cap) silently truncated normal
                // source files. 4 MB comfortably holds even large
                // generated files while keeping the stream-json payload
                // sane.
                let maxBytes = 4 * 1024 * 1024
                let truncated = raw.count > maxBytes
                let slice = truncated ? raw.prefix(maxBytes) : raw
                guard let body = String(data: slice, encoding: .utf8) else {
                    importError = "Not a text file."
                    return
                }
                let f = StagedFile(
                    name: url.lastPathComponent,
                    relativePath: url.lastPathComponent,
                    content: body,
                    truncated: truncated
                )
                attachments.append(.file(f))
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
