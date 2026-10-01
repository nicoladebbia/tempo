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
        VStack(spacing: TempoSpacing.md) {
            HStack {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.tempoElectric)
                    Text("WATER")
                        .font(.tempoModuleTag)
                        .tracking(TempoTracking.drillLabel)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Text("\(totalMl) / \(target) ml")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(totalMl >= target ? Color.tempoSuccess : Color.tempoTextPrimary)
                    .contentTransition(.numericText())
                    .accessibilityIdentifier("water.total")
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoElectric.opacity(0.15))
                    Capsule()
                        .fill(Color.tempoElectric)
                        .frame(width: geo.size.width * progress)
                        .animation(TempoAnimation.springData, value: progress)
                }
            }
            .frame(height: 10)

            HStack(spacing: TempoSpacing.sm) {
                chip("+250", id: "water.add250") { add(250) }
                chip("+500", id: "water.add500") { add(500) }
                chip("Custom", id: "water.addCustom") { showCustom = true }
                Spacer(minLength: 0)
                if let lastEntryMl {
                    Button {
                        undo()
                    } label: {
                        Label("Undo \(lastEntryMl)", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("water.undo")
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .accessibilityIdentifier("water.card")
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWaterLogged)) { _ in
            reload()
        }
        .sheet(isPresented: $showCustom) {
            CustomWaterSheet { ml in
                add(ml)
            }
            .presentationDetents([.height(260)])
        }
    }

    private func chip(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticManager.lightImpact()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.tempoElectric)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.tempoElectric.opacity(0.12))
                .clipShape(Capsule())
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
        VStack(spacing: TempoSpacing.lg) {
            Text("HOW MUCH?")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            HStack {
                TextField("330", text: $text)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("water.customField")
                Text("ml")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(.horizontal, TempoSpacing.xl)
            Button("Add water") {
                if let amount {
                    onAdd(amount)
                    dismiss()
                }
            }
            .buttonStyle(.tempoPrimary)
            .disabled(amount == nil)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .accessibilityIdentifier("water.customAdd")
        }
        .padding(.top, TempoSpacing.xl)
        .background(Color.tempoBgPrimary.ignoresSafeArea())
        .onAppear { focused = true }
    }
}
