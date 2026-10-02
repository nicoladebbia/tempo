//
// PoundsUITestSeed.swift
// Tempo
//
// DEBUG-only: `--uitesting-lbs` switches the stored settings to pounds, so
// every weight/run-unit surface can be checked in lbs/miles in the simulator
// without driving the Settings screen. Same pattern as the other UITestSeed
// files.
//

import Foundation
import SwiftData

#if DEBUG
    enum PoundsUITestSeed {
        static let argument = "--uitesting-lbs"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(argument) else {
                return
            }
            for settings in (try? context.fetch(FetchDescriptor<UserSettings>())) ?? [] {
                settings.weightUnit = .lbs
            }
            try? context.save()
        }
    }
#endif
