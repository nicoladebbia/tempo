//
// NutritionWeeklyPlanView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Nutrition Weekly Plan View

// 7-day expandable meal plan overview with day types and generation.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct NutritionWeeklyPlanView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var expandedDay: Int?
    @State
    private var showDisclaimerAlert = false
    @State
    private var wizardSnapshot: WizardLaunchSnapshot?
    @State
    private var isPreparingWizard = false
    @State
    private var showProfileSetup = false
    @AppStorage("tempo.nutrition.disclaimerAccepted")
    private var disclaimerAccepted = false

    private let calendar = Calendar.current
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.lg) {
                if let plan = viewModel.weeklyPlan {
                    planHeaderCard(plan)
                    weekDaysList(plan)
                } else {
                    emptyPlanState
                }

                generateButton
                    .padding(.top, TempoSpacing.md)

                if let error = viewModel.planGenerationError {
                    HStack(spacing: TempoSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.tempoError)
                        Text(error)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoError)
                    }
                    .tempoCard()
                }
                // AI disclaimer
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("AI-generated guidance. Not medical or dietetic advice. Consult a professional for personalized plans.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .padding(.vertical, TempoSpacing.sm)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe)
        }
        .alert("AI-Generated Meal Plan", isPresented: $showDisclaimerAlert) {
            Button("I Understand") {
                disclaimerAccepted = true
                launchWizard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Meal plans are created by AI for general wellness guidance. They are not a substitute for professional dietary advice. If you have medical conditions, allergies, or eating disorders, consult a healthcare professional before following any meal plan."
            )
        }
        // Pantry-gap alert lives on the outer `NutritionTabView`, not here —
        // attaching it to both would render two competing `.alert` modifiers
        // against the same binding when this view is mounted as a tab child.
        .sheet(isPresented: $showProfileSetup) {
            DietaryProfileSetupView(onSaveAndGenerate: { _ in
                showProfileSetup = false
                viewModel.loadToday(modelContext: modelContext)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if disclaimerAccepted {
                        launchWizard()
                    } else {
                        showDisclaimerAlert = true
                    }
                }
            })
        }
        .sheet(item: $wizardSnapshot) { snapshot in
            MealPlanIntakeWizardView(
                snapshot: snapshot,
                onComplete: { intake in
                    wizardSnapshot = nil
                    viewModel.generatePlan(
                        modelContext: modelContext,
                        whoop: services.whoop,
                        notifications: services.notifications,
                        intake: intake
                    )
                },
                onCancel: {
                    wizardSnapshot = nil
                }
            )
        }
    }

    // MARK: - Plan Header

    private func planHeaderCard(_ plan: WeeklyMealPlan) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Image(systemName: "calendar")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.tempoViolet)

                Text("ACTIVE PLAN")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Spacer()

                Text("Active")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.tempoSuccess)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.tempoSuccess.opacity(0.12))
                    .clipShape(Capsule())
            }

            let dateFormatter: DateFormatter = {
                let f = DateFormatter()
                f.dateFormat = "MMM d"
                return f
            }()

            Text("\(dateFormatter.string(from: plan.startDate)) - \(dateFormatter.string(from: plan.endDate))")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)

            let totalMeals = plan.meals?.count ?? 0
            let eatenMeals = plan.meals?.count(where: { $0.status == .eaten }) ?? 0
            Text("\(eatenMeals)/\(totalMeals) meals completed")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .tempoCard()
    }

    // MARK: - Week Days List

    private func weekDaysList(_ plan: WeeklyMealPlan) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            ForEach(0 ..< 7, id: \.self) { dayOffset in
                let date = calendar.date(byAdding: .day, value: dayOffset, to: plan.startDate)!
                let weekday = calendar.component(.weekday, from: date)
                let dayMeals = mealsForDate(date, in: plan)
                let dayType = plan.dayTypes[weekday]
                let isExpanded = expandedDay == dayOffset
                let isToday = calendar.isDateInToday(date)

                VStack(spacing: 0) {
                    // Day header
                    dayHeaderRow(
                        date: date,
                        dayType: dayType,
                        mealCount: dayMeals.count,
                        totalCalories: dayMeals.reduce(0) { $0 + Int($1.totalCalories) },
                        isToday: isToday,
                        isExpanded: isExpanded
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(TempoAnimation.springMedium) {
                            expandedDay = isExpanded ? nil : dayOffset
                        }
                        HapticManager.selection()
                    }

                    // Expanded meals
                    if isExpanded, !dayMeals.isEmpty {
                        Divider()
                            .background(Color.tempoDivider)
                            .padding(.horizontal, TempoSpacing.sm)

                        VStack(spacing: TempoSpacing.xs) {
                            ForEach(dayMeals, id: \.id) { meal in
                                compactMealRow(meal)
                            }
                        }
                        .padding(.top, TempoSpacing.sm)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .tempoCard()
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                        .stroke(isToday ? Color.tempoViolet.opacity(0.4) : Color.clear, lineWidth: 1)
                )
            }
        }
    }

    private func dayHeaderRow(
        date: Date,
        dayType: DayType?,
        mealCount: Int,
        totalCalories: Int,
        isToday: Bool,
        isExpanded: Bool
    ) -> some View {
        HStack(spacing: TempoSpacing.md) {
            // Day label
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: TempoSpacing.xs) {
                    Text(dayLabel(for: date))
                        .font(.tempoBody)
                        .fontWeight(isToday ? .bold : .medium)
                        .foregroundStyle(isToday ? Color.tempoViolet : Color.tempoTextPrimary)

                    if isToday {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.tempoViolet)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tempoViolet.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                if let dayType {
                    dayTypeBadge(dayType)
                }
            }

            Spacer()

            // Stats
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalCalories) kcal")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("\(mealCount) meals")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.tempoTextTertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
    }

    private func dayTypeBadge(_ dayType: DayType) -> some View {
        HStack(spacing: 4) {
            Image(systemName: dayTypeIcon(dayType))
                .font(.system(size: 9))
            Text(dayType.displayName.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
        }
        .foregroundStyle(dayTypeColor(dayType))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(dayTypeColor(dayType).opacity(0.12))
        .clipShape(Capsule())
    }

    private func compactMealRow(_ meal: PlannedMeal) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Circle()
                .fill(mealStatusColor(meal.status))
                .frame(width: 8, height: 8)

            Text(meal.mealName)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)

            Text(meal.scheduledTime)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            Spacer()

            Text("\(Int(meal.totalCalories)) kcal")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyPlanState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer().frame(height: 40)

            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No Weekly Plan")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("Generate a personalized meal plan based on your goals, training schedule, and dietary preferences.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.xl)

            if !viewModel.hasProfile {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.tempoWarning)
                    Text("Set up your dietary profile first.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoWarning)
                }
            }
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: 6) {
            if viewModel.isGeneratingPlan, !viewModel.planGenerationStatusLabel.isEmpty {
                Text(viewModel.planGenerationStatusLabel)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .transition(.opacity)
            }
            generateButtonInner
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.planGenerationStatusLabel)
    }

    private var generateButtonInner: some View {
        Button {
            guard viewModel.hasProfile else {
                showProfileSetup = true
                return
            }
            if disclaimerAccepted {
                launchWizard()
            } else {
                showDisclaimerAlert = true
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isGeneratingPlan || isPreparingWizard {
                    ProgressView()
                        .tint(Color.tempoTextInverse)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                }
                Text(viewModel.weeklyPlan != nil ? "Regenerate Plan" : "Generate New Plan")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.tempoTextInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                (viewModel.isGeneratingPlan || isPreparingWizard)
                    ? Color.tempoSignal.opacity(0.6)
                    : Color.tempoSignal
            )
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .disabled(viewModel.isGeneratingPlan || isPreparingWizard)
    }

    // MARK: - Actions

    private func launchWizard() {
        guard !isPreparingWizard else {
            return
        }
        isPreparingWizard = true
        Task {
            let snapshot = await viewModel.buildWizardSnapshot(
                modelContext: modelContext,
                whoop: services.whoop
            )
            isPreparingWizard = false
            wizardSnapshot = snapshot
        }
    }

    // MARK: - Helpers

    private func mealsForDate(_ date: Date, in plan: WeeklyMealPlan) -> [PlannedMeal] {
        let dayStart = calendar.startOfDay(for: date)
        return (plan.meals ?? [])
            .filter { calendar.isDate($0.dayDate, inSameDayAs: dayStart) }
            .sorted { $0.mealNumber < $1.mealNumber }
    }

    private func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func dayTypeIcon(_ dayType: DayType) -> String {
        switch dayType {
        case .strength: "dumbbell.fill"
        case .cardio: "figure.run"
        case .soccer: "soccerball"
        case .double: "bolt.fill"
        case .rest: "bed.double.fill"
        }
    }

    private func dayTypeColor(_ dayType: DayType) -> Color {
        switch dayType {
        case .strength: .tempoAmber
        case .cardio: .tempoElectric
        case .soccer: .tempoSuccess
        case .double: .tempoError
        case .rest: .tempoTextTertiary
        }
    }

    private func mealStatusColor(_ status: MealStatus) -> Color {
        switch status {
        case .planned: .tempoTextTertiary
        case .eaten: .tempoSuccess
        case .skipped: .tempoError
        case .modified: .tempoWarning
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NutritionWeeklyPlanView(viewModel: NutritionTabViewModel())
    }
    .modelContainer(for: [PlannedMeal.self, WeeklyMealPlan.self, MealPreset.self, DietaryProfile.self], inMemory: true)
}
