//
// MealReviewHost.swift
// Tempo
//
// One place that shows the "Confirm meal" sheet and saves what it confirms, so
// Quick Log (Today sheet or Log tab), a meal photo and a scanned product all
// land on the same screen, wherever the user already is, and all save through
// the same path (duplicate check -> EatenMealRecorder -> toast). The sheet is
// presented ON TOP of the current screen: no tab switch, no dismiss-then-present.
//

import SwiftData
import SwiftUI

extension Notification.Name {
    /// Posted after a confirmed meal was saved (or failed to). The Nutrition tab shows the toast.
    static let tempoMealLogToast = Notification.Name("tempoMealLogToast")
}

// MARK: - Request

/// What the Confirm Meal sheet is asked to review.
struct MealReviewRequest: Identifiable, Equatable {
    let items: [ParsedFoodItem]
    /// Meal the user literally named ("for lunch"). nil = follow the time.
    var mealType: MealType?
    /// Time the parser read ("at 1pm"). nil = now.
    var eatenAt: Date?

    /// Derived from the foods, never a fresh UUID: an id that changes every
    /// time SwiftUI re-reads the binding re-presents the sheet in a loop.
    var id: String {
        items.map(\.id).joined(separator: "|")
    }

    static func == (lhs: MealReviewRequest, rhs: MealReviewRequest) -> Bool {
        lhs.id == rhs.id
    }

    init(items: [ParsedFoodItem], mealType: MealType? = nil, eatenAt: Date? = nil) {
        self.items = items
        self.mealType = mealType
        self.eatenAt = eatenAt
    }

    init(foods: [FoodItem]) {
        self.init(items: foods.map(Self.parsedFood(from:)))
    }

    static func parsedFood(from food: FoodItem) -> ParsedFoodItem {
        ParsedFoodItem(
            id: food.id.uuidString,
            name: food.name,
            quantityGrams: EatenMealRecorder.gramsFromServingSize(food.servingSize) * food.servingQuantity,
            calories: Double(food.calories),
            proteinG: food.protein,
            carbsG: food.carbs,
            fatG: food.fat,
            isVerified: food.source != .manual,
            source: food.source,
            barcode: food.barcode
        )
    }

    /// Maps the parser's lowercase meal name to a typed MealType (nil = unknown).
    static func mealType(fromHint raw: String?) -> MealType? {
        switch raw {
        case "breakfast": .breakfast
        case "lunch": .lunch
        case "dinner": .dinner
        case "snack": .snack
        default: nil
        }
    }

    /// Quick Log text -> request. nil when nothing could be parsed.
    static func parsing(_ text: String, apiClient: APIClient) async throws -> MealReviewRequest? {
        let parsed = try await NaturalLanguageLoggingService(apiClient: apiClient).parseNaturalLanguageWithTiming(text)
        guard !parsed.items.isEmpty else {
            return nil
        }
        return MealReviewRequest(items: parsed.items, mealType: mealType(fromHint: parsed.mealType), eatenAt: parsed.eatenAt)
    }
}

// MARK: - Commit

/// Saves a confirmed review. Pure of UI so it is unit-testable.
@MainActor
enum MealReviewCommitter {
    enum Outcome {
        case logged(ToastData)
        case failed(ToastData)
        /// The foods repeat ones already in the (eaten) meal: ask Add or Edit.
        case needsDecision(names: [String])
    }

    static func inputs(from items: [ParsedFoodItem]) -> [MealFoodItemInput] {
        items.map { item in
            MealFoodItemInput(
                foodId: item.id,
                name: item.name,
                brand: nil,
                servings: 1,
                servingSize: item.quantityGrams,
                servingUnit: "g",
                calories: item.calories,
                proteinGrams: item.proteinG,
                carbsGrams: item.carbsG,
                fatGrams: item.fatG,
                source: item.source ?? (item.isVerified ? .cached : .claude),
                barcode: item.barcode,
                origin: item.origin
            )
        }
    }

    static func duplicateNames(items: [ParsedFoodItem], type: MealType, eatenAt: Date, modelContext: ModelContext) -> [String] {
        EatenMealRecorder.duplicateNames(
            of: inputs(from: items), type: type, eatenAt: eatenAt,
            in: CanonicalMeals.meals(on: Date(), in: modelContext)
        )
    }

