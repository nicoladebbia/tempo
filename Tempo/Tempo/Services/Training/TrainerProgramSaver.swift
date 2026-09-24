//
// TrainerProgramSaver.swift
// Tempo
//
// Persists a reviewed Trainer Program: resolves (or creates) a library
// Exercise for every row, deactivates any other active program (only one
// runs at a time), inserts the new TrainerProgram, and posts
// `.tempoTrainingSettingsChanged` so the plan regenerates. Pure enough to
// unit-test with an in-memory ModelContext — no view/service dependencies.
//

import Foundation
import SwiftData

// MARK: - TrainerProgramSaver

enum TrainerProgramSaver {
    /// Saves `weeks` as a new active TrainerProgram. Every `ProgramExercise`
    /// with no `exerciseID` set (the review screen sets one for anything the
    /// user matched or the live matcher already resolved) is matched against
    /// the library here; if still no match, a custom Exercise is created —
    /// exactly once per distinct name, even if it appears on several
    /// days/weeks.
    @MainActor
    @discardableResult
    static func save(
        name: String,
        startDate: Date,
        weeks: [ProgramWeek],
        repeats: Bool,
        sourceKind: String,
        sourceText: String?,
        modelContext: ModelContext
    ) throws -> TrainerProgram {
        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        var candidates = library.map { ExerciseMatcher.Candidate(id: $0.id, name: $0.name) }
        var knownExerciseIDs = Set(library.map(\.id))
        // Custom exercises created during THIS save, keyed by normalized
        // name, so "Trap Bar Deadlift" repeated across 4 days creates one
        // Exercise, not four.
        var resolvedByName: [String: UUID] = [:]

        func resolvedExerciseID(for exercise: ProgramExercise) -> UUID {
            if let id = exercise.exerciseID, knownExerciseIDs.contains(id) {
                return id
            }
            let key = ExerciseMatcher.normalize(exercise.name)
            if let existingID = resolvedByName[key] {
                return existingID
            }
            if let match = ExerciseMatcher.match(exercise.name, in: candidates) {
                resolvedByName[key] = match.id
                return match.id
            }
            let custom = Exercise(
                name: exercise.name,
                muscleGroup: .fullBody,
                equipment: .none,
                movementPattern: .isolation,
                isCompound: false,
                isCustom: true
            )
            modelContext.insert(custom)
            knownExerciseIDs.insert(custom.id)
            candidates.append(ExerciseMatcher.Candidate(id: custom.id, name: custom.name))
            resolvedByName[key] = custom.id
            return custom.id
        }

        var resolvedWeeks: [ProgramWeek] = []
        for week in weeks {
            var days: [ProgramDay] = []
            for day in week.days {
                var exercises: [ProgramExercise] = []
                for exercise in day.exercises {
                    var updated = exercise
                    updated.exerciseID = resolvedExerciseID(for: exercise)
                    exercises.append(updated)
                }
                var updatedDay = day
                updatedDay.exercises = exercises
                days.append(updatedDay)
            }
            var updatedWeek = week
            updatedWeek.days = days
            resolvedWeeks.append(updatedWeek)
        }

        // Only one program runs at a time.
        let existingPrograms = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        for program in existingPrograms where program.isActive {
            program.isActive = false
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let program = TrainerProgram(
            name: trimmedName.isEmpty ? "Trainer Program" : trimmedName,
            startDate: startDate,
            weeks: resolvedWeeks,
            repeats: repeats,
            isActive: true,
            sourceKind: sourceKind,
            sourceText: sourceText
        )
        modelContext.insert(program)
        try modelContext.save()

        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        return program
    }

    /// Activates `program` (deactivating every other one) and posts the
    /// settings-changed notification so the plan regenerates. Used by the
    /// program list's "Activate" action on a past program.
    @MainActor
    static func activate(_ program: TrainerProgram, modelContext: ModelContext) {
        let all = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        for other in all where other.id != program.id && other.isActive {
            other.isActive = false
        }
        program.isActive = true
        try? modelContext.save()
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }

    /// Deactivates `program` (no program becomes active) and posts the
    /// settings-changed notification.
    @MainActor
    static func deactivate(_ program: TrainerProgram, modelContext: ModelContext) {
        program.isActive = false
        try? modelContext.save()
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }
}
