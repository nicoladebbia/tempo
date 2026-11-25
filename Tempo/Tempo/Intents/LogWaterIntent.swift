//
// LogWaterIntent.swift
// Tempo
//
// "Log water": from Siri, Shortcuts, the Action button, a lock-screen control
// or the water widget's +250 ml button, without opening the app. Compiled into
// both the app and the widget extension (the widget needs the type to draw a
// button); the work itself is `WaterLogging.log`, which each target provides:
// the app saves through `WaterStore` (the store every screen uses, so Health
// and the Today number follow), the extension hands the entry to the app.
//
// `LiveActivityIntent` is what makes the widget button run in the app's
// process (checked on the simulator, with the app running and not running):
// without it the system runs `perform()` in the widget extension, which cannot
// reach the app's database. The extension's queue is the safety net for a
// surface that still runs it there.
//

import AppIntents
import Foundation

// MARK: - WaterLogOutcome

/// What a log did, for the confirmation and for tests.
struct WaterLogOutcome: Equatable, Sendable {
    var addedMl: Int
    var totalMl: Int
    var targetMl: Int?

    /// The spoken and shown confirmation: "250 ml added. 1,250 of 2,900 ml today."
    var sentence: String {
        if let targetMl, targetMl > 0 {
            return "\(addedMl) ml added. \(totalMl.formatted()) of \(targetMl.formatted()) ml today."
        }
        return "\(addedMl) ml added. \(totalMl.formatted()) ml today."
    }
}

// MARK: - WaterIntentError

enum WaterIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appNotReady
    case couldNotSave

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appNotReady: "Tempo could not start. Open Tempo once and try again."
        case .couldNotSave: "The water could not be saved. Try again."
        }
    }
}

// MARK: - LogWaterIntent

struct LogWaterIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log water"
    static let description = IntentDescription(
        "Adds water to today's total and to Apple Health, without opening Tempo.",
        categoryName: "Fuel"
    )
    /// Apple Health is not writable while the phone is locked, so a log made
    /// from the lock screen waits for Face ID instead of silently missing Health.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Amount (ml)", default: 250, inclusiveRange: (1, 3000))
    var amountMl: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amountMl) ml of water")
    }

    init() {}

    init(amountMl: Int) {
        self.amountMl = amountMl
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = try await WaterLogging.log(ml: amountMl)
        return .result(dialog: IntentDialog(stringLiteral: outcome.sentence))
    }
}
