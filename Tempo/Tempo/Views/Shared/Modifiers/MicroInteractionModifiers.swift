//
// MicroInteractionModifiers.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - PressScaleModifier

// Per DESIGN_SYSTEM.md Section 8 — Motion system.
// Per BUILD_PLAN Step 19.2 — Button press scales, card tap highlight, tab switch animation.

struct PressScaleModifier: ViewModifier {
    @State
    private var isPressed = false
    @Environment(\.accessibilityReduceMotion)
    var reduceMotion
    let scale: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && !reduceMotion ? scale : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}

extension View {
    /// Adds a subtle press-scale micro-interaction. Per DESIGN_SYSTEM.md motion.
    func pressScale(_ scale: CGFloat = 0.96) -> some View {
        modifier(PressScaleModifier(scale: scale))
    }
}

// MARK: - AppearAnimationModifier

struct AppearAnimationModifier: ViewModifier {
    @State
    private var isVisible = false
    @Environment(\.accessibilityReduceMotion)
    var reduceMotion
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (isVisible ? 1 : 0))
            .offset(y: reduceMotion ? 0 : (isVisible ? 0 : 12))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(delay), value: isVisible)
            .onAppear { isVisible = true }
    }
}

extension View {
    /// Fade-slide-in on appear. Respects Reduce Motion.
    func appearAnimation(delay: Double = 0) -> some View {
        modifier(AppearAnimationModifier(delay: delay))
    }
}

// MARK: - ScoreRingAnimationModifier

struct ScoreRingAnimationModifier: ViewModifier {
    @State
    private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion)
    var reduceMotion
    let targetProgress: Double

    func body(content: Content) -> some View {
        content
            .onAppear {
                if reduceMotion {
                    animatedProgress = targetProgress
                } else {
                    withAnimation(.easeOut(duration: 1.0)) {
                        animatedProgress = targetProgress
                    }
                }
            }
    }
}

// MARK: - CelebrationShakeModifier

struct CelebrationShakeModifier: ViewModifier {
    @State
    private var shakeOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion)
    var reduceMotion

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
    }

    func trigger() {
        guard !reduceMotion else {
            return
        }
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 5)) {
            shakeOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.interpolatingSpring(stiffness: 300, damping: 5)) {
                shakeOffset = 0
            }
        }
    }
}
