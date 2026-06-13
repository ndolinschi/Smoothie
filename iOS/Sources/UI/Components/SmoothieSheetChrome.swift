import SwiftUI

/// Shared presentation chrome for the NavigationStack-based sheets
/// (model/branch/MCP/repo pickers, Create-PR, mention, past-chats, etc.).
/// Before this, each sheet repeated the same three presentation modifiers
/// plus `.smoothieThemed()`; this collapses that into one call so the
/// detents and corner radius stay consistent and a change lands in one
/// place.
///
/// It deliberately does NOT impose a navigation bar or toolbar — those
/// vary per sheet (Done vs Cancel/Save, leading vs trailing) — so callers
/// keep their own `NavigationStack { … .toolbar { … } }` and just append
/// `.smoothieSheetChrome()`.
extension View {
    /// Apply the standard medium/large detents, 20pt corner, drag
    /// indicator, and theme propagation used across Smoothie's sheets.
    /// Pass `large: true` for sheets that should open fully expanded
    /// (diff review, full model list) with no medium stop.
    func smoothieSheetChrome(large: Bool = false) -> some View {
        modifier(SmoothieSheetChrome(large: large))
    }
}

private struct SmoothieSheetChrome: ViewModifier {
    let large: Bool

    func body(content: Content) -> some View {
        content
            .presentationDetents(large ? [.large] : [.medium, .large])
            .presentationCornerRadius(20)
            .presentationDragIndicator(.visible)
            .smoothieThemed()
    }
}
