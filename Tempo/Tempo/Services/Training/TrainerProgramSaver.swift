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
// Fix #10 (kettlebell/equipment variants): a trainer sheet often writes
// shorthand on equipment the library doesn't have its own row for ("KT Lat
// Step Up", "KT Reverse Lunge") — ExerciseMatcher correctly matches the
// MOVEMENT (Step-Up, Reverse Lunge) but that library row is built on
// dumbbell/barbell, so its weight increments and prescriptions are wrong for
// a kettlebell. When the trainer's written equipment conflicts with the
// matched row's, this creates (once, deduped by name) a cloned Exercise on
// the trainer's equipment and links to THAT instead — same muscle group,
// secondary muscles, movement pattern, compound flag, instructions and cues
// as the match, just the right piece of iron.
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
        var exerciseByID = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
        // Custom exercises (and equipment variants) created during THIS save,
        // keyed by normalized name, so "Trap Bar Deadlift" repeated across 4
        // days creates one Exercise, not four — and so does a repeated
        // variant name ("Kettlebell Single Leg Romanian Deadlift").
        var resolvedByName: [String: UUID] = [:]

        func resolvedExerciseID(for exercise: ProgramExercise) -> UUID {
            if let id = exercise.exerciseID, knownExerciseIDs.contains(id) {
                return id
            }
            let key = ExerciseMatcher.normalize(exercise.name)
            if let existingID = resolvedByName[key] {
                return existingID
            }
            let writtenEquipment = ExerciseMatcher.writtenEquipment(in: exercise.name)

            if let match = ExerciseMatcher.match(exercise.name, in: candidates) {
                guard let matched = exerciseByID[match.id],
                      let writtenEquipment, writtenEquipment != matched.equipment
                else {
                    resolvedByName[key] = match.id
                    return match.id
                }
                // Equipment conflict: the movement matched, but the trainer
                // wrote a different piece of equipment than this library row
                // is built on. Clone a variant on the trainer's equipment.
                let variantName = Self.variantName(rawName: exercise.name, matchedName: matched.name, equipment: writtenEquipment)
                let variantKey = ExerciseMatcher.normalize(variantName)
                if let existingVariantID = resolvedByName[variantKey] {
                    resolvedByName[key] = existingVariantID
                    return existingVariantID
                }
                let variant = Exercise(
                    name: variantName,
                    muscleGroup: matched.muscleGroup,
                    secondaryMuscles: matched.secondaryMuscles,
                    equipment: writtenEquipment,
                    movementPattern: matched.movementPattern,
                    isCompound: matched.isCompound,
                    isCustom: true,
                    instructions: matched.instructions,
                    cues: matched.cues
                )
                modelContext.insert(variant)
                knownExerciseIDs.insert(variant.id)
                candidates.append(ExerciseMatcher.Candidate(id: variant.id, name: variant.name))
                exerciseByID[variant.id] = variant
                resolvedByName[key] = variant.id
                resolvedByName[variantKey] = variant.id
                return variant.id
            }

            let custom = Exercise(
                name: exercise.name,
                muscleGroup: .fullBody,
                equipment: writtenEquipment ?? .none,
                movementPattern: .isolation,
                isCompound: false,
                isCustom: true
            )
            modelContext.insert(custom)
            knownExerciseIDs.insert(custom.id)
            candidates.append(ExerciseMatcher.Candidate(id: custom.id, name: custom.name))
            exerciseByID[custom.id] = custom
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

    // MARK: - Equipment-variant naming

    /// Names a cloned equipment variant from the trainer's own words: the
    /// written equipment ("Kettlebell") + any of the trainer's own expanded
    /// words not already equipment and not already part of the matched name,
    /// + the matched name itself. "KT Lat Step Up" (expands to "kettlebell
    /// lateral step up") + matched "Step-Up" -> "Kettlebell Lateral
    /// Step-Up". "KT SL RDL" (-> "kettlebell single leg romanian deadlift")
    /// + matched "Romanian Deadlift" -> "Kettlebell Single Leg Romanian
    /// Deadlift". "KT Reverse Lunge" + matched "Reverse Lunge" -> "Kettlebell
    /// Reverse Lunge" (no extra words — "reverse" and "lunge" are already in
    /// the matched name). Not `private` — the review screen's match
    /// indicator previews this same name before the program is saved.
    static func variantName(rawName: String, matchedName: String, equipment: Equipment) -> String {
        let expandedWords = ExerciseMatcher.expandShorthand(ExerciseMatcher.normalize(rawName))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let matchedWords = Set(
            matchedName.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        var seen = Set<String>()
        let qualifiers = expandedWords.filter { word in
            guard !ExerciseMatcher.isEquipmentWord(word), !matchedWords.contains(word), !seen.contains(word) else {
                return false
            }
            seen.insert(word)
            return true
        }
        let prefix = ([equipmentDisplayName(equipment)] + qualifiers.map(\.capitalized)).joined(separator: " ")
        return "\(prefix) \(matchedName)"
    }

    /// Short display name for the equipment tokens a trainer would actually
    /// write ("KT", "DB", "BB", ...). Not `Equipment.displayName` — kept
    /// local since this is the only place that needs it and the values here
    /// (e.g. "Band" not "Resistance_Band") are for a generated exercise NAME,
    /// not a UI label.
    private static func equipmentDisplayName(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        case .resistanceBand: "Band"
        case .smithMachine: "Smith Machine"
        case .ezBar: "EZ-Bar"
        case .trapBar: "Trap Bar"
        case .pullUpBar: "Pull-Up Bar"
        case .bench: "Bench"
        case .none: ""
        }
    }
}
