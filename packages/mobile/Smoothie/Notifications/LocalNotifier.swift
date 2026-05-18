import Foundation
import UserNotifications

@MainActor
final class LocalNotifier {
    static let shared = LocalNotifier()
    private var permissionRequested = false
    private var permissionGranted = false

    private init() {}

    func ensurePermissions() async {
        if permissionRequested { return }
        permissionRequested = true
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        permissionGranted = granted
    }

    func notifyWaiting(projectName: String, sessionId: String) {
        send(title: "Agent waiting", body: projectName, sessionId: sessionId)
    }

    func notifyDone(projectName: String, sessionId: String) {
        send(title: "Agent done", body: projectName, sessionId: sessionId)
    }

    private func send(title: String, body: String, sessionId: String) {
        Task { @MainActor in
            await ensurePermissions()
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
