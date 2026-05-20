import Foundation
import Observation
import Shared

/// Persisted preferences (JSON at ~/Library/Application Support/Smoothie/
/// preferences.json). Holds the user's allowed project roots and per-provider
/// default model. Read at startup, written through every mutation.
@MainActor
@Observable
final class Preferences {
    struct Stored: Codable {
        var allowedRoots: [String]
        var defaultModelByCli: [String: String]
        var geminiFlashApiKey: String?

        static var defaults: Stored {
            let home = NSHomeDirectory()
            let candidates = [
                "\(home)/Developer",
                "\(home)/Projects",
                "\(home)/Documents",
            ]
            let existing = candidates.filter { FileManager.default.fileExists(atPath: $0) }
            return Stored(
                allowedRoots: existing.isEmpty ? [home] : existing,
                defaultModelByCli: [:],
                geminiFlashApiKey: nil
            )
        }
    }

    private(set) var stored: Stored

    var allowedRoots: [String] { stored.allowedRoots }
    var defaultModelByCli: [String: String] { stored.defaultModelByCli }
    var geminiFlashApiKey: String? { stored.geminiFlashApiKey }

    private let url: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Smoothie", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("preferences.json")

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Stored.self, from: data) {
            self.stored = decoded
        } else {
            self.stored = .defaults
            persist()
        }
    }

    func setDefaultModel(_ model: String?, for cli: CLIType) {
        if let model {
            stored.defaultModelByCli[cli.name] = model
        } else {
            stored.defaultModelByCli.removeValue(forKey: cli.name)
        }
        persist()
    }

    func addRoot(_ path: String) {
        let normalized = (path as NSString).standardizingPath
        if !stored.allowedRoots.contains(normalized) {
            stored.allowedRoots.append(normalized)
            persist()
        }
    }

    func removeRoot(_ path: String) {
        stored.allowedRoots.removeAll { $0 == path }
        persist()
    }

    func setGeminiFlashApiKey(_ key: String?) {
        stored.geminiFlashApiKey = key?.isEmpty == true ? nil : key
        persist()
    }

    // MARK: - Path validation

    func isPathAllowed(_ path: String) -> Bool {
        let normalized = (path as NSString).standardizingPath
        let resolved = (normalized as NSString).resolvingSymlinksInPath
        if resolved.contains("/..") { return false }
        return stored.allowedRoots.contains { root in
            resolved == root || resolved.hasPrefix(root + "/")
        }
    }

    // MARK: - Apply defaults

    func applyDefaults(to request: CreateSessionRequest) -> CreateSessionRequest {
        let model = request.model ?? stored.defaultModelByCli[request.cli.name]
        return CreateSessionRequest(
            projectPath: request.projectPath,
            cli: request.cli,
            model: model,
            reasoningEffort: request.reasoningEffort,
            mode: request.mode,
            providerSessionId: request.providerSessionId
        )
    }

    // MARK: - Persistence

    private func persist() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(stored) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
