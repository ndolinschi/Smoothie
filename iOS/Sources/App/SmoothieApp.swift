import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    @State private var pairing = PairingStore()
    @State private var recents = RecentsStore()
    @State private var sessionMeta = SessionMetaStore()
    @State private var settings = SettingsStore()
    @StateObject private var notifications = NotificationRouter()

    var body: some Scene {
        WindowGroup {
            RootView(notifications: notifications)
                .environment(pairing)
                .environment(recents)
                .environment(sessionMeta)
                .environment(settings)
                // P27.d/f — preferredColorScheme follows the user's
                // Settings override; `nil` means follow system. Tokens
                // in DesignTokens are adaptive either way.
                .preferredColorScheme(settings.theme.colorScheme)
                .tint(SmoothieColor.accent)
                .task {
                    await LocalNotifier.shared.ensureAuthorization()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    /// Deep links — three shapes:
    /// - `smoothie://session/<id>` — local notification taps surfacing
    ///   the session that produced the WAITING / DONE event.
    /// - `smoothie://pair?host=…&port=…&token=…` — Mac menubar's "Copy
    ///   pairing URL" output. Tapping it on the phone pairs in one go.
    /// - `smoothie://pair?host=…&port=…&token=…&scheme=https` — variant
    ///   that includes a scheme (Cloudflare-tunnelled deployments).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "smoothie" else { return }
        switch url.host {
        case "session":
            let id = url.lastPathComponent
            if !id.isEmpty { notifications.pendingSessionId = id }
        case "pair":
            // Hand the full URL string to PairingStore so it can parse
            // host/port/token/scheme query params consistently with the
            // QR-scanned path.
            Task { _ = await pairing.tryPairFromURL(url.absoluteString) }
        default:
            break
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
