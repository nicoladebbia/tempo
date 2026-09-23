//
// DashboardViewModel+WatchSync.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

import Foundation
import SwiftData

extension DashboardViewModel {
    func pushWatchSnapshot() {
        let totalXP: Int
        if let context = fuelContext {
            let events = (try? context.fetch(FetchDescriptor<XPEvent>())) ?? []
            totalXP = events.reduce(0) { $0 + $1.amount }
        } else {
            totalXP = 0
        }

        let unlocked = nonNegotiablesTotal > 0 && nonNegotiablesDone >= nonNegotiablesTotal
        let timeToLeisure = AccountabilityEngine().ps5Time().timeIntervalSince(Date())

        let input = WatchSnapshotBuilder.Input(
            dailyScore: dailyScore,
            recoveryScore: body.recoveryScore,
            recoveryZone: body.recoveryZone,
            sleepHours: body.sleepHours,
            hrv: body.hrv,
            rhr: body.rhr,
            nonNegotiables: nonNegotiables.map {
                WatchNonNegotiableItem(id: $0.id.uuidString, title: $0.title, isCompleted: $0.isCompleted)
            },
            leisureUnlocked: unlocked,
            timeToLeisureUnlock: timeToLeisure > 0 ? timeToLeisure : nil,
            currentStreak: mind.currentStreakDays,
            totalXP: totalXP,
            nextMeal: fuel.nextMeal.map { WatchNextMeal(id: $0.id.uuidString, name: $0.mealName) }
        )
        let snapshot = WatchSnapshotBuilder.build(from: input)
        PhoneWatchConnectivityService.shared.pushSnapshot(snapshot.toDictionary())
    }
}
