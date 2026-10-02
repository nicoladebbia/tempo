//
// PlanGenerationBlocker.swift
// Tempo
//
// Why a plan build can't succeed no matter how often it is retried: the user
// needs Pro, or hasn't allowed AI features. These never fall back to an
// on-device build (it asks the same backend) and the UI offers the fix
// (paywall / turn on AI) instead of a generic "try again". The mapping is the
// shared `AIBlocker`; only the plan-specific wording lives here.
//

import Foundation

enum PlanGenerationBlocker: Equatable {
    case proRequired
    case aiConsentRequired

    init?(_ error: Error) {
        switch AIBlocker(error) {
        case .proRequired?: self = .proRequired
        case .aiConsentRequired?: self = .aiConsentRequired
        case nil: return nil
        }
    }

    init(from blocker: AIBlocker) {
        switch blocker {
        case .proRequired: self = .proRequired
        case .aiConsentRequired: self = .aiConsentRequired
        }
    }

    /// The shared blocker this maps to (card, action and consent flow).
    var aiBlocker: AIBlocker {
        switch self {
        case .proRequired: .proRequired
        case .aiConsentRequired: .aiConsentRequired
        }
    }

    var message: String {
        switch self {
        case .proRequired: "Weekly plans are a Tempo Pro feature."
        case .aiConsentRequired: "Turn on AI features to build your plan."
        }
    }

    /// Button label for the fix.
    var actionTitle: String {
        aiBlocker.actionTitle
    }

    /// What the user reads for any plan-build failure.
    static func message(for error: Error) -> String {
        if let blocker = PlanGenerationBlocker(error) {
            return blocker.message
        }
        return AIBlocker.readableDescription(error)
    }
}
