import SwiftUI
import Shared

@main
struct SmoothieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var pairing: PairingService
    @State private var prefs: Preferences
    @State private var processes: ProcessRegistry
    @State private var server: SmoothieHTTPServer

    init() {
        let p = PairingService()
        let prefs = Preferences()
        let manager = SessionManager(registry: AdapterRegistry())
        let registry = AdapterRegistry()
        let proc = ProcessRegistry(manager: manager, registry: registry, prefs: prefs)
        let s = SmoothieHTTPServer(
            pairing: p,
            manager: manager,
            registry: registry,
            processes: proc,
            prefs: prefs
        )
        _pairing = State(initialValue: p)
        _prefs = State(initialValue: prefs)
        _processes = State(initialValue: proc)
        _server = State(initialValue: s)
        AppDelegate.bootstrap = AppDelegate.Bootstrap(
            server: s,
            registry: registry,
            processes: proc
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenubarPopover()
                .environment(pairing)
                .environment(server)
                .environment(prefs)
                .environment(processes)
        } label: {
            iconView
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var iconView: some View {
        switch server.status {
        case .running:
            if processes.activeCount > 0 {
                Image(systemName: "waveform.path.badge.plus")
                    .accessibilityLabel("Smoothie running with \(processes.activeCount) session(s)")
            } else {
                Image(systemName: "waveform.path")
                    .accessibilityLabel("Smoothie running")
            }
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
        let registry: AdapterRegistry
        let processes: ProcessRegistry
    }
    static var bootstrap: Bootstrap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SafetyHost.shared.loadPrompts()
        if let boot = AppDelegate.bootstrap {
            Task { @MainActor in
                await AdapterProbe.probeAll(into: boot.registry)
                boot.server.start()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            if let boot = AppDelegate.bootstrap {
                await boot.processes.terminateAll()
                boot.server.stop()
            }
        }
    }
}
