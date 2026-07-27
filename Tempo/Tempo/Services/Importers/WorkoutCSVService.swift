//
// WorkoutCSVService.swift
// Tempo
//
// §20 — workout import/export. Imports lifting history from Strong, Hevy,
// or a generic CSV into completed WorkoutPlans + ExerciseHistory rows (the
// trend signal progression reads), and exports Tempo history as a
// Strong-compatible CSV. Idempotent per workout start time — re-importing
// the same file never duplicates history, mirroring RunImporter.
//

import Foundation
import SwiftData

enum WorkoutCSVService {
    // MARK: - Types

    enum Format: String {
        case strong = "Strong"
        case hevy = "Hevy"
        case generic = "CSV"
    }

    enum ImportError: LocalizedError {
        case unrecognizedFormat
        case noWorkouts

        var errorDescription: String? {
            switch self {
            case .unrecognizedFormat:
                "Unrecognized CSV format. Export from Strong or Hevy, or use columns: date, exercise, weight, reps."
            case .noWorkouts:
                "No importable sets found in this file."
            }
        }
    }

    struct ImportSummary: Equatable {
        var format: Format
        var workouts = 0
        var sets = 0
        var duplicates = 0
        var newExercises = 0

        var label: String {
            if workouts == 0, duplicates > 0 {
                return "Nothing new — all \(duplicates) workouts were already in Tempo."
            }
            var parts = ["\(workouts) workouts", "\(sets) sets"]
            if newExercises > 0 { parts.append("\(newExercises) new exercises") }
            if duplicates > 0 { parts.append("\(duplicates) already in Tempo") }
            return "\(format.rawValue): " + parts.joined(separator: ", ") + "."
        }
    }

    /// One completed working set as parsed from any supported CSV.
    struct ParsedSet: Equatable {
        let workoutName: String
        let start: Date
        let durationMinutes: Int?
        let exercise: String
        let weightKg: Double?
        let reps: Int
        let rpe: Int?
    }

    // MARK: - Parsing

    /// Header-detect the format and flatten the file to working-set rows.
    /// Warmup rows and rep-less rows (cardio/duration entries) are dropped.
    static func parse(_ text: String) throws -> (format: Format, sets: [ParsedSet]) {
        let rows = WhoopExportParser.keyedRows(text).map { row in
            Dictionary(row.map { key, value in
                (key.trimmingCharacters(in: .whitespaces).lowercased(),
                 value.trimmingCharacters(in: .whitespaces))
            }) { first, _ in first }
        }
        guard let first = rows.first else {
            throw ImportError.unrecognizedFormat
        }

        let format: Format
        if first["exercise_title"] != nil {
            format = .hevy
        } else if first["exercise name"] != nil, first["workout name"] != nil {
            format = .strong
        } else if first["exercise"] != nil, first["reps"] != nil {
            format = .generic
        } else {
            throw ImportError.unrecognizedFormat
        }

        let sets = rows.compactMap { parsedSet(from: $0, format: format) }
        guard !sets.isEmpty else {
            throw ImportError.noWorkouts
        }
        return (format, sets)
    }

