import SwiftUI

/// Lets the user pick a previous session to reference as context in
/// the next outgoing message. Opens from MentionPickerSheet's "Past
/// Chats" row. The picker lists sessions other than the currently
/// active one, with the same project grouped at the top so the most
/// likely reference is one tap away.
///
/// Backend: `GET /sessions` (already cached) + `GET
/// /sessions/:id/transcript`. The picked transcript becomes a
/// `StagedChat` attachment on the composer.
struct PastChatsPickerSheet: View {
    /// The current session — excluded from the list and used to bubble
    /// other sessions in the same project to the top.
    let currentSession: SessionDescriptorWire
    let pairing: PairingStore
    let sessionMeta: SessionMetaStore
    let onPicked: (StagedChat) -> Void
    let onDismiss: () -> Void

    @State private var sessions: [SessionDescriptorWire] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var query: String = ""
    /// While non-nil, the picked session row shows a spinner and every
    /// other row disables — the transcript fetch can take a beat for a
    /// long session and we don't want a double-tap to fire twice.
    @State private var fetching: String?
    @State private var fetchError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                content
            }
            .navigationTitle("Past Chats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { onDismiss() }
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView()
                .tint(SmoothieColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            errorState(loadError)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if let fetchError {
                        Text(fetchError)
                            .font(.system(size: 12))
                            .foregroundStyle(SmoothieColor.statusErr)
                            .padding(.horizontal, 6)
                    }
                    let grouped = groupedSessions
                    if grouped.isEmpty {
                        emptyState
                    } else {
                        ForEach(grouped, id: \.title) { bucket in
                            section(title: bucket.title) {
                                VStack(spacing: 6) {
                                    ForEach(bucket.entries, id: \.id) { row($0) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SmoothieColor.textTertiary)
            TextField("Search chats", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text(query.isEmpty ? "No other chats yet" : "No matching chats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            if query.isEmpty {
                Text("Start more sessions and they'll show up here as context you can pull into a new turn.")
                    .font(.system(size: 12))
                    .foregroundStyle(SmoothieColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
    }

    private func section<C: View>(title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.leading, 6)
            content()
        }
    }

    private func row(_ session: SessionDescriptorWire) -> some View {
        let isFetching = fetching == session.id
        let title = sessionMeta.displayName(for: session.id, fallback: session.projectName)
        return Button {
            Task { await pick(session) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isFetching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SmoothieColor.textPrimary)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)
                } else {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .frame(width: 18, height: 18)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(session.cli.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SmoothieColor.textTertiary)
                        Text("·")
                            .foregroundStyle(SmoothieColor.textTertiary)
                        Text(relativeTime(session.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(SmoothieColor.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .smoothieCard(cornerRadius: SmoothieMetrics.cornerRow)
        }
        .buttonStyle(.plain)
        .disabled(fetching != nil)
        .opacity(fetching != nil && !isFetching ? 0.45 : 1)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.statusErr)
            Text("Couldn't load chats")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await load() }
            }
            .buttonStyle(.bordered)
            .tint(SmoothieColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Grouping

    /// Bucket the visible sessions into two groups: "Same project"
    /// (matches the active session's project path) and "Other
    /// projects". Each group is sorted most-recent-first.
    private struct Bucket { let title: String; let entries: [SessionDescriptorWire] }

    private var groupedSessions: [Bucket] {
        let filtered = sessions
            .filter { $0.id != currentSession.id }
            .filter { matchesQuery($0) }
            .sorted { $0.createdAt > $1.createdAt }
        let same = filtered.filter { $0.projectPath == currentSession.projectPath }
        let other = filtered.filter { $0.projectPath != currentSession.projectPath }
        var out: [Bucket] = []
        if !same.isEmpty {
            out.append(Bucket(title: "SAME PROJECT", entries: same))
        }
        if !other.isEmpty {
            out.append(Bucket(title: "OTHER PROJECTS", entries: other))
        }
        return out
    }

    private func matchesQuery(_ s: SessionDescriptorWire) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return true }
        let title = sessionMeta.displayName(for: s.id, fallback: s.projectName).lowercased()
        let project = s.projectName.lowercased()
        return title.contains(q) || project.contains(q) || s.cli.displayName.lowercased().contains(q)
    }

    private func relativeTime(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86_400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d ago" }
        return "\(Int(interval / 604_800))w ago"
    }

    // MARK: - Actions

    private func load() async {
        loading = true
        loadError = nil
        let api = APIClient(store: pairing)
        do {
            sessions = try await api.sessions()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func pick(_ session: SessionDescriptorWire) async {
        guard fetching == nil else { return }
        fetching = session.id
        fetchError = nil
        let api = APIClient(store: pairing)
        do {
            let body = try await api.transcript(sessionId: session.id)
            let title = sessionMeta.displayName(for: session.id, fallback: session.projectName)
            let staged = StagedChat(sessionId: session.id, title: title, transcript: body)
            fetching = nil
            onPicked(staged)
            onDismiss()
        } catch {
            fetchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            fetching = nil
        }
    }
}
