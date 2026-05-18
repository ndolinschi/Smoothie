import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text("Smoothie")
                    .font(.system(size: 13, weight: .semibold))
                Text("v0.2.0 · K/N shared business logic ready")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(12)
            .frame(width: 280)
        } label: {
            Image(systemName: "waveform.path")
        }
        .menuBarExtraStyle(.window)
    }
}
