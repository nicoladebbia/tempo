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
    /// Today's target in ml. nil = work it out from the canonical daily target.
    var targetMl: Int?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var totalMl = 0
    @State
    private var lastEntryMl: Int?
    @State
    private var resolvedTargetMl = 2500
    @State
    private var showCustom = false

    private var target: Int {
        max(targetMl ?? resolvedTargetMl, 1)
    }

    private var progress: Double {
        min(Double(totalMl) / Double(target), 1.0)
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
                    color: totalMl >= target ? Tide.good : Tide.text
                )
                Text("/ \(target.formatted()) ml")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water \(totalMl) of \(target) millilitres")
            .accessibilityIdentifier("water.total")

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
        chip("Custom", id: "water.addCustom") { showCustom = true }
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

    private func add(_ ml: Int) {
        store().add(ml: ml)
    }

    private func undo() {
        store().undoLast()
        HapticManager.lightImpact()
    }

    private func reload() {
        totalMl = WaterStore.total(in: modelContext)
        lastEntryMl = WaterStore.entries(on: Date(), in: modelContext).last?.ml
        if targetMl == nil {
            resolvedTargetMl = DailyNutritionTargets.today(
                in: modelContext,
                whoopAvgTDEE: nil,
                recoveryScore: DailyNutritionTargets.storedRecoveryScore(in: modelContext)
            ).hydrationMl
        }
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
