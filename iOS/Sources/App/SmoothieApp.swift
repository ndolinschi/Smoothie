import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Text("Smoothie")
                    .font(.system(size: 32, weight: .bold))
                Text(Placeholder.shared.versionString)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .preferredColorScheme(.dark)
        }
    }
}
