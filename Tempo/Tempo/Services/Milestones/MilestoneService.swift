//
// MilestoneService.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import Foundation
import os
import SwiftData

enum MilestoneService {
    private static let logger = Logger(subsystem: "com.tempo", category: "Milestones")

    // MARK: - Milestone Definitions

    enum Milestone: Int, CaseIterable {
        case day7 = 7
        case day14 = 14
        case day21 = 21
        case day30 = 30

        var title: String {
            switch self {
            case .day7: "FIRST WEEK DOWN"
            case .day14: "TWO WEEKS STRONG"
            case .day21: "HABIT FORMED"
            case .day30: "ONE MONTH IN"
            }
        }

        var message: String {
            switch self {
            case .day7: "Most people quit by now. You didn't. That's the difference between talkers and doers."
            case .day14: "Two weeks of showing up. The foundation is set. Now we build."
            case .day21: "Science says 21 days makes a habit. You're officially a Tempo athlete. This is who you are now."
            case .day30: "30 days. One month of discipline. Check your progress report — the data doesn't lie."
            }
        }

        var icon: String {
            switch self {
            case .day7: "flame.fill"
            case .day14: "bolt.fill"
            case .day21: "brain.head.profile"
            case .day30: "chart.line.uptrend.xyaxis"
            }
        }
    }

    // MARK: - Check

    /// Check if a milestone should be shown based on app install date (UserProfile.createdAt).
    static func checkMilestone(modelContext: ModelContext) -> Milestone? {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let profile = try? modelContext.fetch(descriptor).first else {
            return nil
        }

        let daysSinceInstall = Calendar.current.dateComponents(
            [.day], from: profile.createdAt, to: Date()
        ).day ?? 0

        // Check milestones in reverse order — show highest applicable that hasn't been shown yet
        for milestone in Milestone.allCases.reversed() where daysSinceInstall >= milestone.rawValue {
            let key = "tempo.milestone.\(milestone.rawValue).shown"
            if !UserDefaults.standard.bool(forKey: key) {
                return milestone
            }
        }
        return nil
    }

    // MARK: - Mark Shown

    /// Persist that a milestone has been shown so it won't appear again.
    static func markShown(_ milestone: Milestone) {
        let key = "tempo.milestone.\(milestone.rawValue).shown"
        UserDefaults.standard.set(true, forKey: key)
        logger.info("Milestone day \(milestone.rawValue) marked as shown")
    }
}
