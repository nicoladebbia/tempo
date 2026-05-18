//
// MealLoggingView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - MealLoggingView

// Full-screen modal for logging a meal.
// Per DESIGN_SYSTEM.md — all tokens, drill-sergeant voice, haptic feedback.

struct MealLoggingView: View {
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var selectedMealType: MealType = .breakfast
    @State
    var foodItems: [FoodItem] = []
    @State
    private var showFoodSearch = false
    @State
    private var showPhotoAnalysis = false
    @State
    private var showBarcodeScanner = false
    @State
    private var showVoiceLog = false
    /// Pre-fills FoodSearchView when a low-confidence voice item taps
    /// "Search instead".
    @State
    private var searchPrefill: String?
    @State
    private var toast: ToastData?

    var onMealLogged: (([FoodItem], MealType) -> Void)?

    // MARK: - Meal Type

    enum MealType: String, CaseIterable, Identifiable {
        case breakfast = "Breakfast"
        case lunch = "Lunch"
        case dinner = "Dinner"
        case snack = "Snack"

        var id: String {
            rawValue
        }
    }

    // MARK: - Running Totals

    private var totalCalories: Int {
        foodItems.reduce(0) { $0 + $1.calories }
    }

    private var totalProtein: Double {
        foodItems.reduce(0) { $0 + $1.protein }
    }

    private var totalCarbs: Double {
        foodItems.reduce(0) { $0 + $1.carbs }
    }

