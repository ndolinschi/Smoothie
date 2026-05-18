import SwiftUI

struct SessionView: View {
    let session: SessionDTO
    @Environment(\.dismiss) private var dismiss
    @Environment(ServerStore.self) private var server
    @State private var store: SessionStore?
    @State private var confirmKill = false

    var body: some View {
        ZStack {
            BackdropView()

            VStack(spacing: 0) {
                if let store {
                    eventList(store: store)
                    MessageInput(state: store.state) { content in
                        await store.sendMessage(content)
                    }
                } else {
                    ProgressView()
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
                    Text(session.projectName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    if let store {
                        StatusBadge(state: store.state, connected: store.connected)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(role: .destructive) { confirmKill = true } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.error.opacity(0.9))
                }
            }
        }
        .onAppear {
            guard store == nil, let api = server.api else { return }
            let s = SessionStore(session: session, api: api)
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
}
