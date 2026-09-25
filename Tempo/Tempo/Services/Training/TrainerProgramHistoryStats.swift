//
// TrainerProgramHistoryStats.swift
// Tempo
//
// Fix #11(c) — basic completion stats for a finished/archived TrainerProgram:
// how many of the sessions Tempo ever generated for it were actually
// completed. Deliberately simple — "scheduled" is every WorkoutPlan row
// Tempo ever tagged to the program (main or secondary key), "done" is how
// many of those got marked `.completed`. Not deduped by session key: a
// repeating program reuses the same keys every loop, so counting rows (not
// distinct keys) is what makes the stat grow across loops instead of
// permanently capping at "1 per session".
//

import Foundation
import SwiftData

// MARK: - TrainerProgramHistoryStats

enum TrainerProgramHistoryStats {
    struct Stats: Equatable {
        let done: Int
        let scheduled: Int

        var fraction: Double {
            guard scheduled > 0 else {
                return 0
            }
            return Double(done) / Double(scheduled)
        }
    }

    @MainActor
    static func stats(for program: TrainerProgram, modelContext: ModelContext) -> Stats {
        let prefix = "\(program.id.uuidString)#"
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let tagged = all.filter { plan in
            (plan.programSessionKey?.hasPrefix(prefix) ?? false) || (plan.programSecondaryKey?.hasPrefix(prefix) ?? false)
        }
        let done = tagged.filter { $0.status == .completed }.count
        return Stats(done: done, scheduled: tagged.count)
    }
}
