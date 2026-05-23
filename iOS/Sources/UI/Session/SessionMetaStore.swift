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
    /// Bump when SessionMeta gains a non-optional field. The init reads
    /// the envelope's version and only treats the entries as usable if
    /// it matches; mismatches fall back to a fresh map but the raw
    /// payload is preserved in a backup key so the user can recover
    /// titles manually if needed.
    private static let schemaVersion = 1
    private static let backupKey = "smoothie.sessionMeta.backup"

    /// On-disk envelope. Existing v1 blobs decode cleanly because the
    /// extra `version` field is decoded with a default; missing keys
    /// in the dictionary entries are tolerated by SessionMeta's
    /// `Codable` since all fields except `updatedAt` are easy to back-
    /// fill, and `updatedAt` has `init(from:)` defaulting on absence.
    private struct Envelope: Codable {
        var version: Int
        var entries: [String: SessionMeta]
    }

    private var entries: [String: SessionMeta]

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.key) else {
            self.entries = [:]
            return
        }
        let decoder = JSONDecoder()
        // Try the v2+ envelope first.
        if let envelope = try? decoder.decode(Envelope.self, from: data),
           envelope.version == Self.schemaVersion {
            self.entries = envelope.entries
            return
        }
        // Legacy: pre-envelope blobs are a raw [String: SessionMeta] map.
        // Keep them on schemaVersion == 1 so existing installs migrate
        // silently. If the legacy decode ALSO fails, stash the raw
        // payload in a backup key for diagnosis and start fresh — DO
        // NOT silently drop unrecoverable user data.
        if let legacy = try? decoder.decode([String: SessionMeta].self, from: data) {
            self.entries = legacy
            return
        }
        UserDefaults.standard.set(data, forKey: Self.backupKey)
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
        // Also drop any diagnostic backup from a previous decode
        // failure so "Delete local data" actually leaves no trace.
        UserDefaults.standard.removeObject(forKey: Self.backupKey)
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
        let envelope = Envelope(version: Self.schemaVersion, entries: entries)
        if let data = try? JSONEncoder().encode(envelope) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
