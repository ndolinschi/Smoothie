import SwiftUI

/// Claude Code-inspired dashboard header — greeting + four stat tiles +
/// activity heatmap. Sits above the project-grouped session list on
/// HomeView. Everything computes locally from the live `/sessions`
/// response we already fetch, plus a one-shot `/me` for the greeting.
struct DashboardHeader: View {
    let me: MeWire?
    let sessions: [SessionDescriptorWire]
    let adapters: [AdapterInfoWire]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            greeting
            statsCard
        }
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SmoothieColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textPrimary)
                if let host = me?.hostname {
                    Text("Driving \(host)")
                        .font(.system(size: 12))
                        .foregroundStyle(SmoothieColor.textTertiary)
                }
            }
            Spacer()
        }
    }

    private var greetingText: String {
        if let name = me?.greetingName, !name.isEmpty {
            return "What's up next, \(name)?"
        }
        return "What's up next?"
    }

    // MARK: - Stats card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                tile(label: "Sessions",     value: "\(stats.totalSessions)")
                tile(label: "Active days",  value: "\(stats.activeDays)")
                tile(label: "Current streak", value: stats.streakLabel)
                tile(label: "Top provider", value: stats.topCliLabel)
            }

            // GitHub-style heatmap — sessions started per day over the
            // last 12 weeks. Empty days stay neutral; busier days deepen
            // toward the coral accent.
            ActivityHeatmap(buckets: stats.weeklyBuckets, weeks: 12)
                .padding(.top, 4)

            // Gentle scale comparison — same vibe as Claude Code
            // desktop's "You've used 1341× more tokens than The Great
            // Gatsby" footer. Token count isn't tracked here yet so we
            // use sessions × 100 messages as a rough proxy; we'll
            // upgrade to a real token tally once the K/N side counts.
            if stats.totalSessions > 0 {
                Text(comparisonLine)
                    .font(.system(size: 11))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
        }
        .padding(14)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private func tile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SmoothieColor.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SmoothieColor.bgChip, in: .rect(cornerRadius: 10))
    }

    // MARK: - Stats computation

    private var stats: SessionStats { SessionStats.compute(sessions) }

    /// Stable, slightly cheeky comparison line. Cycles based on the
    /// session count so the wording doesn't change on every refresh.
    private var comparisonLine: String {
        let lines = [
            "That's a lot of agent turns.",
            "Driving more silicon than a small render farm.",
            "Each session is one prompt closer to shipped.",
            "Your CLIs have been busy.",
        ]
        return lines[stats.totalSessions % lines.count]
    }
}

/// Pure computation over the live session list. Centralised so future
/// stats (token totals, hours of week heatmap, model breakdown) have a
/// home that doesn't require touching the view.
struct SessionStats {
    let totalSessions: Int
    let activeDays: Int
    let currentStreak: Int
    let topCli: CLIWire?
    /// Sessions-per-day buckets keyed by `Date` truncated to midnight,
    /// covering the most recent 84 days (12 weeks).
    let weeklyBuckets: [Date: Int]

    var streakLabel: String {
        currentStreak == 0 ? "—" : "\(currentStreak)d"
    }

    var topCliLabel: String {
        topCli?.displayName ?? "—"
    }

    static func compute(_ sessions: [SessionDescriptorWire]) -> SessionStats {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let allDates: [Date] = sessions.map {
            let raw = Date(timeIntervalSince1970: Double($0.createdAt) / 1000.0)
            return cal.startOfDay(for: raw)
        }
        let uniqueDays = Set(allDates)

        // Streak: walk back from today; a streak day is any day with at
        // least one session. Stop at the first day with zero sessions.
        var streak = 0
        var cursor = today
        while uniqueDays.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        // Top CLI = most common across all sessions; ties broken by
        // CLIWire.CaseIterable ordering (deterministic).
        var cliCounts: [CLIWire: Int] = [:]
        for s in sessions { cliCounts[s.cli, default: 0] += 1 }
        let top = cliCounts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key.rawValue > rhs.key.rawValue
        }?.key

        // Date histogram for the heatmap — 84 days (12 weeks), most
        // recent on the right.
        var buckets: [Date: Int] = [:]
        for date in allDates {
            buckets[date, default: 0] += 1
        }

        return SessionStats(
            totalSessions: sessions.count,
            activeDays: uniqueDays.count,
            currentStreak: streak,
            topCli: top,
            weeklyBuckets: buckets
        )
    }
}
