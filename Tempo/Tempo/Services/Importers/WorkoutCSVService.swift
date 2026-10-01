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
        /// Tags every workout/exercise this import created (see `undoImport`).
        var batchID: UUID?
        /// The unit weights were read in (nil when the file has no weights).
        var unit: WeightUnit?

        var label: String {
            if workouts == 0, duplicates > 0 {
                return "Nothing new — all \(duplicates) workouts were already in Tempo."
            }
            var parts = ["\(workouts) workouts", "\(sets) sets"]
            if newExercises > 0 {
                parts.append("\(newExercises) new exercises")
            }
            if duplicates > 0 {
                parts.append("\(duplicates) already in Tempo")
            }
            var text = "\(format.rawValue): " + parts.joined(separator: ", ") + "."
            if let unit {
                text += " Weights read as \(unit.abbreviation)."
            }
            return text
        }
    }

    /// One completed working set as parsed from any supported CSV. `weight`
    /// is exactly what the file says, in `unit` when the file declares one
    /// (a "Weight Unit" column, a "Weight (lbs)" / `weight_lbs` header) — the
    /// importer converts to kg, so a pound file is never read as kilos.
    struct ParsedSet: Equatable, Sendable {
        let workoutName: String
        let start: Date
        let durationMinutes: Int?
        let exercise: String
        let weight: Double?
        let unit: WeightUnit?
        let reps: Int
        let rpe: Int?

        /// The load in kg; `fallback` is the unit to assume when the file
        /// doesn't declare one. nil for a bodyweight set.
        func weightKg(assuming fallback: WeightUnit) -> Double? {
            guard let weight, weight > 0 else {
                return nil
            }
            return (unit ?? fallback).convert(weight, to: .kg)
        }
    }

    struct ParsedFile: Sendable {
        let format: Format
        let sets: [ParsedSet]
        /// The unit the file itself declares (header or unit column); nil
        /// when it doesn't say — the caller must ask or default.
        let declaredUnit: WeightUnit?
    }

    // MARK: - Parsing

    /// Header-detect the format and flatten the file to working-set rows.
    /// Warmup rows and rep-less rows (cardio/duration entries, Strong's
    /// rest-timer rows) are dropped. Pure and `nonisolated` so big files
    /// parse off the main actor.
    nonisolated static func parse(_ text: String) throws -> ParsedFile {
        var body = Substring(text)
        if body.hasPrefix("\u{FEFF}") {
            body = body.dropFirst()
        }
        let rows = WhoopExportParser.keyedRows(String(body)).map { row in
            Dictionary(row.map { key, value in
                (
                    key.trimmingCharacters(in: .whitespaces).lowercased(),
                    value.trimmingCharacters(in: .whitespacesAndNewlines)
                )
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
        } else if first["reps"] != nil,
                  first["exercise"] != nil || first["exercise name"] != nil || first["exercise_name"] != nil,
                  first["date"] != nil || first["start_time"] != nil
        {
            format = .generic
        } else {
            throw ImportError.unrecognizedFormat
        }

        let dates = DateParser()
        let sets = rows.compactMap { parsedSet(from: $0, format: format, dates: dates) }
        guard !sets.isEmpty else {
            throw ImportError.noWorkouts
        }
        return ParsedFile(format: format, sets: sets, declaredUnit: declaredUnit(header: first, sets: sets))
    }

    /// A unit named by a weight header ("Weight (lbs)", `weight_lbs`) wins;
    /// else the most common per-row "Weight Unit" value.
    private nonisolated static func declaredUnit(header first: [String: String], sets: [ParsedSet]) -> WeightUnit? {
        for key in first.keys.sorted() where key.hasPrefix("weight") && key != "weight unit" {
            if let unit = unit(fromName: key) {
                return unit
            }
        }
        let counts = sets.compactMap(\.unit).reduce(into: [WeightUnit: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    /// "weight_lbs", "Weight (lb)", "pounds", "kg", "kilograms" -> a unit.
    private nonisolated static func unit(fromName name: String?) -> WeightUnit? {
        guard let name = nonEmpty(name)?.lowercased() else {
            return nil
        }
        if name.contains("lb") || name.contains("pound") {
            return .lbs
        }
        if name.contains("kg") || name.contains("kilo") {
            return .kg
        }
        return nil
    }

    /// The load column, whatever the export called it, plus the unit that
    /// column (or a sibling "Weight Unit" column) declares.
    private nonisolated static func weightAndUnit(_ row: [String: String]) -> (Double?, WeightUnit?) {
        let candidates = row.keys.filter { $0.hasPrefix("weight") && $0 != "weight unit" }.sorted()
        // A column that names its unit first, a bare "weight" last.
        let ordered = candidates.filter { unit(fromName: $0) != nil } + candidates.filter { unit(fromName: $0) == nil }
        for key in ordered {
            if let value = double(row[key]) {
                return (value, unit(fromName: key) ?? unit(fromName: row["weight unit"]))
            }
        }
        return (nil, unit(fromName: row["weight unit"]))
    }

    private nonisolated static func parsedSet(
        from row: [String: String],
        format: Format,
        dates: DateParser
    ) -> ParsedSet? {
        let (weight, unit) = weightAndUnit(row)
        switch format {
        case .strong:
            // Strong marks warmups in "Set Order" ("W"/"W1"; "D" = drop set,
            // "F" = failure, both real working sets) and emits rest-timer /
            // note rows with no reps — all skipped.
            let order = (row["set order"] ?? "").uppercased()
            guard !order.hasPrefix("W"),
                  let start = dates.parse(row["date"]),
                  let exercise = nonEmpty(row["exercise name"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            return ParsedSet(
                workoutName: nonEmpty(row["workout name"]) ?? "Imported workout",
                start: start,
                durationMinutes: durationMinutes(row["duration"]) ?? durationMinutes(row["workout duration"]),
                exercise: exercise,
                weight: weight,
                unit: unit,
                reps: reps,
                rpe: int(row["rpe"])
            )
        case .hevy:
            // set_type: normal / warmup / failure / dropset.
            guard (row["set_type"] ?? "").lowercased() != "warmup",
                  let start = dates.parse(row["start_time"]),
                  let exercise = nonEmpty(row["exercise_title"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            let end = dates.parse(row["end_time"])
            let duration = end.map { Int($0.timeIntervalSince(start) / 60) }
            return ParsedSet(
                workoutName: nonEmpty(row["title"]) ?? "Imported workout",
                start: start,
                durationMinutes: duration.flatMap { $0 > 0 ? $0 : nil },
                exercise: exercise,
                weight: weight,
                unit: unit,
                reps: reps,
                rpe: int(row["rpe"])
            )
        case .generic:
            let kind = (row["set_type"] ?? row["set order"] ?? "").lowercased()
            let warmupFlag = (row["warmup"] ?? "").lowercased()
            guard !kind.hasPrefix("w"), !["true", "yes", "1"].contains(warmupFlag),
                  let start = dates.parse(row["date"] ?? row["start_time"]),
                  let exercise = nonEmpty(row["exercise"] ?? row["exercise name"] ?? row["exercise_name"]),
                  let reps = int(row["reps"]), reps > 0
            else {
                return nil
            }
            return ParsedSet(
                workoutName: nonEmpty(row["workout"]) ?? nonEmpty(row["workout name"]) ?? "Imported workout",
                start: start,
                durationMinutes: int(row["duration"]),
                exercise: exercise,
                weight: weight,
                unit: unit,
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
    static func importCSV(
        _ text: String,
        assumedUnit: WeightUnit? = nil,
        batchID: UUID = UUID(),
        modelContext: ModelContext
    ) throws -> ImportSummary {
        try importParsed(
            parse(text), assumedUnit: assumedUnit, batchID: batchID, modelContext: modelContext
        )
    }

    /// Persist an already-parsed file (the view parses first to learn whether
    /// it must ask which unit the weights are in).
    @MainActor
    static func importParsed(
        _ parsed: ParsedFile,
        assumedUnit: WeightUnit? = nil,
        batchID: UUID = UUID(),
        modelContext: ModelContext
    ) throws -> ImportSummary {
        let format = parsed.format
        let sets = parsed.sets
        // A unit the file declares wins per row; otherwise the caller's
        // choice; otherwise kg (what the app stores).
        let unit = assumedUnit ?? parsed.declaredUnit ?? .kg
        var summary = ImportSummary(format: format, batchID: batchID)
        if sets.contains(where: { ($0.weight ?? 0) > 0 }) {
            summary.unit = parsed.declaredUnit ?? unit
        }

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
            guard let groupSets = groups[key] else {
                continue
            }

            let plan = WorkoutPlan(date: key.start, type: inferType(from: key.name))
            plan.status = .completed
            plan.startedAt = key.start
            plan.durationMinutes = groupSets.compactMap(\.durationMinutes).max()
            plan.finishedAt = plan.durationMinutes.map { key.start.addingTimeInterval(Double($0) * 60) }
                ?? key.start
            plan.notes = "Imported from \(format.rawValue)"
            plan.importBatchID = batchID
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
                    exercise = Exercise(
                        name: name,
                        muscleGroup: .fullBody,
                        equipment: .none,
                        movementPattern: .isolation,
                        isCompound: false,
                        isCustom: true
                    )
                    exercise.importBatchID = batchID
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
                        targetWeight: set.weightKg(assuming: unit),
                        actualReps: set.reps,
                        actualWeight: set.weightKg(assuming: unit),
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

    // MARK: - Undo

    /// Removes everything one import created: its workouts (sets cascade),
    /// their history rows and records, and the custom exercises it added that
    /// nothing else uses. Returns how many workouts were removed.
    @MainActor
    @discardableResult
    static func undoImport(batchID: UUID, modelContext: ModelContext) throws -> Int {
        let plans = try modelContext.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.importBatchID == batchID }
        ))
        let planIDs = Set(plans.map(\.id))

        for history in try modelContext.fetch(FetchDescriptor<ExerciseHistory>())
            where history.workoutPlanID.map(planIDs.contains) == true
        {
            modelContext.delete(history)
        }
        for record in try modelContext.fetch(FetchDescriptor<PersonalRecord>())
            where record.workoutPlanID.map(planIDs.contains) == true
        {
            modelContext.delete(record)
        }
        for plan in plans {
            modelContext.delete(plan)
        }
        try modelContext.save()

        // Custom exercises this import created that no remaining session uses.
        let created = try modelContext.fetch(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.importBatchID == batchID }
        ))
        for exercise in created where (exercise.plannedExercises ?? []).isEmpty {
            modelContext.delete(exercise)
        }
        try modelContext.save()
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        return plans.count
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
                guard let exercise = slot.exercise else {
                    continue
                }
                let working = slot.orderedSets.filter { $0.completed && !$0.isWarmup }
                for (index, set) in working.enumerated() {
                    let weight = set.actualWeight.map { String(format: "%g", $0) } ?? ""
                    let rpe = set.rpe.map(String.init) ?? ""
                    // §6.4 — a drop step is exported as a set like any other
                    // (it counts toward volume/history), just annotated so
                    // it isn't mistaken for a straight working set.
                    let notes = set.dropStepIndex.map { "Drop \($0)" } ?? ""
                    lines.append([
                        date, escape(name), duration, escape(exercise.name),
                        "\(index + 1)", weight, "\(set.actualReps ?? 0)",
                        "", "", escape(notes), "", rpe,
                    ].joined(separator: ","))
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    static func inferType(from workoutName: String) -> WorkoutType {
        let name = workoutName.lowercased()
        if name.contains("push") {
            return .push
        }
        if name.contains("pull") {
            return .pull
        }
        if name.contains("leg") {
            return .legs
        }
        if name.contains("lower") {
            return .lower
        }
        if name.contains("upper") {
            return .upper
        }
        return .fullBody
    }

    /// Date formats seen in Strong, Hevy and hand-made CSVs. Formatters are
    /// built once per parse, not once per row, and the format that matched
    /// last is tried first (a file nearly always uses one format throughout).
    private final class DateParser {
        private static let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "d MMM yyyy, HH:mm",
            "d MMM yyyy, HH:mm:ss",
            "d MMM yyyy HH:mm",
            "MMM d, yyyy, h:mm a",
            "MMMM d, yyyy 'at' h:mm a",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "M/d/yyyy HH:mm",
            "M/d/yy HH:mm",
            "M/d/yyyy",
            "yyyy-MM-dd",
        ]

        private let formatters: [DateFormatter]
        private var lastHit = 0

        init() {
            formatters = Self.formats.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = format
                return formatter
            }
        }

        func parse(_ value: String?) -> Date? {
            guard let value, !value.isEmpty else {
                return nil
            }
            if let parsed = formatters[lastHit].date(from: value) {
                return parsed
            }
            for (index, formatter) in formatters.enumerated() where index != lastHit {
                if let parsed = formatter.date(from: value) {
                    lastHit = index
                    return parsed
                }
            }
            // ISO-8601 with a "Z" / fractional seconds.
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = iso.date(from: value) {
                return parsed
            }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: value)
        }
    }

    /// Strong duration strings: "1h 5m", "45m", "1h", "50s".
    private nonisolated static func durationMinutes(_ value: String?) -> Int? {
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
            } else if scanner.scanString("s") != nil {
                minutes += number / 60
            } else {
                _ = scanner.scanString("m")
                minutes += number
            }
        }
        return minutes > 0 ? minutes : nil
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    /// "82.5", "82,5" (decimal comma, quoted in the file) and "1,082.5"
    /// (thousands comma) all read as the number they mean.
    nonisolated static func double(_ value: String?) -> Double? {
        guard var text = nonEmpty(value)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }
        if text.contains(","), text.contains(".") {
            text = text.replacingOccurrences(of: ",", with: "")
        } else {
            text = text.replacingOccurrences(of: ",", with: ".")
        }
        return Double(text)
    }

    private nonisolated static func int(_ value: String?) -> Int? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        return Int(value) ?? double(value).map { Int($0) }
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
