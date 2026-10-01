//
// PlanGenerationBlocker.swift
// Tempo
//
// Why a plan build can't succeed no matter how often it is retried: the user
// needs Pro, or hasn't allowed AI features. These never fall back to an
// on-device build (it asks the same backend) and the UI offers the fix
// (paywall / turn on AI) instead of a generic "try again".
//

import Foundation

enum PlanGenerationBlocker: Equatable {
    case proRequired
    case aiConsentRequired

    init?(_ error: Error) {
        switch error {
        case let api as APIError:
            switch api {
            case .subscriptionRequired: self = .proRequired
            case .aiConsentRequired: self = .aiConsentRequired
            default: return nil
            }
        case let MealPlanGeneratorError.generationFailed(inner):
            guard let blocker = PlanGenerationBlocker(inner) else {
                return nil
            }
            self = blocker
        case let WeeklyPlanService.BuildError.server(code):
            switch code {
            case "subscription_required": self = .proRequired
            case "ai_consent_required": self = .aiConsentRequired
            default: return nil
            }
        default:
            return nil
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
        switch self {
        case .proRequired: "See Pro"
        case .aiConsentRequired: "Turn on AI"
        }
    }

    /// What the user reads for any plan-build failure.
    static func message(for error: Error) -> String {
        if let blocker = PlanGenerationBlocker(error) {
            return blocker.message
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
