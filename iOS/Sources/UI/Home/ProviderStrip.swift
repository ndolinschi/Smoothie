import SwiftUI

/// P29 §1 — Horizontal carousel of CLI brand chips on the Home
/// dashboard. Each chip shows a glowing brand-tinted dot, the CLI's
/// SF Symbol mark, and the display name; tapping an installed chip
/// filters the session list below to that CLI. Uninstalled chips
/// render dimmed and ignore taps — the user has to install the CLI
/// on the paired Mac (the install hint surfaces via the alert on
/// long-press, since iOS chips don't have hover state).
///
/// Antigravity and `.unknown` are filtered out — Antigravity is
/// globally hidden from the picker, and `.unknown` is the
/// forward-compat sentinel for daemon CLIs this iOS build doesn't
/// know about.
struct ProviderStrip: View {
    let adapters: [AdapterInfoWire]
    /// nil = "no CLI filter active" (show all sessions). Otherwise the
    /// CLI whose sessions are visible below the strip.
    @Binding var selected: CLIWire?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false
    @State private var infoForChip: CLIWire?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(visibleAdapters) { adapter in
                    chip(adapter)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
        .onAppear {
            // Single pulse cycle drives the dot glow when the dashboard
            // first appears — purely cosmetic; no motion when reduce-motion is on.
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .alert(
            "Not installed",
            isPresented: Binding(
                get: { infoForChip != nil },
                set: { if !$0 { infoForChip = nil } }
            ),
            presenting: infoForChip
        ) { _ in
            Button("OK", role: .cancel) { infoForChip = nil }
        } message: { cli in
            Text(installHint(for: cli))
        }
    }

    private var visibleAdapters: [AdapterInfoWire] {
        adapters.filter { $0.cli != .antigravity && $0.cli != .unknown }
    }

    // MARK: - Chip

    private func chip(_ adapter: AdapterInfoWire) -> some View {
        let cli = adapter.cli
        let brand = SmoothieColor.brand(for: cli)
        let installed = adapter.installed
        let isSelected = (selected == cli)

        return Button {
            if installed {
                // Tap-again toggles the filter off so the user can
                // always escape back to "show everything".
                selected = isSelected ? nil : cli
            } else {
                infoForChip = cli
            }
        } label: {
            HStack(spacing: 8) {
                glowingDot(brand: brand, installed: installed)
                ProviderIcon(cli: cli, size: 14)
                    .opacity(installed ? 1 : 0.4)
                Text(cli.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(installed ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? brand.opacity(0.12) : SmoothieColor.bgCard,
                in: .capsule
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? brand.opacity(0.55) : SmoothieColor.strokeSoft,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .opacity(installed ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func glowingDot(brand: Color, installed: Bool) -> some View {
        Circle()
            .fill(installed ? brand : brand.opacity(0.35))
            .frame(width: 6, height: 6)
            .shadow(
                color: installed ? brand.opacity(pulse ? 0.85 : 0.45) : .clear,
                radius: installed ? (pulse ? 5 : 3) : 0
            )
    }

    private func installHint(for cli: CLIWire) -> String {
        switch cli {
        case .claudeCode:
            return "Install Claude Code on your Mac: `npm install -g @anthropic-ai/claude-code` (or use the official installer)."
        case .gemini:
            return "Install Gemini CLI on your Mac: `npm install -g @google/gemini-cli`."
        case .openCode:
            return "Install OpenCode on your Mac: `brew install sst/tap/opencode`."
        case .codex:
            return "Install Codex CLI on your Mac: `npm install -g @openai/codex`."
        case .cursor:
            return "Install Cursor's CLI on your Mac: `curl https://cursor.com/install -fsS | bash`."
        case .antigravity, .unknown:
            return "This CLI isn't available yet."
        }
    }
}
