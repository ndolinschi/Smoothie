import SwiftUI

// The legacy "+" ComposerMenu View struct was removed in P18 — AttachSheet
// in iOS/Sources/UI/Session/AttachSheet.swift owns that surface now. The
// drill-in sheets below (ModelPickerSheet, SlashCommandSheet,
// MCPComingSoonSheet) are still presented by AttachSheet via callbacks, so
// they live on here.

// MARK: - Model picker

struct ModelPickerSheet: View {
    let currentModel: String?
    let currentEffort: String?
    let features: ProviderFeaturesWire
    let onPickModel: (String) async -> Void
    let onPickEffort: (String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    /// While non-nil, the sheet is awaiting the restart triggered by the
    /// row's tap. The selected row shows a spinner; all other rows disable.
    @State private var pickingModel: String?
    @State private var pickingEffort: String?

    private var filtered: [String] {
        if query.isEmpty { return features.availableModels }
        let q = query.lowercased()
        return features.availableModels.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        searchField

                        if features.supportsReasoningEffort, !features.availableReasoningEfforts.isEmpty {
                            section("REASONING EFFORT") {
                                effortRow
                            }
                        }

                        section("MODELS") {
                            VStack(spacing: 6) {
                                ForEach(filtered, id: \.self) { model in
                                    modelRow(model)
                                }
                            }
                        }

                        if filtered.isEmpty && !query.isEmpty {
                            Text("No matches.")
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
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(SmoothieColor.textSecondary)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SmoothieColor.textTertiary)
            TextField("Search models", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(SmoothieColor.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
        )
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(SmoothieColor.textTertiary).padding(.leading, 6)
            content()
        }
    }

    private var effortRow: some View {
        HStack(spacing: 6) {
            ForEach(features.availableReasoningEfforts, id: \.self) { effort in
                Button {
                    Task { await selectEffort(effort) }
                } label: {
                    HStack(spacing: 5) {
                        if pickingEffort == effort {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.black)
                        }
                        Text(effort)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(currentEffort == effort ? .black : .white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        currentEffort == effort ? Color.white : Color.clear,
                        in: .capsule
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isPicking)
                .opacity(isPicking && pickingEffort != effort ? 0.45 : 1)
            }
        }
    }

    private var isPicking: Bool { pickingModel != nil || pickingEffort != nil }

    private func selectModel(_ model: String) async {
        guard !isPicking else { return }
        pickingModel = model
        await onPickModel(model)
        pickingModel = nil
        dismiss()
    }

    private func selectEffort(_ effort: String) async {
        guard !isPicking else { return }
        pickingEffort = effort
        await onPickEffort(effort)
        pickingEffort = nil
        dismiss()
    }

    private func modelRow(_ model: String) -> some View {
        let isCurrent = (currentModel ?? features.defaultModel) == model
        let isLoading = pickingModel == model
        return Button {
            Task { await selectModel(model) }
        } label: {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                        .frame(width: 17, height: 17)
                } else {
                    Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.35))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    if isLoading {
                        Text("switching…")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(SmoothieColor.accent)
                    } else if model == features.defaultModel {
                        Text("default")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isCurrent ? SmoothieColor.linkBlue.opacity(0.6) : SmoothieColor.strokeSoft,
                        lineWidth: isCurrent ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isPicking)
        .opacity(isPicking && !isLoading ? 0.45 : 1)
    }
}

// MARK: - Compact model dropdown (P25.b)

/// Centered-toolbar model dropdown — small rounded card with one row per
/// available model. Mirrors the Claude Code mobile reference where the
/// model name + chevron in the nav bar opens a compact popover (not a
/// full sheet). The existing `ModelPickerSheet` remains reachable from
/// AttachSheet for power-user search + reasoning effort.
struct ModelDropdownMenu: View {
    let cli: CLIWire
    let currentModel: String?
    let features: ProviderFeaturesWire
    let onPickModel: (String) async -> Void
    let onMoreOptions: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picking: String?

