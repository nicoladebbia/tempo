//
// WhatsNextIntent.swift
// Tempo
//
// "What's next": answers from today's real state (next session, next meal,
// next task) without opening the app. See `NextUpSummary` for the facts and
// the wording.
//

import AppIntents
import Foundation

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription(
        "Tells you your next session, next meal and next task, without opening Tempo.",
        categoryName: "Today"
    )
    /// The answer names your plan, so it waits for the phone to be unlocked.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let env = await TempoIntentEnvironment.resolve() else {
            throw StartIntentError.appNotReady
        }
        let summary = NextUpReader.read(in: env.context)
        return .result(dialog: IntentDialog(stringLiteral: summary.spoken))
    }
}
