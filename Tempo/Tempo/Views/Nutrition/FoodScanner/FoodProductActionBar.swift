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
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
        VStack(spacing: Tide.s2) {
            if let inventory {
                // On glass, so the page text scrolling under the bar never shows through it.
                HStack(spacing: 0) {
                    Text(inventory.line)
                        .font(Tide.caption)
                        .foregroundStyle(inventory.atHome != nil || inventory.onList ? Tide.text : Tide.text2)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .padding(.horizontal, Tide.s3)
                        .padding(.vertical, Tide.s1)
                        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
                        .accessibilityIdentifier("foodInventoryLine")
                    Spacer(minLength: 0)
                }
                .transition(.opacity)
            }
            // One slim row: the primary action takes the width, the two
            // secondary ones sit beside it as round glass buttons. At the
            // accessibility sizes they drop under it with their words.
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            GlassEffectContainer(spacing: Tide.s3) {
                layout {
                    Button {
                        HapticManager.lightImpact()
                        mealType = EatenMealRecorder.defaultMealType()
                        showLogSheet = true
                    } label: {
                        Text("Log \(FoodProductView.format(grams)) \(product.unit) · \(portionKcal) kcal")
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(!product.per100g.hasCoreMacros || grams <= 0)
                    .accessibilityIdentifier("foodCheckLog")

                    HStack(spacing: Tide.s3) {
                        secondaryButton("Pantry", label: "Add to pantry", systemImage: "refrigerator", id: "foodCheckPantry", action: addToPantry)
                        secondaryButton("List", label: "Add to list", systemImage: "cart.badge.plus", id: "foodCheckList", action: addToList)
                    }
                }
            }
            .animation(Tide.snap, value: portionKcal)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s2)
        .animation(Tide.snap, value: inventory)
        .task(id: product.id) { refreshInventory() }
        .sheet(isPresented: $showLogSheet) {
            logSheet
                .presentationDetents([.height(Tide.Kitchen.logSheet)])
                .presentationDragIndicator(.visible)
        }
    }

    /// A round glass button with the icon alone; the words come back (and the
    /// buttons grow to full width) at the accessibility text sizes.
    private func secondaryButton(
        _ title: String, label: String, systemImage: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                Button(action: action) {
                    Label(title, systemImage: systemImage)
                        .lineLimit(1)
                        .minimumScaleFactor(Tide.labelShrink)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                }
                .buttonStyle(.tideGlass)
                .accessibilityLabel(label)
            } else {
                KitchenIconButton(systemImage: systemImage, label: label, size: Tide.Kitchen.barButton, action: action)
            }
        }
        .accessibilityIdentifier(id)
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
            let result = try FoodProductActions.record(
                product, grams: grams, type: mealType, origin: origin,
                modelContext: modelContext, notifications: services.notifications
            )
            let logged = result.logged
            HomeLocationStore().lastOrigin = origin
            showLogSheet = false
            HapticManager.notification(.success)
            onLogged?()
            toast = FuelLogToast.logged(
                "\(mealType.displayName) logged. \(Int(logged.calories.rounded())) kcal, \(Int(logged.protein.rounded())) g protein.",
                result: result,
                modelContext: modelContext,
                notifications: services.notifications
            )
        } catch {
            HapticManager.notification(.error)
            showLogSheet = false
            toast = ToastData(message: "Couldn't log it: \(error.localizedDescription)", style: .error)
        }
    }

    private func addToPantry() {
        do {
            let added = try FoodProductActions.addToPantryWithUndo(product, modelContext: modelContext)
            let context = modelContext
            HapticManager.notification(.success)
            toast = ToastData(
                message: "\(added.item.displayName) is in your pantry.", style: .success, actionTitle: "Undo"
            ) {
                KitchenUndo.restorePantry(added.undo, in: context)
                refreshInventory()
            }
            refreshInventory()
        } catch {
            HapticManager.notification(.error)
            toast = ToastData(message: "Couldn't add it to the pantry: \(error.localizedDescription)", style: .error)
        }
    }

    private func addToList() {
        do {
            let context = modelContext
            let added = try FoodProductActions.addToListReturningItem(product, modelContext: context)
            switch added.outcome {
            case .added:
                HapticManager.notification(.success)
                toast = ToastData(message: "\(product.name) is on your list.", style: .success, actionTitle: "Undo") {
                    if let id = added.itemID {
                        FoodProductActions.removeFromList(itemID: id, modelContext: context)
                    }
                    refreshInventory()
                }
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
