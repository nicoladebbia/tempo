//
// DeloadStatus.swift
// Tempo
//
// Single source for "is this a deload week". The Dashboard used its own
// week-of-year % frequency rule, so every user saw "Deload week" on weeks
// 5, 10, 15… while Training (counting from the athlete's start date, gated on
// Auto Deload, with the fatigue trigger) said full volume.
//

import Foundation
import SwiftData

extension TrainingEngineProtocol {
    /// Whether `date` falls in a deload week for the stored athlete — the
    /// Auto Deload toggle, frequency, start date and fatigue trend, exactly as
    /// Training prescribes it.
    @MainActor
    func isDeloadWeek(on date: Date = Date(), modelContext: ModelContext) -> Bool {
        let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first
        guard settings?.autoDeload ?? true else {
            return false
        }
        let fatigue = (try? modelContext.fetch(FetchDescriptor<AdaptiveProfile>()).first)?.fatigueEWMA
        return isDeloadWeek(
            date: date,
            deloadFrequencyWeeks: settings?.deloadFrequencyWeeks ?? 5,
            trainingStartDate: settings?.userProfile?.createdAt,
            fatigueEWMA: fatigue
        )
    }
}
