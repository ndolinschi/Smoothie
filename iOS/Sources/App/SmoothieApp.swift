import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    @State private var pairing = PairingStore()
    @State private var recents = RecentsStore()
    @StateObject private var notifications = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            RootView(notifications: notifications)
                .environment(pairing)
                .environment(recents)
                .preferredColorScheme(.dark)
                .tint(.white)
                .task {
                    await LocalNotifier.shared.ensureAuthorization()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    /// `smoothie://session/<id>` deep links — used by local notification taps
    /// to surface the session that produced the WAITING / DONE event.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "smoothie" else { return }
        if url.host == "session" {
            let id = url.lastPathComponent
            if !id.isEmpty { notifications.pendingSessionId = id }
        }
    }
}

private struct RootView: View {
    @ObservedObject var notifications: NotificationRouter
    @Environment(PairingStore.self) private var pairing
    @State private var deepLinkedSession: SessionDescriptorWire?

    var body: some View {
        Group {
            if pairing.current != nil {
                HomeView()
                    .navigationDestination(item: $deepLinkedSession) { s in
                        SessionView(session: s)
                    }
            } else {
                ConnectView()
            }
        }
        .onChange(of: notifications.pendingSessionId) { _, new in
            guard let id = new else { return }
            notifications.pendingSessionId = nil
            Task { await resolveSession(id: id) }
        }
    }

    /// Resolve a deep-linked session id to its descriptor via /sessions, then
    /// trigger the navigation destination. Silently fails if the session no
    /// longer exists (e.g. already killed).
    private func resolveSession(id: String) async {
        let api = APIClient(store: pairing)
        guard let list = try? await api.sessions() else { return }
        if let descriptor = list.first(where: { $0.id == id }) {
            deepLinkedSession = descriptor
        }
    }
}
