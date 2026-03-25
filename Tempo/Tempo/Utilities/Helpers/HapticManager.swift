import UIKit

// MARK: - Haptic Manager
// Per SOUND_AND_HAPTICS.md Section 4 — Complete haptic catalog.
// Centralized haptic feedback for all interactions.

enum HapticManager {

    // MARK: - Impact

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func lightImpact() {
        impact(.light)
    }

    static func mediumImpact() {
        impact(.medium)
    }

    static func heavyImpact() {
        impact(.heavy)
    }

    // MARK: - Notification

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }

    static func success() {
        notification(.success)
    }

    static func warning() {
        notification(.warning)
    }

    static func error() {
        notification(.error)
    }

    // MARK: - Selection

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: - Workout Haptics
    // Per SOUND_AND_HAPTICS.md Section 4.2

    /// Set completed — sharp medium impact
    static func setComplete() {
        impact(.medium)
    }

    /// Exercise completed — double medium impact
    static func exerciseComplete() {
        impact(.medium)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            impact(.medium)
        }
    }

    /// Workout started — heavy impact
    static func workoutStart() {
        impact(.heavy)
    }

    /// Workout completed — success notification
    static func workoutComplete() {
        notification(.success)
    }

    /// PR achieved — triple heavy impact (celebration)
    static func prAchieved() {
        impact(.heavy)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            impact(.heavy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            notification(.success)
        }
    }

    /// Rest timer tick (last 5 seconds) — light impact
    static func restTick() {
        impact(.light)
    }

    /// Rest timer done — double notification
    static func restDone() {
        notification(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            impact(.heavy)
        }
    }

    // MARK: - Timer Haptics

    /// Focus timer start
    static func timerStart() {
        impact(.medium)
    }

    /// Focus timer complete — success
    static func timerComplete() {
        notification(.success)
    }

    // MARK: - Arena Haptics

    /// XP earned — light impact
    static func xpGain() {
        impact(.light)
    }

    /// Level up — triple success
    static func levelUp() {
        notification(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            notification(.success)
        }
    }

    /// Achievement unlocked
    static func achievementUnlocked() {
        notification(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            impact(.medium)
        }
    }

    // MARK: - System Haptics

    /// Non-negotiable completed — success
    static func nonNegotiableComplete() {
        notification(.success)
    }

    /// Leisure unlocked — double success
    static func leisureUnlocked() {
        notification(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            notification(.success)
        }
    }

    /// Streak fire — medium impact
    static func streakFire() {
        impact(.medium)
    }
}
