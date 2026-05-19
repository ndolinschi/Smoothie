import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    @State private var pairing = PairingStore()
    @State private var recents = RecentsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(pairing)
                .environment(recents)
                .preferredColorScheme(.dark)
                .tint(.white)
        }
    }
}

private struct RootView: View {
    @Environment(PairingStore.self) private var pairing

    var body: some View {
        if pairing.current != nil {
            HomeView()
        } else {
            ConnectView()
        }
    }
}
