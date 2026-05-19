import Foundation
import Observation

/// UserDefaults-backed list of pinned + recently-used project paths. Mirrors
/// the "Recents" section in Cursor's "Run Cursor anywhere…" picker. Capped at
/// 20 entries.
@MainActor
@Observable
final class RecentsStore {
    private static let key = "smoothie.recents"
    private static let cap = 20

    private(set) var paths: [String]

    init() {
        if let stored = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            self.paths = stored
        } else {
            self.paths = []
        }
    }

    func touch(_ path: String) {
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > Self.cap { paths.removeLast(paths.count - Self.cap) }
        persist()
    }

    func remove(_ path: String) {
        paths.removeAll { $0 == path }
        persist()
    }

    func clear() {
        paths.removeAll()
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(paths, forKey: Self.key)
    }
}
