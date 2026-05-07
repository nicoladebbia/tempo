//
// DailyPrescription.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - DailyPrescription

@Model
final class DailyPrescription {
    @Attribute(.unique)
    var id: UUID

    var date: Date

    var trainingRec: String

    var trainingDetail: String?

    var nutritionRecsJSON: Data?

    var bedtimeTarget: Date?

    var caffeineCutoff: Date?

    var hydrationTargetMl: Int?

    var warningsJSON: Data?

    var wasFollowed: Bool?

    // MARK: - Relationships

    @Relationship(deleteRule: .nullify)
    var dailyRecovery: DailyRecovery?

    // MARK: - Computed

    @Transient
    var nutritionRecs: [String] {
        get {
            guard let data = nutritionRecsJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            nutritionRecsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var warnings: [String] {
        get {
            guard let data = warningsJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return decoded
        }
        set {
            warningsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var hasWarnings: Bool {
        !warnings.isEmpty
    }

    @Transient
    var caffeineCutoffFormatted: String? {
        guard let cutoff = caffeineCutoff else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: cutoff)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        trainingRec: String,
        trainingDetail: String? = nil,
        nutritionRecs: [String] = [],
        bedtimeTarget: Date? = nil,
        caffeineCutoff: Date? = nil,
        hydrationTargetMl: Int? = nil,
        warnings: [String] = [],
        wasFollowed: Bool? = nil,
        dailyRecovery: DailyRecovery? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.trainingRec = trainingRec
        self.trainingDetail = trainingDetail
        nutritionRecsJSON = try? JSONEncoder().encode(nutritionRecs)
        self.bedtimeTarget = bedtimeTarget
        self.caffeineCutoff = caffeineCutoff
        self.hydrationTargetMl = hydrationTargetMl
        warningsJSON = try? JSONEncoder().encode(warnings)
        self.wasFollowed = wasFollowed
        self.dailyRecovery = dailyRecovery
    }
}

// MARK: - DTO

extension DailyPrescription {
    struct DTO: Codable {
        let id: UUID
        let date: Date
        let training_rec: String
        let training_detail: String?
        let nutrition_recs: [String]
        let bedtime_target: Date?
        let caffeine_cutoff: Date?
        let hydration_target_ml: Int?
        let warnings: [String]
        let was_followed: Bool?
        let recovery_id: UUID?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            training_rec: trainingRec,
            training_detail: trainingDetail,
            nutrition_recs: nutritionRecs,
            bedtime_target: bedtimeTarget,
            caffeine_cutoff: caffeineCutoff,
            hydration_target_ml: hydrationTargetMl,
            warnings: warnings,
            was_followed: wasFollowed,
            recovery_id: dailyRecovery?.id
        )
    }
}
