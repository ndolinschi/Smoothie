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
    @State private var sessions: [SessionDescriptorWire] = []
    @State private var adapters: [AdapterInfoWire] = []
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

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
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
                        }

                        if loading {
                            ProgressView()
                                .tint(SmoothieColor.textSecondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if let loadError {
                            errorBanner(loadError)
                        } else {
                            filterRow
                            sessionGroups
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    topBarButton(systemName: "line.3.horizontal", filled: false) {
                        presentingPairings = true
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("Code")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    topBarButton(systemName: "plus", filled: true) {
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
            Task { await refresh() }
        }
    }

    // MARK: - Top bar

    private func topBarButton(systemName: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(filled ? SmoothieColor.textPrimary : SmoothieColor.textPrimary)
                .frame(width: SmoothieMetrics.topCircle, height: SmoothieMetrics.topCircle)
                .background(
                    filled ? SmoothieColor.accent : Color.clear,
                    in: .circle
                )
                .overlay(
                    Circle().strokeBorder(filled ? Color.clear : SmoothieColor.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
    private var sessionGroups: some View {
        if filteredSessions.isEmpty {
            emptyState
        } else {
            let buckets = bucketed(filteredSessions)
            ForEach(buckets, id: \.key) { bucket in
                Text(bucket.key)
                    .font(.system(size: 13))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .padding(.top, 12)
                ForEach(bucket.value) { s in
                    Button { selectedSession = s } label: { taskRow(s) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await deleteSession(s) }
                            } label: {
                                Label("Remove", systemImage: "minus.circle")
                            }
                        }
                }
            }
        }
    }

    private func bucketed(_ ss: [SessionDescriptorWire]) -> [(key: String, value: [SessionDescriptorWire])] {
        let week = TimeInterval(7 * 86_400)
        var thisWeek: [SessionDescriptorWire] = []
        var earlier: [SessionDescriptorWire] = []
        let now = Date.now
        for s in ss.sorted(by: { $0.createdAt > $1.createdAt }) {
            let date = Date(timeIntervalSince1970: TimeInterval(s.createdAt) / 1000.0)
            if now.timeIntervalSince(date) < week {
                thisWeek.append(s)
            } else {
                earlier.append(s)
            }
        }
        var out: [(String, [SessionDescriptorWire])] = []
        if !thisWeek.isEmpty { out.append(("This week", thisWeek)) }
        if !earlier.isEmpty  { out.append(("Earlier", earlier))  }
        return out
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
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.system(size: 13))
        }
        .foregroundStyle(SmoothieColor.statusErr)
        .padding(12)
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
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func deleteSession(_ s: SessionDescriptorWire) async {
        let api = APIClient(store: pairing)
        _ = try? await api.killSession(sessionId: s.id)
        await refresh()
    }
}

/// Minimal wrapper that presents ConnectView when adding another Mac. The
/// cover auto-dismisses when the pairing list count changes, so a successful
/// pair returns the user straight to HomeView with the new Mac active.
private struct AddPairingCover: View {
    @Environment(PairingStore.self) private var pairing
    @State private var initialCount: Int = 0
    let onDismiss: () -> Void

    var body: some View {
        ConnectView()
            .overlay(alignment: .topTrailing) {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(SmoothieColor.bgGlyph, in: .circle)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 12)
            }
            .onAppear { initialCount = pairing.pairings.count }
            .onChange(of: pairing.pairings.count) { _, new in
                if new > initialCount { onDismiss() }
            }
    }
}
