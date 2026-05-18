import SwiftUI

@main
struct SmoothieMenubarApp: App {
    @State private var monitor = ServerMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenubarContent()
                .environment(monitor)
                .frame(width: 320)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.isHealthy ? "circle.fill" : "circle.dotted")
                    .font(.system(size: 9))
                Image(systemName: "waveform")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
