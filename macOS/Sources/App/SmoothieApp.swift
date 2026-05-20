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
        // Sweep up orphans from prior `kill -9` events. macOS doesn't give us
        // PR_SET_PDEATHSIG, and Xcode debug stops leave subprocesses
        // re-parented to launchd. Match by the exact spawn signatures we use
        // so we don't touch anything the user runs themselves.
        Self.killOrphanSubprocesses()
        if let boot = AppDelegate.bootstrap {
            Task { @MainActor in
                await AdapterProbe.probeAll(into: boot.registry)
                boot.server.start()
            }
        }
    }

    private static func killOrphanSubprocesses() {
        // Each pattern is matched against the full argv. Kept narrow so we
        // only hit subprocesses spawned by a previous Smoothie daemon — never
        // the user's own `opencode`, `claude`, etc. that they might run by
        // hand in a terminal.
        let patterns = [
            "opencode serve --port 0 --print-logs",
            "claude -p --output-format stream-json --input-format stream-json",
        ]
        for pattern in patterns {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            task.arguments = ["-9", "-f", pattern]
            task.standardOutput = Pipe()
            task.standardError = Pipe()
            do { try task.run(); task.waitUntilExit() } catch { /* best-effort */ }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // AppKit doesn't wait for async Tasks here — we'd return before the
        // SIGTERM was sent and orphan our subprocesses (we hit this with
        // stale `opencode serve` workers piling up across debug sessions).
        // Send SIGTERM synchronously first, then schedule the rest of
        // cleanup best-effort.
        if let boot = AppDelegate.bootstrap {
            boot.processes.terminateAllSync()
            boot.server.stop()
        }
    }
}
