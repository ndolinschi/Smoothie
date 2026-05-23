import SwiftUI

/// User-facing settings screen. Reached from HomeView's leading toolbar
/// button (P27.f). Lives in its own sheet so it can scroll independent
/// of the dashboard.
///
/// Layout: list with four sections.
///   • Appearance — theme override (System / Light / Dark)
///   • Pairings   — pushes PairingsSheet
///   • Data       — destructive "Delete local data" button
///   • About      — version + build pulled from Bundle.main
struct SettingsView: View {
    /// HomeView passes this callback so the "Pair another Mac" row inside
    /// PairingsSheet can hand the user off to the AddPairingCover flow.
    /// Settings dismisses itself before invoking the closure; HomeView
    /// then fires `presentingAddPair`.
    let onAddPairing: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings
    @Environment(RecentsStore.self) private var recents
    @Environment(SessionMetaStore.self) private var sessionMeta
    @Environment(PairingStore.self) private var pairing

    @State private var showingPairings = false
    @State private var confirmingWipe = false

    init(onAddPairing: @escaping () -> Void = {}) {
        self.onAddPairing = onAddPairing
    }

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(SettingsStore.ThemeOverride.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Pairings") {
                    Button {
                        showingPairings = true
                    } label: {
                        HStack {
                            Label(
                                pairing.current?.label ?? "Manage pairings",
                                systemImage: "desktopcomputer"
                            )
                            .foregroundStyle(SmoothieColor.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(SmoothieColor.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Button(role: .destructive) {
                        confirmingWipe = true
                    } label: {
                        Label("Delete local data", systemImage: "trash")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Removes recents, custom session titles, pin/archive state, and the theme override from this phone. Pairing tokens stay (manage them above). Sessions on your Mac aren't touched.")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: appBuild)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPairings) {
                PairingsSheet(
                    onAddPairing: {
                        // Close both this Settings sheet and the
                        // nested PairingsSheet, then ask HomeView to
                        // present its AddPairingCover via the host's
                        // onAddPairing closure.
                        showingPairings = false
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(200))
                            onAddPairing()
                        }
                    },
                    onDismiss: { showingPairings = false }
                )
                .environment(pairing)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
            }
            .alert("Delete local data?", isPresented: $confirmingWipe) {
                Button("Delete", role: .destructive) {
                    settings.clearLocalData(recents: recents, sessionMeta: sessionMeta)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears recents, custom titles, pin/archive flags, and your theme preference. It can't be undone, but everything is rebuilt from scratch as you use the app.")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
