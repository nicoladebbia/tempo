import Foundation
import SwiftData

@MainActor
struct ExerciseLibraryLoader {

    static func loadIfNeeded(context: ModelContext) throws {
        let descriptor = FetchDescriptor<Exercise>()
        let count = try context.fetchCount(descriptor)
        guard count == 0 else { return }

        let exercises = try loadFromBundle()
        for entry in exercises {
            let exercise = Exercise(
                name: entry.name,
                muscleGroup: MuscleGroup(rawValue: entry.muscleGroup) ?? .chest,
                secondaryMuscles: entry.secondaryMuscles.compactMap { MuscleGroup(rawValue: $0) },
                equipment: Equipment(rawValue: entry.equipment) ?? .barbell,
                movementPattern: MovementPattern(rawValue: entry.movementPattern) ?? .isolation,
                isCompound: entry.isCompound,
                instructions: entry.instructions,
                cues: entry.cues ?? []
            )
            context.insert(exercise)
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
}
