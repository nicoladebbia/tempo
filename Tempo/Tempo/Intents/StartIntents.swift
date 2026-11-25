//
// StartIntents.swift
// Tempo
//
// "Start workout" and "Start focus": Siri, Shortcuts and the Action button
// open Tempo straight into that flow. The intent only leaves a request on
// `AppState`; `TempoSystemRequestHost` (the one place that can put the screen
// up) starts the session, exactly as the Today "Start" button does.
//

import AppIntents
import Foundation

// MARK: - StartWorkoutIntent

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start workout"
    static let description = IntentDescription(
        "Opens Tempo and starts today's session, or picks up the one you have started.",
        categoryName: "Train"
    )
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = await TempoIntentEnvironment.resolve()?.appState else {
            throw StartIntentError.appNotReady
        }
        appState.requestedStart = .workout
        return .result()
    }
}

// MARK: - StartFocusIntent

struct StartFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Start focus"
    static let description = IntentDescription(
        "Opens Tempo and starts a focus timer.",
        categoryName: "Mind"
    )
    static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @Parameter(title: "Minutes", default: 25, inclusiveRange: (1, 180))
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute focus timer")
    }

    init() {}

    init(minutes: Int) {
        self.minutes = minutes
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let appState = await TempoIntentEnvironment.resolve()?.appState else {
            throw StartIntentError.appNotReady
        }
        appState.requestedStart = .focus(minutes: minutes)
        return .result()
    }
}

// MARK: - StartIntentError

enum StartIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady

    var localizedStringResource: LocalizedStringResource {
        "Tempo could not start. Open Tempo once and try again."
    }
}
