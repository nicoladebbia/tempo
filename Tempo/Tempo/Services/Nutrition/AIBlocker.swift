//
// AIBlocker.swift
// Tempo
//
// Why an AI feature can't run no matter how often it is retried: the user
// needs Pro, or hasn't turned AI features on. Every nutrition AI surface
// (plans, Quick Log, photo, voice, recipes, receipts, coach) maps its error
// through here so the same card/alert, with the same fix button, appears
// everywhere. Any other failure stays a readable sentence.
//

import Foundation
import OSLog

enum AIBlocker: Equatable {
    case proRequired
    case aiConsentRequired

    /// Maps an error (or whatever error it wraps) to a blocker. Nil when the
    /// failure is anything else.
    init?(_ error: Error) {
        switch error {
        case let api as APIError:
            switch api {
            case .subscriptionRequired: self = .proRequired
            case .aiConsentRequired: self = .aiConsentRequired
            default: return nil
            }
        case let MealPlanGeneratorError.generationFailed(inner):
            guard let blocker = AIBlocker(inner) else { return nil }
            self = blocker
        case let WeeklyPlanService.BuildError.server(code):
            switch code {
            case "subscription_required": self = .proRequired
            case "ai_consent_required": self = .aiConsentRequired
            default: return nil
            }
        case let NutritionCoachError.apiFailed(inner):
            guard let blocker = AIBlocker(inner) else { return nil }
            self = blocker
        case let VoiceMealLogError.apiFailed(inner):
            guard let blocker = AIBlocker(inner) else { return nil }
            self = blocker
        case let VoicePantryError.apiFailed(inner):
            guard let blocker = AIBlocker(inner) else { return nil }
            self = blocker
        default:
            // Foundation wrappers keep the original under NSUnderlyingError.
            let ns = error as NSError
            guard let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error,
                  let blocker = AIBlocker(underlying)
            else { return nil }
            self = blocker
        }
    }

    var title: String {
        switch self {
        case .proRequired: "Pro feature"
        case .aiConsentRequired: "AI is off"
        }
    }

    var message: String {
        switch self {
        case .proRequired: "AI features are part of Tempo Pro."
        case .aiConsentRequired: "AI features are turned off. Turn them on to use this."
        }
    }

    /// Button label for the fix.
    var actionTitle: String {
        switch self {
        case .proRequired: "See Pro"
        case .aiConsentRequired: "Turn on AI"
        }
    }

    /// What the user reads for any AI failure: the blocker's message, or the
    /// error's own readable description.
    static func message(for error: Error) -> String {
        if let blocker = AIBlocker(error) {
            return blocker.message
        }
        return readableDescription(error)
    }

    static func readableDescription(_ error: Error) -> String {
        if let api = error as? APIError {
            return api.userMessage
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

// MARK: - Readable text for errors that were plain `Error`

extension NutritionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .foodNotFound, .barcodeNotFound: "We couldn't find that food."
        case let .searchFailed(detail): detail
        case .apiKeyMissing, .contextUnavailable: "Something went wrong. Please try again."
        case .rateLimited: "Too many requests. Please wait a moment."
        case .networkError: "Network error. Check your connection and try again."
        case let .photoAnalysisFailed(detail): "Couldn't read that photo: \(detail)"
        case .noFoodDetected: "No food found in that photo. Try a closer shot."
        case .unclearPhoto: "That photo is too unclear. Try better light."
        case .invalidResponse: "Received unexpected data from the server."
        case .mealNotFound: "That meal could not be found."
        case let .healthKitWriteFailed(detail): "Couldn't save to Health: \(detail)"
        }
    }
}

// MARK: - AI consent (Settings switch + "Turn on AI")

/// Reads and writes the user's AI-features consent. The backend is the source
/// of truth (`GET /v1/user/me` → `ai_consent_at`, `POST /v1/user/ai-consent`);
/// the last known value is cached in UserDefaults so the Settings switch has
/// an answer before the network does.
enum AIConsentStore {
    static let defaultsKey = "tempo.aiFeaturesEnabled"

    static func cachedValue(defaults: UserDefaults = .standard) -> Bool? {
        defaults.object(forKey: defaultsKey) as? Bool
    }

    static func cache(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: defaultsKey)
    }

    /// Current server-side state; refreshes the cache.
    static func fetch(apiClient: APIClient) async throws -> Bool {
        let me: UserMeResponseDTO = try await apiClient.request(APIEndpoint<UserMeResponseDTO>.currentUser())
        let on = me.aiConsentAt != nil
        cache(on)
        return on
    }

    /// Turns AI features on or off on the server; refreshes the cache.
    static func set(_ on: Bool, apiClient: APIClient) async throws {
        let _: AIConsentResponseDTO = try await apiClient.request(
            APIEndpoint<AIConsentResponseDTO>.setAIConsent(),
            body: AIConsentRequestDTO(consented: on)
        )
        cache(on)
    }
}
