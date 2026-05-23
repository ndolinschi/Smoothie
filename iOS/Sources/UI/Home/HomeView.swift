import SwiftUI

enum HomeFilter: Hashable {
    case all, completed

    var title: String {
        switch self {
        case .all: return "All"
        case .completed: return "Completed"
        }
    }
}

struct HomeView: View {
    @Environment(PairingStore.self) private var pairing
    @Environment(RecentsStore.self) private var recents
    /// Set by SmoothieApp when a `smoothie://session/<id>` deep link fires
    /// from a notification tap. HomeView resolves the id against the live
    /// `/sessions` list and pushes SessionView via its own NavigationStack.
    @Binding var deepLinkedSessionId: String?
    /// Toast surfaced when a deep link can't resolve (session gone, daemon
    /// unreachable). Cleared after the user dismisses the alert. Without
    /// this, a tap on a notification for a killed session was a silent
    /// no-op and the user had no idea why nothing happened.
    @State private var deepLinkErrorMessage: String?

    init(deepLinkedSessionId: Binding<String?> = .constant(nil)) {
        self._deepLinkedSessionId = deepLinkedSessionId
    }

    @State private var sessions: [SessionDescriptorWire] = []
    @State private var adapters: [AdapterInfoWire] = []
    @State private var me: MeWire?
    @State private var loading = true
    @State private var loadError: String?
    @State private var presentingPicker = false
    @State private var presentingNew = false
    @State private var pendingPath: String?
    @State private var selectedSession: SessionDescriptorWire?
    @State private var filter: HomeFilter = .all
    @State private var presentingPairings = false
    @State private var presentingAddPair = false
    @AppStorage("smoothie.homeTipDismissed") private var tipDismissed: Bool = false

