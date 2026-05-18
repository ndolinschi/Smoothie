import SwiftUI

struct ContentView: View {
    @Environment(ServerStore.self) private var server

    var body: some View {
        ZStack {
            BackdropView()

            Group {
                if server.serverURL == nil {
                    ConnectView()
                } else {
                    HomeView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(ServerStore())
        .preferredColorScheme(.dark)
}
