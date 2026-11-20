//
// RecoveryCoachCard.swift
// Tempo
//
// Small card on Nutrition Today. Hidden unless a session from the last 48 h
// needs a weigh-in or has a result. Tapping opens the Recovery Coach.
//

import SwiftUI

struct RecoveryCoachCard: View {
    @Environment(RecoveryCoachModel.self) private var model: RecoveryCoachModel?
    @Environment(ServiceContainer.self) private var services

    var body: some View {
        // Always-present container hosts the view; the card inside is conditional.
        VStack(spacing: 0) {
            if let model, let session = model.session {
                Button {
                    services.appState.requestedCoach = CoachRequest(id: session.id)
                } label: {
                    HStack(spacing: TempoSpacing.md) {
                        Image(systemName: "drop.fill")
                            .foregroundStyle(Color.tempoElectric)
                            .frame(width: 32, height: 32)
                            .background(Color.tempoElectric.opacity(0.14))
                            .clipShape(Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                            Text(title(model, session))
                                .font(.tempoSubheadline.weight(.semibold))
                                .foregroundStyle(Color.tempoTextPrimary)
                                .multilineTextAlignment(.leading)
                            Text(detail(model, session))
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: TempoSpacing.sm)
                        Image(systemName: "chevron.right")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card")
            }
        }
    }

    private func title(_ model: RecoveryCoachModel, _ session: CoachSession) -> String {
        if let start = model.startHere { return start.title }
        return "Recovery after your \(session.label.lowercased())"
    }

    private func detail(_ model: RecoveryCoachModel, _ session: CoachSession) -> String {
        guard let result = model.result else { return "Tap to see what to drink and eat." }
        if model.startHere != nil { return "Ended \(RecoveryCoachModel.ago(session.end, now: Date())). Tap to see what to do." }
        guard let sweat = result.sweat, let plan = result.plan else { return "Tap to open." }
        let low = sweat.sweatLitersLow ?? sweat.sweatLitersRaw ?? 0
        let high = sweat.sweatLitersHigh ?? low
        let sweatText = sweat.isLowerBound
            ? "At least \(RecoveryCoachFormat.liters(low)) sweat"
            : "About \(RecoveryCoachFormat.litersRange(low: low, high: high)) sweat"
        if let drink = plan.drinkLiters { return "\(sweatText). Drink \(RecoveryCoachFormat.liters(drink)) with a meal." }
        return sweatText + "."
    }
}
