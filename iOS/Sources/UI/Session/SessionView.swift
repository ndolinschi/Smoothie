import SwiftUI

// SessionLiveStore lives in its own file (P24.d D1) to keep this view
// focused on layout / toolbar / sheets. See SessionLiveStore.swift.

struct SessionView: View {
    let session: SessionDescriptorWire
    @Environment(PairingStore.self) private var pairing
    @Environment(RecentsStore.self) private var recents
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentSession: SessionDescriptorWire
    @State private var store: SessionLiveStore?
    @State private var features: ProviderFeaturesWire?
    @State private var confirmKill = false
    @State private var switchError: String?
    @State private var lastNotifiedState: SessionStateWire?
    @State private var showingModeSheet = false
    @State private var showingDiffSheet = false
    /// Drives the bottom-sheet presentation of `ContextBudgetPanel`
    /// from the toolbar ellipsis menu's "Context usage" item (P27.a —
    /// the always-visible StatusFooter that hosted this tap target was
    /// removed; the data is still one tap away via the menu).
    @State private var showingBudget = false
    @State private var showingModelSheet = false
    /// P25.b — compact rounded-card popover anchored to the toolbar
    /// title. The full search-enabled `ModelPickerSheet` is still
    /// reachable from this dropdown's "All models…" footer.
    @State private var showingModelDropdown = false
    /// P25.f — repository picker bottom sheet. Opened via the leading
    /// `+` button on the repo chips row, or via tapping a non-active
    /// chip directly (which goes through `onSwitchRepo` instead).
    @State private var showingRepoPicker = false

    enum SwitchTarget: Identifiable, Equatable {
        case model(String)
        case effort(String)
        case mode(String)
        case provider(CLIWire)

        var id: String {
            switch self {
            case .model(let s): return "model:\(s)"
            case .effort(let s): return "effort:\(s)"
            case .mode(let s): return "mode:\(s)"
            case .provider(let c): return "provider:\(c.rawValue)"
            }
        }

        var label: String {
            switch self {
            case .model(let s): return "model = \(s)"
            case .effort(let s): return "reasoning effort = \(s)"
            case .mode(let s): return "mode = \(s)"
            case .provider(let c): return "provider = \(c.displayName)"
            }
        }
    }

    /// Pairing id this SessionView was opened against. Captured at init
    /// so we can detect the user removing or switching pairings mid-
    /// session — SessionView dismisses itself in that case rather than
    /// continuing to drive a dead daemon.
    @State private var originPairingId: String?

    init(session: SessionDescriptorWire) {
        self.session = session
        _currentSession = State(initialValue: session)
    }

    private var toolbarSubtitle: String {
        let modeLabel = (currentSession.mode ?? "default")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return "\(currentSession.cli.displayName) · \(modeLabel)"
    }

    /// Friendly model name (e.g. `sonnet` → `Claude Sonnet 4.6`). Falls
    /// back to the CLI's display name when the session has no explicit
    /// model set.
    private var modelChipLabel: String {
        if let model = currentSession.model, !model.isEmpty {
            return currentSession.cli.friendlyModelName(model)
        }
        return currentSession.cli.displayName
    }