    private var totalFat: Double {
        foodItems.reduce(0) { $0 + $1.fat }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.tempoBgPrimary
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Meal type picker
                    mealTypePicker

                    // Food items list or empty state
                    if foodItems.isEmpty {
                        emptyState
                    } else {
                        foodItemsList
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 140) // Room for sticky bottom bar

                // Sticky bottom bar
                stickyBottomBar
            }
            .navigationTitle("Log Meal")
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
            .sheet(isPresented: $showFoodSearch) {
                FoodSearchView(
                    onFoodSelected: { item in
                        addFoodItem(item)
                    },
                    initialQuery: searchPrefill
                )
            }
            .sheet(isPresented: $showVoiceLog) {
                VoiceMealLogView(
                    onFoodSelected: { item in
                        addFoodItem(item)
                    },
                    onSearchInstead: { name in
                        searchPrefill = name
                        showFoodSearch = true
                    }
                )
            }
            .sheet(isPresented: $showPhotoAnalysis) {
                PhotoAnalysisView { items in
                    for item in items {
                        addFoodItem(item)
                    }
                }
            }
            .sheet(isPresented: $showBarcodeScanner) {
                BarcodeScannerView { item in
                    addFoodItem(item)
                }
            }
            .tempoToast($toast)
        }
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        Picker("Meal Type", selection: $selectedMealType) {
            ForEach(MealType.allCases) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.vertical, TempoSpacing.sm)
        .onChange(of: selectedMealType) { _, _ in
            HapticManager.selection()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "fork.knife")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color.tempoAsh)

            Text("Nothing here yet. That's on you.")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
                .padding(.top, TempoSpacing.lg)

            Text("Search, scan, or snap a photo to add food.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, TempoSpacing.sm)

            // Input method buttons
            inputMethodButtons
                .padding(.top, TempoSpacing.xxl)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Food Items List

    private var foodItemsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Input method buttons at top
                inputMethodButtons
                    .padding(.top, TempoSpacing.md)
                    .padding(.bottom, TempoSpacing.lg)

                // Items
                ForEach(foodItems) { item in
                    foodItemRow(item)

                    if item.id != foodItems.last?.id {
                        Divider()
                            .background(Color.tempoDivider)
                            .padding(.horizontal, TempoSpacing.cardPadding)
                    }
                }
            }
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
        }
    }

    // MARK: - Food Item Row

    private func foodItemRow(_ item: FoodItem) -> some View {
        HStack(spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(item.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Text(item.portionDescription)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: TempoSpacing.xxs) {
                Text("\(item.calories) kcal")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("P: \(Int(item.protein))g")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // Delete button
            Button {
                removeFoodItem(item)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.tempoTextDisabled)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, TempoSpacing.cardPadding)
        .padding(.vertical, TempoSpacing.listItemVertical)
    }

    // MARK: - Input Method Buttons

    private var inputMethodButtons: some View {
        HStack(spacing: TempoSpacing.lg) {
            inputMethodButton(icon: "magnifyingglass", label: "Search") {
                showFoodSearch = true
            }

            inputMethodButton(icon: "camera.fill", label: "Photo") {
                showPhotoAnalysis = true
            }

            inputMethodButton(icon: "barcode.viewfinder", label: "Scan") {
                showBarcodeScanner = true
            }

            inputMethodButton(icon: "mic.fill", label: "Voice") {
                showVoiceLog = true
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    private func inputMethodButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.lightImpact()
            action()
        }) {
            VStack(spacing: TempoSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 56, height: 56)
                    .background(Color.tempoSignal.opacity(0.1))
                    .clipShape(Circle())

                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sticky Bottom Bar

    private var stickyBottomBar: some View {
        VStack(spacing: TempoSpacing.md) {
            // Running totals
            if !foodItems.isEmpty {
                HStack(spacing: 0) {
                    macroChip("\(totalCalories) kcal", color: Color.tempoViolet)
                    Spacer()
                    macroChip("P: \(Int(totalProtein))g", color: Color.tempoMacroProtein)
                    Spacer()
                    macroChip("C: \(Int(totalCarbs))g", color: Color.tempoMacroCarbs)
                    Spacer()
                    macroChip("F: \(Int(totalFat))g", color: Color.tempoMacroFat)
                }
                .padding(.horizontal, TempoSpacing.xs)
            }

            // Log Meal button
            Button {
                logMeal()
            } label: {
                Text("Log Meal")
            }
            .buttonStyle(.tempoPrimary)
            .disabled(foodItems.isEmpty)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.bottomSafe)
        .background(
            Color.tempoSurfaceCard
                .shadow(color: Color.tempoInk.opacity(0.08), radius: 8, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func macroChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.tempoCaption1)
            .fontWeight(.medium)
            .foregroundStyle(color)
    }

    // MARK: - Actions

    private func addFoodItem(_ item: FoodItem) {
        withAnimation(TempoAnimation.springMedium) {
            foodItems.append(item)
        }
        HapticManager.lightImpact()
    }

    private func removeFoodItem(_ item: FoodItem) {
        withAnimation(TempoAnimation.springMedium) {
            foodItems.removeAll { $0.id == item.id }
        }
        HapticManager.lightImpact()
    }

    private func logMeal() {
        guard !foodItems.isEmpty else {
            return
        }
        HapticManager.notification(.success)
        onMealLogged?(foodItems, selectedMealType)
        toast = ToastData(
            message: "\(selectedMealType.rawValue) logged. \(totalCalories) kcal.",
            style: .success
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
}

// MARK: - FoodItem

struct FoodItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var brand: String?
    var servingSize: String
    var servingQuantity: Double
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double

    var portionDescription: String {
        let qty = servingQuantity == 1.0
            ? servingSize
            : "\(String(format: "%.1f", servingQuantity)) x \(servingSize)"
        if let brand {
            return "\(brand) - \(qty)"
        }
        return qty
    }

    static func == (lhs: FoodItem, rhs: FoodItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ConfidenceLevel

enum ConfidenceLevel {
    case high
    case medium
    case low

    var label: String {
        switch self {
        case .high: "Verified"
        case .medium: "Estimate"
        case .low: "Best guess"
        }
    }

    var color: Color {
        switch self {
        case .high: .tempoSuccess
        case .medium: .tempoWarning
        case .low: .tempoError
        }
    }

    var icon: String {
        switch self {
        case .high: "checkmark.circle.fill"
        case .medium: "exclamationmark.circle.fill"
        case .low: "questionmark.circle.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    MealLoggingView()
}

#Preview("With Items") {
    MealLoggingView(
        foodItems: [
            FoodItem(
                id: UUID(), name: "Chicken Breast", brand: nil,
                servingSize: "150g", servingQuantity: 1.0,
                calories: 248, protein: 46.0, carbs: 0.0, fat: 5.4
            ),
            FoodItem(
                id: UUID(), name: "Brown Rice", brand: nil,
                servingSize: "200g cooked", servingQuantity: 1.0,
                calories: 220, protein: 5.0, carbs: 46.0, fat: 1.8
            ),
            FoodItem(
                id: UUID(), name: "Greek Yogurt", brand: "Fage",
                servingSize: "170g", servingQuantity: 1.0,
                calories: 100, protein: 18.0, carbs: 6.0, fat: 0.7
            ),
        ]
    )
}
