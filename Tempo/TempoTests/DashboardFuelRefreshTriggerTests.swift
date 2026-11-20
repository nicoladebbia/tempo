@testable import Tempo
import Foundation
import Testing

@MainActor
struct DashboardFuelRefreshTriggerTests {
    /// Regression: the Fuel quadrant kept the pre-plan TDEE-estimate target
    /// (3,156 kcal) after a server week was applied while Nutrition Today showed
    /// the plan's 2,975, because the Dashboard never heard `.tempoWeeklyPlanApplied`.
    @Test func fuelQuadrantRefreshesWhenTodaysTargetMoves() {
        let triggers = DashboardViewModel.fuelRefreshTriggers
        #expect(triggers.contains(.tempoNutritionLogged))
        #expect(triggers.contains(.tempoWeeklyPlanApplied))
        #expect(triggers.contains(.tempoDietaryProfileChanged))
    }
}
