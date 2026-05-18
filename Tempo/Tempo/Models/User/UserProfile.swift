//
// UserProfile.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - UserProfile

@Model
final class UserProfile {
    // MARK: - Identity

    @Attribute(.unique)
    var id: UUID

    @Attribute(.unique)
    var appleID: String

    @Attribute(.unique)
    var username: String

    var displayName: String

    var avatarURL: String?

    /// User-selected identity label chosen during onboarding
    /// ("What best describes you?"). Defaults to "Athlete" so the
    /// additive property migrates losslessly on existing stores.
    var identityLabel: String = "Athlete"

    // MARK: - Biometrics

    var timezone: String

    var weightKg: Double?

    var heightCm: Double?

    var age: Int?

    // MARK: - Training Configuration

    var trainingSplitRaw: String

    var footballDaysRaw: Int

    var equipmentJSON: Data?

    var weightUnitRaw: String

    // MARK: - Cached Aggregates

    var totalXP: Int

    var currentLevel: Int

    // MARK: - Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Relationships

    @Relationship(deleteRule: .cascade, inverse: \UserSettings.userProfile)
    var settings: UserSettings?

    // MARK: - Computed Properties

    @Transient
    var trainingSplit: TrainingSplit {
        get { TrainingSplit(rawValue: trainingSplitRaw) ?? .pushPullLegs }
        set { trainingSplitRaw = newValue.rawValue }
    }

    @Transient
    var footballDays: ActiveDays {
        get { ActiveDays(rawValue: footballDaysRaw) }
        set { footballDaysRaw = newValue.rawValue }
    }

    @Transient
    var equipment: [Equipment] {
        get {
            guard let data = equipmentJSON,
                  let raw = try? JSONDecoder().decode([String].self, from: data)
            else {
                return []
            }
            return raw.compactMap { Equipment(rawValue: $0) }
        }
        set {
            let raw = newValue.map(\.rawValue)
            equipmentJSON = try? JSONEncoder().encode(raw)
        }
    }

    @Transient
    var weightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnitRaw) ?? .kg }
        set { weightUnitRaw = newValue.rawValue }
    }

    @Transient
    var estimatedBMR: Double? {
        guard let w = weightKg, let h = heightCm, let a = age else {
            return nil
        }
        return (10 * w) + (6.25 * h) - (5 * Double(a)) + 5
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        appleID: String,
        username: String,
        displayName: String,
        avatarURL: String? = nil,
        identityLabel: String = "Athlete",
        timezone: String = TimeZone.current.identifier,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        age: Int? = nil,
        trainingSplit: TrainingSplit = .pushPullLegs,
        footballDays: ActiveDays = ActiveDays(rawValue: 0),
        equipment: [Equipment] = [],
        weightUnit: WeightUnit = .kg
    ) {
        self.id = id
        self.appleID = appleID
        self.username = username
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.identityLabel = identityLabel
        self.timezone = timezone
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        trainingSplitRaw = trainingSplit.rawValue
        footballDaysRaw = footballDays.rawValue
        equipmentJSON = try? JSONEncoder().encode(equipment.map(\.rawValue))
        weightUnitRaw = weightUnit.rawValue
        totalXP = 0
        currentLevel = 1
        createdAt = Date()
        updatedAt = Date()
    }
}

// MARK: - Codable DTO (for API sync)

extension UserProfile {
    struct DTO: Codable {
        let id: UUID
        let apple_id: String
        let username: String
        let display_name: String
        let avatar_url: String?
        let identity_label: String?
        let timezone: String
        let weight_kg: Double?
        let height_cm: Double?
        let age: Int?
        let training_split: String
        let football_days: Int
        let equipment: [String]
        let weight_unit: String
        let total_xp: Int
        let current_level: Int
        let created_at: Date
        let updated_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            apple_id: appleID,
            username: username,
            display_name: displayName,
            avatar_url: avatarURL,
            identity_label: identityLabel,
            timezone: timezone,
            weight_kg: weightKg,
            height_cm: heightCm,
            age: age,
            training_split: trainingSplitRaw,
            football_days: footballDaysRaw,
            equipment: equipment.map(\.rawValue),
            weight_unit: weightUnitRaw,
            total_xp: totalXP,
            current_level: currentLevel,
            created_at: createdAt,
            updated_at: updatedAt
        )
    }

    func apply(dto: DTO) {
        username = dto.username
        displayName = dto.display_name
        avatarURL = dto.avatar_url
        if let label = dto.identity_label, !label.isEmpty {
            identityLabel = label
        }
        timezone = dto.timezone
        weightKg = dto.weight_kg
        heightCm = dto.height_cm
        age = dto.age
        trainingSplitRaw = dto.training_split
        footballDaysRaw = dto.football_days
        equipmentJSON = try? JSONEncoder().encode(dto.equipment)
        weightUnitRaw = dto.weight_unit
        updatedAt = dto.updated_at
    }
}

// MARK: - Validation

extension UserProfile {
    enum ValidationError: LocalizedError {
        case usernameTooShort
        case usernameTooLong
        case usernameInvalidChars
        case displayNameEmpty
        case displayNameTooLong
        case invalidWeight
        case invalidHeight
        case invalidAge

        var errorDescription: String? {
            switch self {
            case .usernameTooShort: "Username must be at least 3 characters."
            case .usernameTooLong: "Username must be at most 30 characters."
            case .usernameInvalidChars: "Username may only contain letters, numbers, and underscores."
            case .displayNameEmpty: "Display name cannot be empty."
            case .displayNameTooLong: "Display name must be at most 50 characters."
            case .invalidWeight: "Weight must be between 30 and 300 kg."
            case .invalidHeight: "Height must be between 100 and 250 cm."
            case .invalidAge: "Age must be between 13 and 100."
            }
        }
    }

    func validate() throws {
        guard username.count >= 3 else {
            throw ValidationError.usernameTooShort
        }
        guard username.count <= 30 else {
            throw ValidationError.usernameTooLong
        }

        let usernameRegex = /^[a-zA-Z0-9_]+$/
        guard username.wholeMatch(of: usernameRegex) != nil else {
            throw ValidationError.usernameInvalidChars
        }

        guard !displayName.isEmpty else {
            throw ValidationError.displayNameEmpty
        }
        guard displayName.count <= 50 else {
            throw ValidationError.displayNameTooLong
        }

        if let w = weightKg {
            guard (30 ... 300).contains(w) else {
                throw ValidationError.invalidWeight
            }
        }
        if let h = heightCm {
            guard (100 ... 250).contains(h) else {
                throw ValidationError.invalidHeight
            }
        }
        if let a = age {
            guard (13 ... 100).contains(a) else {
                throw ValidationError.invalidAge
            }
        }
    }
}
