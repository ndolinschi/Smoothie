import SwiftUI
import UIKit

/// P29 §8 — Create-PR sheet wired to the daemon's `POST
/// /sessions/:id/create-pr` endpoint. Lets the user title + describe
/// the change, pick the destination branch, then triggers the full
/// `git push` + `gh pr create` pipeline on the Mac.
///
/// While the request is in-flight the sheet shows a staged progress
/// overlay. On success it copies the returned URL, dismisses, and
/// optionally opens the PR in Safari.
struct CreatePRSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PairingStore.self) private var pairing

    let session: SessionDescriptorWire
    let events: [SmoothieEventWire]
    let onCreated: (URL) -> Void

    @State private var title: String = ""
    @State private var descriptionText: String = ""
    @State private var branch: String = ""
    @State private var useCurrentBranch: Bool = false
    @State private var openInSafari: Bool = true
    @State private var inflight: Bool = false
    @State private var lastError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Title") {
                            TextField("PR title", text: $title)
                                .font(.system(size: 15, weight: .medium))
                                .padding(12)
                                .smoothieCard(cornerRadius: SmoothieMetrics.cornerRow)
                        }

                        section("Description") {
                            TextEditor(text: $descriptionText)
                                .font(.system(size: 13, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 160)
                                .padding(8)
                                .smoothieCard(cornerRadius: SmoothieMetrics.cornerRow)
                        }

                        section("Branch") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("smoothie/short-id", text: $branch)
                                    .font(.system(size: 14, design: .monospaced))
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .padding(12)
                                    .smoothieCard(cornerRadius: SmoothieMetrics.cornerRow)
                                    .disabled(useCurrentBranch)
                                    .opacity(useCurrentBranch ? 0.55 : 1)
                                Toggle("Push to current branch instead", isOn: $useCurrentBranch)
                                    .font(.system(size: 13))
                                    .tint(SmoothieColor.accent)
                            }
                        }

                        section("Open PR in Safari after creation") {
                            Toggle(isOn: $openInSafari) {
                                HStack(spacing: 8) {
                                    Image(systemName: "safari")
                                    Text("Auto-open URL")
                                        .font(.system(size: 13))
                                }
                            }
                            .tint(SmoothieColor.accent)
                        }

                        if let lastError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(SmoothieColor.statusErr)
                                Text(lastError)
                                    .font(.system(size: 13))
                                    .foregroundStyle(SmoothieColor.statusErr)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                SmoothieColor.statusErr.opacity(0.12),
                                in: .rect(cornerRadius: SmoothieMetrics.cornerRow)
                            )
                        }
                    }
                    .padding(20)
                }

                if inflight {
                    Color.black.opacity(0.45).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(.white).controlSize(.large)
                        Text("Creating pull request…")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(28)
                    .background(SmoothieColor.bgCard.opacity(0.96), in: .rect(cornerRadius: SmoothieMetrics.cornerCard))
                }
            }
            .navigationTitle("Create PR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(SmoothieColor.textSecondary)
                        .disabled(inflight)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: submit) {
                        Text("Create")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canSubmit || inflight)
                    .foregroundStyle(canSubmit ? SmoothieColor.textPrimary : SmoothieColor.textTertiary)
                }
            }
        }
        .onAppear(perform: prefill)
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (useCurrentBranch || !branch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(SmoothieColor.textTertiary)
                .padding(.leading, 6)
            content()
        }
    }

    private func prefill() {
        guard title.isEmpty else { return }
        // Default title — first user message, trimmed to 70 chars.
        if let firstUser = events.first(where: { $0.type == .message }) {
            let raw = firstUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
            title = String(raw.prefix(70))
        }
        // Default body — diff stats summary so reviewers know the
        // rough scope before opening the PR.
        var added = 0
        var removed = 0
        var files: Set<String> = []
        for event in events where event.type == .fileEdit {
            if let entry = DiffEntry(event: event) {
                let rows = entry.diffRows()
                added += rows.filter { $0.kind == .addition }.count
                removed += rows.filter { $0.kind == .deletion }.count
                files.insert(entry.path)
            }
        }
        descriptionText = """
        ## Summary

        Smoothie session in \(session.projectName) (\(session.cli.displayName)).

        ## Changes

        \(added) additions, \(removed) deletions across \(files.count) file\(files.count == 1 ? "" : "s").

        ## Test plan

        - [ ] …
        """
        // Default branch — `smoothie/<short id prefix>` keeps PR
        // branches obviously distinct from main work branches.
        let prefix = String(session.id.replacingOccurrences(of: "-", with: "").prefix(8))
        branch = "smoothie/\(prefix)"
    }

    private func submit() {
        guard canSubmit, !inflight else { return }
        let api = APIClient(store: pairing)
        let request = CreatePRRequestWire(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: descriptionText,
            branch: branch.trimmingCharacters(in: .whitespacesAndNewlines),
            useCurrentBranch: useCurrentBranch
        )
        inflight = true
        lastError = nil
        Task {
            do {
                let response = try await api.createPR(sessionId: session.id, request)
                guard let url = URL(string: response.url) else {
                    lastError = "Daemon returned an unparseable URL: \(response.url)"
                    inflight = false
                    return
                }
                UIPasteboard.general.string = response.url
                if openInSafari {
                    await UIApplication.shared.open(url)
                }
                onCreated(url)
                inflight = false
                dismiss()
            } catch {
                inflight = false
                if isCancellation(error) { return }
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
