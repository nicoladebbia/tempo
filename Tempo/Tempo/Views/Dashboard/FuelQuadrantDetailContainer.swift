//
// FuelQuadrantDetailContainer.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import SwiftData
import SwiftUI

/// Thin container that owns the `FuelDayScheduleViewModel` lifecycle and
/// feeds annotated rows into `FuelQuadrantDetailView`. Kept separate so the
/// detail view stays a dumb renderer that's easy to preview.
struct FuelQuadrantDetailContainer: View {
    let fuelData: FuelQuadrantData

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var scheduleVM: FuelDayScheduleViewModel?
    @State
    private var calorieTrend: [DailyEatenTotals] = []

    var body: some View {
        FuelQuadrantDetailView(
            data: fuelData,
            mealRows: scheduleVM?.rows ?? [],
            shiftMinutes: scheduleVM?.shiftMinutes ?? 0,
            calorieTrend: calorieTrend
        )
        .task {
            if scheduleVM == nil {
                scheduleVM = FuelDayScheduleViewModel(
                    healthKit: services.healthKit,
                    calendar: services.calendar
                )
            }
            calorieTrend = EatenNutritionHistory.dailyTotals(in: modelContext)
            await scheduleVM?.refresh(modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoNutritionLogged)) { _ in
            // Re-pull the annotated rows when a meal is logged elsewhere
            // so this detail sheet's calories + eat-times stay live while
            // it's open.
            calorieTrend = EatenNutritionHistory.dailyTotals(in: modelContext)
            Task { await scheduleVM?.refresh(modelContext: modelContext) }
        }
    }
}
