import Foundation
import Observation

/// User-added project roots that aren't auto-discovered by the server's
/// `/projects` endpoint. Persisted in UserDefaults as an ordered list.
@MainActor
@Observable
final class CustomProjectsStore {
    private static let key = "smoothie.customProjects"

    private(set) var paths: [String]

    init() {
        if let stored = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            self.paths = stored
        } else {
            self.paths = []
        }
    }

    func add(_ path: String) {
        guard !paths.contains(path) else { return }
        paths.insert(path, at: 0)
        persist()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    func contains(_ path: String) -> Bool {
        paths.contains(path)
    }

    /// Materialize as `ProjectDTO` entries (we infer name from last path component and isGit must be enriched separately).
    func asProjects() -> [ProjectDTO] {
        paths.map { p in
            ProjectDTO(
                name: (p as NSString).lastPathComponent,
                path: p,
                isGit: FileManager.default.fileExists(atPath: (p as NSString).appendingPathComponent(".git"))
            )
        }
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: Self.key)
    }
}
