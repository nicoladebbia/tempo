import SwiftUI

// MARK: - Accessibility Extensions
// Per DESIGN_SYSTEM.md Section 4.3 — Dynamic Type support.
// Per BUILD_PLAN Step 19.1 — Dark Mode + Dynamic Type Audit.

extension View {
    /// Caps dynamic type scaling for large display elements (score, timer, XP).
    /// Prevents display elements from scaling beyond readability at AX sizes.
    func tempoDisplayCapped() -> some View {
        self.dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Prevents dynamic type scaling entirely — use only for elements where
    /// scaling would break layout (ring labels, widget-like compact areas).
    func tempoFixedSize() -> some View {
        self.dynamicTypeSize(.large...DynamicTypeSize.large)
    }
}

// MARK: - Reduced Motion Support

extension View {
    /// Conditionally applies animation, respecting Reduce Motion accessibility setting.
    func tempoAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        self.modifier(ReducedMotionAnimationModifier(animation: animation, value: value))
    }
}

private struct ReducedMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}
