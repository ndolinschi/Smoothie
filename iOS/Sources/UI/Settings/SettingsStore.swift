import Foundation
import SwiftUI
import Observation

/// User-facing iOS preferences. Persisted in UserDefaults; cleared by
/// SettingsView's "Delete local data" along with the other smoothie.* keys.
/// Injected into the app environment in SmoothieApp.
@MainActor
@Observable
final class SettingsStore {
    enum ThemeOverride: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light:  return "Light"
            case .dark:   return "Dark"
            }
        }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }

    static let themeKey = "smoothie.theme.v1"

    var theme: ThemeOverride {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey) }
    }

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.themeKey) ?? ThemeOverride.system.rawValue
        self.theme = ThemeOverride(rawValue: raw) ?? .system
    }

    /// Wipe every UserDefaults key the iOS app owns. Called from
    /// SettingsView's destructive "Delete local data" button.
    func clearLocalData(recents: RecentsStore, sessionMeta: SessionMetaStore) {
        recents.clear()
        sessionMeta.clearAll()
        UserDefaults.standard.removeObject(forKey: "smoothie.homeTipDismissed")
        // Reset theme to .system first — didSet rewrites the key —
        // THEN remove the key so it's actually absent on disk. The
        // in-memory `theme` stays .system so the UI doesn't flicker.
        // Order matters: doing removeObject before the assignment
        // would let didSet immediately re-add it.
        theme = .system
        UserDefaults.standard.removeObject(forKey: Self.themeKey)
    }
}
