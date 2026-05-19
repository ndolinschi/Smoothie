import SwiftUI

/// The "+" menu inside MessageInput, inspired by Cursor's "Add agents,
/// context, tools…" sheet. Renders only the sections the active provider
/// supports — Claude has reasoning effort, Gemini has modes, OpenCode has
/// HTTP-routed models, etc.
///
/// Model / effort / mode changes lock a session at startup (each CLI starts
/// with the chosen flags), so picking a new value triggers a confirm-and-
/// restart flow rather than mutating the live process.
struct ComposerMenu: View {
    let session: SessionDescriptorWire
    let features: ProviderFeaturesWire?
    let onInsertSlash: (String) -> Void
    let onAttachFile: () -> Void
    let onMentionFile: () -> Void
    let onRestartWithModel: (String) -> Void
    let onRestartWithEffort: (String) -> Void
    let onRestartWithMode: (String) -> Void

    @State private var showingModels = false
    @State private var showingSlash = false
    @State private var showingMCP = false

    var body: some View {
        Menu {
            Section("Add agents, context, tools…") {
                // Modes (Plan/Debug/Multitask/Ask in Cursor; Smoothie maps to
                // provider modes — Gemini's plan/auto_edit/yolo/default).
                if let f = features, f.supportsModes, !f.availableModes.isEmpty {
                    Menu("Modes") {
                        ForEach(f.availableModes, id: \.self) { mode in
                            Button {
                                onRestartWithMode(mode)
                            } label: {
                                if session.mode == mode {
                                    Label(modeDisplay(mode), systemImage: "checkmark")
                                } else {
                                    Text(modeDisplay(mode))
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    onAttachFile()
                } label: {
                    Label("Image / file", systemImage: "paperclip")
                }

                Button {
                    onMentionFile()
                } label: {
                    Label("Mention file (@)", systemImage: "at")
                }
            }

            Section {
                if let f = features, f.supportsModelPicker {
                    Button {
                        showingModels = true
                    } label: {
                        Label("Models", systemImage: "cube")
                    }
                }

                if let f = features, !f.slashCommands.isEmpty {
                    Button {
                        showingSlash = true
                    } label: {
                        Label("Skills", systemImage: "wand.and.stars")
                    }
                }

                Button {
                    showingMCP = true
                } label: {
                    Label("MCP Servers", systemImage: "server.rack")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .glassEffect(in: .rect(cornerRadius: 14))
        }
        .sheet(isPresented: $showingModels) {
            if let f = features {
                ModelPickerSheet(
                    currentModel: session.model,
                    currentEffort: session.reasoningEffort,
                    features: f,
                    onPickModel: onRestartWithModel,
                    onPickEffort: onRestartWithEffort
                )
                .presentationDetents([.medium, .large])
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingSlash) {
            if let f = features {
                SlashCommandSheet(
                    commands: f.slashCommands,
                    onPick: onInsertSlash
                )
                .presentationDetents([.medium])
                .presentationBackground(.clear)
            }
        }
        .sheet(isPresented: $showingMCP) {
            MCPComingSoonSheet()
                .presentationDetents([.medium])
                .presentationBackground(.clear)
        }
    }

    private func modeDisplay(_ raw: String) -> String {
        // Gemini's underscored names; show as plain words
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

// MARK: - Model picker

struct ModelPickerSheet: View {
    let currentModel: String?
    let currentEffort: String?
    let features: ProviderFeaturesWire
    let onPickModel: (String) -> Void
    let onPickEffort: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    private var filtered: [String] {
        if query.isEmpty { return features.availableModels }
        let q = query.lowercased()
        return features.availableModels.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
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
                                .foregroundStyle(.white.opacity(0.4))
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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.45))
            TextField("Search models", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .glassEffect(in: .rect(cornerRadius: 14))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(.white.opacity(0.4)).padding(.leading, 6)
            content()
        }
    }

    private var effortRow: some View {
        HStack(spacing: 6) {
            ForEach(features.availableReasoningEfforts, id: \.self) { effort in
                Button {
                    onPickEffort(effort)
                    dismiss()
                } label: {
                    Text(effort)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(currentEffort == effort ? .black : .white.opacity(0.7))
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
            }
        }
    }

    private func modelRow(_ model: String) -> some View {
        let isCurrent = (currentModel ?? features.defaultModel) == model
        // We don't have access to CLIWire in this scope (the sheet is
        // adapter-agnostic), so the raw id falls through unaltered. Most of
        // the time it IS already friendly because Cursor's pattern of "alias
        // first" is also how Claude / Gemini are configured. Provider chip
        // outside the sheet handles the marketing-name lookup.
        return Button {
            onPickModel(model)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(isCurrent ? .white : .white.opacity(0.35))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    if model == features.defaultModel {
                        Text("default")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                Spacer()
            }
            .padding(12)
            .glassEffect(in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Slash command picker (Skills)

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
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.white.opacity(0.45))
                            TextField("Search skills", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .glassEffect(in: .rect(cornerRadius: 14))

                        VStack(spacing: 6) {
                            ForEach(filtered) { c in
                                Button {
                                    onPick(c.name)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(c.name)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text(c.description)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .lineLimit(1)
                                    }
                                    .padding(12)
                                    .glassEffect(in: .rect(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(20)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
