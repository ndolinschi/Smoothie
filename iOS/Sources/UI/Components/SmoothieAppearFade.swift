import SwiftUI

/// P29 §7 — Gentle scroll-reveal modifier.
///
/// Applies an opacity + translateY fade-in when the view first appears.
/// Used to bring polish to top-level dashboard sections and onboarding
/// surfaces (provider strip, stat tiles, heatmap, terminal install card,
/// session group headers).
///
/// Apply only to **sections**, not individual rows — staggering hundreds
/// of session rows would chatter on first paint.
///
/// Honours `@Environment(\.accessibilityReduceMotion)`: when the system
/// toggle is on, the modifier becomes a no-op (jumps straight to the
/// final state with no animation).
struct SmoothieAppearFadeModifier: ViewModifier {
    let delay: Double
    let yOffset: CGFloat
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : yOffset)
            .onAppear {
                guard !hasAppeared else { return }
                if reduceMotion {
                    hasAppeared = true
                    return
                }
                // Slight delay so SwiftUI has a frame to settle the
                // initial layout — without it, the first paint can
                // skip the animation entirely.
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: duration)) {
                        hasAppeared = true
                    }
                }
            }
    }
}

extension View {
    /// Apply a soft fade-in + lift-up animation when this view first
    /// appears. Pass `delay` to stagger sibling sections.
    func smoothieAppearFade(
        delay: Double = 0,
        yOffset: CGFloat = 8,
        duration: Double = 0.28
    ) -> some View {
        modifier(SmoothieAppearFadeModifier(
            delay: delay,
            yOffset: yOffset,
            duration: duration
        ))
    }
}
