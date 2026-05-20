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
    @State private var deepLinkedSessionId: String?

    var body: some View {
        Group {
            if pairing.current != nil {
                // HomeView owns its own NavigationStack; pass the deep-link
                // binding in so the navigation push happens INSIDE that
                // stack. Previous wiring attached `.navigationDestination`
                // outside the stack — SwiftUI silently dropped the route and
                // notification taps went nowhere.
                HomeView(deepLinkedSessionId: $deepLinkedSessionId)
            } else {
                ConnectView()
            }
        }
        .onChange(of: notifications.pendingSessionId) { _, new in
            guard let id = new else { return }
            notifications.pendingSessionId = nil
            deepLinkedSessionId = id
        }
    }
}