    /// Saves through `EatenMealRecorder` (the one write path) and describes
    /// the result as a toast. `resolution` only matters for a repeat of a food
    /// already in an eaten meal.
    static func commit(
        _ items: [ParsedFoodItem],
        type: MealType,
        eatenAt: Date,
        origin: MealOrigin?,
        resolution: EatenMealRecorder.DuplicateResolution,
        modelContext: ModelContext,
        notifications: (any NotificationServiceProtocol)?
    ) -> Outcome {
        let foods = inputs(from: items).map(EatenMealRecorder.plannedFood(from:))
        // Dry run first (the recorder does the real deduction): only foods
        // from the kitchen come off the pantry.
        let pantryLines = PantryDecrementService.preview(
            foods: EatenMealRecorder.pantryFoods(foods, origin: origin), modelContext: modelContext
        )
        do {
            let result = try EatenMealRecorder.record(
                inputs(from: items),
                type: type,
                eatenAt: eatenAt,
                source: .naturalLanguage,
                resolution: resolution,
                origin: origin,
                modelContext: modelContext,
                notifications: notifications
            )
            var message = "\(type.displayName) logged. \(Int(result.logged.calories)) kcal."
            if resolution == .add, !pantryLines.isEmpty {
                message += " Off your pantry: " + pantryLines.prefix(3).map(\.displayName).joined(separator: ", ")
                    + (pantryLines.count > 3 ? " +\(pantryLines.count - 3)" : "") + "."
            }
            return .logged(ToastData(message: message, style: .success))
        } catch {
            return .failed(ToastData(message: "Couldn't save: \(error.localizedDescription)", style: .error))
        }
    }
}

// MARK: - Host

struct MealReviewHost: ViewModifier {
    @Binding
    var request: MealReviewRequest?
    /// Called once a meal was saved (not on cancel): close the screen that started the flow.
    var onLogged: () -> Void = {}

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var duplicate: Pending?

    private struct Pending: Identifiable {
        let id = UUID()
        let items: [ParsedFoodItem]
        let type: MealType
        let eatenAt: Date
        let origin: MealOrigin?
        let names: [String]
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $request) { current in
                ParsedFoodReviewSheet(
                    items: current.items,
                    hintedMealType: current.mealType,
                    hintedDate: current.eatenAt,
                    onConfirm: { items, type, eatenAt, origin in
                        confirm(items, type: type, eatenAt: eatenAt, origin: origin)
                    },
                    onCancel: {}
                )
            }
            .alert(
                "Already logged",
                isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }),
                presenting: duplicate
            ) { pending in
                Button("Add another") {
                    finish(pending.items, pending.type, pending.eatenAt, pending.origin, .add)
                }
                Button("Edit existing") {
                    finish(pending.items, pending.type, pending.eatenAt, pending.origin, .edit)
                }
                Button("Cancel", role: .cancel) {}
            } message: { pending in
                Text("You already have \(pending.names.joined(separator: ", ")) in this meal. Add another portion, or edit the existing one?")
            }
    }

    private func confirm(_ items: [ParsedFoodItem], type: MealType, eatenAt: Date, origin: MealOrigin) {
        let names = MealReviewCommitter.duplicateNames(items: items, type: type, eatenAt: eatenAt, modelContext: modelContext)
        if names.isEmpty {
            finish(items, type, eatenAt, origin, .add)
        } else {
            duplicate = Pending(items: items, type: type, eatenAt: eatenAt, origin: origin, names: names)
        }
    }

    private func finish(
        _ items: [ParsedFoodItem], _ type: MealType, _ eatenAt: Date, _ origin: MealOrigin?,
        _ resolution: EatenMealRecorder.DuplicateResolution
    ) {
        let outcome = MealReviewCommitter.commit(
            items, type: type, eatenAt: eatenAt, origin: origin, resolution: resolution,
            modelContext: modelContext, notifications: services.notifications
        )
        switch outcome {
        case let .logged(toast):
            Self.post(toast)
            request = nil
            duplicate = nil
            onLogged()
        case let .failed(toast):
            Self.post(toast)
        case .needsDecision:
            break
        }
    }

    private static func post(_ toast: ToastData) {
        NotificationCenter.default.post(
            name: .tempoMealLogToast, object: nil,
            userInfo: ["message": toast.message, "error": toast.style == .error]
        )
    }
}

extension View {
    /// Shows the Confirm Meal sheet for `request` on top of this screen and saves what it confirms.
    func mealReview(_ request: Binding<MealReviewRequest?>, onLogged: @escaping () -> Void = {}) -> some View {
        modifier(MealReviewHost(request: request, onLogged: onLogged))
    }
}
