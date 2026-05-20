import Foundation

/// Pure computation over the live session list. Centralised so future
/// stats (token totals, hours-of-week heatmap, model breakdown) have a
/// home that doesn't require touching the view.
///
/// Extracted from DashboardHeader.swift in P24.d D6 — the view file
/// should only contain SwiftUI; computation belongs at its own seam.
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
