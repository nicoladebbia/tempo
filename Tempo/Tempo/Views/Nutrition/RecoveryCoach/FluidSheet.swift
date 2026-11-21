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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("WHAT YOU DRANK")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.tempoSubheadline.weight(.semibold))
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(width: 44, height: 44)
                        .background(Color.tempoSurfaceElevated)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)

            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    Text("From the start of the session until you weighed yourself. Everything you drank after the weigh-in doesn't count.")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: TempoSpacing.sm) {
                        ForEach(CoachQuickAnswerAction.allCases, id: \.rawValue) { action in
                            Button(action.title) {
                                Task { await model.answerFluid(action) }
                                dismiss()
                            }
                            .buttonStyle(.tempoSecondary)
                            .accessibilityIdentifier("coach.answer.\(action.rawValue)")
                        }
                    }

                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("OR AN EXACT AMOUNT")
                            .font(.tempoModuleTag)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoTextSecondary)
                        HStack {
                            TextField("500", text: $exactText)
                                .keyboardType(.numberPad)
                                .font(.tempoTimerDisplaySmall)
                                .accessibilityIdentifier("coach.exactField")
                            Text("mL").foregroundStyle(Color.tempoTextTertiary)
                            Button("Use") { saveExact() }
                                .buttonStyle(.tempoPrimary)
                                .frame(width: 100)
                                .accessibilityIdentifier("coach.exactUse")
                        }
                        if let error {
                            Text(error).font(.tempoCaption1).foregroundStyle(Color.tempoError)
                        }
                    }

                    VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                        Text("YOUR BOTTLE")
                            .font(.tempoModuleTag)
                            .tracking(TempoTracking.drillLabel)
                            .foregroundStyle(Color.tempoTextSecondary)
                        HStack {
                            TextField("750", text: $bottleText)
                                .keyboardType(.numberPad)
                                .font(.tempoHeadline)
                                .onChange(of: bottleText) { _, new in
                                    if let ml = Int(new) { model.setBottleMl(ml) }
                                }
                                .accessibilityIdentifier("coach.bottleField")
                            Text("mL per bottle").foregroundStyle(Color.tempoTextTertiary)
                        }
                        Text("The notification buttons use this size.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }

                    if model.fluids.editedLiters != nil || model.fluids.quickAnswerLiters != nil {
                        Button("Clear and start over") {
                            Task { await model.clearFluid() }
                            dismiss()
                        }
                        .buttonStyle(.tempoGhost)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.xl)
                .padding(.bottom, TempoSpacing.xl)
            }
        }
        .background(Color.tempoBgPrimary.ignoresSafeArea())
        .onAppear {
            bottleText = String(model.bottleMl)
            bottleAtOpen = model.bottleMl
        }
        .onDisappear {
            // A new bottle size re-prices an earlier "one bottle" answer.
            if model.bottleMl != bottleAtOpen { Task { await model.recompute() } }
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
