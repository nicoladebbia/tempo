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

                    GlassEffectContainer(spacing: Tide.s2) {
                        VStack(spacing: Tide.s2) {
                            ForEach(CoachQuickAnswerAction.allCases, id: \.rawValue) { action in
                                Button {
                                    Task { await model.answerFluid(action) }
                                    dismiss()
                                } label: {
                                    Text(action.title)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.tideGlass)
                                .accessibilityIdentifier("coach.answer.\(action.rawValue)")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Tide.s2) {
                        Text("Or an exact amount").tideLabel()
                        HStack(spacing: Tide.s2) {
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
                                .frame(width: useWidth)
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

    private func saveExact() {
        guard let ml = Int(exactText.trimmingCharacters(in: .whitespaces)), ml >= 0, ml <= 10000 else {
            error = "Enter millilitres between 0 and 10000."
            return
        }
        Task { await model.editFluid(liters: Double(ml) / 1000) }
        dismiss()
    }
}
