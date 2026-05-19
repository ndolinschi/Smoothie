import Foundation
import UserNotifications

/// Local notification scheduler. When the app is backgrounded or inactive
/// and a session reaches WAITING / DONE / LIMIT_REACHED, we schedule a
/// notification with the session id in `userInfo` so the launch handler
/// can deep-link back to that SessionView.
@MainActor
final class LocalNotifier {
    static let shared = LocalNotifier()
    private var permissionAsked = false
    private var permissionGranted = false

    private init() {}

    func ensureAuthorization() async {
        if permissionAsked { return }
        permissionAsked = true
        let center = UNUserNotificationCenter.current()
        permissionGranted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func notifyWaiting(projectName: String, sessionId: String) {
        send(title: "Agent waiting", body: projectName, sessionId: sessionId)
    }

    func notifyDone(projectName: String, sessionId: String) {
        send(title: "Agent done", body: projectName, sessionId: sessionId)
    }

    func notifyLimitReached(projectName: String, sessionId: String) {
        send(title: "Agent hit its limit", body: projectName, sessionId: sessionId)
    }

    private func send(title: String, body: String, sessionId: String) {
        Task { @MainActor in
            await ensureAuthorization()
            guard permissionGranted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["sessionId": sessionId]
            let req = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(req)
        }
    }
}

/// Notification delegate that turns notification taps into a published
/// `pendingSessionId` the root view can observe and route on.
@MainActor
final class NotificationRouter: NSObject, @preconcurrency UNUserNotificationCenterDelegate, ObservableObject {
    @Published var pendingSessionId: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let id = response.notification.request.content.userInfo["sessionId"] as? String {
            pendingSessionId = id
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Foreground delivery — still show the banner, but the UI is already
        // in the user's hands so we don't need to push a deep link.
        completionHandler([.banner, .sound])
    }
}
