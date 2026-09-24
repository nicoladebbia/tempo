//
// MealPlanScheduleEnforcer.swift
// Tempo
//
// Deterministic guard applied to the AI's weekly plan BEFORE macro scaling.
// The prompt asks the model to honor the eating window and the onboarding
// "I skip breakfast" answer, but a prompt is a request, not a guarantee:
//   - breakfastSkipped → drop mealNumber 1 (as long as the day keeps at least
//     one other meal); the day-total scaler that runs next re-spreads the
//     calories over the remaining meals so the day target still holds.
//   - every scheduledTime is clamped into the eating window.
// postWorkoutMandatory can't be enforced here (we can't invent a meal) — it
// is carried by the prompt only.
//

import Foundation

enum MealPlanScheduleEnforcer {
    struct Slot: Equatable, Sendable {
        let mealNumber: Int
        let scheduledTime: String
    }

    /// Returns the slots to keep, as (original index, corrected time) pairs,
    /// preserving the input order.
    static func enforce(
        _ slots: [Slot],
        window: EatingWindow,
        breakfastSkipped: Bool
    ) -> [(index: Int, scheduledTime: String)] {
        let hasNonBreakfast = slots.contains { $0.mealNumber != 1 }
        return slots.enumerated().compactMap { index, slot in
            if breakfastSkipped, slot.mealNumber == 1, hasNonBreakfast {
                return nil
            }
            let time = window.isValid ? window.clamp(slot.scheduledTime) : slot.scheduledTime
            return (index, time)
        }
    }
}
