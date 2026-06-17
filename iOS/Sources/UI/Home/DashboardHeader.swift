import SwiftUI

/// Claude Code-inspired dashboard header — greeting + four stat tiles +
/// activity heatmap. Sits above the project-grouped session list on
/// HomeView. Everything computes locally from the live `/sessions`
/// response we already fetch, plus a one-shot `/me` for the greeting.
struct DashboardHeader: View {
    let me: MeWire?
    let sessions: [SessionDescriptorWire]
    let adapters: [AdapterInfoWire]
    /// P29 §1 — current CLI brand filter from HomeView. Bound so the
    /// provider strip's chip toggles flow back up to the session list.
    @Binding var selectedCLI: CLIWire?

    init(
        me: MeWire?,
        sessions: [SessionDescriptorWire],
        adapters: [AdapterInfoWire],
        selectedCLI: Binding<CLIWire?> = .constant(nil)
    ) {
        self.me = me
        self.sessions = sessions
        self.adapters = adapters
        self._selectedCLI = selectedCLI
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            greeting
                .smoothieAppearFade(delay: 0.00)
            statsCard
                .smoothieAppearFade(delay: 0.05)
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

    /// Inner stat tiles + heatmap. No outer surface — sits directly on
    /// `bgPrimary` so the header flows into the filter row + session
    /// cards below without a visible card boundary.
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
            // monochromatically (P25 mono palette).
            ActivityHeatmap(buckets: stats.weeklyBuckets, weeks: 12)
                .padding(.top, 4)

            // P29 §1 — provider chip strip. Brand-tinted dots, taps
            // filter the session list below. Hidden until adapters
            // arrive so we don't flash a row of empty chips on first
            // paint.
            if !adapters.isEmpty {
                ProviderStrip(adapters: adapters, selected: $selectedCLI)
                    .padding(.top, 2)
                    .smoothieAppearFade(delay: 0.10)
            }

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
        .background(SmoothieColor.bgChip, in: .rect(cornerRadius: SmoothieMetrics.cornerSm))
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

// SessionStats lives in its own file (P24.d D6). See SessionStats.swift.
