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
// A section of the Fuel tab: the Tide field is already drawn by the tab root.

struct NutritionWeeklyPlanView: View {
    @Bindable
    var viewModel: NutritionTabViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
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
    @State
    private var showEditSetup = false
    @State
    private var showRebuildConfirm = false
    @AppStorage("tempo.nutrition.disclaimerAccepted")
    private var disclaimerAccepted = false

    private let calendar = Calendar.current
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private static let rangeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s4) {
                NextWeekPlanCard()
                if let plan = viewModel.weeklyPlan {
                    if viewModel.showPlanUpdateBanner {
                        PlanUpdateBanner(viewModel: viewModel)
                    }
                    planHeaderCard(plan)
                    weekDaysList(plan)
                } else if viewModel.isGeneratingPlan {
                    // First plan being built: say so, in the same look as every AI wait.
                    FuelAIState(kind: .working(
                        viewModel.planGenerationStatusLabel.isEmpty
                            ? "Building your week…" : viewModel.planGenerationStatusLabel
                    ))
                } else {
                    emptyPlanState
                }

                generateButton
                    .padding(.top, Tide.s2)

                aiMealsPreferencesLink

                if let blocker = viewModel.planGenerationBlocker {
                    PlanBlockerCard(blocker: blocker, viewModel: viewModel)
                } else if let error = viewModel.planGenerationError {
                    FuelBanner(icon: "exclamationmark.triangle.fill", tint: Tide.danger, title: error)
                }

                // AI disclaimer
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "info.circle")
                        .font(Tide.caption)
                        .accessibilityHidden(true)
                    Text("AI-generated guidance. Not medical or dietetic advice. Consult a professional for personalized plans.")
                        .font(Tide.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Tide.text3)
                .padding(.vertical, Tide.s2)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s8)
            // Pin the content to the screen width: nothing inside can make the
            // page wider, so it only ever scrolls up and down.
            .containerRelativeFrame(.horizontal)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
            FuelSetupView(onSaveAndGenerate: { _ in
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
            // A sheet draws its own field; it must not inherit "already on a page".
            .environment(\.tideInsidePage, false)
        }
        .sheet(isPresented: $showEditSetup) {
            FuelSetupView(startInReview: true)
                .environment(\.tideInsidePage, false)
        }
        .sheet(item: $wizardSnapshot) { snapshot in
            MealPlanIntakeWizardView(
                snapshot: snapshot,
                onComplete: { intake in
                    wizardSnapshot = nil
                    // The wizard only asks THIS WEEK's questions; they're
                    // stored against this week's Monday and expire with it.
                    // Everything permanent (eating window, leftovers, budget,
                    // stores...) lives in Fuel setup.
                    let descriptor = FetchDescriptor<UserSettings>()
                    if let settings = (try? modelContext.fetch(descriptor))?.first {
                        intake.persist(to: settings)
                        try? modelContext.save()
                    }
                    viewModel.generatePlan(
                        modelContext: modelContext,
                        whoop: services.whoop,
                        apiClient: services.apiClient,
                        notifications: services.notifications,
                        intake: intake,
                        trainingEngine: services.trainingEngine,
                        healthKit: services.healthKit
                    )
                },
                onCancel: {
                    wizardSnapshot = nil
                }
            )
            .environment(\.tideInsidePage, false)
        }
    }

    // MARK: - Plan Header

    /// The week at a glance: its dates, how many meals are done, and whether
    /// the plan still matches the setup.
    private func planHeaderCard(_ plan: WeeklyMealPlan) -> some View {
        // Planned slots only: a Quick Log or a supplement dose isn't a plan meal.
        let planMeals = plan.meals?.filter { !$0.isUnplannedLog } ?? []
        let totalMeals = planMeals.count
        let eatenMeals = planMeals.count(where: { $0.status == .eaten })
        // A plan built from inputs that have since changed is not
        // "Active" any more — say so (Update lives in the banner).
        let stale = viewModel.isPlanOutOfDate

        return VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text("Active plan")
                    .tideLabel()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tide.s2)
                FuelPill(text: stale ? "Out of date" : "Active", color: stale ? Tide.warn : Tide.good)
            }

            Text("\(Self.rangeFormatter.string(from: plan.startDate)) - \(Self.rangeFormatter.string(from: plan.endDate))")
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber("\(eatenMeals)", size: Tide.numeralM)
                    Text("of \(totalMeals) meals completed")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                TideLevelBar(
                    progress: totalMeals > 0 ? min(Double(eatenMeals) / Double(totalMeals), 1) : 0,
                    height: Tide.bar
                )
                .animation(Tide.settle, value: eatenMeals)
            }
        }
        .tideCard()
    }

    // MARK: - Week Days List

    private func weekDaysList(_ plan: WeeklyMealPlan) -> some View {
        VStack(spacing: Tide.s3) {
            ForEach(0 ..< 7, id: \.self) { dayOffset in
                let date = calendar.date(byAdding: .day, value: dayOffset, to: plan.startDate)!
                let dayMeals = mealsForDate(date, in: plan)
                // dayTypeAssignments is keyed Mon=1 … Sun=7 (the generator
                // writes `dayIndex + 1`, and plan.startDate is the Monday).
                // dayOffset is 0=Mon … 6=Sun, so the key is dayOffset + 1.
                // Do NOT use Calendar.weekday here — its Sun=1 numbering does
                // not match the dict and shifted every day (Saturday showed the
                // wrong type; confirmed via [PlanDiag] raw dump).
                let dayType = plan.dayTypes[dayOffset + 1]
                let isExpanded = expandedDay == dayOffset
                let isToday = calendar.isDateInToday(date)

                VStack(spacing: 0) {
                    // Day header
                    Button {
                        withAnimation(Tide.snap) {
                            expandedDay = isExpanded ? nil : dayOffset
                        }
                        HapticManager.selection()
                    } label: {
                        dayHeaderRow(
                            date: date,
                            dayType: dayType,
                            mealCount: dayMeals.count,
                            totalCalories: dayMeals.reduce(0) { $0 + Int($1.totalCalories) },
                            isToday: isToday,
                            isExpanded: isExpanded
                        )
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

                    // Expanded meals
                    if isExpanded, !dayMeals.isEmpty {
                        Divider()
                            .overlay(Tide.hairline)
                            .padding(.vertical, Tide.s2)

                        VStack(spacing: 0) {
                            ForEach(dayMeals, id: \.id) { meal in
                                // Opens the same meal page as Today, so a
                                // wrong log from an earlier day can be
                                // deleted or undone too.
                                NavigationLink {
                                    MealDetailView(meal: meal)
                                } label: {
                                    compactMealRow(meal)
                                        .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                .overlay {
                    RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                        .stroke(isToday ? mood.accent.opacity(0.5) : Color.clear, lineWidth: 1)
                        .allowsHitTesting(false)
                }
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
        let name = Text(dayLabel(for: date))
            .font(Tide.bodyStrong)
            .foregroundStyle(isToday ? mood.accent : Tide.text)
        let chevron = Image(systemName: "chevron.down")
            .font(Tide.label)
            .foregroundStyle(Tide.text3)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityHidden(true)
        let label = VStack(alignment: .leading, spacing: Tide.s1) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    name
                    if isToday {
                        FuelPill(text: "Today", color: mood.accent)
                    }
                }
                VStack(alignment: .leading, spacing: Tide.s1) {
                    name
                    if isToday {
                        FuelPill(text: "Today", color: mood.accent)
                    }
                }
            }
            if let dayType {
                dayTypeBadge(dayType)
            }
        }
        let stats = { (alignment: HorizontalAlignment) in
            VStack(alignment: alignment, spacing: Tide.hair) {
                TideNumber("\(totalCalories)", unit: "kcal", size: Tide.numeralS, relativeTo: .headline)

                Text("\(mealCount) meals")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }

        // One line when it fits; at large text sizes the numbers drop under
        // the day instead of squeezing it letter by letter.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                label
                Spacer(minLength: Tide.s2)
                stats(.trailing)
                chevron
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                label
                HStack(spacing: Tide.s3) {
                    stats(.leading)
                    Spacer(minLength: Tide.s2)
                    chevron
                }
            }
        }
        .frame(minHeight: Tide.hit)
    }

    private func dayTypeBadge(_ dayType: DayType) -> some View {
        let color = dayTypeColor(dayType)
        return HStack(spacing: Tide.s1) {
            Image(systemName: dayTypeIcon(dayType))
                .accessibilityHidden(true)
            Text(dayType.displayName)
        }
        .font(Tide.label)
        .foregroundStyle(color)
        .padding(.horizontal, Tide.s2)
        .padding(.vertical, Tide.s1)
        .background(color.opacity(0.16), in: .capsule)
    }

    private func compactMealRow(_ meal: PlannedMeal) -> some View {
        // The name wraps instead of widening the row, so a long recipe name can
        // never push the page past the screen; time and kcal keep their width.
        HStack(spacing: Tide.s3) {
            Circle()
                .fill(mealStatusColor(meal.status))
                .frame(width: Tide.s2, height: Tide.s2)
                .accessibilityHidden(true)

            Text(meal.mealName)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .layoutPriority(0)

            Spacer(minLength: Tide.s2)

            Text(meal.scheduledTime)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Text("\(Int(meal.totalCalories)) kcal")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
    }

    // MARK: - Empty State

    private var emptyPlanState: some View {
        FuelEmptyState(
            icon: "calendar.badge.plus",
            title: "No Weekly Plan",
            message: "Generate a personalized meal plan based on your goals, training schedule, and dietary preferences."
        ) {
            if !viewModel.hasProfile || FuelSetupDraft.requiredMissingMessage(in: modelContext) != nil {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Tide.caption)
                        .accessibilityHidden(true)
                    Text(FuelSetupDraft.requiredMissingMessage(in: modelContext) ?? "Set up your dietary profile first.")
                        .font(Tide.caption)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Tide.warn)
            }
        }
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        VStack(spacing: Tide.s2) {
            if viewModel.isGeneratingPlan, !viewModel.planGenerationStatusLabel.isEmpty {
                Text(viewModel.planGenerationStatusLabel)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            generateButtonInner
        }
        .animation(Tide.snap, value: viewModel.planGenerationStatusLabel)
    }

    private var generateButtonInner: some View {
        Button {
            HapticManager.lightImpact()
            guard viewModel.hasProfile, FuelSetupDraft.requiredMissingMessage(in: modelContext) == nil else {
                showProfileSetup = true
                return
            }
            // Replacing planned meals needs a yes first.
            if viewModel.weeklyPlan != nil {
                showRebuildConfirm = true
            } else {
                startGenerate()
            }
        } label: {
            HStack(spacing: Tide.s2) {
                if viewModel.isGeneratingPlan || isPreparingWizard {
                    ProgressView()
                        .tint(Tide.ink)
                } else {
                    Image(systemName: "sparkles")
                        .accessibilityHidden(true)
                }
                Text(viewModel.weeklyPlan != nil ? "Regenerate Plan" : "Generate New Plan")
            }
        }
        .buttonStyle(.tidePrimary)
        .disabled(viewModel.isGeneratingPlan || isPreparingWizard)
        .alert("Rebuild the rest of the week?", isPresented: $showRebuildConfirm) {
            Button("Rebuild") { startGenerate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Meals you've eaten and past days stay. Planned meals from today on are replaced.")
        }
    }

    private func startGenerate() {
        if disclaimerAccepted {
            launchWizard()
        } else {
            showDisclaimerAlert = true
        }
    }

    /// Opens Fuel setup on its review/edit step: the one place for permanent
    /// settings. Saving there posts `.tempoDietaryProfileChanged`, which the
    /// plan already follows (outdated-plan banner / rebuild prompt).
    private var aiMealsPreferencesLink: some View {
        Button {
            HapticManager.lightImpact()
            showEditSetup = true
        } label: {
            HStack(spacing: Tide.s2) {
                Image(systemName: "slider.horizontal.3")
                    .accessibilityHidden(true)
                Text("Edit setup")
                Spacer(minLength: Tide.s2)
                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
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
            // Sort by clock time, not mealNumber — the afternoon Snack
            // (mealNumber 4) falls before Dinner (mealNumber 3), so a
            // mealNumber sort would render them out of order. Mirrors the
            // Today view's time sort (NutritionTabViewModel.minutesOfDay).
            .sorted {
                let lhs = NutritionTabViewModel.minutesOfDay(from: $0.scheduledTime) ?? Int.max
                let rhs = NutritionTabViewModel.minutesOfDay(from: $1.scheduledTime) ?? Int.max
                return lhs < rhs
            }
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
        case .strength: Tide.warn
        case .cardio: Tide.water
        case .soccer: Tide.good
        case .double: Tide.danger
        case .rest: Tide.text3
        }
    }

    private func mealStatusColor(_ status: MealStatus) -> Color {
        switch status {
        case .planned: Tide.text3
        case .eaten: Tide.good
        case .skipped: Tide.danger
        case .modified: Tide.warn
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
