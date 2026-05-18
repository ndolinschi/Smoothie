import SwiftUI

struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server

    @State private var currentSession: SessionDTO
    @State private var store: SessionStore?
    @State private var confirmKill = false
    @State private var showCLIPicker = false
    @State private var switching = false
    @State private var switchError: String?

    init(session: SessionDTO) {
        _currentSession = State(initialValue: session)
    }

    var body: some View {
        ZStack {
            BackdropView()

            VStack(spacing: 0) {
                if let store {
                    eventList(store: store)
                        .id(currentSession.id)
                    MessageInput(
                        state: store.state,
                        cli: currentSession.cli,
                        projectPath: currentSession.projectPath,
                        onSend: { text, attachments in
                            await sendMessage(text: text, attachments: attachments, store: store)
                        },
                        onSwitchCLI: { showCLIPicker = true }
                    )
                } else if switching {
                    VStack(spacing: 12) {
                        ProgressView().tint(.white.opacity(0.6))
                        Text("Switching CLI…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .tint(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 3) {
                    Text(currentSession.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let store {
                        StatusBadge(state: store.state, connected: store.connected)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                sessionMenu
            }
        }
        .onAppear {
            guard store == nil, let api = server.api else { return }
            let s = SessionStore(session: currentSession, api: api)
            store = s
            s.connect()
        }
        .onDisappear {
            store?.disconnect()
        }
        .alert("Kill session?", isPresented: $confirmKill) {
            Button("Kill", role: .destructive) {
                Task {
                    await store?.kill()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will terminate the agent process on your Mac.")
        }
        .alert("Couldn't switch CLI", isPresented: Binding(
            get: { switchError != nil },
            set: { if !$0 { switchError = nil } }
        )) {
            Button("OK", role: .cancel) { switchError = nil }
        } message: {
            Text(switchError ?? "")
        }
        .sheet(isPresented: $showCLIPicker) {
            CLIPickerSheet(currentCLI: currentSession.cli) { newCLI in
                Task { await switchCLI(to: newCLI) }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(.clear)
        }
    }

    private var sessionMenu: some View {
        Menu {
            Section("Provider") {
                Text("\(currentSession.cli.label)")
                Button {
                    showCLIPicker = true
                } label: {
                    Label("Switch CLI…", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmKill = true
                } label: {
                    Label("Kill session", systemImage: "xmark.circle")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    private func eventList(store: SessionStore) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.events) { event in
                        EventRow(event: event)
                            .id(event.id)
                    }
                    Color.clear.frame(height: 1).id("BOTTOM")
                }
                .padding(.vertical, 12)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: store.events.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Send

    private func sendMessage(
        text: String,
        attachments: [StagedAttachment],
        store: SessionStore
    ) async {
        let composed = composeMessage(text: text, attachments: attachments)
        await store.sendMessage(composed)
    }

    private func composeMessage(text: String, attachments: [StagedAttachment]) -> String {
        guard !attachments.isEmpty else { return text }
        var lines: [String] = []
        lines.append("--- attached files ---")
        for att in attachments {
            lines.append("file: \(att.relativePath)\(att.truncated ? " (truncated)" : "")")
            lines.append("```")
            lines.append(att.content)
            lines.append("```")
        }
        lines.append("--- end attached files ---")
        if !text.isEmpty {
            lines.append("")
            lines.append(text)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Switch CLI

    private func switchCLI(to newCLI: CLIType) async {
        guard let api = server.api else { return }
        guard newCLI != currentSession.cli else { return }

        let oldStore = store
        switching = true
        store = nil

        await oldStore?.kill()

        do {
            let newSession = try await api.createSession(projectPath: currentSession.projectPath, cli: newCLI)
            currentSession = newSession
            let newStore = SessionStore(session: newSession, api: api)
            store = newStore
            newStore.connect()
        } catch {
            switchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        switching = false
    }
}