    private var models: [String] { features.availableModels }
    private var showsMoreFooter: Bool { models.count > 4 || features.supportsReasoningEffort }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(models.enumerated()), id: \.element) { index, model in
                modelRow(model)
                if index < models.count - 1 {
                    Divider()
                        .background(SmoothieColor.menuDivider)
                        .padding(.leading, SmoothieMetrics.space16 + 16 + SmoothieMetrics.space12)
                }
            }
            if showsMoreFooter {
                Divider().background(SmoothieColor.menuDivider)
                moreOptionsRow
            }
        }
        .frame(minWidth: 280, idealWidth: 300)
        .background(SmoothieColor.menuBg)
        .clipShape(RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg))
        .overlay(
            RoundedRectangle(cornerRadius: SmoothieMetrics.cornerLg)
                .strokeBorder(SmoothieColor.menuStroke, lineWidth: 0.5)
        )
        .presentationCompactAdaptation(.popover)
    }

    private func modelRow(_ model: String) -> some View {
        let isCurrent = (currentModel ?? features.defaultModel) == model
        let isLoading = picking == model
        return Button {
            Task { await select(model) }
        } label: {
            HStack(alignment: .top, spacing: SmoothieMetrics.space12) {
                leadingGutter(isCurrent: isCurrent, isLoading: isLoading)
                VStack(alignment: .leading, spacing: SmoothieMetrics.space2) {
                    Text(cli.friendlyModelName(model))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SmoothieColor.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let descriptor = cli.modelDescriptor(model) {
                        Text(descriptor)
                            .font(.system(size: 13))
                            .foregroundStyle(SmoothieColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SmoothieMetrics.space16)
            .padding(.vertical, SmoothieMetrics.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(picking != nil)
        .opacity(picking != nil && !isLoading ? 0.45 : 1)
    }

    private func leadingGutter(isCurrent: Bool, isLoading: Bool) -> some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(SmoothieColor.textPrimary)
            } else if isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(SmoothieColor.textPrimary)
            }
        }
        .frame(width: 16, height: 18)
        .padding(.top, 1)
    }

    private var moreOptionsRow: some View {
        Button {
            dismiss()
            onMoreOptions()
        } label: {
            HStack(spacing: SmoothieMetrics.space12) {
                Text("All models…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SmoothieColor.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SmoothieColor.textTertiary)
            }
            .padding(.horizontal, SmoothieMetrics.space16)
            .padding(.vertical, SmoothieMetrics.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ model: String) async {
        guard picking == nil else { return }
        picking = model
        await onPickModel(model)
        picking = nil
        dismiss()
    }
}

// MARK: - Slash command picker (Commands)

struct SlashCommandSheet: View {
    let commands: [SlashCommandWire]
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [SlashCommandWire] {
        if query.isEmpty { return commands }
        let q = query.lowercased()
        return commands.filter { $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SmoothieColor.bgPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(SmoothieColor.textTertiary)
                            TextField("Search commands", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(SmoothieColor.textPrimary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                        )

                        VStack(spacing: 6) {
                            ForEach(filtered) { c in
                                Button {
                                    onPick(c.name)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(c.name)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(SmoothieColor.textPrimary)
                                        Spacer()
                                        Text(c.description)
                                            .font(.system(size: 12))
                                            .foregroundStyle(SmoothieColor.textSecondary)
                                            .lineLimit(1)
                                    }
                                    .padding(12)
                                    .background(SmoothieColor.bgCard, in: .rect(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(SmoothieColor.strokeSoft, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Commands")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(SmoothieColor.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }
}

// MARK: - MCP placeholder

struct MCPComingSoonSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("MCP Servers")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("MCP connectors land after the v1 release. The Mac daemon will broker connections for each session and surface them here.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                    Button("Got it") { dismiss() }
                        .buttonStyle(.glassProminent)
                        .tint(.white)
                        .foregroundStyle(.black)
                        .padding(.top, 8)
                }
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
    }
}
