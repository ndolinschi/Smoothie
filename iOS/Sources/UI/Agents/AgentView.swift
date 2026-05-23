import SwiftUI

/// "Agent View" — a compact dashboard of every live session on the
/// daemon. Inspired by Claude Code's terminal agent dashboard: instead
/// of juggling separate session tabs, the user sees every background
/// agent at a glance with its current state and steps in when one is
/// WAITING (needs input) or has just finished. Sessions are sorted so
/// the attention-required ones float to the top.
///
/// Entry point: HomeView's leading toolbar (grid glyph next to the
/// settings / `+` buttons). Tapping a row pushes the standard
/// `SessionView` so the user lands in the existing chat UI — no
/// separate detail layout to maintain.
struct AgentView: View {
    @Environment(PairingStore.self) private var pairing
    @Environment(SessionMetaStore.self) private var sessionMeta
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [SessionDescriptorWire] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var selectedSession: SessionDescriptorWire?
    /// Polling cadence — short enough that state changes (THINKING →
    /// WAITING / DONE) feel live, long enough that the daemon isn't
    /// hammered when the user is parked on this screen.
    private let pollInterval: TimeInterval = 3.0

    var body: some View {
        ZStack {
            SmoothieColor.bgPrimary.ignoresSafeArea()
            content
        }
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(item: $selectedSession) { s in
            SessionView(session: s)
        }
        .task {
            // Continuous polling while this view is mounted. Cancels
            // automatically when the user navigates away.
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(pollInterval))
            }
        }
        .refreshable {
            await refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading && sessions.isEmpty {
            ProgressView()
                .tint(SmoothieColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, sessions.isEmpty {
            errorState(loadError)
        } else if sessions.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    summaryBar
                        .padding(.bottom, 4)
                    ForEach(sortedSessions, id: \.id) { row($0) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Rows

    private func row(_ s: SessionDescriptorWire) -> some View {
        let bucket = AgentBucket.from(state: s.state)
        let title = sessionMeta.displayName(for: s.id, fallback: s.projectName)
        return Button {
            selectedSession = s
        } label: {
            HStack(alignment: .center, spacing: 12) {
                statusGlyph(bucket: bucket, state: s.state)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SmoothieColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        Text(relativeTime(s.createdAt))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SmoothieColor.textTertiary)
                    }
                    HStack(spacing: 6) {
                        Text(s.cli.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(SmoothieColor.textSecondary)
                        Text("·")
                            .foregroundStyle(SmoothieColor.textTertiary)
                        Text(bucket.label)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(bucket.color)
                        if let model = s.model, !model.isEmpty {
                            Text("·")
                                .foregroundStyle(SmoothieColor.textTertiary)
                            Text(s.cli.friendlyModelName(model))
                                .font(.system(size: 11))
                                .foregroundStyle(SmoothieColor.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerMd))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerMd)
                    .strokeBorder(
                        bucket == .waiting
                            ? bucket.color.opacity(0.55)
                            : SmoothieColor.strokeSoft,
                        lineWidth: bucket == .waiting ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Coloured dot at the front of the row. Pulses when the agent is
    /// THINKING so the row reads as live activity. Other states use a
    /// static glyph that matches the bucket meaning.
    @ViewBuilder
    private func statusGlyph(bucket: AgentBucket, state: SessionStateWire) -> some View {
        switch bucket {
        case .waiting:
            PulsingDot(color: bucket.color)
                .frame(width: 12, height: 12)
        case .thinking:
            PulsingDot(color: bucket.color)
                .frame(width: 12, height: 12)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(bucket.color)
                .frame(width: 16, height: 16)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(bucket.color)
                .frame(width: 16, height: 16)
        case .idle:
            Circle()
                .fill(bucket.color)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Summary header

    private var summaryBar: some View {
        let buckets = bucketCounts
        return HStack(spacing: 8) {
            summaryChip(label: "Waiting", count: buckets[.waiting] ?? 0, color: AgentBucket.waiting.color, emphasised: true)
            summaryChip(label: "Thinking", count: buckets[.thinking] ?? 0, color: AgentBucket.thinking.color, emphasised: false)
            summaryChip(label: "Done", count: buckets[.done] ?? 0, color: AgentBucket.done.color, emphasised: false)
            Spacer(minLength: 0)
        }
    }

    private func summaryChip(label: String, count: Int, color: Color, emphasised: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(emphasised && count > 0 ? color : SmoothieColor.textSecondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            emphasised && count > 0 ? color.opacity(0.12) : SmoothieColor.bgChip,
            in: .capsule
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    emphasised && count > 0 ? color.opacity(0.4) : SmoothieColor.strokeSoft,
                    lineWidth: 0.5
                )
        )
    }

    private var bucketCounts: [AgentBucket: Int] {
        var counts: [AgentBucket: Int] = [:]
        for s in sessions {
            let bucket = AgentBucket.from(state: s.state)
            counts[bucket, default: 0] += 1
        }
        return counts
    }

    // MARK: - Empty / error states

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("No agents running")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text("Start a session from the Home screen and it'll show up here with live state.")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.statusErr)
            Text("Couldn't load agents")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Retry") {
                Task { await refresh() }
            }
            .buttonStyle(.bordered)
            .tint(SmoothieColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sorting + data

    /// Surface attention-required sessions first. Within the same
    /// bucket, most-recent createdAt wins so the user's latest activity
    /// stays at the top of its group.
    private var sortedSessions: [SessionDescriptorWire] {
        sessions.sorted { lhs, rhs in
            let lb = AgentBucket.from(state: lhs.state)
            let rb = AgentBucket.from(state: rhs.state)
            if lb.priority != rb.priority { return lb.priority < rb.priority }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func relativeTime(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3600))h" }
        if interval < 604_800 { return "\(Int(interval / 86_400))d" }
        return "\(Int(interval / 604_800))w"
    }

    private func refresh() async {
        let api = APIClient(store: pairing)
        do {
            // Mirror HomeView's filter — agy is hidden across iOS until
            // its host story firms up.
            sessions = (try await api.sessions()).filter { $0.cli != .antigravity }
            loadError = nil
        } catch {
            if !isCancellation(error) {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        loading = false
    }
}

// MARK: - Bucket model

/// Coarse status bucket used for sorting + summary chips. The wire
/// state enum has more cases than the dashboard needs to express; the
/// bucket collapses related states into a single visual lane.
enum AgentBucket: Hashable {
    case waiting    // needs user input
    case thinking   // agent currently working
    case done       // turn finished
    case error      // errored or limit-reached
    case idle       // starting / unknown — show as a grey dot

    static func from(state: SessionStateWire) -> AgentBucket {
        switch state {
        case .waiting:                    return .waiting
        case .thinking:                   return .thinking
        case .done:                       return .done
        case .error, .limitReached:       return .error
        case .starting, .unknown:         return .idle
        }
    }

    /// Lower is higher in the visible list. Waiting tops the screen
    /// because it's the only state that requires user action; errored
    /// runs come second so the user can recover them; ongoing work
    /// next; finished + idle drop to the bottom.
    var priority: Int {
        switch self {
        case .waiting:  return 0
        case .error:    return 1
        case .thinking: return 2
        case .done:     return 3
        case .idle:     return 4
        }
    }

    var label: String {
        switch self {
        case .waiting:  return "needs input"
        case .thinking: return "thinking"
        case .done:     return "done"
        case .error:    return "error"
        case .idle:     return "idle"
        }
    }

    var color: Color {
        switch self {
        case .waiting:  return SmoothieColor.statusWaiting
        case .thinking: return SmoothieColor.statusThinking
        case .done:     return SmoothieColor.statusDone
        case .error:    return SmoothieColor.statusErr
        case .idle:     return SmoothieColor.textTertiary
        }
    }
}

/// Small breathing dot used for "live" status indicators. Animates
/// opacity from 0.45 → 1.0 on a 1.2s autoreversing loop. Respects the
/// reduce-motion accessibility setting (falls back to a static dot).
private struct PulsingDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .opacity(reduceMotion || !pulsing ? 1.0 : 0.45)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
