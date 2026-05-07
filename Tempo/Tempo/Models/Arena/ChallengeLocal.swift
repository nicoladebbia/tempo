//
// ChallengeLocal.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - ChallengeLocal

@Model
final class ChallengeLocal {
    @Attribute(.unique)
    var id: UUID

    var serverID: UUID?

    var name: String

    var metric: String

    var startDate: Date

    var endDate: Date

    var myScore: Double

    var isActive: Bool

    var challengeDescription: String?

    var participantCount: Int?

    var myRank: Int?

    // MARK: - Computed

    @Transient
    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    @Transient
    var hasEnded: Bool {
        Date() > endDate
    }

    @Transient
    var hasStarted: Bool {
        Date() >= startDate
    }

    @Transient
    var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }

    @Transient
    var timelineProgress: Double {
        guard hasStarted else {
            return 0
        }
        guard !hasEnded else {
            return 1
        }
        let elapsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        return Double(elapsed) / Double(totalDays)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        serverID: UUID? = nil,
        name: String,
        metric: String,
        startDate: Date,
        endDate: Date,
        myScore: Double = 0,
        isActive: Bool = true,
        challengeDescription: String? = nil,
        participantCount: Int? = nil,
        myRank: Int? = nil
    ) {
        self.id = id
        self.serverID = serverID
        self.name = name
        self.metric = metric
        self.startDate = startDate
        self.endDate = endDate
        self.myScore = myScore
        self.isActive = isActive
        self.challengeDescription = challengeDescription
        self.participantCount = participantCount
        self.myRank = myRank
    }
}

// MARK: - DTO

extension ChallengeLocal {
    struct DTO: Codable {
        let id: UUID
        let server_id: UUID?
        let name: String
        let metric: String
        let start_date: Date
        let end_date: Date
        let my_score: Double
        let is_active: Bool
        let description: String?
        let participant_count: Int?
        let my_rank: Int?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            server_id: serverID,
            name: name,
            metric: metric,
            start_date: startDate,
            end_date: endDate,
            my_score: myScore,
            is_active: isActive,
            description: challengeDescription,
            participant_count: participantCount,
            my_rank: myRank
        )
    }
}
