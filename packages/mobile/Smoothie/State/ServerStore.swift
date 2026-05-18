import Foundation
import Observation

@MainActor
@Observable
final class ServerStore {
    private static let key = "smoothie.serverURL"

    var serverURL: URL?
    var api: API?
    var health: HealthResponse?
    var isConnected: Bool { health != nil }
    var lastError: String?

    private var pollTask: Task<Void, Never>?

    init() {
        if let s = UserDefaults.standard.string(forKey: Self.key),
           let url = URL(string: s) {
            self.serverURL = url
            self.api = API(baseURL: url)
        }
    }

    func setServerURL(_ url: URL?) async {
        serverURL = url
        if let url {
            UserDefaults.standard.set(url.absoluteString, forKey: Self.key)
            api = API(baseURL: url)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            api = nil
        }
        health = nil
        lastError = nil
        await refresh()
        startPolling()
    }

    func startPolling() {
        pollTask?.cancel()
        guard api != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let api else { return false }
        do {
            let h = try await api.health()
            health = h
            lastError = nil
            return true
        } catch {
            health = nil
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
