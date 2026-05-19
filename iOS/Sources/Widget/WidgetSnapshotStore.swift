import Foundation

/// File-backed exchange channel between the host app and the widget extension.
/// The host writes the latest live-session state into the App Group container
/// after every state change; the widget reads it inside the TimelineProvider.
///
/// Group identifier `group.dev.smoothie.shared` must be present in both
/// targets' entitlements. If the entitlement is absent (e.g. free Apple
/// Developer account without App Group provisioning) `containerURL` returns
/// `nil` and every operation silently no-ops — the widget falls back to the
/// `WidgetSnapshot.placeholder`.
public enum WidgetSnapshotStore {
    public static let appGroup = "group.dev.smoothie.shared"
    public static let filename = "widgetState.json"

    public static func read() -> WidgetSnapshot {
        guard let url = fileURL() else { return .placeholder }
        guard let data = try? Data(contentsOf: url) else { return .placeholder }
        return (try? JSONDecoder().decode(WidgetSnapshot.self, from: data)) ?? .placeholder
    }

    @discardableResult
    public static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = fileURL() else { return false }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(filename)
    }
}
