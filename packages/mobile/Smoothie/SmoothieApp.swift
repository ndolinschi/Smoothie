import SwiftUI

@main
struct SmoothieApp: App {
    @State private var server = ServerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(server)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    await LocalNotifier.shared.ensurePermissions()
                    server.startPolling()
                }
        }
    }
}
