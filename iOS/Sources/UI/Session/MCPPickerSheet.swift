import SwiftUI

/// Lists MCP servers discovered for the active session's CLI and lets
/// the user toggle the per-session enabled subset. Replaces the
/// previous `MCPComingSoonSheet` placeholder.
///
/// Backend: `GET /sessions/:id/mcp-servers` returns `{ available,
/// enabled }`. `POST /sessions/:id/mcp-servers { enabled: [...] }`
/// persists the new selection. The toggle takes effect on the next
/// host spawn — the v1 daemon doesn't restart the running CLI
/// automatically, so the sheet surfaces that as a footnote rather than
/// hiding it.
struct MCPPickerSheet: View {
    let session: SessionDescriptorWire
    let pairing: PairingStore
    let onDismiss: () -> Void

    @State private var listing: MCPListingWire?
    @State private var loading = true
    @State private var loadError: String?
    /// Local mirror of `listing.enabled` so toggles feel instant.
    @State private var enabled: Set<String> = []
    @State private var saving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                content
            }
            .navigationTitle("MCP Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { Task { await commitAndDismiss() } }
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .disabled(saving)
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
        } else if let listing {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro(listing: listing)
                    if listing.available.isEmpty {
                        emptyState
                    } else {
                        section("AVAILABLE") {
                            VStack(spacing: 6) {
                                ForEach(listing.available) { server in
                                    row(server)
                                }
                            }
                        }
                    }
                    if let saveError {
                        Text(saveError)
                            .font(.system(size: 12))
                            .foregroundStyle(SmoothieColor.statusErr)
                            .padding(.horizontal, 6)
                    }
                    footnote
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func intro(listing: MCPListingWire) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.cli.displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text(introSubtitle(listing: listing))
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func introSubtitle(listing: MCPListingWire) -> String {
        if listing.available.isEmpty {
            return "No MCP servers found in this provider's config."
        }
        let total = listing.available.count
        let on = enabled.count
        return "\(on)/\(total) servers enabled for this session."
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.textTertiary)
            Text("No MCP servers discovered")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SmoothieColor.textPrimary)
            Text("Add servers via your provider's CLI — e.g. `claude mcp add <name> -- <command>` — and they'll appear here on next open.")
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .padding(.horizontal, 16)
        .smoothieCard(cornerRadius: SmoothieMetrics.cornerMd)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.leading, 6)
            content()
        }
    }

    private func row(_ server: MCPServerWire) -> some View {
        let isOn = enabled.contains(server.id)
        return Button {
            toggle(server.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isOn ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let desc = server.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundStyle(SmoothieColor.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    Text(server.source)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerRow))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerRow)
                    .strokeBorder(
                        isOn ? SmoothieColor.linkBlue.opacity(0.6) : SmoothieColor.strokeSoft,
                        lineWidth: isOn ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(saving)
        .opacity(saving ? 0.5 : 1)
    }

    private var footnote: some View {
        Text("Changes apply on the next session start. Use the chat menu's Reload to pick them up now.")
            .font(.system(size: 11))
            .foregroundStyle(SmoothieColor.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.statusErr)
            Text("Couldn't load MCP servers")
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

    // MARK: - Actions

    private func toggle(_ id: String) {
        if enabled.contains(id) {
            enabled.remove(id)
        } else {
            enabled.insert(id)
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        let api = pairing.api
        do {
            let fetched = try await api.mcpServers(sessionId: session.id)
            listing = fetched
            enabled = Set(fetched.enabled)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// On Done we POST the new enabled set then dismiss. If the user
    /// hasn't changed anything we skip the POST so the sheet closes
    /// instantly. Failures surface inline; the sheet stays open so the
    /// user doesn't lose their selection.
    private func commitAndDismiss() async {
        guard let listing else {
            onDismiss()
            return
        }
        let currentSet = Set(listing.enabled)
        if currentSet == enabled {
            onDismiss()
            return
        }
        saving = true
        saveError = nil
        let api = pairing.api
        do {
            _ = try await api.setMCPEnabled(sessionId: session.id, enabled: Array(enabled))
            saving = false
            onDismiss()
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            saving = false
        }
    }
}
