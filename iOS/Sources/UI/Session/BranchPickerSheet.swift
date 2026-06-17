import SwiftUI

/// Lists the git branches in the active session's project and lets the
/// user switch with a tap. Mirrors `ModelPickerSheet`'s layout so the
/// composer's picker family reads consistent.
///
/// Backend: `GET /sessions/:id/branches` → list; `POST
/// /sessions/:id/branch` → checkout. Non-zero git exits (dirty tree,
/// conflicts) come back as 409 with stderr in the body; the sheet
/// surfaces that message inline so the user knows whether to commit /
/// stash first.
struct BranchPickerSheet: View {
    let session: SessionDescriptorWire
    let pairing: PairingStore
    let onSwitched: (SessionDescriptorWire) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var listing: BranchListingWire?
    @State private var loading = true
    @State private var loadError: String?
    /// While non-nil, that branch row shows a spinner; every other row
    /// disables. The post-success descriptor is forwarded to the host
    /// via `onSwitched` so the chip can refresh.
    @State private var switching: String?
    @State private var switchError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                content
            }
            .navigationTitle("Branches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDismiss() }
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
        } else if let listing {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if let banner = switchError {
                        switchErrorBanner(banner)
                    }
                    section(title: listing.current.map { "ON \($0.uppercased())" } ?? "BRANCHES") {
                        VStack(spacing: 6) {
                            ForEach(filtered(listing), id: \.self) { branch in
                                row(branch, current: branch == listing.current)
                            }
                        }
                    }
                    if filtered(listing).isEmpty && !query.isEmpty {
                        Text("No branches match.")
                            .font(.system(size: 13))
                            .foregroundStyle(SmoothieColor.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
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
            TextField("Search branches", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
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

    private func row(_ branch: String, current: Bool) -> some View {
        let isLoading = switching == branch
        return Button {
            Task { await switchTo(branch) }
        } label: {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SmoothieColor.textPrimary)
                        .frame(width: 17, height: 17)
                } else {
                    Image(systemName: current ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(current ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(branch)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isLoading {
                        Text("switching…")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(SmoothieColor.accent)
                    } else if current {
                        Text("current")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(SmoothieColor.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerRow))
            .overlay(
                RoundedRectangle(cornerRadius: SmoothieMetrics.cornerRow)
                    .strokeBorder(
                        current ? SmoothieColor.linkBlue.opacity(0.6) : SmoothieColor.strokeSoft,
                        lineWidth: current ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(switching != nil)
        .opacity(switching != nil && !isLoading ? 0.45 : 1)
    }

    private func switchErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SmoothieColor.statusErr)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(SmoothieColor.textPrimary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: SmoothieMetrics.cornerRow))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerRow)
                .strokeBorder(SmoothieColor.statusErr.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(SmoothieColor.statusErr)
            Text("Couldn't list branches")
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

    // MARK: - Filtering + actions

    private func filtered(_ listing: BranchListingWire) -> [String] {
        let q = query.lowercased()
        if q.isEmpty { return listing.branches }
        return listing.branches.filter { $0.lowercased().contains(q) }
    }

    private func load() async {
        loading = true
        loadError = nil
        let api = pairing.api
        do {
            listing = try await api.branches(sessionId: session.id)
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func switchTo(_ branch: String) async {
        guard switching == nil, branch != listing?.current else { return }
        switching = branch
        switchError = nil
        let api = pairing.api
        do {
            let updated = try await api.switchBranch(sessionId: session.id, branch: branch)
            switching = nil
            onSwitched(updated)
            onDismiss()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            switching = nil
        }
    }
}
