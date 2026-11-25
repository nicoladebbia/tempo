//
// RecoveryCoachCard.swift
// Tempo
//
// Small card on Nutrition Today. Hidden unless a session from the last 48 h
// needs a weigh-in or has a result. Tapping opens the Coach section of Fuel,
// where that session is the first thing on the page.
//

import SwiftUI

struct RecoveryCoachCard: View {
    @Environment(RecoveryCoachModel.self) private var model: RecoveryCoachModel?
    /// Opens the Coach section.
    let onOpen: () -> Void
    @State private var opens = 0

    var body: some View {
        // Always-present container hosts the view; the card inside is conditional.
        VStack(spacing: 0) {
            if let model, let session = model.session {
                Button {
                    opens += 1
                    onOpen()
                } label: {
                    HStack(spacing: Tide.s3) {
                        TideIconTile(systemName: "drop.fill", tint: Tide.water, size: Tide.hit - Tide.s2)
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(title(model, session))
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(detail(model, session))
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Tide.s2)
                        Image(systemName: "chevron.right")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Tide.hit)
                    .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                    .contentShape(.rect(cornerRadius: Tide.tileRadius))
                }
                .buttonStyle(FuelPressStyle())
                .sensoryFeedback(.selection, trigger: opens)
                .accessibilityIdentifier("coach.card")
            }
        }
    }

    private func title(_ model: RecoveryCoachModel, _ session: CoachSession) -> String {
        if let start = model.startHere {
            return start.title
        }
        return String(localized: "Recovery after your \(session.label.lowercased())")
    }

    private func detail(_ model: RecoveryCoachModel, _ session: CoachSession) -> String {
        guard let result = model.result else {
            return String(localized: "Tap to see what to drink and eat.")
        }
        if model.startHere != nil {
            return String(localized: "Ended \(RecoveryCoachModel.ago(session.end, now: Date())). Tap to see what to do.")
        }
        guard let sweat = result.sweat, let plan = result.plan else {
            return String(localized: "Tap to open.")
        }
        let low = sweat.sweatLitersLow ?? sweat.sweatLitersRaw ?? 0
        let high = sweat.sweatLitersHigh ?? low
        let sweatText = sweat.isLowerBound
            ? String(localized: "At least \(RecoveryCoachFormat.liters(low)) sweat")
            : String(localized: "About \(RecoveryCoachFormat.litersRange(low: low, high: high)) sweat")
        if let drink = plan.drinkLiters {
            return String(localized: "\(sweatText). Drink \(RecoveryCoachFormat.liters(drink)) with a meal.")
        }
        return sweatText + "."
    }
}
