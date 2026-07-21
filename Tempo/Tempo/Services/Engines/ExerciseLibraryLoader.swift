//
// ExerciseLibraryLoader.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - ExerciseLibraryLoader

@MainActor
struct ExerciseLibraryLoader {
    static func loadIfNeeded(context: ModelContext) throws {
        let entries = try loadFromBundle()
        let existing = try context.fetch(FetchDescriptor<Exercise>())

        if existing.isEmpty {
            // Fresh install — seed the full library.
            for entry in entries {
                let exercise = Exercise(
                    name: entry.name,
                    muscleGroup: MuscleGroup(rawValue: entry.muscleGroup) ?? .chest,
                    secondaryMuscles: entry.secondaryMuscles.compactMap { MuscleGroup(rawValue: $0) },
                    equipment: Equipment(rawValue: entry.equipment) ?? .barbell,
                    movementPattern: MovementPattern(rawValue: entry.movementPattern) ?? .isolation,
                    isCompound: entry.isCompound,
                    demoAsset: entry.demoAsset,
                    instructions: entry.instructions,
                    cues: entry.cues ?? []
                )
                context.insert(exercise)
            }
        } else {
            // Already seeded (possibly before demoAsset existed): backfill demo
            // photos onto existing rows that lack one. Idempotent — once set, the
            // `where` clause skips it. Preserves the user's workout history.
            var assetByName: [String: String] = [:]
            for entry in entries {
                if let asset = entry.demoAsset {
                    assetByName[entry.name] = asset
                }
            }
            for exercise in existing where exercise.demoAsset == nil {
                if let asset = assetByName[exercise.name] {
                    exercise.demoAsset = asset
                }
            }
        }
        try context.save()
    }

    private static func loadFromBundle() throws -> [ExerciseEntry] {
        guard let url = Bundle.main.url(forResource: "Exercises", withExtension: "json") else {
            throw LoaderError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ExerciseEntry].self, from: data)
    }

    enum LoaderError: Error {
        case fileNotFound
    }
}

// MARK: - ExerciseEntry

private struct ExerciseEntry: Decodable {
    let name: String
    let muscleGroup: String
    let secondaryMuscles: [String]
    let equipment: String
    let movementPattern: String
    let isCompound: Bool
    let defaultSets: Int
    let defaultReps: Int
    let restSeconds: Int
    let instructions: String
    let cues: [String]?
    let demoAsset: String?
}
