//
// FluidSheet.swift
// Tempo
//
// "What did you drink?" for one session: the same four answers as the
// notification buttons, an exact amount, and the bottle size they are based on.
//

import SwiftUI

struct FluidSheet: View {
    let model: RecoveryCoachModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var exactText = ""
    @State private var bottleText = ""
    @State private var error: String?
    @State private var bottleAtOpen = 0
    @ScaledMetric(relativeTo: .title) private var exactSize: CGFloat = Tide.numeralM
    @ScaledMetric(relativeTo: .body) private var useWidth: CGFloat = Tide.s10 * 2.5

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: Tide.s3) {
                Text("What you drank")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Tide.s2)
                FuelIconButton(systemImage: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s4)

            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s6) {
                    Text("From the start of the session until you weighed yourself. Everything you drank after the weigh-in doesn't count.")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)

                    // The four quick answers as tiles: the amount drawn as a drop,
                    // the size in mL from the bottle below.
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: Tide.s3),
                            count: typeSize.isAccessibilitySize ? 1 : 2
                        ),
                        spacing: Tide.s3
                    ) {
                        ForEach(CoachQuickAnswerAction.allCases, id: \.rawValue) { action in
                            answerTile(action)
                        }
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("Or an exact amount").tideLabel()
                        exactLayout {
                            HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                                TextField("500", text: $exactText)
                                    .keyboardType(.numberPad)
                                    .font(Tide.numeral(exactSize))
                                    .foregroundStyle(Tide.text)
                                    .accessibilityIdentifier("coach.exactField")
                                Text("mL")
                                    .font(Tide.body)
                                    .foregroundStyle(Tide.text3)
                            }
                            .fuelField(radius: Tide.tileRadius)
                            Button("Use") { saveExact() }
                                .buttonStyle(.tidePrimary)
                                .frame(width: typeSize.isAccessibilitySize ? nil : useWidth)
                                .accessibilityIdentifier("coach.exactUse")
                        }
                        if let error {
                            Text(error)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("Your bottle").tideLabel()
                        HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                            TextField("750", text: $bottleText)
                                .keyboardType(.numberPad)
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                                .onChange(of: bottleText) { _, new in
                                    if let ml = Int(new) {
                                        model.setBottleMl(ml)
                                    }
                                }
                                .accessibilityIdentifier("coach.bottleField")
                            Text("mL per bottle")
                                .font(Tide.body)
                                .foregroundStyle(Tide.text3)
                        }
                        .fuelField(radius: Tide.tileRadius)
                        Text("The notification buttons use this size.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if model.fluids.editedLiters != nil || model.fluids.quickAnswerLiters != nil {
                        Button {
                            Task { await model.clearFluid() }
                            dismiss()
                        } label: {
                            Text("Clear and start over")
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.tideGlass)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s5)
                .padding(.bottom, Tide.s8)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .top)
        }
        .tidePage()
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onAppear {
            bottleText = String(model.bottleMl)
            bottleAtOpen = model.bottleMl
        }
        .onDisappear {
            // A new bottle size re-prices an earlier "one bottle" answer.
            if model.bottleMl != bottleAtOpen {
                Task { await model.recompute() }
            }
        }
    }

    /// Field and Use side by side; stacked at accessibility sizes.
    private var exactLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s2))
    }

    private func answerTile(_ action: CoachQuickAnswerAction) -> some View {
        let icon = switch action {
        case .nothing: "drop"
        case .halfBottle: "drop.halffull"
        case .oneBottle: "drop.fill"
        case .twoBottles: "drop.circle.fill"
        }
        let ml = Int((action.bottles * Double(model.bottleMl)).rounded())
        return Button {
            HapticManager.selection()
            Task { await model.answerFluid(action) }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideIconTile(systemName: icon, tint: Tide.water)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(action.title)
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                    Text(ml == 0 ? "0 mL" : "about \(ml) mL")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Tide.hit + Tide.s10, alignment: .topLeading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(FuelPressStyle())
        .accessibilityIdentifier("coach.answer.\(action.rawValue)")
    }

    private func saveExact() {
        guard let ml = Int(exactText.trimmingCharacters(in: .whitespaces)), ml >= 0, ml <= 10000 else {
            error = "Enter millilitres between 0 and 10000."
            return
        }
        Task { await model.editFluid(liters: Double(ml) / 1000) }
        dismiss()
    }
}
