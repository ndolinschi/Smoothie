import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var pairing: PairingService
    @State private var server: SmoothieHTTPServer

    init() {
        let p = PairingService()
        let s = SmoothieHTTPServer(pairing: p)
        _pairing = State(initialValue: p)
        _server = State(initialValue: s)
        AppDelegate.bootstrap = AppDelegate.Bootstrap(server: s)
    }

    var body: some Scene {
        MenuBarExtra {
            MenubarPopover()
                .environment(pairing)
                .environment(server)
        } label: {
            iconView
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var iconView: some View {
        switch server.status {
        case .running:
            Image(systemName: "waveform.path.badge.plus")
                .accessibilityLabel("Smoothie running")
        case .starting:
            Image(systemName: "waveform.path")
                .accessibilityLabel("Smoothie starting")
        case .failed:
            Image(systemName: "waveform.path.badge.minus")
                .accessibilityLabel("Smoothie failed")
        case .stopped:
            Image(systemName: "waveform.path")
                .accessibilityLabel("Smoothie stopped")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Bootstrap {
        let server: SmoothieHTTPServer
    }
    static var bootstrap: Bootstrap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.bootstrap?.server.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDelegate.bootstrap?.server.stop()
    }
}
