//
// MealPlanInputsFingerprint.swift
// Tempo
//
// A stable digest of everything outside the wizard that shapes a weekly meal
// plan: training split, football days, the active trainer program, and the
// diet-profile fields the generator reads. Stamped onto WeeklyMealPlan at
// generation; on load, a mismatch means the plan was built from inputs that
// have since changed (edited in Settings, Training, or anywhere else — even
// while the Nutrition tab was never opened), so it's out of date.
//
// Deterministic across launches (SHA-256 of a canonical string — NOT
// Hasher, which is seeded per process).
//

import CryptoKit
import Foundation
import SwiftData

enum MealPlanInputsFingerprint {
    /// Plain-value snapshot of the inputs, so the digest is testable without
    /// SwiftData in the loop.
    struct Inputs: Equatable {
        var trainingSplit: String?
        var footballDays: Int?
        var activeTrainerProgramIDs: [UUID]
        var profile: [String]
    }

    static func fingerprint(_ inputs: Inputs) -> String {
        var lines: [String] = []
        lines.append("split=\(inputs.trainingSplit ?? "-")")
        lines.append("football=\(inputs.footballDays.map(String.init) ?? "-")")
        lines.append("program=\(inputs.activeTrainerProgramIDs.map(\.uuidString).sorted().joined(separator: ","))")
        lines.append(contentsOf: inputs.profile)
        let digest = SHA256.hash(data: Data(lines.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical, order-independent description of the plan-shaping profile
    /// fields. Lists are lowercased + sorted so reordering chips doesn't read
    /// as a change. nil profile → empty (the generator can't run without one).
    static func profileFields(_ profile: DietaryProfile?) -> [String] {
        guard let profile else {
            return ["profile=-"]
        }
        func list(_ values: [String]) -> String {
            values.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.sorted().joined(separator: "|")
        }
        func number(_ value: Double?) -> String {
            value.map { String(format: "%.2f", $0) } ?? "-"
        }
        return [
            "goal=\(profile.primaryGoalRaw)",
            "weight=\(number(profile.currentWeightKg))",
            "goalWeight=\(number(profile.goalWeightKg))",
            "rate=\(number(profile.weeklyRateKg))",
            "height=\(number(profile.heightCm))",
            "bodyFat=\(number(profile.bodyFatPercent))",
            "age=\(profile.age)",
            "sex=\(profile.biologicalSexRaw)",
            "trainingFrequency=\(profile.trainingFrequency)",
            "skill=\(profile.skillLevelRaw)",
            "cooking=\(profile.cookingSkillRaw)",
            "flags=\(profile.isLactoseFree)\(profile.noCoffee)\(profile.isGlutenFree)\(profile.isVegetarian)"
                + "\(profile.isVegan)\(profile.isHalal)\(profile.isNutFree)\(profile.isShellFishAllergy)"
                + "\(profile.avoidAddedSugars)",
            "allergies=\(list(profile.allergies))",
            "disliked=\(list(profile.dislikedFoods))",
            "favorite=\(list(profile.favoriteFoods))",
            "bored=\(list(profile.boredOfFoods))",
        ]
    }

    /// Reads the current inputs from SwiftData and digests them.
    @MainActor
    static func current(in context: ModelContext) -> String {
        let settings = NutritionTabViewModel.loadUserSettings(modelContext: context)
        let programs = (try? context.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        let profileDescriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate<DietaryProfile> { $0.isActive == true }
        )
        let profile = (try? context.fetch(profileDescriptor))?.first
        return fingerprint(Inputs(
            trainingSplit: settings?.trainingSplitRaw,
            footballDays: settings?.footballDaysRaw,
            activeTrainerProgramIDs: programs.filter(\.isActive).map(\.id),
            profile: profileFields(profile)
        ))
    }
}
