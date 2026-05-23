//
// DietaryProfileSetupView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Dietary Profile Setup View

// First-run setup form for dietary preferences, body stats, and goals.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice.

struct DietaryProfileSetupView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    // MARK: - Body Stats

    @State
    private var weightKg: Double = 75
    @State
    private var heightCm: Double = 175
    @State
    private var age: Int = 22
    @State
    private var biologicalSex: BiologicalSex = .male
    @State
    private var bodyFatPercent: String = ""
    @State
    private var healthKitSynced = false
    @State
    private var lastMeasurementDate: Date?

    // MARK: - Goals

    @State
    private var primaryGoal: DietaryGoal = .maintain

    // MARK: - Dietary Restrictions

    @State
    private var isLactoseFree: Bool = false
    @State
    private var noCoffee: Bool = false
    @State
    private var isGlutenFree: Bool = false
    @State
    private var isVegetarian: Bool = false
    @State
    private var isVegan: Bool = false
    @State
    private var isHalal: Bool = false
    @State
    private var isNutFree: Bool = false
    @State
    private var isShellFishAllergy: Bool = false
    @State
    private var allergyInput: String = ""
    @State
    private var allergies: [String] = []
    @State
    private var dislikedFoodInput: String = ""
    @State
    private var dislikedFoods: [String] = []

    // MARK: - Training

    @State
    private var trainingFrequency: Int = 4
    @State
    private var skillLevel: SkillLevel = .intermediate

    // MARK: - Cooking Skill

    @State
    private var cookingSkill: CookingSkill = .beginner

    // MARK: - State

    @State
    private var isSaving = false
    @State
    private var existingProfile: DietaryProfile?

    // MARK: - Callbacks

    /// Called after save with the saved profile to auto-trigger plan generation
    var onSaveAndGenerate: ((DietaryProfile) -> Void)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: TempoSpacing.xl) {
                        headerSection
                        bodyStatsSection
                        goalSection
                        dietaryRestrictionsSection
                        trainingSection
                        cookingSkillSection
                        goalProjectionSection
                        saveButton
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.bottom, TempoSpacing.bottomSafe)
                }
            }
            .navigationTitle("PROFILE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .task {
                loadExistingProfile()
                await syncFromHealthKit()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: TempoSpacing.sm) {
            Image(systemName: "figure.arms.open")
                .font(.system(size: 36))
                .foregroundStyle(Color.tempoViolet)

            Text("Build Your Fuel Profile")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("This drives your macro targets, meal plans, and coaching. Be accurate.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)

            if healthKitSynced {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Auto-filled from Withings scale via Apple Health")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoSuccess)
                }
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Body Stats

    private var bodyStatsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("BODY STATS")

            // Managed-by-Health caption + deep link. Weight, height, age, sex
            // come from the Apple Health app and update automatically every
            // time a meal plan is generated. The user cannot edit them here.
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                Image(systemName: "heart.text.square.fill")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoSignal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synced from Apple Health")
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Update weight, height, date of birth, and biological sex in the Health app.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSignal)
                }
            }
            .padding(.vertical, TempoSpacing.xs)

            // Weight — read-only
            biometricReadOnlyRow(
                label: "Weight",
                value: String(format: "%.1f kg", weightKg)
            )

            // Height — read-only
            biometricReadOnlyRow(
                label: "Height",
                value: String(format: "%.0f cm", heightCm)
            )

            // Age — read-only
            biometricReadOnlyRow(
                label: "Age",
                value: "\(age) years"
            )

            // Biological sex — read-only
            biometricReadOnlyRow(
                label: "Biological Sex",
                value: biologicalSex.displayName
            )

            // Body Fat — still editable, since HealthKit often lacks it and
            // the user may want to enter a measured value (DEXA, calipers).
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                HStack {
                    Text("Body Fat %")
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text("(optional)")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                TextField("e.g. 15", text: $bodyFatPercent)
                    .font(.tempoBody)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .padding(.horizontal, TempoSpacing.md)
                    .padding(.vertical, 12)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
            }
        }
        .tempoCard()
    }

    /// Single read-only biometric row used inside `bodyStatsSection`. Keeps the
    /// HealthKit-synced fields visually consistent.
    @ViewBuilder
    private func biometricReadOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.tempoCallout)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Goal

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("GOAL")

            ForEach(DietaryGoal.allCases, id: \.self) { goal in
                goalOption(goal)
            }
        }
        .tempoCard()
    }

    private func goalOption(_ goal: DietaryGoal) -> some View {
        Button {
            primaryGoal = goal
            HapticManager.selection()
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: goalIcon(goal))
                    .font(.system(size: 18))
                    .foregroundStyle(primaryGoal == goal ? Color.tempoViolet : Color.tempoTextTertiary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.displayName)
                        .font(.tempoBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text(goalDescription(goal))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                Spacer()

                Image(systemName: primaryGoal == goal ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(primaryGoal == goal ? Color.tempoViolet : Color.tempoTextTertiary)
            }
            .padding(.vertical, TempoSpacing.xs)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dietary Restrictions

    private var dietaryRestrictionsSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("DIETARY RESTRICTIONS")

            // Toggles
            Toggle(isOn: $isLactoseFree) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "drop.triangle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoElectric)
                    Text("Lactose-Free")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $noCoffee) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoAmber)
                    Text("No Coffee")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isGlutenFree) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "leaf.arrow.triangle.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Gluten-Free")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isVegetarian) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Vegetarian")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isVegan) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "tree.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Vegan")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isHalal) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoViolet)
                    Text("Halal")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isNutFree) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoError)
                    Text("Nut-Free")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Toggle(isOn: $isShellFishAllergy) {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoError)
                    Text("Shellfish Allergy")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
            }
            .tint(Color.tempoViolet)

            Divider()
                .background(Color.tempoDivider)

            // Allergies
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Allergies")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                tagInputField(
                    input: $allergyInput,
                    tags: $allergies,
                    placeholder: "Add allergy (e.g. peanuts)"
                )
            }

            // Disliked Foods
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Disliked Foods")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                tagInputField(
                    input: $dislikedFoodInput,
                    tags: $dislikedFoods,
                    placeholder: "Add food to avoid"
                )
            }
        }
        .tempoCard()
    }

    // MARK: - Training

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("TRAINING")

            // Frequency
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Training Frequency")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                Stepper(value: $trainingFrequency, in: 0 ... 7) {
                    Text("\(trainingFrequency) days/week")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                .tint(Color.tempoViolet)
            }

            // Skill Level
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("Skill Level")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                Picker("Skill Level", selection: $skillLevel) {
                    ForEach(SkillLevel.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .tempoCard()
    }

    // MARK: - Cooking Skill

    private var cookingSkillSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("COOKING SKILL")

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Picker("Cooking Skill", selection: $cookingSkill) {
                    ForEach(CookingSkill.allCases, id: \.self) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                .pickerStyle(.segmented)

                Text("Higher skill = more complex recipes. Keep using the app and your skills will grow!")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .tempoCard()
    }

    // MARK: - Save Button

    // MARK: - Goal Projection

    private var goalProjectionSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            sectionLabel("PROJECTION")

            let projection = computeProjection()

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: projection.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.tempoViolet)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(projection.headline)
                            .font(.tempoBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoTextPrimary)

                        Text(projection.detail)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }

                // Daily calorie info
                HStack(spacing: TempoSpacing.lg) {
                    VStack(spacing: 2) {
                        Text("\(projection.dailyCalories)")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tempoSignal)
                        Text("kcal/day")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    VStack(spacing: 2) {
                        Text("\(projection.proteinG)g")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.tempoAmber)
                        Text("protein")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    if projection.weeklyChange != 0 {
                        VStack(spacing: 2) {
                            Text(String(format: "%+.1f kg", projection.weeklyChange))
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(projection.weeklyChange > 0 ? Color.tempoSuccess : Color.tempoAmber)
                            Text("/week")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, TempoSpacing.xs)
            }

            // Disclaimer
            Text(
                "Projections are estimates based on standard metabolic formulas. Actual results vary with adherence, genetics, and activity."
            )
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextTertiary)
        }
        .tempoCard()
    }

    private struct GoalProjection {
        let headline: String
        let detail: String
        let icon: String
        let dailyCalories: Int
        let proteinG: Int
        let weeklyChange: Double // kg per week
    }

    private func computeProjection() -> GoalProjection {
        let bf = Double(bodyFatPercent)

        let tdee = TDEECalculator.calculate(
            weightKg: weightKg,
            heightCm: heightCm,
            age: age,
            biologicalSex: biologicalSex,
            bodyFatPercent: bf,
            trainingFrequency: trainingFrequency,
            whoopAverageTDEE: nil,
            goal: primaryGoal
        )

        let cals = tdee.adjustedCalories
        let protein = Int(weightKg * 2.0)

        switch primaryGoal {
        case .leanGain:
            let surplus = Double(cals) - tdee.tdee
            let weeklyGain = surplus * 7.0 / 7700.0 // ~7700 kcal per kg
            let weeksToGoal = weeklyGain > 0 ? 5.0 / weeklyGain : 0 // 5kg gain estimate
            let months = Int((weeksToGoal / 4.3).rounded())
            return GoalProjection(
                headline: "Lean Gain: +\(Int(surplus)) kcal surplus",
                detail: "At this rate, expect ~5 kg of lean mass gain in \(max(3, months)) months with consistent training and nutrition.",
                icon: "arrow.up.right",
                dailyCalories: cals,
                proteinG: protein,
                weeklyChange: weeklyGain
            )

        case .cut:
            let deficit = tdee.tdee - Double(cals)
            let weeklyLoss = deficit * 7.0 / 7700.0
            let weeksTo5kg = weeklyLoss > 0 ? 5.0 / weeklyLoss : 0
            let months = Int((weeksTo5kg / 4.3).rounded())
            return GoalProjection(
                headline: "Cut: -\(Int(deficit)) kcal deficit",
                detail: "At this rate, expect ~5 kg fat loss in \(max(2, months)) months while preserving muscle with high protein.",
                icon: "arrow.down.right",
                dailyCalories: cals,
                proteinG: protein,
                weeklyChange: -weeklyLoss
            )

        case .maintain:
            return GoalProjection(
                headline: "Maintain: performance optimization",
                detail: "Eating at maintenance. Focus on nutrient timing and recovery-adjusted macros for peak performance.",
                icon: "equal",
                dailyCalories: cals,
                proteinG: protein,
                weeklyChange: 0
            )
        }
    }

    // MARK: - Save Button

    private var saveButton: some View {
        Button {
            saveProfile()
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                        .tint(Color.tempoTextInverse)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16))
                }
                Text("Save & Generate Plan")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(Color.tempoTextInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isSaving ? Color.tempoSignal.opacity(0.6) : Color.tempoSignal)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
        .disabled(isSaving)
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Tag Input Field

    private func tagInputField(input: Binding<String>, tags: Binding<[String]>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            // Tag display
            if !tags.wrappedValue.isEmpty {
                FlowLayout(spacing: TempoSpacing.xs, lineSpacing: TempoSpacing.xs) {
                    ForEach(tags.wrappedValue, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextPrimary)

                            Button {
                                withAnimation(TempoAnimation.springMedium) {
                                    tags.wrappedValue.removeAll { $0 == tag }
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tempoBgSecondary)
                        .clipShape(Capsule())
                    }
                }
            }

            // Input field
            HStack(spacing: TempoSpacing.sm) {
                TextField(placeholder, text: input)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .submitLabel(.done)
                    .onSubmit {
                        addTag(input: input, tags: tags)
                    }

                Button {
                    addTag(input: input, tags: tags)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(
                            input.wrappedValue.isEmpty
                                ? Color.tempoTextDisabled
                                : Color.tempoViolet
                        )
                }
                .disabled(input.wrappedValue.isEmpty)
            }
            .padding(.horizontal, TempoSpacing.md)
            .padding(.vertical, 10)
            .background(Color.tempoBgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                    .stroke(Color.tempoBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoModuleTag)
            .tracking(TempoTracking.drillLabel)
            .foregroundStyle(Color.tempoTextSecondary)
    }

    private func goalIcon(_ goal: DietaryGoal) -> String {
        switch goal {
        case .leanGain: "arrow.up.right"
        case .cut: "arrow.down.right"
        case .maintain: "equal"
        }
    }

    private func goalDescription(_ goal: DietaryGoal) -> String {
        switch goal {
        case .leanGain: "Build muscle with minimal fat gain. +200 kcal surplus."
        case .cut: "Lose fat while preserving muscle. -400 kcal deficit."
        case .maintain: "Hold current weight. Optimize performance."
        }
    }

    private func addTag(input: Binding<String>, tags: Binding<[String]>) {
        let trimmed = input.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !tags.wrappedValue.contains(trimmed) else {
            return
        }
        withAnimation(TempoAnimation.springMedium) {
            tags.wrappedValue.append(trimmed)
        }
        input.wrappedValue = ""
        HapticManager.lightImpact()
    }

    // MARK: - Load Existing

    private func loadExistingProfile() {
        let descriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { profile in
                profile.isActive == true
            }
        )
        guard let profile = try? modelContext.fetch(descriptor).first else {
            return
        }
        existingProfile = profile
        weightKg = profile.currentWeightKg
        heightCm = profile.heightCm
        age = profile.age
        biologicalSex = profile.biologicalSex
        if let bf = profile.bodyFatPercent {
            bodyFatPercent = String(format: "%.1f", bf)
        }
        primaryGoal = profile.primaryGoal
        isLactoseFree = profile.isLactoseFree
        noCoffee = profile.noCoffee
        isGlutenFree = profile.isGlutenFree
        isVegetarian = profile.isVegetarian
        isVegan = profile.isVegan
        isHalal = profile.isHalal
        isNutFree = profile.isNutFree
        isShellFishAllergy = profile.isShellFishAllergy
        allergies = profile.allergies
        dislikedFoods = profile.dislikedFoods
        trainingFrequency = profile.trainingFrequency
        skillLevel = profile.skillLevel
        cookingSkill = profile.cookingSkill
    }

    // MARK: - HealthKit Sync (Withings Body Comp)

    private func syncFromHealthKit() async {
        // Pull live biometrics from HealthKit and write through to the
        // `DietaryProfile` + `UserProfile` rows. This is the single source of
        // truth for weight, height, age, biological sex. We then mirror the
        // synced values into the view's `@State` so the read-only labels show
        // the just-refreshed numbers without waiting for a SwiftData refetch.
        let snapshot = await BiometricsSync.refresh(
            healthKit: services.healthKit,
            modelContext: modelContext
        )

        if let w = snapshot.weightKg { weightKg = w }
        if let h = snapshot.heightCm { heightCm = h }
        if let a = snapshot.age { age = a }
        if let s = snapshot.biologicalSex { biologicalSex = s }
        if let bf = snapshot.bodyFatPercent {
            bodyFatPercent = String(format: "%.1f", bf)
        }
        lastMeasurementDate = snapshot.measurementDate
        healthKitSynced = snapshot.isCompleteForTDEE
    }

    // MARK: - Save

    private func saveProfile() {
        isSaving = true
        HapticManager.lightImpact()

        let bf = Double(bodyFatPercent)

        if let existing = existingProfile {
            existing.currentWeightKg = weightKg
            existing.heightCm = heightCm
            existing.age = age
            existing.biologicalSex = biologicalSex
            existing.bodyFatPercent = bf
            existing.primaryGoal = primaryGoal
            existing.isLactoseFree = isLactoseFree
            existing.noCoffee = noCoffee
            existing.isGlutenFree = isGlutenFree
            existing.isVegetarian = isVegetarian
            existing.isVegan = isVegan
            existing.isHalal = isHalal
            existing.isNutFree = isNutFree
            existing.isShellFishAllergy = isShellFishAllergy
            existing.cookingSkill = cookingSkill
            existing.allergies = allergies
            existing.dislikedFoods = dislikedFoods
            existing.trainingFrequency = trainingFrequency
            existing.skillLevel = skillLevel
            existing.updatedAt = Date()
        } else {
            let profile = DietaryProfile(
                isLactoseFree: isLactoseFree,
                noCoffee: noCoffee,
                isGlutenFree: isGlutenFree,
                isVegetarian: isVegetarian,
                isVegan: isVegan,
                isHalal: isHalal,
                isNutFree: isNutFree,
                isShellFishAllergy: isShellFishAllergy,
                cookingSkill: cookingSkill,
                allergies: allergies,
                dislikedFoods: dislikedFoods,
                primaryGoal: primaryGoal,
                bodyFatPercent: bf,
                currentWeightKg: weightKg,
                heightCm: heightCm,
                age: age,
                biologicalSex: biologicalSex,
                trainingFrequency: trainingFrequency,
                skillLevel: skillLevel
            )
            modelContext.insert(profile)
        }

        try? modelContext.save()

        // Get the saved profile for auto-generation
        let savedProfile: DietaryProfile?
        if let existing = existingProfile {
            savedProfile = existing
        } else {
            let descriptor = FetchDescriptor<DietaryProfile>(
                predicate: #Predicate<DietaryProfile> { $0.isActive == true }
            )
            savedProfile = try? modelContext.fetch(descriptor).first
        }

        Task {
            try? await Task.sleep(for: .seconds(0.3))
            isSaving = false
            HapticManager.notification(.success)
            dismiss()

            // Auto-trigger plan generation after dismiss
            if let profile = savedProfile {
                onSaveAndGenerate?(profile)
            }
        }
    }
}

// FlowLayout is defined in DashboardView.swift and shared across the app.

// MARK: - Preview

#Preview {
    DietaryProfileSetupView()
        .modelContainer(for: [DietaryProfile.self], inMemory: true)
}
