import SwiftUI

/// Re-applies the user's theme override (System / Light / Dark) to a
/// view subtree. The modifier on `SmoothieApp`'s WindowGroup covers the
/// primary navigation tree, but sheets and fullScreenCovers in SwiftUI
/// create their own UIHostingController and on iOS 26 don't reliably
/// inherit the root's `preferredColorScheme`. Sheet roots tag themselves
/// with `.smoothieThemed()` so the chosen scheme follows them.
///
/// Implemented as a separate `ViewModifier` rather than a one-line
/// inline call so Observation registers a dependency on `SettingsStore`
/// at the modifier's body site, not at the host view's, which keeps the
/// theme switch re-rendering the sheet content without dismiss.
struct SmoothieThemedModifier: ViewModifier {
    @Environment(SettingsStore.self) private var settings

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(settings.theme.colorScheme)
            .tint(SmoothieColor.accent)
    }
}

extension View {
    func smoothieThemed() -> some View {
        modifier(SmoothieThemedModifier())
    }
}
