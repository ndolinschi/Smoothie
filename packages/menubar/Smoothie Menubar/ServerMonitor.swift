import Foundation
import Observation
import AppKit

// MARK: - Wire types (subset of the server's models)

struct HealthAdapter: Codable, Sendable, Identifiable {
    var id: String { cli }
    let cli: String
    let installed: Bool
    let version: String?
    let supported: Bool
}

struct HealthResponse: Codable, Sendable {
    let version: String
    let uptime: Double
    let bindAddress: String
    let adapters: [HealthAdapter]
}

struct SessionInfo: Codable, Sendable, Identifiable {
    let id: String
    let projectPath: String
    let projectName: String
    let cli: String
    let state: String
    let createdAt: Double
}

// MARK: - Monitor

@MainActor
@Observable
final class ServerMonitor {
    var serverURL: URL = URL(string: "http://127.0.0.1:7749")!

    private(set) var isHealthy: Bool = false
    private(set) var health: HealthResponse?
    private(set) var sessions: [SessionInfo] = []
    private(set) var lastError: String?

    var serverDisplay: String { health?.bindAddress ?? "—" }
    var versionDisplay: String { health.map { "v\($0.version)" } ?? "" }
    var uptimeDisplay: String {
        guard let h = health else { return "" }
        let s = Int(h.uptime)
        let hh = s / 3600, mm = (s / 60) % 60, ss = s % 60
        if hh > 0 { return String(format: "%dh %02dm", hh, mm) }
        if mm > 0 { return String(format: "%dm %02ds", mm, ss) }
        return "\(ss)s"
    }

    private var pollTask: Task<Void, Never>?

    init() {
        start()
    }

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let h = try await fetch(HealthResponse.self, path: "/health")
            health = h
            isHealthy = true
            lastError = nil

            let s = try await fetch([SessionInfo].self, path: "/sessions")
            sessions = s
        } catch {
            isHealthy = false
            sessions = []
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetch<T: Decodable>(_ type: T.Type, path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: serverURL)?.absoluteURL else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: cfg)
        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Actions

    func openLogs() {
        let path = "\(NSHomeDirectory())/Library/Logs/Smoothie/smoothie.err.log"
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else {
            // Fallback: open the Smoothie logs folder if present, else show alert
            let folder = "\(NSHomeDirectory())/Library/Logs/Smoothie"
            if FileManager.default.fileExists(atPath: folder) {
                NSWorkspace.shared.open(URL(fileURLWithPath: folder))
            } else {
                let alert = NSAlert()
                alert.messageText = "No log file yet"
                alert.informativeText = "Logs appear here once the server runs via the LaunchAgent installer (scripts/install-launchagent.sh)."
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
    }

    func openServerInBrowser() {
        NSWorkspace.shared.open(serverURL.appendingPathComponent("health"))
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
