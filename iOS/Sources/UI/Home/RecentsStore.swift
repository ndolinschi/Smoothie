import Foundation
import Observation

/// UserDefaults-backed timestamped path map. Each path is stored with the
/// `Date` it was last touched so the picker can render "Opened 2h ago"
/// sublabels and HomeView can sort by recency. Capped at 20 entries; oldest
/// rows are evicted first when the cap is exceeded.
///
/// Migration: a prior version of the app persisted a plain `[String]` under
/// `smoothie.recents`. We read that on first launch, stamp each entry with
/// `now`, and persist into the new key.
@MainActor
@Observable
final class RecentsStore {
    private static let key = "smoothie.recents.v2"
    private static let legacyKey = "smoothie.recents"
    private static let cap = 20

    private var timestamps: [String: Date]

    /// Paths sorted by most-recent first. Mirrors the prior `paths` API so
    /// HomeView / FolderPickerSheet keep compiling.
    var paths: [String] {
        timestamps.keys.sorted { a, b in
            (timestamps[a] ?? .distantPast) > (timestamps[b] ?? .distantPast)
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.timestamps = decoded
            return
        }
        if let legacy = UserDefaults.standard.array(forKey: Self.legacyKey) as? [String] {
            let now = Date()
            self.timestamps = Dictionary(uniqueKeysWithValues: legacy.map { ($0, now) })
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
            persistInline()
            return
        }
        self.timestamps = [:]
    }

    func touch(_ path: String) {
        timestamps[path] = Date()
        if timestamps.count > Self.cap {
            let oldest = timestamps.sorted { ($0.value) < ($1.value) }
            for (k, _) in oldest.prefix(timestamps.count - Self.cap) {
                timestamps.removeValue(forKey: k)
            }
        }
        persistInline()
    }

    func remove(_ path: String) {
        timestamps.removeValue(forKey: path)
        persistInline()
    }

    func clear() {
        timestamps.removeAll()
        persistInline()
    }

    func lastOpened(_ path: String) -> Date? { timestamps[path] }

    private func persistInline() {
        if let data = try? JSONEncoder().encode(timestamps) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