    private static func parsedSet(from row: [String: String], format: Format) -> ParsedSet? {
        switch format {
        case .strong:
            // Strong marks warmups in "Set Order" ("W"/"W1") and emits
            // rest-timer/note rows with no reps — all skipped.
            let order = (row["set order"] ?? "").uppercased()
            guard !order.hasPrefix("W"),
                  let start = date(row["date"]),
                  let exercise = nonEmpty(row["exercise name"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            return ParsedSet(
                workoutName: nonEmpty(row["workout name"]) ?? "Imported workout",
                start: start,
                durationMinutes: durationMinutes(row["duration"]),
                exercise: exercise,
                weightKg: double(row["weight"]),
                reps: reps,
                rpe: int(row["rpe"])
            )
        case .hevy:
            guard (row["set_type"] ?? "").lowercased() != "warmup",
                  let start = date(row["start_time"]),
                  let exercise = nonEmpty(row["exercise_title"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            let end = date(row["end_time"])
            let duration = end.map { Int($0.timeIntervalSince(start) / 60) }
            return ParsedSet(
                workoutName: nonEmpty(row["title"]) ?? "Imported workout",
                start: start,
                durationMinutes: duration.flatMap { $0 > 0 ? $0 : nil },
                exercise: exercise,
                weightKg: double(row["weight_kg"]),
                reps: reps,
                rpe: int(row["rpe"])
            )
        case .generic:
            guard (row["set_type"] ?? row["warmup"] ?? "").lowercased() != "warmup",
                  (row["warmup"] ?? "").lowercased() != "true",
                  let start = date(row["date"]),
                  let exercise = nonEmpty(row["exercise"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            return ParsedSet(
                workoutName: nonEmpty(row["workout"]) ?? nonEmpty(row["workout name"]) ?? "Imported workout",
                start: start,
                durationMinutes: int(row["duration"]),
                exercise: exercise,
                weightKg: double(row["weight_kg"]) ?? double(row["weight"]),
                reps: reps,
                rpe: int(row["rpe"])
            )
        }
    }

    // MARK: - Import

    /// Parse + persist. One completed WorkoutPlan per (start time, name)
    /// group, one ExerciseHistory row per exercise — the same shape
    /// persistCompletion writes, so charts and progression see the history.
    /// Unknown exercise names become custom Exercises (editable later).
    @MainActor
    static func importCSV(_ text: String, modelContext: ModelContext) throws -> ImportSummary {
        let (format, sets) = try parse(text)
        var summary = ImportSummary(format: format)

        struct GroupKey: Hashable {
            let start: Date
            let name: String
        }
        let groups = Dictionary(grouping: sets) { GroupKey(start: $0.start, name: $0.workoutName) }

        // Idempotency floor: any plan already carrying one of these start
        // times was imported (or lifted live) before — skip it.
        let existingStarts = Set(
            ((try? modelContext.fetch(FetchDescriptor<WorkoutPlan>())) ?? []).compactMap(\.startedAt)
        )
        var exercisesByName: [String: Exercise] = Dictionary(
            ((try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? [])
                .map { ($0.name.lowercased(), $0) }
        ) { first, _ in first }

        for key in groups.keys.sorted(by: { $0.start < $1.start }) {
            guard !existingStarts.contains(key.start) else {
                summary.duplicates += 1
                continue
            }
            guard let groupSets = groups[key] else { continue }

            let plan = WorkoutPlan(date: key.start, type: inferType(from: key.name))
            plan.status = .completed
            plan.startedAt = key.start
            plan.durationMinutes = groupSets.compactMap(\.durationMinutes).max()
            plan.finishedAt = plan.durationMinutes.map { key.start.addingTimeInterval(Double($0) * 60) }
                ?? key.start
            plan.notes = "Imported from \(format.rawValue)"
            modelContext.insert(plan)

            // Exercises in first-appearance order (CSV rows are in set order).
            var orderedNames: [String] = []
            for set in groupSets where !orderedNames.contains(set.exercise) {
                orderedNames.append(set.exercise)
            }

            for (order, name) in orderedNames.enumerated() {
                let exercise: Exercise
                if let known = exercisesByName[name.lowercased()] {
                    exercise = known
                } else {
                    // Classification unknown from a CSV — land it as a custom
                    // exercise with neutral traits; editable in the library.
                    exercise = Exercise(name: name, muscleGroup: .fullBody,
                                        equipment: .none, movementPattern: .isolation,
                                        isCompound: false, isCustom: true)
                    modelContext.insert(exercise)
                    exercisesByName[name.lowercased()] = exercise
                    summary.newExercises += 1
                }

                let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
                var planned: [PlannedSet] = []
                for (index, set) in groupSets.filter({ $0.exercise == name }).enumerated() {
                    let row = PlannedSet(
                        setNumber: index + 1,
                        targetReps: set.reps,
                        targetWeight: set.weightKg,
                        actualReps: set.reps,
                        actualWeight: set.weightKg,
                        completed: true,
                        plannedExercise: slot
                    )
                    row.completedAt = key.start
                    row.rpe = set.rpe
                    planned.append(row)
                }
                slot.sets = planned
                summary.sets += planned.count

                let best = planned.max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }
                let volume = planned.reduce(0.0) { acc, row in
                    acc + ((row.actualWeight ?? 0) * Double(row.actualReps ?? 0))
                }
                modelContext.insert(ExerciseHistory(
                    date: key.start,
                    estimated1RM: planned.compactMap(\.estimated1RM).max(),
                    totalVolume: volume,
                    bestSetWeight: best?.actualWeight,
                    bestSetReps: best?.actualReps,
                    setsPerformed: planned.count,
                    workoutPlanID: plan.id,
                    exercise: exercise
                ))
            }
            summary.workouts += 1
        }

        try modelContext.save()
        return summary
    }

    // MARK: - Export

    /// Strong-compatible CSV of completed workouts (kg, working sets with
    /// actuals only) — importable by Strong/Hevy and by Tempo itself.
    static func exportCSV(plans: [WorkoutPlan]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines = ["Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE"]
        for plan in plans.filter({ $0.status == .completed }).sorted(by: { $0.date < $1.date }) {
            let date = formatter.string(from: plan.startedAt ?? plan.date)
            let name = plan.type.displayName
            let duration = plan.durationMinutes.map { "\($0)m" } ?? ""
            for slot in plan.orderedExercises {
                guard let exercise = slot.exercise else { continue }
                let working = slot.orderedSets.filter { $0.completed && !$0.isWarmup }
                for (index, set) in working.enumerated() {
                    let weight = set.actualWeight.map { String(format: "%g", $0) } ?? ""
                    let rpe = set.rpe.map(String.init) ?? ""
                    lines.append([
                        date, escape(name), duration, escape(exercise.name),
                        "\(index + 1)", weight, "\(set.actualReps ?? 0)",
                        "", "", "", "", rpe,
                    ].joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    static func inferType(from workoutName: String) -> WorkoutType {
        let name = workoutName.lowercased()
        if name.contains("push") { return .push }
        if name.contains("pull") { return .pull }
        if name.contains("leg") { return .legs }
        if name.contains("lower") { return .lower }
        if name.contains("upper") { return .upper }
        return .fullBody
    }

    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "d MMM yyyy, HH:mm",
        "dd MMM yyyy, HH:mm",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss",
        "M/d/yyyy HH:mm",
        "M/d/yy HH:mm",
        "yyyy-MM-dd",
    ]

    private static func date(_ value: String?) -> Date? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in dateFormats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: value) {
                return parsed
            }
        }
        return nil
    }

    /// Strong duration strings: "1h 5m", "45m", "1h".
    private static func durationMinutes(_ value: String?) -> Int? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        var minutes = 0
        let scanner = Scanner(string: value)
        while !scanner.isAtEnd {
            guard let number = scanner.scanInt() else {
                _ = scanner.scanCharacter()
                continue
            }
            if scanner.scanString("h") != nil {
                minutes += number * 60
            } else {
                _ = scanner.scanString("m")
                minutes += number
            }
        }
        return minutes > 0 ? minutes : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func double(_ value: String?) -> Double? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        return Double(value.replacingOccurrences(of: ",", with: "."))
    }

    private static func int(_ value: String?) -> Int? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        return Int(value) ?? Double(value).map(Int.init)
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
