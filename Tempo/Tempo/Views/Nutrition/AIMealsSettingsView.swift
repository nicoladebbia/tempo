//
// AIMealsSettingsView.swift
// Tempo
//
// The editable home for everything the meal-plan AI personalizes on: cooking
// capacity, meal structure, taste, kitchen equipment, and recovery. Phases 1-4
// built the data + prompt layers; this is the shell over them — preferences
// are viewable/editable anytime and persist across regenerates (no more
// re-running the wizard to change one answer).
//
// Edits are held in local draft state and committed on Save, which writes back
// to UserSettings + DietaryProfile + KitchenEquipment and then offers to
// regenerate the active plan so the changes take effect immediately.
//

import SwiftData
import SwiftUI

struct AIMealsSettingsView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext

    @Query
    private var allSettings: [UserSettings]
    @Query(filter: #Predicate<DietaryProfile> { $0.isActive == true })
    private var activeProfiles: [DietaryProfile]
    @Query(sort: \KitchenEquipment.kindRaw)
    private var equipment: [KitchenEquipment]
    /// Newest first — same row `UserDailyPlanProfile.current(in:)` returns.
    @Query(sort: \UserDailyPlanProfile.updatedAt, order: .reverse)
    private var dailyPlanProfiles: [UserDailyPlanProfile]

    /// Called when the user saves and chooses to regenerate. The parent owns
    /// the generation call (it has the WhoopService / APIClient handles).
    var onRegenerate: () -> Void

    // MARK: - Draft state (committed on Save)

    @State private var cookableDays: Int = MealPlanIntake.default.cookableDaysThisWeek
    @State private var leftoverTolerance: LeftoverTolerance = MealPlanIntake.default.leftoverTolerance
    @State private var cookingSkill: CookingSkill = .beginner
    @State private var cookWeekdayMins: Int = 30
    @State private var cookWeekendMins: Int = 60

    /// nil = "Auto" (let the AI pick 4-5); 3/4/5 = a hard count.
    @State private var mealsPerDay: Int? = nil
    @State private var firstMealHour: Int = EatingWindow.default.firstMealHour
    @State private var lastMealHour: Int = EatingWindow.default.lastMealHour

    @State private var favoriteFoods: [String] = []
    @State private var boredOfFoods: [String] = []
    @State private var exclusions: [String] = []
    @State private var favoriteDraft: String = ""
    @State private var boredDraft: String = ""
    @State private var exclusionDraft: String = ""

    @State private var recoveryAdjusted: Bool = false
    @State private var clearSkinFocus: Bool = false

    @State private var didLoad = false
    @State private var showRegeneratePrompt = false

    private static let cookTimeOptions = [15, 30, 45, 60, 90]

    var body: some View {
        List {
            cookingSection
            mealsSection
            tasteSection
            kitchenSection
            recoverySection
            focusSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("AI Meals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoSignal)
            }
        }
        .task { loadIfNeeded() }
        .confirmationDialog(
            "Regenerate this week's plan with your new preferences?",
            isPresented: $showRegeneratePrompt,
            titleVisibility: .visible
        ) {
            Button("Regenerate now") {
                onRegenerate()
                dismiss()
            }
            Button("Later", role: .cancel) { dismiss() }
        } message: {
            Text("Your changes are saved. The current plan keeps its old meals until you regenerate.")
        }
    }

    // MARK: - Cooking

    private var cookingSection: some View {
        Section("Cooking") {
            Stepper(value: $cookableDays, in: 0 ... 7) {
                labeledValue("Cookable days / week", "\(cookableDays)")
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Picker("Leftover tolerance", selection: $leftoverTolerance) {
                ForEach(LeftoverTolerance.allCases) { tol in
                    Text(tol.displayName).tag(tol)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Picker("Cooking skill", selection: $cookingSkill) {
                ForEach(CookingSkill.allCases, id: \.self) { skill in
                    Text(skill.displayName).tag(skill)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            cookTimePicker("Weekday cook time", selection: $cookWeekdayMins)
            cookTimePicker("Weekend cook time", selection: $cookWeekendMins)
        }
    }

    private func cookTimePicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Self.cookTimeOptions, id: \.self) { mins in
                Text("\(mins) min").tag(mins)
            }
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Meals

    private var mealsSection: some View {
        Section("Meals") {
            Picker("Meals per day", selection: $mealsPerDay) {
                Text("Auto").tag(Int?.none)
                ForEach([3, 4, 5], id: \.self) { n in
                    Text("\(n)").tag(Int?.some(n))
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Picker("First meal", selection: $firstMealHour) {
                ForEach(EatingWindowStepView.range(4 ... 14, including: firstMealHour), id: \.self) { h in
                    Text(hourLabel(h)).tag(h)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Picker("Last meal", selection: $lastMealHour) {
                ForEach(EatingWindowStepView.range(16 ... 23, including: lastMealHour), id: \.self) { h in
                    Text(hourLabel(h)).tag(h)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
    }

    // MARK: - Taste

    private var tasteSection: some View {
        Section("Taste") {
            chipEditor(
                title: "Favorite foods + cuisines",
                placeholder: "e.g. salmon, thai",
                items: $favoriteFoods,
                draft: $favoriteDraft
            )
            chipEditor(
                title: "Bored of",
                placeholder: "e.g. chicken breast",
                items: $boredOfFoods,
                draft: $boredDraft
            )
            chipEditor(
                title: "Off the table (excluded)",
                placeholder: "e.g. broccoli",
                items: $exclusions,
                draft: $exclusionDraft
            )
        }
    }

    // MARK: - Kitchen

    private var kitchenSection: some View {
        Section {
            ForEach(equipment) { item in
                if let kind = item.kind {
                    Toggle(isOn: bindingForEquipment(item)) {
                        Label {
                            Text(kind.displayName)
                                .foregroundStyle(Color.tempoTextPrimary)
                        } icon: {
                            Image(systemName: kind.icon)
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                    .tint(Color.tempoSignal)
                    .listRowBackground(Color.tempoSurfaceCard)
                }
            }
        } header: {
            Text("Kitchen")
        } footer: {
            Text("The AI only programs recipes makeable with the appliances you have.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func bindingForEquipment(_ item: KitchenEquipment) -> Binding<Bool> {
        Binding(
            get: { item.isAvailable },
            set: { newValue in
                item.isAvailable = newValue
                item.updatedAt = Date()
                HapticManager.selection()
            }
        )
    }

    // MARK: - Recovery

    private var recoverySection: some View {
        Section {
            Toggle(isOn: $recoveryAdjusted) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recovery-adjust meals")
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Shift carbs + calories toward training days using Whoop recovery.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .tint(Color.tempoSignal)
            .listRowBackground(Color.tempoSurfaceCard)
        } header: {
            Text("Recovery")
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        Section {
            Toggle(isOn: $clearSkinFocus) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear-skin / low-dairy focus")
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Low-GI carbs, no added sweeteners, minimal dairy.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .tint(Color.tempoSignal)
            .listRowBackground(Color.tempoSurfaceCard)
        } header: {
            Text("Focus")
        } footer: {
            Text("Changes which foods the AI favors. Macro targets stay the same.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Chip editor (favorites / bored-of / exclusions)

    private func chipEditor(
        title: String,
        placeholder: String,
        items: Binding<[String]>,
        draft: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            HStack(spacing: TempoSpacing.sm) {
                TextField(placeholder, text: draft)
                    .font(.tempoBody)
                    .submitLabel(.done)
                    .onSubmit { addChip(to: items, draft: draft) }

                Button {
                    addChip(to: items, draft: draft)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.tempoTextInverse)
                        .frame(width: 32, height: 32)
                        .background(Color.tempoSignal)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                }
                .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
            }

            if !items.wrappedValue.isEmpty {
                FlowLayout(spacing: TempoSpacing.xs, lineSpacing: TempoSpacing.xs) {
                    ForEach(items.wrappedValue, id: \.self) { food in
                        chip(food, items: items)
                    }
                }
            }
        }
        .padding(.vertical, TempoSpacing.xs)
        .listRowBackground(Color.tempoSurfaceCard)
    }

    private func chip(_ food: String, items: Binding<[String]>) -> some View {
        HStack(spacing: 6) {
            Text(food)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextPrimary)
            Button {
                items.wrappedValue.removeAll { $0 == food }
                HapticManager.selection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TempoSpacing.sm)
        .padding(.vertical, 6)
        .background(Color.tempoSurfaceElevated)
        .clipShape(Capsule())
    }

    private func addChip(to items: Binding<[String]>, draft: Binding<String>) {
        let trimmed = draft.wrappedValue.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return }
        if !items.wrappedValue.contains(trimmed) {
            items.wrappedValue.append(trimmed)
            HapticManager.selection()
        }
        draft.wrappedValue = ""
    }

    // MARK: - Helpers

    private func labeledValue(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text(value)
                .font(.tempoBody.monospacedDigit())
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let suffix = hour < 12 ? "AM" : "PM"
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(suffix)"
    }

    // MARK: - Load + Save

    /// Seed the draft from persisted state on first appear. Idempotent — guarded
    /// by `didLoad` so re-renders don't clobber in-flight edits.
    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        if let settings = allSettings.first {
            cookableDays = settings.mealIntakeCookableDays ?? cookableDays
            leftoverTolerance = settings.mealIntakeLeftoverToleranceRaw
                .flatMap { LeftoverTolerance(rawValue: $0) } ?? leftoverTolerance
            cookWeekdayMins = settings.cookTimeWeekdayMins ?? cookWeekdayMins
            cookWeekendMins = settings.cookTimeWeekendMins ?? cookWeekendMins
            mealsPerDay = settings.mealsPerDayPreference
            recoveryAdjusted = settings.mealIntakeRecoveryAdjusted
            exclusions = settings.mealIntakeExclusionsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        // Same window the planner uses: saved override, else onboarding's
        // window, else the default. Showing 8–20 here while the planner used
        // the onboarding window made Save silently overwrite onboarding.
        let window = MealPlanIntake.seeded(settings: allSettings.first, dailyPlan: dailyPlanProfiles.first).eatingWindow
        firstMealHour = window.firstMealHour
        lastMealHour = window.lastMealHour

        if let profile = activeProfiles.first {
            cookingSkill = profile.cookingSkill
            favoriteFoods = profile.favoriteFoods
            boredOfFoods = profile.boredOfFoods
        }

        clearSkinFocus = ClearSkinFocusSetting.resolve(modelContext: modelContext)

        seedEquipmentIfEmpty()
    }

    /// First open with no KitchenEquipment rows → seed the standard set so the
    /// toggles render (basic kitchen on, specialty off). Per §9.
    private func seedEquipmentIfEmpty() {
        guard equipment.isEmpty else { return }
        for row in KitchenEquipment.seededSet() {
            modelContext.insert(row)
        }
    }

    private func save() {
        let settings = allSettings.first ?? {
            let fresh = UserSettings()
            modelContext.insert(fresh)
            return fresh
        }()

        settings.mealIntakeCookableDays = cookableDays
        settings.mealIntakeLeftoverToleranceRaw = leftoverTolerance.rawValue
        settings.cookTimeWeekdayMins = cookWeekdayMins
        settings.cookTimeWeekendMins = cookWeekendMins
        settings.mealsPerDayPreference = mealsPerDay
        settings.mealIntakeFirstMealHour = firstMealHour
        settings.mealIntakeLastMealHour = lastMealHour
        settings.mealIntakeRecoveryAdjusted = recoveryAdjusted
        settings.mealIntakeExclusionsRaw = exclusions.joined(separator: ", ")
        settings.updatedAt = Date()

        if let profile = activeProfiles.first {
            profile.cookingSkill = cookingSkill
            profile.favoriteFoods = favoriteFoods
            profile.boredOfFoods = boredOfFoods
        }

        ClearSkinFocusSetting.setEnabled(clearSkinFocus)

        // Kitchen toggles already wrote through their bindings.
        try? modelContext.save()
        HapticManager.success()
        showRegeneratePrompt = true
    }
}
