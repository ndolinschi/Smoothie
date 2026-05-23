import Foundation
import Observation

/// Per-session local-only metadata: user-set title, archive flag, pin flag.
/// Persisted in UserDefaults (key `smoothie.sessionMeta.v1`) so it survives
/// app restarts but never leaves the phone — the Mac daemon doesn't know
/// about these fields. Capped at 500 entries; the oldest-touched are
/// evicted on write. "Delete local data" in SettingsView clears the whole
/// map (P27.f).
@MainActor
@Observable
final class SessionMetaStore {
    struct SessionMeta: Codable, Equatable {
        var title: String?
        var archived: Bool
        var pinned: Bool
        var updatedAt: Date

        static let empty = SessionMeta(title: nil, archived: false, pinned: false, updatedAt: .distantPast)

        var isDefault: Bool {
            title == nil && !archived && !pinned
        }
    }

    private static let key = "smoothie.sessionMeta.v1"
    private static let cap = 500

    private var entries: [String: SessionMeta]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([String: SessionMeta].self, from: data) {
            self.entries = decoded
            return
        }
        self.entries = [:]
    }

    // MARK: - Reads

    func meta(for sessionId: String) -> SessionMeta {
        entries[sessionId] ?? .empty
    }

    /// User-set title if non-empty, else the descriptor's projectName.
    /// Call sites use this in place of `session.projectName` so the
    /// rename surfaces everywhere (HomeView row label, etc.).
    func displayName(for sessionId: String, fallback: String) -> String {
        if let t = entries[sessionId]?.title, !t.isEmpty { return t }
        return fallback
    }

    func isArchived(_ sessionId: String) -> Bool {
        entries[sessionId]?.archived ?? false
    }

    func isPinned(_ sessionId: String) -> Bool {
        entries[sessionId]?.pinned ?? false
    }

    // MARK: - Writes

    func setTitle(_ title: String?, for sessionId: String) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalised = (trimmed?.isEmpty == false) ? trimmed : nil
        mutate(sessionId) { $0.title = normalised }
    }

    func setArchived(_ archived: Bool, for sessionId: String) {
        mutate(sessionId) { $0.archived = archived }
    }

    func setPinned(_ pinned: Bool, for sessionId: String) {
        mutate(sessionId) { $0.pinned = pinned }
    }

    func clearAll() {
        entries.removeAll()
        persistInline()
    }

    // MARK: - Internals

    private func mutate(_ sessionId: String, _ change: (inout SessionMeta) -> Void) {
        var current = entries[sessionId] ?? .empty
        change(&current)
        current.updatedAt = Date()
        if current.isDefault {
            // Don't keep all-default rows around — they're equivalent to "no entry".
            entries.removeValue(forKey: sessionId)
        } else {
            entries[sessionId] = current
        }
        evictIfNeeded()
        persistInline()
    }

    private func evictIfNeeded() {
        guard entries.count > Self.cap else { return }
        let surplus = entries.count - Self.cap
        let oldest = entries
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(surplus)
        for (k, _) in oldest {
            entries.removeValue(forKey: k)
        }
    }

    private func persistInline() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
