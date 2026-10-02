//
// BenchedDayUITestSeed.swift
// Tempo
//
// DEBUG-only: `--uitesting-benched-day` marks today's existing workout as
// benched by a severe recovery floor (`.skipped` + `.floorForced`), so the
// "BENCHED TODAY" card and its "Train anyway" override can be checked in the
// simulator without real red recovery data. Same pattern as the other
// UITestSeed files.
//

import Foundation
import SwiftData

#if DEBUG
    enum BenchedDayUITestSeed {
        static let argument = "--uitesting-benched-day"

        @MainActor
        static func seedIfRequested(context: ModelContext) {
            guard ProcessInfo.processInfo.arguments.contains(argument) else {
                return
            }
            let dayStart = Calendar.current.startOfDay(for: Date())
            let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            let plans = (try? context.fetch(FetchDescriptor<WorkoutPlan>(
                predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
            ))) ?? []
            for plan in plans where plan.status == .planned {
                plan.status = .skipped
                plan.skipReason = .floorForced
            }
            try? context.save()
        }
    }
#endif
