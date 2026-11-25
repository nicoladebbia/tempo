//
// WaterCardView.swift
// Tempo
//
// Self-contained water card for Nutrition Today: saved ml / target with a
// progress bar, +250, +500, a custom amount and Undo. Everything goes through
// `WaterStore` (saved on the phone, mirrored to Apple Health as dietaryWater),
// and the card re-reads whenever `.tempoWaterLogged` fires, so the Dashboard
// Fuel tile and this card never disagree.
//

import SwiftData
import SwiftUI

// MARK: - WaterCardView

struct WaterCardView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var totalMl = 0
    @State
    private var lastEntryMl: Int?
    /// nil until the first read, so a placeholder 2,500 never flashes up.
    @State
    private var resolvedTargetMl: Int?
    @State
    private var showCustom = false

    /// Today's target, always the canonical one (`todayWaterTargetMl`), so this
    /// card, the Today tile and the coach show the same number.
    private var target: Int? {
        resolvedTargetMl.map { max($0, 1) }
    }

    private var progress: Double {
        guard let target else {
            return 0
        }
        return min(Double(totalMl) / Double(target), 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            let title = HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Image(systemName: "drop.fill")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.water)
                    .accessibilityHidden(true)
                Text("Water").tideLabel()
            }
            let total = HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                TideNumber(
                    totalMl.formatted(),
                    size: Tide.numeralS,
                    relativeTo: .headline,
                    color: target.map { totalMl >= $0 } == true ? Tide.good : Tide.text
                )
                Text(target.map { String(localized: "/ \($0.formatted()) ml") } ?? String(localized: "ml"))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(target.map { String(localized: "Water \(totalMl) of \($0) millilitres") } ?? String(localized: "Water \(totalMl) millilitres"))
            .accessibilityIdentifier("water.total")

            VStack(alignment: .leading, spacing: Tide.s3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                        title
                        Spacer(minLength: Tide.s2)
                        total
                    }
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        title
                        total
                    }
                }

                TideLevelBar(progress: progress, color: Tide.water, height: Tide.bar)
                    .animation(Tide.settle, value: progress)
            }
            .explains(.fuelWaterTarget.showing(target.map { String(localized: "\(totalMl.formatted()) / \($0.formatted()) ml") }))

            GlassEffectContainer(spacing: Tide.s2) {
                // One row when it fits; otherwise Undo drops under the chips
                // so no label ever wraps mid-word.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tide.s2) {
                        chips
                        Spacer(minLength: 0)
                        undoButton
                    }
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        HStack(spacing: Tide.s2) { chips }
                        undoButton
                    }
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        chips
                        undoButton
                    }
                }
            }
        }
        .tideCard()
        .sensoryFeedback(.success, trigger: totalMl) { old, new in new > old }
        .accessibilityIdentifier("water.card")
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWaterLogged)) { _ in
            reload()
        }
        .sheet(isPresented: $showCustom) {
            CustomWaterSheet { ml in
                add(ml)
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var chips: some View {
        chip("+250", id: "water.add250") { add(250) }
        chip("+500", id: "water.add500") { add(500) }
        chip(String(localized: "Custom"), id: "water.addCustom") { showCustom = true }
    }

    @ViewBuilder
    private var undoButton: some View {
        if let lastEntryMl {
            Button {
                undo()
            } label: {
                Label("Undo \(lastEntryMl)", systemImage: "arrow.uturn.backward")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("water.undo")
        }
    }

    private func chip(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.water)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, Tide.s4)
                .frame(minHeight: Tide.hit)
                .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func store() -> WaterStore {
        WaterStore(context: modelContext, healthKit: services.healthKit)
    }

    /// Saves the water and offers a few seconds to take back exactly that entry.
    private func add(_ ml: Int) {
        guard let log = store().add(ml: ml) else {
            FuelLogToast.post(ToastData(message: String(localized: "Couldn't save that water. Try again."), style: .error))
            return
        }
        let id = log.id
        let context = modelContext
        let healthKit = services.healthKit
        FuelLogToast.post(ToastData(message: String(localized: "\(ml) ml of water added."), style: .success, actionTitle: String(localized: "Undo")) {
            let undone = WaterStore(context: context, healthKit: healthKit).remove(id: id)
            FuelLogToast.post(
                undone
                    ? ToastData(message: String(localized: "Water taken back."), style: .info)
                    : ToastData(message: String(localized: "That water was already taken back."), style: .info)
            )
        })
    }

    private func undo() {
        store().undoLast()
        HapticManager.lightImpact()
    }

    private func reload() {
        totalMl = WaterStore.total(in: modelContext)
        lastEntryMl = WaterStore.entries(on: Date(), in: modelContext).last?.ml
        resolvedTargetMl = DailyNutritionTargets.todayWaterTargetMl(in: modelContext)
    }
}

// MARK: - CustomWaterSheet

private struct CustomWaterSheet: View {
    let onAdd: (Int) -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State
    private var text = ""
    @FocusState
    private var focused: Bool

    private var amount: Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
              value > 0, value <= WaterStore.maxEntryMl
        else {
            return nil
        }
        return value
    }

    var body: some View {
        VStack(spacing: Tide.s4) {
            Text("How much?").tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TextField("330", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(Tide.numeral(Tide.numeralL))
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("water.customField")
                Text("ml")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text2)
            }
            .padding(.horizontal, Tide.edge)
            Button("Add water") {
                if let amount {
                    onAdd(amount)
                    dismiss()
                }
            }
            .buttonStyle(.tidePrimary)
            .disabled(amount == nil)
            .padding(.horizontal, Tide.edge)
            .accessibilityIdentifier("water.customAdd")
        }
        .padding(.top, Tide.s6)
        .frame(maxHeight: .infinity, alignment: .top)
        .tidePage()
        .onAppear { focused = true }
    }
}
