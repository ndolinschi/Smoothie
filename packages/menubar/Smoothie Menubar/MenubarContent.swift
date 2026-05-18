import SwiftUI

struct MenubarContent: View {
    @Environment(ServerMonitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader

            Divider()

            if monitor.isHealthy {
                sessionsSection
                Divider()
                adaptersSection
                Divider()
            } else {
                offlineHint
                Divider()
            }

            actionRow("Open /health in browser", systemImage: "globe") {
                monitor.openServerInBrowser()
            }
            actionRow("Open server logs", systemImage: "doc.text") {
                monitor.openLogs()
            }
            actionRow("Refresh now", systemImage: "arrow.clockwise") {
                Task { await monitor.refresh() }
            }

            Divider()

            actionRow("Quit Smoothie Menubar", systemImage: "power", tint: .red) {
                monitor.quit()
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Sections

    private var statusHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Circle()
                .fill(monitor.isHealthy ? Color.green : Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
                .shadow(color: monitor.isHealthy ? Color.green.opacity(0.6) : .clear, radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smoothie")
                    .font(.system(size: 13, weight: .semibold))
                Text(monitor.isHealthy ? "\(monitor.serverDisplay)  ·  \(monitor.versionDisplay)  ·  up \(monitor.uptimeDisplay)" : "Server offline")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Active sessions")
            if monitor.sessions.isEmpty {
                Text("(none)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            } else {
                ForEach(monitor.sessions) { s in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(stateColor(s.state))
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.projectName)
                                .font(.system(size: 12, weight: .medium))
                            Text("\(s.cli)  ·  \(s.state)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .padding(.bottom, 4)
            }
        }
    }

    private var adaptersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionTitle("Adapters")
            if let adapters = monitor.health?.adapters {
                ForEach(adapters) { a in
                    HStack(spacing: 8) {
                        Image(systemName: adapterIcon(a))
                            .font(.system(size: 10))
                            .foregroundStyle(adapterColor(a))
                            .frame(width: 12)
                        Text(adapterLabel(a))
                            .font(.system(size: 11))
                        Spacer()
                        Text(adapterStatus(a))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                }
                .padding(.bottom, 6)
            }
        }
    }

    private var offlineHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                Text("Daemon not reachable")
                    .font(.system(size: 11, weight: .semibold))
            }
            if let err = monitor.lastError {
                Text(err)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text("Start it with `swift run` in packages/server, or install the LaunchAgent.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func actionRow(_ label: String, systemImage: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 12))
                Spacer()
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            // Subtle hover effect handled by macOS automatically with .plain buttons in a menu
            _ = hovering
        }
    }

    private func stateColor(_ state: String) -> Color {
        switch state {
        case "thinking": return .blue
        case "waiting":  return .orange
        case "error":    return .red
        case "done":     return .gray
        default:         return .gray
        }
    }

    private func adapterIcon(_ a: HealthAdapter) -> String {
        if !a.installed { return "xmark.circle" }
        if !a.supported { return "minus.circle" }
        return "checkmark.circle.fill"
    }

    private func adapterColor(_ a: HealthAdapter) -> Color {
        if !a.installed { return .red }
        if !a.supported { return .secondary }
        return .green
    }

    private func adapterLabel(_ a: HealthAdapter) -> String {
        switch a.cli {
        case "opencode": return "OpenCode"
        case "claude":   return "Claude Code"
        case "gemini":   return "Gemini"
        case "codex":    return "Codex"
        default:         return a.cli
        }
    }

    private func adapterStatus(_ a: HealthAdapter) -> String {
        if !a.installed { return "missing" }
        if !a.supported { return "coming" }
        return a.version.map { "v\($0)" } ?? "ready"
    }
}
