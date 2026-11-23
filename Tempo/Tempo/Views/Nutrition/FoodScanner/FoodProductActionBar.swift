//
// FoodProductActionBar.swift
// Tempo
//
// Bottom bar of the Food check product page: Log, Add to pantry, Add to list,
// plus a one-line "what you already have". Every action confirms with a toast.
//

import SwiftData
import SwiftUI

struct FoodProductActionBar: View {
    let product: FoodProduct
    let grams: Double
    @Binding
    var toast: ToastData?
    /// Remembers the portion the user logged (same as the logger's add bar).
    var onLogged: (() -> Void)?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var inventory: FoodProductActions.Inventory?
    @State
    private var showLogSheet = false
    @State
    private var mealType = EatenMealRecorder.defaultMealType()
    @State
    private var originPickedByHand = false
    @State
    private var origin: MealOrigin = HomeLocationStore().lastOrigin ?? .kitchen

    private var portionKcal: Int {
        Int((product.nutrients(forGrams: grams).kcal ?? 0).rounded())
    }

    var body: some View {
        VStack(spacing: Tide.s3) {
            if let inventory {
                Text(inventory.line)
                    .font(Tide.caption)
                    .foregroundStyle(inventory.atHome != nil || inventory.onList ? Tide.text : Tide.text2)
                    .padding(.horizontal, Tide.s3)
                    .padding(.vertical, Tide.s2)
                    .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("foodInventoryLine")
            }
            Button {
                HapticManager.lightImpact()
                mealType = EatenMealRecorder.defaultMealType()
                showLogSheet = true
            } label: {
                Text("Log \(FoodProductView.format(grams)) \(product.unit) · \(portionKcal) kcal")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .buttonStyle(.tidePrimary)
            .disabled(!product.per100g.hasCoreMacros || grams <= 0)
            .accessibilityIdentifier("foodCheckLog")

            // Two equal secondary buttons under the primary: same width, same
            // height (the style's 52 pt), centred inside the screen gutters.
            GlassEffectContainer(spacing: Tide.s3) {
                HStack(spacing: Tide.s3) {
                    Button {
                        addToPantry()
                    } label: {
                        Label("Pantry", systemImage: "refrigerator")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("foodCheckPantry")

                    Button {
                        addToList()
                    } label: {
                        Label("List", systemImage: "cart.badge.plus")
                            .labelStyle(.titleAndIcon)
                            .lineLimit(1)
                    }
                    .buttonStyle(.tideGlass)
                    .accessibilityIdentifier("foodCheckList")
                }
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s3)
        .padding(.bottom, Tide.s2)
        .task(id: product.id) { refreshInventory() }
        .sheet(isPresented: $showLogSheet) {
            logSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Log sheet

    private var logSheet: some View {
        VStack(spacing: Tide.s4) {
            VStack(spacing: Tide.hair) {
                Text("Log \(FoodProductView.format(grams)) \(product.unit) of \(product.name)")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(portionKcal) kcal. Pick the meal. Change the grams on the page first.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("foodCheckMealType")
            MealOriginPicker(
                origin: $origin,
                foods: [EatenMealRecorder.plannedFood(from: product.foodItem(grams: grams).mealFoodInput)],
                pickedByHand: $originPickedByHand
            )
            Button {
                logIt()
            } label: {
                Text("Log it").frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidePrimary)
            .accessibilityIdentifier("foodCheckLogConfirm")
        }
        .padding(Tide.edge)
        .padding(.top, Tide.s3)
        .kitchenSheet()
    }

    // MARK: - Actions

    private func logIt() {
        do {
            let logged = try FoodProductActions.log(
                product, grams: grams, type: mealType, origin: origin,
                modelContext: modelContext, notifications: services.notifications
            )
            HomeLocationStore().lastOrigin = origin
            showLogSheet = false
            HapticManager.notification(.success)
            onLogged?()
            toast = ToastData(
                message: "\(mealType.displayName) logged. \(Int(logged.calories.rounded())) kcal, \(Int(logged.protein.rounded())) g protein.",
                style: .success
            )
        } catch {
            HapticManager.notification(.error)
            showLogSheet = false
            toast = ToastData(message: "Couldn't log it: \(error.localizedDescription)", style: .error)
        }
    }

    private func addToPantry() {
        do {
            let item = try FoodProductActions.addToPantry(product, modelContext: modelContext)
            HapticManager.notification(.success)
            toast = ToastData(message: "\(item.displayName) is in your pantry.", style: .success)
            refreshInventory()
        } catch {
            HapticManager.notification(.error)
            toast = ToastData(message: "Couldn't add it to the pantry: \(error.localizedDescription)", style: .error)
        }
    }

    private func addToList() {
        do {
            switch try FoodProductActions.addToList(product, modelContext: modelContext) {
            case .added:
                HapticManager.notification(.success)
                toast = ToastData(message: "\(product.name) is on your list.", style: .success)
            case .alreadyOnList:
                HapticManager.lightImpact()
                toast = ToastData(message: "Already on your list.", style: .info)
            case .noList:
                HapticManager.warning()
                toast = ToastData(
                    message: "You have no grocery list yet. Build your weekly plan first, then add it.",
                    style: .warning
                )
            }
            refreshInventory()
        } catch {
            HapticManager.notification(.error)
            toast = ToastData(message: "Couldn't add it to the list: \(error.localizedDescription)", style: .error)
        }
    }

    private func refreshInventory() {
        inventory = FoodProductActions.inventory(for: product, modelContext: modelContext)
    }
}
