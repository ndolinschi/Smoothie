import SwiftUI

@main
struct SmoothieApp: App {
    @State private var server = ServerStore()
    @State private var customProjects = CustomProjectsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(server)
                .environment(customProjects)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .task {
                    await LocalNotifier.shared.ensurePermissions()
                    server.startPolling()
                }
        }
    }
}
