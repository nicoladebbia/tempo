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

    private var portionKcal: Int {
        Int((product.nutrients(forGrams: grams).kcal ?? 0).rounded())
    }

    var body: some View {
        VStack(spacing: TempoSpacing.buttonStackVertical) {
            if let inventory {
                Text(inventory.line)
                    .font(.tempoCaption1)
                    .foregroundStyle(inventory.atHome != nil || inventory.onList ? Color.tempoTextPrimary : Color.tempoTextSecondary)
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
            .buttonStyle(.tempoPrimary)
            .disabled(!product.per100g.hasCoreMacros || grams <= 0)
            .accessibilityIdentifier("foodCheckLog")

            // Two equal secondary buttons under the primary: same width, same
            // height (the style's 52 pt), centred inside the screen gutters.
            HStack(spacing: TempoSpacing.buttonStackVertical) {
                Button {
                    addToPantry()
                } label: {
                    Label("Pantry", systemImage: "refrigerator")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(.tempoSecondary)
                .accessibilityIdentifier("foodCheckPantry")

                Button {
                    addToList()
                } label: {
                    Label("List", systemImage: "cart.badge.plus")
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }
                .buttonStyle(.tempoSecondary)
                .accessibilityIdentifier("foodCheckList")
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.sm)
        .background(Color.tempoBgPrimary)
        .task(id: product.id) { refreshInventory() }
        .sheet(isPresented: $showLogSheet) {
            logSheet
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Log sheet

    private var logSheet: some View {
        VStack(spacing: TempoSpacing.lg) {
            VStack(spacing: TempoSpacing.xxs) {
                Text("Log \(FoodProductView.format(grams)) \(product.unit) of \(product.name)")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("\(portionKcal) kcal. Pick the meal. Change the grams on the page first.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("foodCheckMealType")
            Button {
                logIt()
            } label: {
                Text("Log it").frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .accessibilityIdentifier("foodCheckLogConfirm")
        }
        .padding(TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .background(Color.tempoBgPrimary)
    }

    // MARK: - Actions

    private func logIt() {
        do {
            let logged = try FoodProductActions.log(
                product, grams: grams, type: mealType, modelContext: modelContext, notifications: services.notifications
            )
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
