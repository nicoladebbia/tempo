//
// NutritionLogView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - NutritionLogView

// The Log tab: what was logged today (open, edit, delete with Undo, keep as a
// favourite) and ONE button to log more. Logging itself lives on the capture
// screen (`MealLoggingView`): favourites, the usual, search, scan, photo, voice
// and a typed line, all in one place.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionLogView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Binding
    var showMealLogging: Bool
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    /// Logged meal opened for editing (tap on a row).
    @State
    private var detailMeal: PlannedMeal?
    @State
    private var showFoodCheck = false
    @State
    private var toast: ToastData?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                loggedTodaySection
                checkFoodRow
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s4)
            // Pin the content to the screen width so it only scrolls up and down.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        // The one way to log, under the thumb.
        .fuelBottomBar {
            Button {
                HapticManager.lightImpact()
                showMealLogging = true
            } label: {
                Label("Log a meal", systemImage: "plus")
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("log.logMeal")
        }
        .navigationDestination(item: $detailMeal) { meal in
            MealDetailView(meal: meal)
        }
        .sheet(isPresented: $showFoodCheck) {
            FoodCheckView()
        }
        .fuelToast($toast)
    }

    // MARK: - Logged today (delete a wrong log)

    private var loggedToday: [PlannedMeal] {
        viewModel.todayMeals
            .filter { $0.status == .eaten }
            .sorted { ($0.actualEatenAt ?? .distantPast) > ($1.actualEatenAt ?? .distantPast) }
    }

    @ViewBuilder
    private var loggedTodaySection: some View {
        let meals = loggedToday
        if meals.isEmpty {
            loggedEmptyState
        } else {
            LoggedMealsList(
                meals: meals,
                onOpen: { detailMeal = $0 },
                onDelete: { undoLog($0) },
                onSavePreset: { saveFavouriteFromLog($0) }
            )
        }
    }

    private var loggedEmptyState: some View {
        FuelEmptyState(
            icon: "fork.knife.circle",
            title: String(localized: "Nothing logged yet today"),
            message: String(localized: "Tap Log a meal: your usual, a search, a scan, a photo or a typed line. It lands here.")
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("loggedTodayEmpty")
    }

    /// "Not sure it fits your day?" The food check, kept apart from logging.
    private var checkFoodRow: some View {
        FuelRowGroup {
            FuelActionRow(
                icon: "checkmark.seal",
                title: String(localized: "Check a food"),
                detail: String(localized: "See if it fits your day before you eat it")
            ) {
                HapticManager.lightImpact()
                showFoodCheck = true
            }
            .accessibilityIdentifier("nutritionCheckFood")
        }
    }

    /// Keeps a logged meal as a favourite: pinned at the top of the capture
    /// screen, one tap from logging again.
    private func saveFavouriteFromLog(_ meal: PlannedMeal) {
        let foods = meal.foods
        let saved = viewModel.savePreset(
            from: meal,
            name: foods.count == 1 ? foods[0].name : meal.mealName,
            modelContext: modelContext,
            pinned: true
        )
        toast = saved
            ? ToastData(message: String(localized: "Saved as a favourite."), style: .success)
            : ToastData(message: String(localized: "Couldn't save that favourite. Try again."), style: .error)
    }

    /// Delete a wrong log (or take a plan slot back) with a 5-second Undo.
    private func undoLog(_ meal: PlannedMeal) {
        let name = meal.displayMealName
        guard let snapshot = viewModel.undoMealEaten(
            meal, modelContext: modelContext, notifications: services.notifications
        )
        else {
            toast = ToastData(message: String(localized: "Couldn't undo \(name). Try again."), style: .error)
            return
        }
        let message = snapshot.kind == .removed ? String(localized: "\(name) log deleted.") : String(localized: "\(name) is back on the plan.")
        toast = ToastData(message: message, style: .info, actionTitle: String(localized: "Undo")) {
            if !viewModel.restoreLog(snapshot, modelContext: modelContext, notifications: services.notifications) {
                toast = ToastData(message: String(localized: "Couldn't restore \(name)."), style: .error)
            }
        }
    }

    /// Best-effort grams from a vision serving-size string. See
    /// `EatenMealRecorder.gramsFromServingSize`.
    static func gramsFromServingSize(_ serving: String) -> Double {
        EatenMealRecorder.gramsFromServingSize(serving)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionLogView(
            viewModel: NutritionTabViewModel(),
            showMealLogging: .constant(false)
        )
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
