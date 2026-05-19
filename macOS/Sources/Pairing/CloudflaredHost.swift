import Foundation
import Observation

/// Wraps a `cloudflared tunnel --url http://127.0.0.1:<port>` child process so
/// the Smoothie HTTP server (which binds to 127.0.0.1) becomes reachable
/// from anywhere over HTTPS without router config or external accounts.
///
/// Cloudflare assigns a one-off URL like `https://<random>.trycloudflare.com`
/// per invocation. We parse it out of cloudflared's stderr and surface it
/// via `publicURL`. PairingService rewrites the QR payload when it's set.
@MainActor
@Observable
final class CloudflaredHost {
    enum Status: Sendable {
        case off
        case starting
        case running(URL)
        case failed(String)
    }

    private(set) var status: Status = .off
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var logBuffer = Data()

    private let localPort: Int

    init(localPort: Int) {
        self.localPort = localPort
    }

    /// Returns the resolved `cloudflared` binary path, or `nil` if not
    /// installed. Same lookup pattern as Tailscale / Claude / other CLIs.
    static func locateBinary() -> String? {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/cloudflared",
            "/opt/homebrew/bin/cloudflared",
            "/usr/local/bin/cloudflared",
            "/usr/bin/cloudflared",
        ]
        for p in candidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return nil
    }

    var isInstalled: Bool { Self.locateBinary() != nil }

    func start() {
        guard case .off = status else { return }
        guard let bin = Self.locateBinary() else {
            status = .failed("`cloudflared` is not installed. Run `brew install cloudflared` and try again.")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = [
            "tunnel",
            "--no-autoupdate",
            "--url", "http://127.0.0.1:\(localPort)",
        ]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        let weakSelfRef = WeakBox(self)
        out.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.absorbLog(data) }
        }
        err.fileHandleForReading.readabilityHandler = { fh in
            let data = fh.availableData
            if data.isEmpty { return }
            Task { @MainActor in weakSelfRef.value?.absorbLog(data) }
        }
        proc.terminationHandler = { p in
            let code = p.terminationStatus
            Task { @MainActor in weakSelfRef.value?.handleTermination(code: code) }
        }

        do {
            try proc.run()
            self.process = proc
            self.stdoutPipe = out
            self.stderrPipe = err
            self.logBuffer = Data()
            self.status = .starting
        } catch {
            self.status = .failed("Couldn't launch cloudflared: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            status = .off
            return
        }
        proc.terminate()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        }
    }

    // MARK: - Log parsing

    private func absorbLog(_ data: Data) {
        logBuffer.append(data)
        guard let text = String(data: logBuffer, encoding: .utf8) else { return }
        logBuffer.removeAll(keepingCapacity: true)

        if case .running = status { return } // already resolved

        // cloudflared prints a banner with the assigned URL once the tunnel
        // is ready. Matches `https://<words>.trycloudflare.com` (or
        // potentially a custom domain — we keep the regex generic).
        let pattern = #"https?://[A-Za-z0-9.-]+\.trycloudflare\.com"#
        if let range = text.range(of: pattern, options: .regularExpression),
           let url = URL(string: String(text[range])) {
            status = .running(url)
        }
    }

    private func handleTermination(code: Int32) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        stdoutPipe = nil
        stderrPipe = nil

        switch status {
        case .running:
            status = .off
        case .starting:
            status = .failed("cloudflared exited before reporting a URL (code \(code)).")
        case .failed, .off:
            break
        }
    }
}

@MainActor
private final class WeakBox {
    weak var value: CloudflaredHost?
    init(_ value: CloudflaredHost) { self.value = value }
}