    /// Lowercase mode token for the cloud chip below the model.
    private var modeChipLabel: String {
        (currentSession.mode ?? "default")
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Recent project paths excluding the active session's path. Surfaced
    /// as the trailing chips on the repo row (P25.e); the picker sheet
    /// presents the same list under a search field.
    private var otherRecentProjects: [String] {
        recents.paths.filter { $0 != currentSession.projectPath }
    }

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            if let store {
                VStack(spacing: 8) {
                    ConnectionBanner(
                        connection: store.connection,
                        state: store.state,
                        hasReceivedEvent: store.hasReceivedEvent,
                        onReconnect: { store.reconnect() }
                    )
                    .animation(.easeInOut(duration: 0.2), value: store.connected)
                    .animation(.easeInOut(duration: 0.2), value: store.hasReceivedEvent)
                    // P27.c — EnvPill only renders for non-default modes.
                    // "Default" is the no-op case and carries no signal
                    // worth a permanent capsule. The inline StatusBadge
                    // ("thinking") was removed entirely; AgentStream's
                    // ThinkingPulseRow communicates the agent working
                    // state, which is enough.
                    if let mode = currentSession.mode,
                       !mode.isEmpty,
                       mode.lowercased() != "default" {
                        EnvPill(label: modeChipLabel.capitalized) {
                            showingModeSheet = true
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, SmoothieMetrics.space2)
                    }
                    AgentStream(
                        events: store.events,
                        connection: store.connection,
                        state: store.state,
                        expandStore: store
                    )
                    if !store.events.isEmpty {
                        ActionChipsRow(
                            events: store.events,
                            onPlanTap: { showingModeSheet = true },
                            onDiffTap: { showingDiffSheet = true }
                        )
                    }
                    MessageInput(
                        session: currentSession,
                        features: features,
                        isFreshSession: store.events.isEmpty,
                        sessionState: store.state,
                        onSend: { text, attachments in
                            let composed = attachments.composedMessage(with: text)
                            await sendMessage(composed, images: attachments.images)
                        },
                        onAbort: { Task { await abortTurn() } },
                        onTapMode: { showingModeSheet = true },
                        otherProjects: otherRecentProjects,
                        onTapRepoPlus: { showingRepoPicker = true },
                        onSwitchRepo: { path in switchToProject(path) }
                    )
                }
            } else {
                ProgressView().tint(SmoothieColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    showingModelDropdown = true
                } label: {
                    HStack(spacing: 4) {
                        Text(modelChipLabel)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SmoothieColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SmoothieColor.textSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingModelDropdown, arrowEdge: .top) {
                    if let f = features {
                        ModelDropdownMenu(
                            cli: currentSession.cli,
                            currentModel: currentSession.model,
                            features: f,
                            onPickModel: { m in await applyRestart(.model(m)) },
                            onMoreOptions: {
                                showingModelDropdown = false
                                showingModelSheet = true
                            }
                        )
                        .presentationBackground(SmoothieColor.menuBg)
                    } else {
                        ProgressView()
                            .tint(SmoothieColor.textSecondary)
                            .padding(SmoothieMetrics.space24)
                            .presentationCompactAdaptation(.popover)
                            .presentationBackground(SmoothieColor.menuBg)
                    }
                }
                // Note: my earlier p25 work kept a small "cloud + mode"
                // pill inline next to the model button. The parallel
                // branch (p25.c) moved that to a standalone `EnvPill`
                // row sitting below the ConnectionBanner, so the inline
                // version is removed here — see the EnvPill above
                // `AgentStream` in `body`.
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if store?.contextSnapshot != nil {
                        Button {
                            showingBudget = true
                        } label: {
                            Label("Context usage", systemImage: "gauge.with.dots.needle.50percent")
                        }
                    }
                    Button {
                        Task { await handoffToTerminal() }
                    } label: {
                        Label("Open in Terminal on Mac", systemImage: "terminal")
                    }
                    Divider()
                    Button(role: .destructive) {
                        confirmKill = true
                    } label: {
                        Label("Kill session", systemImage: "stop.circle")
                    }
                } label: {
                    // P27.g — flat ellipsis glyph to match the rest of
                    // the toolbar's flat icon-button language.
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
            }
        }
        .sheet(isPresented: $showingBudget) {
            if let store, let snap = store.contextSnapshot {
                ContextBudgetPanel(snapshot: snap, onDismiss: { showingBudget = false })
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingModeSheet) {
            ModeSheet(
                session: currentSession,
                features: features,
                onPick: { applyMode($0) },
                onDismiss: { showingModeSheet = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingDiffSheet) {
            DiffSheet(
                events: store?.events ?? [],
                onSend: { body in await sendMessage(body) },
                onDismiss: { showingDiffSheet = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .sheet(isPresented: $showingModelSheet) {
            if let f = features {
                ModelPickerSheet(
                    currentModel: currentSession.model,
                    currentEffort: currentSession.reasoningEffort,
                    features: f,
                    onPickModel: { m in await applyRestart(.model(m)) },
                    onPickEffort: { e in await applyRestart(.effort(e)) }
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingRepoPicker) {
            RepoPickerSheet(
                currentPath: currentSession.projectPath,
                recentPaths: otherRecentProjects,
                onPick: { path in
                    showingRepoPicker = false
                    if path != currentSession.projectPath {
                        switchToProject(path)
                    }
                },
                onDismiss: { showingRepoPicker = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(20)
        }
        .onAppear {
            // Remember which pairing this session belongs to so we can
            // bail out if it gets removed or switched while we're still
            // pushed on the stack.
            if originPairingId == nil {
                originPairingId = pairing.activeId
            }
            connectStore()
            Task { await loadFeatures() }
        }
        .onDisappear {
            store?.disconnect()
        }
        .onChange(of: store?.state) { _, new in
            guard let new else { return }
            handlePotentialNotification(state: new)
        }
        .onChange(of: pairing.activeId) { _, new in
            // User removed the active Mac (or switched to a different
            // one). The current session lives on the OLD pairing's
            // daemon — keep driving it would 404. Tear down the live
            // store and pop back to HomeView.
            guard let origin = originPairingId else { return }
            if new == nil || new != origin {
                store?.disconnect()
                dismiss()
            }
        }
        .alert("Kill session?", isPresented: $confirmKill) {
            Button("Kill", role: .destructive) {
                Task { await killSession() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This terminates the agent process on your Mac.")
        }
        .alert("Couldn't switch", isPresented: Binding(
            get: { switchError != nil },
            set: { if !$0 { switchError = nil } }
        )) {
            Button("OK", role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
    }

    // MARK: - Lifecycle

    private func connectStore() {
        guard store == nil else { return }
        let s = SessionLiveStore(session: currentSession)
        s.connect(api: APIClient(store: pairing))
        store = s
    }

    private func loadFeatures() async {
        let api = APIClient(store: pairing)
        do {
            let adapters = try await api.adapters()
            features = adapters.first { $0.cli == currentSession.cli }?.features
        } catch {
            // non-fatal; ComposerMenu degrades gracefully
        }
    }

    /// Hand the active session off to the Mac's Terminal.app. The daemon
    /// kills its subprocess and runs `osascript` so the user can keep
    /// typing in Terminal. We disconnect the SSE first so late frames
    /// don't show up after we've moved on, then pop back to HomeView —
    /// the session shows up as `done` on the next refresh, and the user
    /// can resume from there.
    private func handoffToTerminal() async {
        let api = APIClient(store: pairing)
        store?.disconnect()
        do {
            _ = try await api.openTerminal(sessionId: currentSession.id)
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Re-connect so the user isn't stranded on a dead SSE if the
            // handoff failed (e.g. user denied Terminal automation perm).
            store?.connect(api: api)
            return
        }
        dismiss()
    }

    private func handlePotentialNotification(state: SessionStateWire) {
        guard scenePhase != .active else {
            lastNotifiedState = state
            return
        }
        guard state != lastNotifiedState else { return }
        lastNotifiedState = state
        switch state {
        case .waiting:
            LocalNotifier.shared.notifyWaiting(projectName: currentSession.projectName, sessionId: currentSession.id)
        case .done:
            LocalNotifier.shared.notifyDone(projectName: currentSession.projectName, sessionId: currentSession.id)
        case .limitReached:
            LocalNotifier.shared.notifyLimitReached(projectName: currentSession.projectName, sessionId: currentSession.id)
        default:
            break
        }
    }

    /// Soft mode switch — no process restart, no confirmation dialog. The
    /// mode chip flips immediately and the live store renders a divider in
    /// the stream once the in-flight turn (if any) settles.
    private func applyMode(_ mode: String) {
        let normalised = mode.lowercased() == "default" ? nil : mode
        currentSession = currentSession.withMode(normalised)
        store?.queueModeChange(mode)
    }

    private func sendMessage(_ content: String, images: [StagedImage] = []) async {
        let api = APIClient(store: pairing)
        do {
            try await api.sendMessage(
                sessionId: currentSession.id,
                content: content,
                images: images
            )
        } catch {
            // SSE error event surfaces server-side failures
        }
    }

    private func killSession() async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: currentSession.id)
        dismiss()
    }

    /// Switch the user's focus to a different project (P25.e). The current
    /// session keeps running on the daemon — we just stamp the recents
    /// store so HomeView surfaces the picked project, then pop back. The
    /// user re-enters via the session list there.
    private func switchToProject(_ path: String) {
        recents.touch(path)
        dismiss()
    }

    private func abortTurn() async {
        let api = APIClient(store: pairing)
        _ = try? await api.abortSession(sessionId: currentSession.id)
    }

    // MARK: - Silent restart for setting changes

    /// Apply a model / effort / provider switch with the same silent UX as
    /// `applyMode`: no confirmation dialog, no full-screen spinner. The old
    /// process is terminated in the background while we create a fresh
    /// session with the new args; the composer chip updates immediately so
    /// the change feels instantaneous. Events from the old session stay
    /// visible until the new SSE stream takes over.
    private func applyRestart(_ target: SwitchTarget) async {
        let api = APIClient(store: pairing)

        let cli: CLIWire = {
            if case .provider(let c) = target { return c }
            return currentSession.cli
        }()
        let providerChanged = cli != currentSession.cli
        let model: String? = {
            if case .model(let m) = target { return m }
            return providerChanged ? nil : currentSession.model
        }()
        let effort: String? = {
            if case .effort(let e) = target { return e }
            return providerChanged ? nil : currentSession.reasoningEffort
        }()
        let mode: String? = {
            if case .mode(let m) = target { return m }
            return providerChanged ? nil : currentSession.mode
        }()

        // Snapshot the previous store so we can resume it on failure (don't
        // strand the user on a stopped stream if create fails).
        let previousStore = store
        let oldId = currentSession.id

        // Stop the old SSE FIRST so late URLSession callbacks can't slip
        // events into a store we're about to replace. We previously did
        // this in the wrong order; events that arrived during the
        // await-createSession window were attributed to the old store and
        // then discarded, which was OK but caused brief duplicate rows on
        // slower networks.
        previousStore?.disconnect()
        Task.detached { _ = try? await api.killSession(sessionId: oldId) }

        do {
            let req = CreateSessionRequestWire(
                projectPath: currentSession.projectPath,
                cli: cli,
                model: model,
                reasoningEffort: effort,
                mode: mode
            )
            let new = try await api.createSession(req)
            currentSession = new
            let s = SessionLiveStore(session: new)
            s.connect(api: api)
            store = s
            await loadFeatures()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            // Failure: reconnect the previous session's SSE so the user
            // can keep typing without losing the live link.
            previousStore?.connect(api: api)
        }
    }
}