    private var allCount: Int { sessions.count }
    private var completedCount: Int {
        sessions.filter { $0.state.isCompleted }.count
    }
    private var filteredSessions: [SessionDescriptorWire] {
        switch filter {
        case .all: return sessions
        case .completed: return sessions.filter { $0.state.isCompleted }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()

                List {
                    if !tipDismissed {
                        DashedBanner(
                            title: "Take your sessions on the go",
                            message: "Tap + to start a new Claude session in any project on \(activeMacLabel).",
                            linkText: nil,
                            onLink: nil,
                            onDismiss: { withAnimation(.easeOut(duration: 0.2)) { tipDismissed = true } }
                        ) {
                            Image(systemName: "macbook")
                                .font(.system(size: 28))
                                .foregroundStyle(SmoothieColor.textTertiary)
                                .padding(.trailing, 4)
                        }
                        .padding(.top, 4)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                    }

                    if loading {
                        ProgressView()
                            .tint(SmoothieColor.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 40)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    } else if let loadError {
                        errorBanner(loadError)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                    } else {
                        // Claude Code-inspired dashboard header: greeting,
                        // 4 stat tiles, activity heatmap. Hidden during
                        // the initial fetch so the skeleton state is
                        // just a spinner.
                        DashboardHeader(me: me, sessions: sessions, adapters: adapters)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                        filterRow
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                        sessionListContent
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listSectionSpacing(.compact)
                .environment(\.defaultMinListRowHeight, 0)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    topBarButton(systemName: "line.3.horizontal") {
                        presentingPairings = true
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Code")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    topBarButton(systemName: "plus") {
                        presentingPicker = true
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { s in
                SessionView(session: s)
            }
            .sheet(isPresented: $presentingPicker) {
                let liveProjects = sessions.filter { !$0.state.isCompleted }.map(\.projectPath)
                FolderPickerSheet(activeProjects: liveProjects) { path in
                    pendingPath = path
                    presentingPicker = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(200))
                        presentingNew = true
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $presentingNew) {
                NewSessionView(preselectedPath: pendingPath) { new in
                    presentingNew = false
                    pendingPath = nil
                    Task { await refresh() }
                    selectedSession = new
                }
                .presentationDetents([.large])
                .presentationBackground(.clear)
            }
            .sheet(isPresented: $presentingPairings) {
                PairingsSheet(
                    onAddPairing: {
                        presentingPairings = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            presentingAddPair = true
                        }
                    },
                    onDismiss: { presentingPairings = false }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .fullScreenCover(isPresented: $presentingAddPair) {
                AddPairingCover(onDismiss: { presentingAddPair = false })
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onChange(of: pairing.activeId) { _, _ in
            // Clear any pushed session — switching Mac means the SSE stream
            // would 404 if we kept the previous session on screen. Also
            // refresh the list under the new Mac's adapters / sessions.
            selectedSession = nil
            Task { await refresh() }
        }
        .onChange(of: deepLinkedSessionId) { _, new in
            guard let id = new, !id.isEmpty else { return }
            // Consume the binding so we don't re-trigger on view re-render.
            deepLinkedSessionId = nil
            Task { await resolveAndPush(sessionId: id) }
        }
        .alert(
            "Couldn't open session",
            isPresented: Binding(
                get: { deepLinkErrorMessage != nil },
                set: { if !$0 { deepLinkErrorMessage = nil } }
            ),
            presenting: deepLinkErrorMessage
        ) { _ in
            Button("OK", role: .cancel) { deepLinkErrorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    /// Resolve a notification-tapped session id against the live list and
    /// push SessionView via the local NavigationStack. Silently no-ops if
    /// the session was already killed.
    private func resolveAndPush(sessionId id: String) async {
        if let cached = sessions.first(where: { $0.id == id }) {
            selectedSession = cached
            return
        }
        let api = APIClient(store: pairing)
        do {
            let list = try await api.sessions()
            if let descriptor = list.first(where: { $0.id == id }) {
                selectedSession = descriptor
            } else {
                // Surface the no-op to the user — silent failure was the
                // worst part of the prior behaviour: tap a notification,
                // nothing happens, no way to tell whether the app froze
                // or the session was already killed on the Mac.
                deepLinkErrorMessage = "Session not found. It may have already been killed on your Mac."
            }
        } catch {
            deepLinkErrorMessage = "Couldn't reach your Mac. \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
        }
    }

    // MARK: - Top bar

    /// Compatibility shim — delegates to the shared
    /// `SmoothieIconButton`. Kept so existing call sites in this file
    /// don't need to be migrated in one pass; future surfaces should
    /// reach for `SmoothieIconButton` directly.
    private func topBarButton(systemName: String, action: @escaping () -> Void) -> some View {
        SmoothieIconButton(systemName: systemName, size: 36, action: action)
    }

    // MARK: - Filter row

    private var filterRow: some View {
        HStack(spacing: 8) {
            filterChip(.all, count: allCount)
            filterChip(.completed, count: completedCount)
            Spacer()
        }
        .padding(.top, 2)
    }

    private func filterChip(_ f: HomeFilter, count: Int) -> some View {
        let active = filter == f
        return Button {
            filter = f
        } label: {
            HStack(spacing: 6) {
                Text(f.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? SmoothieColor.textPrimary : SmoothieColor.textSecondary)
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? SmoothieColor.textPrimary.opacity(0.55) : SmoothieColor.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(active ? SmoothieColor.bgPrimary : Color.clear, in: .capsule)
            .overlay(
                Capsule().strokeBorder(active ? SmoothieColor.stroke : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session groups

    @ViewBuilder
    private var sessionListContent: some View {
        if filteredSessions.isEmpty {
            emptyState
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        } else {
            let buckets = bucketed(filteredSessions)
            ForEach(buckets, id: \.key) { bucket in
                Section {
                    ForEach(bucket.value) { s in
                        Button { selectedSession = s } label: { taskRow(s) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 0, trailing: 16))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteSession(s) }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SmoothieColor.textTertiary)
                        Text(bucket.key)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SmoothieColor.textSecondary)
                        Text("\(bucket.value.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(SmoothieColor.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(SmoothieColor.bgChip, in: .capsule)
                        Spacer(minLength: 0)
                    }
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
    }

    /// Group sessions by their project (last path component) — mirrors
    /// the left-rail layout in Claude Code desktop. Within each project
    /// group, sessions are sorted by most-recent first. Projects
    /// themselves are ordered by their most-recent session's timestamp
    /// so the project you just touched bubbles to the top.
    private func bucketed(_ ss: [SessionDescriptorWire]) -> [(key: String, value: [SessionDescriptorWire])] {
        let sorted = ss.sorted(by: { $0.createdAt > $1.createdAt })
        var grouped: [String: [SessionDescriptorWire]] = [:]
        var firstSeen: [String: Int64] = [:]
        for s in sorted {
            grouped[s.projectName, default: []].append(s)
            // First time we see a project in the sorted-desc list = most
            // recent activity. Locked in via `default` semantics.
            if firstSeen[s.projectName] == nil {
                firstSeen[s.projectName] = s.createdAt
            }
        }
        let orderedKeys = grouped.keys.sorted {
            (firstSeen[$0] ?? 0) > (firstSeen[$1] ?? 0)
        }
        return orderedKeys.map { (key: $0, value: grouped[$0] ?? []) }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text(filter == .completed ? "No completed sessions yet." : "Tap + to start.")
                .font(.system(size: 14))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    /// REF-4 task row: dashed-circle icon + title + cloud-style project label + relative time.
    private func taskRow(_ s: SessionDescriptorWire) -> some View {
        let date = Date(timeIntervalSince1970: TimeInterval(s.createdAt) / 1000.0)
        return HStack(spacing: 12) {
            DashedCircleIcon(dotColor: dotColor(for: s.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.projectName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(SmoothieColor.textSecondary)
                    Text(shortProject(s.projectPath))
                        .font(.system(size: 12))
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
            Text(compactTime(date))
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textTertiary)
        }
        .padding(.horizontal, SmoothieMetrics.rowPaddingH)
        .padding(.vertical, SmoothieMetrics.rowPaddingV)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
    }

    private func dotColor(for state: SessionStateWire) -> Color? {
        switch state {
        case .thinking:                   return SmoothieColor.statusThinking
        case .waiting:                    return SmoothieColor.statusWaiting
        case .done:                       return SmoothieColor.statusDone
        case .error, .limitReached:       return SmoothieColor.statusErr
        case .starting:                   return SmoothieColor.textSecondary
        case .unknown:                    return SmoothieColor.textTertiary
        }
    }

    private func shortProject(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            let trimmed = String(path.dropFirst(home.count))
            return "~" + trimmed
        }
        return path
    }

    private func compactTime(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d" }
        return "\(Int(interval / 604_800))w"
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SmoothieColor.statusErr)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(SmoothieColor.statusErr)
                .lineLimit(2)
            Spacer(minLength: 6)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { loadError = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
    }

    // MARK: - Data

    private var activeMacLabel: String {
        pairing.current?.label ?? "your Mac"
    }

    private func refresh() async {
        let api = APIClient(store: pairing)
        loading = true
        loadError = nil
        do {
            async let s = api.sessions()
            async let a = api.adapters()
            sessions = try await s
            adapters = try await a
        } catch {
            if isCancellation(error) {
                loading = false
                return
            }
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        // `/me` is a nicety for the dashboard greeting — failures don't
        // block the page; we just keep the previous (or nil) value so
        // the header falls back to a generic "What's up next?".
        if let fetched = try? await api.me() {
            me = fetched
        }
        loading = false
    }

    private func deleteSession(_ s: SessionDescriptorWire) async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: s.id)
        await refresh()
    }
}

// AddPairingCover lives in its own file (P24.d D2). See
// iOS/Sources/UI/Pairings/AddPairingCover.swift.
