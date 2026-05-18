import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("Smoothie")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("v0.2.0 · iOS 26 Liquid Glass build")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                Text("Pair via QR (next phase)")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .preferredColorScheme(.dark)
        }
    }
}
