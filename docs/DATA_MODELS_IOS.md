# Tempo iOS — SwiftData Models Specification

> **Version:** 1.1
> **Last Updated:** 2026-03-24
> **Framework:** SwiftData (iOS 17+, Swift 6)
> **Author:** Tempo iOS Architecture
>
> **IMPORTANT — SwiftData Production Notes:**
> - SwiftData auto-generates a `persistentModelID` for every `@Model`. The explicit `@Attribute(.unique) var id: UUID` is intentional: it gives us a stable, sync-friendly identifier that survives re-insertion and server round-trips. Do NOT remove it.
> - All enum properties are stored as their `String` raw values (e.g., `typeRaw: String`) — never store enum types directly. SwiftData can persist `String`/`Int`-backed `Codable` enums, but raw-value storage is more migration-safe.
> - Arrays of custom types (e.g., `[MuscleGroup]`) are serialized as `Data` (JSON) — SwiftData only natively supports `[String]`, `[Int]`, `[Double]`, `[Bool]`, `[Date]`, `[UUID]`, `[Data]` arrays. Use `@Relationship` for arrays of `@Model` objects.
> - Every `@Transient` computed property is excluded from the schema. They exist purely for convenience and are never persisted or migrated.
> - `#Predicate` macros cannot capture local variables in iOS 17. All date computations must be inlined or passed via `FetchDescriptor` — see Section 11 for correct patterns.

---

## Table of Contents

1. [Schema Configuration & ModelContainer](#1-schema-configuration--modelcontainer)
2. [Enums & Shared Types](#2-enums--shared-types)
3. [User & Settings Models](#3-user--settings-models)
4. [Dashboard Models](#4-dashboard-models)
5. [Training Models](#5-training-models)
6. [Accountability Models](#6-accountability-models)
7. [Recovery Models](#7-recovery-models)
8. [Arena Models](#8-arena-models)
9. [Sync Models](#9-sync-models)
10. [Integration State Models](#10-integration-state-models)
11. [Query Patterns Per Screen](#11-query-patterns-per-screen)
12. [Indexes & Performance](#12-indexes--performance)
13. [Sync Conflict Resolution](#13-sync-conflict-resolution)
14. [Data Lifecycle & Cleanup](#14-data-lifecycle--cleanup)
15. [Thread Safety & ModelContext Patterns](#15-thread-safety--modelcontext-patterns)
16. [Migration Strategy](#16-migration-strategy)

---

## 1. Schema Configuration & ModelContainer

```swift
import SwiftData

// MARK: - Schema Versions

enum TempoSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            UserProfile.self,
            UserSettings.self,
            DailySnapshot.self,
            WorkoutPlan.self,
            PlannedExercise.self,
            PlannedSet.self,
            Exercise.self,
            ExerciseHistory.self,
            PersonalRecord.self,
            RunSession.self,
            NonNegotiable.self,
            DailyAccountability.self,
            NonNegotiableProgress.self,
            StudySession.self,
            Streak.self,
            DailyRecovery.self,
            DailyPrescription.self,
            RecoveryInsight.self,
            XPEvent.self,
            Achievement.self,
            ChallengeLocal.self,
            SyncState.self,
            PendingSync.self,
            WhoopConnection.self,
            NutriTrackConnection.self,
            HealthKitState.self,
        ]
    }
}

enum TempoSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    // IMPORTANT: When V2 is actually needed, you MUST duplicate the full model list
    // here with the V2 versions of each model. VersionedSchema requires each schema
    // version to declare its own model types (they can be the same @Model classes
    // if no schema changes affect them, but they must be explicitly listed).
    // Using TempoSchemaV1.models as a placeholder is acceptable ONLY while V2
    // has no actual schema differences. The moment you add/change a V2 model,
    // list all models explicitly.
    static var models: [any PersistentModel.Type] {
        TempoSchemaV1.models // placeholder — replace with explicit list when V2 has changes
    }
}

// MARK: - Migration Plans

enum TempoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TempoSchemaV1.self, TempoSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TempoSchemaV1.self,
        toVersion: TempoSchemaV2.self
    )
}

// MARK: - Container Factory

@MainActor
struct TempoModelContainer {

    static func create(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(TempoSchemaV1.models)

        let config = ModelConfiguration(
            "TempoStore",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            groupContainer: .identifier("group.app.tempo"),
            cloudKitDatabase: .none // CloudKit disabled — we use Vapor sync
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: TempoMigrationPlan.self,
            configurations: [config]
        )
    }

    /// Container for SwiftUI previews and unit tests.
    static func preview() throws -> ModelContainer {
        try create(inMemory: true)
    }
}
```

**Usage in `TempoApp.swift`:**

```swift
import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try TempoModelContainer.create()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
```

---

## 2. Enums & Shared Types

All enums conform to `String, Codable, CaseIterable` so they serialize cleanly for both SwiftData and API JSON payloads.

```swift
import Foundation

// MARK: - Training Enums

enum WorkoutType: String, Codable, CaseIterable {
    case push
    case pull
    case legs
    case upper
    case lower
    case fullBody = "full_body"
    case football
    case run
    case sprint
    case conditioning
    case mobility
    case rest

    var displayName: String {
        switch self {
        case .push: "Push"
        case .pull: "Pull"
        case .legs: "Legs"
        case .upper: "Upper"
        case .lower: "Lower"
        case .fullBody: "Full Body"
        case .football: "Football"
        case .run: "Run"
        case .sprint: "Sprint"
        case .conditioning: "Conditioning"
        case .mobility: "Mobility"
        case .rest: "Rest"
        }
    }

    var isGymWorkout: Bool {
        switch self {
        case .push, .pull, .legs, .upper, .lower, .fullBody: true
        default: false
        }
    }
}

enum WorkoutStatus: String, Codable, CaseIterable {
    case planned
    case inProgress = "in_progress"
    case completed
    case skipped

    var isTerminal: Bool {
        self == .completed || self == .skipped
    }
}

enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case fullBody = "full_body"
    case cardio

    var displayName: String {
        switch self {
        case .fullBody: "Full Body"
        default: rawValue.capitalized
        }
    }
}

enum Equipment: String, Codable, CaseIterable {
    case barbell
    case dumbbell
    case cable
    case machine
    case bodyweight
    case kettlebell
    case resistanceBand = "resistance_band"
    case smithMachine = "smith_machine"
    case ezBar = "ez_bar"
    case trapBar = "trap_bar"
    case pullUpBar = "pull_up_bar"
    case bench
    case none
}

enum MovementPattern: String, Codable, CaseIterable {
    case horizontalPush = "horizontal_push"
    case horizontalPull = "horizontal_pull"
    case verticalPush = "vertical_push"
    case verticalPull = "vertical_pull"
    case squat
    case hinge
    case lunge
    case carry
    case isolation
    case rotation
    case plank
    case cardio
}

enum PRType: String, Codable, CaseIterable {
    case oneRepMax = "1rm"
    case repMax = "rep_max"      // e.g., best 5RM, 8RM, 10RM
    case volume                  // total volume in a single session
}

// MARK: - Accountability Enums

enum NonNegotiableType: String, Codable, CaseIterable {
    case study
    case train
    case meals
    case sleep
    case steps
    case hydration
    case custom

    var defaultIcon: String {
        switch self {
        case .study: "book.fill"
        case .train: "dumbbell.fill"
        case .meals: "fork.knife"
        case .sleep: "moon.fill"
        case .steps: "figure.walk"
        case .hydration: "drop.fill"
        case .custom: "star.fill"
        }
    }
}

enum TrackingMethod: String, Codable, CaseIterable {
    case autoWhoop = "auto_whoop"
    case autoNutritrack = "auto_nutritrack"
    case autoHealthkit = "auto_healthkit"
    case manual
    case timer
}

enum StudySessionType: String, Codable, CaseIterable {
    case pomodoro
    case deepWork = "deep_work"
    case custom
}

enum StreakType: String, Codable, CaseIterable {
    case overall
    case study
    case training
    case meals
    case nonNegotiables = "non_negotiables"
}

// MARK: - Recovery Enums

enum RecoveryZone: String, Codable, CaseIterable {
    case green   // >= 67%
    case yellow  // 34-66%
    case red     // < 34%

    init(score: Double) {
        switch score {
        case 67...100: self = .green
        case 34..<67:  self = .yellow
        default:       self = .red
        }
    }

    /// Asset catalog color name for this zone.
    var colorAssetName: String {
        switch self {
        case .green: "tempo.color.recovery.green"   // #22C55E light, #4ADE80 dark
        case .yellow: "tempo.color.recovery.yellow"  // #EAB308 light, #FACC15 dark
        case .red: "tempo.color.recovery.red"        // #DC2626 light, #F87171 dark
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum RecoveryInsightType: String, Codable, CaseIterable {
    case correlation
    case pattern
    case recommendation
}

// MARK: - Arena Enums

enum XPSource: String, Codable, CaseIterable {
    case workout
    case study
    case meal
    case sleep
    case steps
    case nonNegotiable = "non_negotiable"
    case streak
    case challenge
    case achievement
    case perfectDay = "perfect_day"
    case penalty
}

enum AchievementCategory: String, Codable, CaseIterable {
    case training
    case study
    case nutrition
    case recovery
    case consistency
    case social
    case milestone
    case hidden
}

enum AchievementRarity: String, Codable, CaseIterable {
    case common
    case uncommon
    case rare
    case epic
    case legendary

    var xpMultiplier: Double {
        switch self {
        case .common: 1.0
        case .uncommon: 1.5
        case .rare: 2.0
        case .epic: 3.0
        case .legendary: 5.0
        }
    }
}

// MARK: - Sync Enums

enum SyncAction: String, Codable, CaseIterable {
    case create
    case update
    case delete
}

// MARK: - Shared Types

enum WeightUnit: String, Codable, CaseIterable {
    case kg
    case lbs

    func convert(_ value: Double, to target: WeightUnit) -> Double {
        guard self != target else { return value }
        switch (self, target) {
        case (.kg, .lbs): return value * 2.20462
        case (.lbs, .kg): return value / 2.20462
        default: return value
        }
    }
}

enum TrainingSplit: String, Codable, CaseIterable {
    case pushPullLegs = "ppl"
    case upperLower = "upper_lower"
    case fullBody = "full_body"
    case bro = "bro_split"
    case custom
}

/// Bitmask for active days of the week.
/// Monday = 1, Tuesday = 2, Wednesday = 4, Thursday = 8,
/// Friday = 16, Saturday = 32, Sunday = 64
struct ActiveDays: Codable, Equatable {
    var rawValue: Int

    static let monday    = ActiveDays(rawValue: 1 << 0)
    static let tuesday   = ActiveDays(rawValue: 1 << 1)
    static let wednesday = ActiveDays(rawValue: 1 << 2)
    static let thursday  = ActiveDays(rawValue: 1 << 3)
    static let friday    = ActiveDays(rawValue: 1 << 4)
    static let saturday  = ActiveDays(rawValue: 1 << 5)
    static let sunday    = ActiveDays(rawValue: 1 << 6)
    static let weekdays  = ActiveDays(rawValue: 0b0011111)
    static let everyday  = ActiveDays(rawValue: 0b1111111)

    func isActive(on weekday: Int) -> Bool {
        // weekday: 1 = Sunday (Calendar), remap to our Monday = 0
        let index = (weekday + 5) % 7
        return (rawValue & (1 << index)) != 0
    }

    mutating func toggle(_ day: ActiveDays) {
        rawValue ^= day.rawValue
    }
}
```

---

## 3. User & Settings Models

### 3.1 UserProfile

```swift
import Foundation
import SwiftData

@Model
final class UserProfile {

    // MARK: - Identity

    /// Unique stable ID for local persistence. Also used as server entity ID.
    @Attribute(.unique)
    var id: UUID

    /// Apple Sign-In user identifier. Unique per Apple account.
    @Attribute(.unique)
    var appleID: String

    /// Public username (3-30 chars, alphanumeric + underscores). Unique globally.
    @Attribute(.unique)
    var username: String

    /// Display name shown in the app (1-50 chars).
    var displayName: String

    /// URL to avatar image. Nil if user hasn't uploaded one.
    var avatarURL: String?

    // MARK: - Biometrics

    /// User's timezone identifier (e.g., "America/New_York").
    var timezone: String

    /// Body weight in kilograms. Used for training load calculations.
    var weightKg: Double?

    /// Height in centimeters. Used for BMR estimation.
    var heightCm: Double?

    /// Age in years. Updated from date_of_birth on backend.
    var age: Int?

    // MARK: - Training Configuration

    /// Preferred training split.
    var trainingSplitRaw: String

    /// Days when football is scheduled (bitmask).
    var footballDaysRaw: Int

    /// Available equipment (serialized JSON array of Equipment raw values).
    var equipmentJSON: Data?

    /// Preferred weight unit for display.
    var weightUnitRaw: String

    // MARK: - Cached Aggregates

    /// Total lifetime XP. Updated incrementally when XPEvents are created.
    /// Avoids fetching all XPEvent records to compute the sum.
    var totalXP: Int

    /// Current level (derived from totalXP using the leveling curve).
    var currentLevel: Int

    // MARK: - Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Relationships

    /// User settings (1:1 relationship).
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
                  let raw = try? JSONDecoder().decode([String].self, from: data) else {
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

    /// Estimated BMR using Mifflin-St Jeor (male).
    @Transient
    var estimatedBMR: Double? {
        guard let w = weightKg, let h = heightCm, let a = age else { return nil }
        return (10 * w) + (6.25 * h) - (5 * Double(a)) + 5
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        appleID: String,
        username: String,
        displayName: String,
        avatarURL: String? = nil,
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
        self.timezone = timezone
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.age = age
        self.trainingSplitRaw = trainingSplit.rawValue
        self.footballDaysRaw = footballDays.rawValue
        self.equipmentJSON = try? JSONEncoder().encode(equipment.map(\.rawValue))
        self.weightUnitRaw = weightUnit.rawValue
        self.totalXP = 0
        self.currentLevel = 1
        self.createdAt = Date()
        self.updatedAt = Date()
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
        guard username.count >= 3 else { throw ValidationError.usernameTooShort }
        guard username.count <= 30 else { throw ValidationError.usernameTooLong }

        let usernameRegex = /^[a-zA-Z0-9_]+$/
        guard username.wholeMatch(of: usernameRegex) != nil else {
            throw ValidationError.usernameInvalidChars
        }

        guard !displayName.isEmpty else { throw ValidationError.displayNameEmpty }
        guard displayName.count <= 50 else { throw ValidationError.displayNameTooLong }

        if let w = weightKg {
            guard (30...300).contains(w) else { throw ValidationError.invalidWeight }
        }
        if let h = heightCm {
            guard (100...250).contains(h) else { throw ValidationError.invalidHeight }
        }
        if let a = age {
            guard (13...100).contains(a) else { throw ValidationError.invalidAge }
        }
    }
}
```

### 3.2 UserSettings

```swift
import Foundation
import SwiftData

@Model
final class UserSettings {

    @Attribute(.unique)
    var id: UUID

    // MARK: - Relationships

    /// The user profile this settings record belongs to.
    @Relationship(deleteRule: .nullify)
    var userProfile: UserProfile?

    // MARK: - Notification Preferences

    /// Notification intensity level: 1 = Gentle Coach, 2 = Firm Coach, 3 = Drill Sergeant, 4 = Savage Mode.
    var notificationIntensity: Int

    // MARK: - Schedule

    /// The time the user typically starts leisure time (minutes from midnight).
    /// Default: 19:30 = 1170 minutes. UI label: "Leisure Time". Default copy references PS5.
    var leisureTimeMinutes: Int

    /// Target wake time (minutes from midnight). Default: 07:00 = 420.
    var wakeTimeMinutes: Int

    /// Target bedtime (minutes from midnight). Default: 23:00 = 1380.
    var bedtimeTargetMinutes: Int

    // MARK: - Focus Timer

    /// Pomodoro work duration in minutes. Default: 25.
    var pomodoroDuration: Int

    /// Pomodoro break duration in minutes. Default: 5.
    var breakDuration: Int

    /// Long break duration in minutes (after 4 pomodoros). Default: 15.
    var longBreakDuration: Int

    // MARK: - Modes

    /// Weekend mode: relaxed non-negotiable targets on Sat/Sun.
    var weekendMode: Bool

    /// Exam mode: higher study targets, reduced training volume.
    var examMode: Bool

    /// Exam mode end date. Nil if exam mode is off.
    var examModeEndDate: Date?

    // MARK: - Timestamps

    var updatedAt: Date

    // MARK: - Computed

    @Transient
    var leisureTime: DateComponents {
        DateComponents(hour: leisureTimeMinutes / 60, minute: leisureTimeMinutes % 60)
    }

    @Transient
    var wakeTime: DateComponents {
        DateComponents(hour: wakeTimeMinutes / 60, minute: wakeTimeMinutes % 60)
    }

    @Transient
    var bedtimeTarget: DateComponents {
        DateComponents(hour: bedtimeTargetMinutes / 60, minute: bedtimeTargetMinutes % 60)
    }

    /// Returns the bedtime as a Date for today.
    @Transient
    var bedtimeToday: Date? {
        Calendar.current.date(from: DateComponents(
            year: Calendar.current.component(.year, from: .now),
            month: Calendar.current.component(.month, from: .now),
            day: Calendar.current.component(.day, from: .now),
            hour: bedtimeTargetMinutes / 60,
            minute: bedtimeTargetMinutes % 60
        ))
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        notificationIntensity: Int = 3,
        leisureTimeMinutes: Int = 1170,       // 19:30
        wakeTimeMinutes: Int = 420,       // 07:00
        bedtimeTargetMinutes: Int = 1380, // 23:00
        pomodoroDuration: Int = 25,
        breakDuration: Int = 5,
        longBreakDuration: Int = 15,
        weekendMode: Bool = true,
        examMode: Bool = false,
        examModeEndDate: Date? = nil
    ) {
        self.id = id
        self.notificationIntensity = notificationIntensity
        self.leisureTimeMinutes = leisureTimeMinutes
        self.wakeTimeMinutes = wakeTimeMinutes
        self.bedtimeTargetMinutes = bedtimeTargetMinutes
        self.pomodoroDuration = pomodoroDuration
        self.breakDuration = breakDuration
        self.longBreakDuration = longBreakDuration
        self.weekendMode = weekendMode
        self.examMode = examMode
        self.examModeEndDate = examModeEndDate
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO

extension UserSettings {

    struct DTO: Codable {
        let notification_intensity: Int
        let leisure_time_minutes: Int
        let wake_time_minutes: Int
        let bedtime_target_minutes: Int
        let pomodoro_duration: Int
        let break_duration: Int
        let long_break_duration: Int
        let weekend_mode: Bool
        let exam_mode: Bool
        let exam_mode_end_date: Date?
    }

    func toDTO() -> DTO {
        DTO(
            notification_intensity: notificationIntensity,
            leisure_time_minutes: leisureTimeMinutes,
            wake_time_minutes: wakeTimeMinutes,
            bedtime_target_minutes: bedtimeTargetMinutes,
            pomodoro_duration: pomodoroDuration,
            break_duration: breakDuration,
            long_break_duration: longBreakDuration,
            weekend_mode: weekendMode,
            exam_mode: examMode,
            exam_mode_end_date: examModeEndDate
        )
    }
}

// MARK: - Validation

extension UserSettings {

    enum ValidationError: LocalizedError {
        case invalidNotificationIntensity
        case invalidPomodoroDuration
        case invalidBreakDuration
        case invalidTimeOfDay

        var errorDescription: String? {
            switch self {
            case .invalidNotificationIntensity: "Notification intensity must be 1-4 (Gentle, Firm, Drill Sergeant, Savage)."
            case .invalidPomodoroDuration: "Pomodoro duration must be 5-120 minutes."
            case .invalidBreakDuration: "Break duration must be 1-60 minutes."
            case .invalidTimeOfDay: "Time of day must be 0-1439 (minutes from midnight)."
            }
        }
    }

    func validate() throws {
        guard (1...4).contains(notificationIntensity) else {
            throw ValidationError.invalidNotificationIntensity
        }
        guard (5...120).contains(pomodoroDuration) else {
            throw ValidationError.invalidPomodoroDuration
        }
        guard (1...60).contains(breakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        guard (1...60).contains(longBreakDuration) else {
            throw ValidationError.invalidBreakDuration
        }
        let validTimeRange = 0..<1440
        guard validTimeRange.contains(leisureTimeMinutes),
              validTimeRange.contains(wakeTimeMinutes),
              validTimeRange.contains(bedtimeTargetMinutes) else {
            throw ValidationError.invalidTimeOfDay
        }
    }
}
```

---

## 4. Dashboard Models

### 4.1 DailySnapshot

The central daily aggregation model. One per day. Sources: Whoop, HealthKit, NutriTrack, local modules.

```swift
import Foundation
import SwiftData

// PERFORMANCE NOTE: DailySnapshot has ~30 stored properties. This is at the upper limit
// for SwiftData fetch performance. If fetch times degrade (>50ms for single-row lookup),
// consider splitting into DailySnapshot (core fields: date, scores, compliance) and
// DailySnapshotDetail (individual metrics). For now, 30 properties on a single-row-per-day
// model is acceptable — the total row count stays low (~365/year).
@Model
final class DailySnapshot {

    @Attribute(.unique)
    var id: UUID

    /// Calendar date (normalized to midnight UTC). Unique constraint.
    @Attribute(.unique)
    var date: Date

    // MARK: - Body (Whoop + HealthKit)

    /// Whoop recovery percentage (0-100). Nil if Whoop not connected or no data.
    var recoveryScore: Double?

    /// Whoop HRV in milliseconds (RMSSD).
    var hrv: Double?

    /// Whoop resting heart rate (bpm).
    var rhr: Double?

    /// Total sleep hours (from Whoop).
    var sleepHours: Double?

    /// Whoop sleep performance percentage (0-100).
    var sleepScore: Double?

    /// Whoop day strain (0-21 scale).
    var strain: Double?

    // MARK: - Fuel (NutriTrack)

    /// Total calories consumed today.
    var caloriesConsumed: Int?

    /// Daily calorie target.
    var calorieTarget: Int?

    /// Actual macros (grams).
    var proteinActual: Double?
    var carbsActual: Double?
    var fatActual: Double?

    /// Target macros (grams).
    var proteinTarget: Double?
    var carbsTarget: Double?
    var fatTarget: Double?

    /// Number of meals logged today.
    var mealsLogged: Int

    /// Number of meals planned for today.
    var mealsPlanned: Int

    // MARK: - Mind (Local)

    /// Total study minutes today (sum of StudySession durations).
    var studyMinutes: Int

    /// Daily study target in minutes.
    var studyTarget: Int

    // MARK: - Move (HealthKit + Local)

    /// Steps from HealthKit.
    var steps: Int?

    /// Active energy burned in kcal (HealthKit).
    var activeCalories: Double?

    /// Whether a workout was completed today.
    var workoutCompleted: Bool

    /// Type of workout completed (raw value of WorkoutType).
    var workoutTypeRaw: String?

    // MARK: - Body Extended (Whoop via DailyRecovery)

    /// Blood oxygen percentage (from Whoop DailyRecovery.spo2). Nil if not available.
    var spo2: Double?

    /// Skin temperature deviation in Celsius (from Whoop DailyRecovery.skinTemp). Nil if not available.
    var skinTemp: Double?

    // MARK: - Score

    /// Composite daily score (0-100).
    var dailyScore: Int

    /// Non-negotiables completed count.
    var nonNegotiablesCompleted: Int

    /// Total non-negotiables for the day.
    var nonNegotiablesTotal: Int

    // MARK: - Timestamps

    var updatedAt: Date

    // MARK: - Computed Properties

    @Transient
    var workoutType: WorkoutType? {
        get { workoutTypeRaw.flatMap { WorkoutType(rawValue: $0) } }
        set { workoutTypeRaw = newValue?.rawValue }
    }

    /// Calorie compliance as a percentage (0.0-1.0+).
    @Transient
    var calorieCompliance: Double? {
        guard let consumed = caloriesConsumed, let target = calorieTarget, target > 0 else {
            return nil
        }
        return Double(consumed) / Double(target)
    }

    /// Protein compliance as a percentage (0.0-1.0+).
    @Transient
    var proteinCompliance: Double? {
        guard let actual = proteinActual, let target = proteinTarget, target > 0 else {
            return nil
        }
        return actual / target
    }

    /// Study compliance as a percentage (0.0-1.0+).
    @Transient
    var studyCompliance: Double {
        guard studyTarget > 0 else { return 1.0 }
        return Double(studyMinutes) / Double(studyTarget)
    }

    /// Non-negotiable compliance as a percentage (0.0-1.0).
    @Transient
    var nonNegotiableCompliance: Double {
        guard nonNegotiablesTotal > 0 else { return 1.0 }
        return Double(nonNegotiablesCompleted) / Double(nonNegotiablesTotal)
    }

    /// Recovery zone derived from recovery score.
    @Transient
    var recoveryZone: RecoveryZone? {
        recoveryScore.map { RecoveryZone(score: $0) }
    }

    /// Whether all macro targets are within 10% tolerance.
    @Transient
    var macrosOnTarget: Bool {
        guard let pA = proteinActual, let pT = proteinTarget, pT > 0,
              let cA = carbsActual, let cT = carbsTarget, cT > 0,
              let fA = fatActual, let fT = fatTarget, fT > 0 else {
            return false
        }
        let tolerance = 0.10
        return abs(pA - pT) / pT <= tolerance &&
               abs(cA - cT) / cT <= tolerance &&
               abs(fA - fT) / fT <= tolerance
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        recoveryScore: Double? = nil,
        hrv: Double? = nil,
        rhr: Double? = nil,
        sleepHours: Double? = nil,
        sleepScore: Double? = nil,
        strain: Double? = nil,
        caloriesConsumed: Int? = nil,
        calorieTarget: Int? = nil,
        proteinActual: Double? = nil,
        carbsActual: Double? = nil,
        fatActual: Double? = nil,
        proteinTarget: Double? = nil,
        carbsTarget: Double? = nil,
        fatTarget: Double? = nil,
        mealsLogged: Int = 0,
        mealsPlanned: Int = 3,
        studyMinutes: Int = 0,
        studyTarget: Int = 120,
        steps: Int? = nil,
        activeCalories: Double? = nil,
        workoutCompleted: Bool = false,
        workoutType: WorkoutType? = nil,
        dailyScore: Int = 0,
        nonNegotiablesCompleted: Int = 0,
        nonNegotiablesTotal: Int = 0
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.recoveryScore = recoveryScore
        self.hrv = hrv
        self.rhr = rhr
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.strain = strain
        self.caloriesConsumed = caloriesConsumed
        self.calorieTarget = calorieTarget
        self.proteinActual = proteinActual
        self.carbsActual = carbsActual
        self.fatActual = fatActual
        self.proteinTarget = proteinTarget
        self.carbsTarget = carbsTarget
        self.fatTarget = fatTarget
        self.mealsLogged = mealsLogged
        self.mealsPlanned = mealsPlanned
        self.studyMinutes = studyMinutes
        self.studyTarget = studyTarget
        self.steps = steps
        self.activeCalories = activeCalories
        self.workoutCompleted = workoutCompleted
        self.workoutTypeRaw = workoutType?.rawValue
        self.dailyScore = dailyScore
        self.nonNegotiablesCompleted = nonNegotiablesCompleted
        self.nonNegotiablesTotal = nonNegotiablesTotal
        self.updatedAt = Date()
    }
}

// MARK: - Codable DTO

extension DailySnapshot {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let recovery_score: Double?
        let hrv: Double?
        let rhr: Double?
        let sleep_hours: Double?
        let sleep_score: Double?
        let strain: Double?
        let calories_consumed: Int?
        let calorie_target: Int?
        let protein_actual: Double?
        let carbs_actual: Double?
        let fat_actual: Double?
        let protein_target: Double?
        let carbs_target: Double?
        let fat_target: Double?
        let meals_logged: Int
        let meals_planned: Int
        let study_minutes: Int
        let study_target: Int
        let steps: Int?
        let active_calories: Double?
        let workout_completed: Bool
        let workout_type: String?
        let daily_score: Int
        let non_negotiables_completed: Int
        let non_negotiables_total: Int
        let updated_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            recovery_score: recoveryScore,
            hrv: hrv,
            rhr: rhr,
            sleep_hours: sleepHours,
            sleep_score: sleepScore,
            strain: strain,
            calories_consumed: caloriesConsumed,
            calorie_target: calorieTarget,
            protein_actual: proteinActual,
            carbs_actual: carbsActual,
            fat_actual: fatActual,
            protein_target: proteinTarget,
            carbs_target: carbsTarget,
            fat_target: fatTarget,
            meals_logged: mealsLogged,
            meals_planned: mealsPlanned,
            study_minutes: studyMinutes,
            study_target: studyTarget,
            steps: steps,
            active_calories: activeCalories,
            workout_completed: workoutCompleted,
            workout_type: workoutTypeRaw,
            daily_score: dailyScore,
            non_negotiables_completed: nonNegotiablesCompleted,
            non_negotiables_total: nonNegotiablesTotal,
            updated_at: updatedAt
        )
    }
}
```

### 4.2 Dashboard View Models

These are `@Transient` computed view models used by MODULE_DASHBOARD.md. They are NOT persisted — they are derived from `DailySnapshot` and related models at display time.

```swift
// MARK: - Dashboard Quadrant View Models

/// Maps DailySnapshot fields to Dashboard's BodyQuadrantData.
/// See MODULE_DASHBOARD.md Section 2.2 for full specification.
struct BodyQuadrantData {
    let recoveryScore: Double?      // ← DailySnapshot.recoveryScore
    let hrvRmssd: Double?           // ← DailySnapshot.hrv
    let restingHeartRate: Double?   // ← DailySnapshot.rhr (Double, not Int)
    let sleepPerformance: Double?   // ← DailySnapshot.sleepScore
    let strain: Double?             // ← DailySnapshot.strain
    let spo2: Double?               // ← DailySnapshot.spo2
    let skinTemp: Double?           // ← DailySnapshot.skinTemp
    let source: DataSource          // ← Computed from WhoopService connection state
    let lastSync: Date?             // ← Computed from WhoopService.lastSyncDate
    let isStale: Bool               // ← Computed: lastSync > 4 hours ago
}

/// Maps DailySnapshot fields to Dashboard's FuelQuadrantData.
struct FuelQuadrantData {
    let caloriesConsumed: Int?      // ← DailySnapshot.caloriesConsumed
    let calorieTarget: Int?         // ← DailySnapshot.calorieTarget
    let proteinActual: Double?      // ← DailySnapshot.proteinActual
    let proteinTarget: Double?      // ← DailySnapshot.proteinTarget
    let mealsLogged: Int            // ← DailySnapshot.mealsLogged
    let mealsPlanned: Int           // ← DailySnapshot.mealsPlanned
    let mealStatuses: [MealStatus]  // ← Computed from NutriTrackService meal data
}

/// Maps DailySnapshot fields to Dashboard's MindQuadrantData.
struct MindQuadrantData {
    let studyMinutes: Int           // ← DailySnapshot.studyMinutes
    let studyTarget: Int            // ← DailySnapshot.studyTarget
    let exams: [UpcomingExam]       // ← Computed from EventKitService calendar data
}

/// Maps DailySnapshot fields to Dashboard's MoveQuadrantData.
struct MoveQuadrantData {
    let steps: Int?                 // ← DailySnapshot.steps
    let activeCalories: Double?     // ← DailySnapshot.activeCalories
    let workoutCompleted: Bool      // ← DailySnapshot.workoutCompleted
    let workoutName: String?        // ← Computed from DailySnapshot.workoutTypeRaw display name
    let heartRateCurrent: Int?      // ← Live from HealthKit HKQuantityType.heartRate query
}
```

> **Note:** `source`, `lastSync`, `isStale`, `mealStatuses`, `exams`, `heartRateCurrent`, and `workoutName` are NOT stored in DailySnapshot. They are populated at display time from their respective services (WhoopService, NutriTrackService, EventKitService, HealthKit). The `DashboardViewModel` assembles these quadrant models by combining DailySnapshot persistence data with live service state.

---

## 5. Training Models

### 5.1 Exercise

The exercise library. Seeded from `Exercises.json` on first launch, plus user-created custom exercises.

```swift
import Foundation
import SwiftData

@Model
final class Exercise {

    @Attribute(.unique)
    var id: UUID

    /// Exercise name (e.g., "Bench Press", "Barbell Squat").
    var name: String

    /// Primary muscle group.
    var muscleGroupRaw: String

    /// Secondary muscles (serialized JSON array of MuscleGroup raw values).
    var secondaryMusclesJSON: Data?

    /// Required equipment.
    var equipmentRaw: String

    /// Movement pattern classification.
    var movementPatternRaw: String

    /// Whether this is a compound (multi-joint) movement.
    var isCompound: Bool

    /// Whether the user created this exercise (vs. seed data).
    var isCustom: Bool

    /// Asset name for demo animation/image. Nil for custom exercises.
    var demoAsset: String?

    /// Text instructions for performing the exercise.
    var instructions: String?

    /// Coaching cues (serialized JSON string array).
    var cuesJSON: Data?

    // MARK: - Relationships

    /// All planned instances of this exercise across workouts.
    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.exercise)
    var plannedExercises: [PlannedExercise]?

    /// Historical performance records.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseHistory.exercise)
    var history: [ExerciseHistory]?

    /// Personal records for this exercise.
    @Relationship(deleteRule: .cascade, inverse: \PersonalRecord.exercise)
    var personalRecords: [PersonalRecord]?

    // MARK: - Computed

    @Transient
    var muscleGroup: MuscleGroup {
        get { MuscleGroup(rawValue: muscleGroupRaw) ?? .chest }
        set { muscleGroupRaw = newValue.rawValue }
    }

    @Transient
    var secondaryMuscles: [MuscleGroup] {
        get {
            guard let data = secondaryMusclesJSON,
                  let raw = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return raw.compactMap { MuscleGroup(rawValue: $0) }
        }
        set {
            secondaryMusclesJSON = try? JSONEncoder().encode(newValue.map(\.rawValue))
        }
    }

    @Transient
    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .barbell }
        set { equipmentRaw = newValue.rawValue }
    }

    @Transient
    var movementPattern: MovementPattern {
        get { MovementPattern(rawValue: movementPatternRaw) ?? .horizontalPush }
        set { movementPatternRaw = newValue.rawValue }
    }

    @Transient
    var cues: [String] {
        get {
            guard let data = cuesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            cuesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    /// Current estimated 1RM from the latest ExerciseHistory entry.
    @Transient
    var currentEstimated1RM: Double? {
        history?
            .sorted { $0.date > $1.date }
            .first?
            .estimated1RM
    }

    /// All-time best 1RM from PersonalRecord.
    @Transient
    var allTimePR: Double? {
        personalRecords?
            .filter { $0.typeRaw == PRType.oneRepMax.rawValue }
            .max(by: { $0.value < $1.value })?
            .value
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup,
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        movementPattern: MovementPattern,
        isCompound: Bool,
        isCustom: Bool = false,
        demoAsset: String? = nil,
        instructions: String? = nil,
        cues: [String] = []
    ) {
        self.id = id
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.secondaryMusclesJSON = try? JSONEncoder().encode(secondaryMuscles.map(\.rawValue))
        self.equipmentRaw = equipment.rawValue
        self.movementPatternRaw = movementPattern.rawValue
        self.isCompound = isCompound
        self.isCustom = isCustom
        self.demoAsset = demoAsset
        self.instructions = instructions
        self.cuesJSON = try? JSONEncoder().encode(cues)
    }
}

// MARK: - DTO

extension Exercise {

    struct DTO: Codable {
        let id: UUID
        let name: String
        let muscle_group: String
        let secondary_muscles: [String]
        let equipment: String
        let movement_pattern: String
        let is_compound: Bool
        let is_custom: Bool
        let demo_asset: String?
        let instructions: String?
        let cues: [String]
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            name: name,
            muscle_group: muscleGroupRaw,
            secondary_muscles: secondaryMuscles.map(\.rawValue),
            equipment: equipmentRaw,
            movement_pattern: movementPatternRaw,
            is_compound: isCompound,
            is_custom: isCustom,
            demo_asset: demoAsset,
            instructions: instructions,
            cues: cues
        )
    }
}
```

### 5.2 WorkoutPlan

```swift
import Foundation
import SwiftData

@Model
final class WorkoutPlan {

    @Attribute(.unique)
    var id: UUID

    /// Date this workout is scheduled for (normalized to midnight).
    var date: Date

    /// Workout type (raw value).
    var typeRaw: String

    /// Recovery-based adjustment factor. 1.0 = normal, <1.0 = reduced, >1.0 = push.
    var recoveryAdjustment: Double

    /// Current status (raw value).
    var statusRaw: String

    /// Estimated duration in minutes.
    var durationMinutes: Int?

    /// Free-text notes (e.g., "Focus on form", "Deload week").
    var notes: String?

    /// Timestamp when the workout started (tapped "Start Workout").
    var startedAt: Date?

    /// Timestamp when the workout was completed or skipped.
    var finishedAt: Date?

    // MARK: - Relationships

    /// Ordered list of exercises in this workout.
    @Relationship(deleteRule: .cascade, inverse: \PlannedExercise.workoutPlan)
    var exercises: [PlannedExercise]?

    // MARK: - Computed

    @Transient
    var type: WorkoutType {
        get { WorkoutType(rawValue: typeRaw) ?? .rest }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var status: WorkoutStatus {
        get { WorkoutStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    /// Exercises sorted by order.
    @Transient
    var orderedExercises: [PlannedExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }

    /// Total number of sets across all exercises.
    @Transient
    var totalSets: Int {
        (exercises ?? []).reduce(0) { $0 + ($1.sets?.count ?? 0) }
    }

    /// Total completed sets.
    @Transient
    var completedSets: Int {
        (exercises ?? []).reduce(0) { total, ex in
            total + (ex.sets ?? []).filter(\.completed).count
        }
    }

    /// Workout completion percentage (0.0-1.0).
    @Transient
    var completionPercentage: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    /// Total volume (weight x reps) for completed sets.
    @Transient
    var totalVolume: Double {
        (exercises ?? []).reduce(0) { total, ex in
            total + (ex.sets ?? []).reduce(0) { setTotal, set in
                guard set.completed,
                      let weight = set.actualWeight,
                      let reps = set.actualReps else { return setTotal }
                return setTotal + (weight * Double(reps))
            }
        }
    }

    /// Actual duration from start to finish.
    @Transient
    var actualDurationMinutes: Int? {
        guard let start = startedAt, let end = finishedAt else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        type: WorkoutType,
        recoveryAdjustment: Double = 1.0,
        status: WorkoutStatus = .planned,
        durationMinutes: Int? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.typeRaw = type.rawValue
        self.recoveryAdjustment = recoveryAdjustment
        self.statusRaw = status.rawValue
        self.durationMinutes = durationMinutes
        self.notes = notes
    }
}

// MARK: - DTO

extension WorkoutPlan {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let type: String
        let recovery_adjustment: Double
        let status: String
        let duration_minutes: Int?
        let notes: String?
        let started_at: Date?
        let finished_at: Date?
        let exercises: [PlannedExercise.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            type: typeRaw,
            recovery_adjustment: recoveryAdjustment,
            status: statusRaw,
            duration_minutes: durationMinutes,
            notes: notes,
            started_at: startedAt,
            finished_at: finishedAt,
            exercises: orderedExercises.map { $0.toDTO() }
        )
    }
}
```

### 5.3 PlannedExercise

```swift
import Foundation
import SwiftData

@Model
final class PlannedExercise {

    @Attribute(.unique)
    var id: UUID

    /// Position in the workout (0-based).
    var order: Int

    /// Superset group identifier. Exercises with the same group number are supersetted.
    /// Nil means standalone exercise.
    var supersetGroup: Int?

    // MARK: - Relationships

    /// The workout this exercise belongs to. Nullified if the workout is deleted
    /// (but cascade from WorkoutPlan side will delete this PlannedExercise first).
    @Relationship(deleteRule: .nullify)
    var workoutPlan: WorkoutPlan?

    /// The exercise definition. Nullified if the Exercise is deleted
    /// (but cascade from Exercise side will delete this PlannedExercise first).
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    /// Sets for this exercise instance.
    @Relationship(deleteRule: .cascade, inverse: \PlannedSet.plannedExercise)
    var sets: [PlannedSet]?

    // MARK: - Computed

    /// Sets sorted by set number.
    @Transient
    var orderedSets: [PlannedSet] {
        (sets ?? []).sorted { $0.setNumber < $1.setNumber }
    }

    /// Whether all sets are completed.
    @Transient
    var isComplete: Bool {
        guard let sets, !sets.isEmpty else { return false }
        return sets.allSatisfy(\.completed)
    }

    /// Best set by weight in this exercise instance.
    @Transient
    var bestSet: PlannedSet? {
        (sets ?? [])
            .filter { $0.completed && $0.actualWeight != nil }
            .max { ($0.actualWeight ?? 0) < ($1.actualWeight ?? 0) }
    }

    /// Total volume for this exercise.
    @Transient
    var totalVolume: Double {
        (sets ?? []).reduce(0) { total, set in
            guard set.completed,
                  let w = set.actualWeight,
                  let r = set.actualReps else { return total }
            return total + (w * Double(r))
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        order: Int,
        supersetGroup: Int? = nil,
        workoutPlan: WorkoutPlan? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.order = order
        self.supersetGroup = supersetGroup
        self.workoutPlan = workoutPlan
        self.exercise = exercise
    }
}

// MARK: - DTO

extension PlannedExercise {

    struct DTO: Codable {
        let id: UUID
        let order: Int
        let superset_group: Int?
        let exercise_id: UUID?
        let sets: [PlannedSet.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            order: order,
            superset_group: supersetGroup,
            exercise_id: exercise?.id,
            sets: orderedSets.map { $0.toDTO() }
        )
    }
}
```

### 5.4 PlannedSet

```swift
import Foundation
import SwiftData

@Model
final class PlannedSet {

    @Attribute(.unique)
    var id: UUID

    /// Set number within the exercise (1-based).
    var setNumber: Int

    // MARK: - Targets (prescribed by TrainingEngine)

    /// Target reps for this set.
    var targetReps: Int

    /// Target weight in kg. Nil for bodyweight exercises.
    var targetWeight: Double?

    // MARK: - Actuals (logged by user during workout)

    /// Actual reps completed. Nil until logged.
    var actualReps: Int?

    /// Actual weight used in kg. Nil until logged.
    var actualWeight: Double?

    /// Rate of Perceived Exertion (1-10). Optional user input.
    var rpe: Int?

    /// Whether this set has been completed.
    var completed: Bool

    /// Rest time in seconds after this set. Nil = use default.
    var restSeconds: Int?

    /// Timestamp when set was completed.
    var completedAt: Date?

    // MARK: - Relationships

    /// The planned exercise this set belongs to. Nullified on delete
    /// (cascade from PlannedExercise side will delete this set first).
    @Relationship(deleteRule: .nullify)
    var plannedExercise: PlannedExercise?

    // MARK: - Computed

    /// Volume for this set (weight x reps).
    @Transient
    var volume: Double? {
        guard completed, let w = actualWeight, let r = actualReps else { return nil }
        return w * Double(r)
    }

    /// Estimated 1RM using Epley formula.
    @Transient
    var estimated1RM: Double? {
        guard completed, let w = actualWeight, let r = actualReps, r > 0 else { return nil }
        if r == 1 { return w }
        return w * (1 + Double(r) / 30.0)
    }

    /// Whether actuals met or exceeded targets.
    @Transient
    var metTarget: Bool {
        guard completed, let ar = actualReps else { return false }
        let weightMet = targetWeight == nil || (actualWeight ?? 0) >= (targetWeight ?? 0)
        return ar >= targetReps && weightMet
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        setNumber: Int,
        targetReps: Int,
        targetWeight: Double? = nil,
        actualReps: Int? = nil,
        actualWeight: Double? = nil,
        rpe: Int? = nil,
        completed: Bool = false,
        restSeconds: Int? = nil,
        plannedExercise: PlannedExercise? = nil
    ) {
        self.id = id
        self.setNumber = setNumber
        self.targetReps = targetReps
        self.targetWeight = targetWeight
        self.actualReps = actualReps
        self.actualWeight = actualWeight
        self.rpe = rpe
        self.completed = completed
        self.restSeconds = restSeconds
        self.plannedExercise = plannedExercise
    }
}

// MARK: - DTO

extension PlannedSet {

    struct DTO: Codable {
        let id: UUID
        let set_number: Int
        let target_reps: Int
        let target_weight: Double?
        let actual_reps: Int?
        let actual_weight: Double?
        let rpe: Int?
        let completed: Bool
        let rest_seconds: Int?
        let completed_at: Date?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            set_number: setNumber,
            target_reps: targetReps,
            target_weight: targetWeight,
            actual_reps: actualReps,
            actual_weight: actualWeight,
            rpe: rpe,
            completed: completed,
            rest_seconds: restSeconds,
            completed_at: completedAt
        )
    }
}

// MARK: - Validation

extension PlannedSet {

    enum ValidationError: LocalizedError {
        case invalidReps
        case invalidWeight
        case invalidRPE
        case invalidRestSeconds

        var errorDescription: String? {
            switch self {
            case .invalidReps: "Reps must be between 1 and 100."
            case .invalidWeight: "Weight must be between 0 and 500 kg."
            case .invalidRPE: "RPE must be between 1 and 10."
            case .invalidRestSeconds: "Rest must be between 0 and 600 seconds."
            }
        }
    }

    func validate() throws {
        guard (1...100).contains(targetReps) else { throw ValidationError.invalidReps }
        if let w = targetWeight {
            guard (0...500).contains(w) else { throw ValidationError.invalidWeight }
        }
        if let ar = actualReps {
            guard (1...100).contains(ar) else { throw ValidationError.invalidReps }
        }
        if let aw = actualWeight {
            guard (0...500).contains(aw) else { throw ValidationError.invalidWeight }
        }
        if let r = rpe {
            guard (1...10).contains(r) else { throw ValidationError.invalidRPE }
        }
        if let rest = restSeconds {
            guard (0...600).contains(rest) else { throw ValidationError.invalidRestSeconds }
        }
    }
}
```

### 5.5 ExerciseHistory

One record per exercise per day. Aggregates session performance for trend tracking.

```swift
import Foundation
import SwiftData

@Model
final class ExerciseHistory {

    @Attribute(.unique)
    var id: UUID

    /// The date this record is for.
    var date: Date

    /// Estimated 1RM achieved during this session (Epley formula, best set).
    var estimated1RM: Double?

    /// Total volume (sum of weight x reps across all sets).
    var totalVolume: Double

    /// Best single-set weight used.
    var bestSetWeight: Double?

    /// Reps achieved at the best weight.
    var bestSetReps: Int?

    // MARK: - Relationships

    /// The exercise this history belongs to. Nullified on delete
    /// (cascade from Exercise side will delete this history record first).
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        estimated1RM: Double? = nil,
        totalVolume: Double = 0,
        bestSetWeight: Double? = nil,
        bestSetReps: Int? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.estimated1RM = estimated1RM
        self.totalVolume = totalVolume
        self.bestSetWeight = bestSetWeight
        self.bestSetReps = bestSetReps
        self.exercise = exercise
    }
}

// MARK: - DTO

extension ExerciseHistory {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let exercise_id: UUID?
        let estimated_1rm: Double?
        let total_volume: Double
        let best_set_weight: Double?
        let best_set_reps: Int?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            exercise_id: exercise?.id,
            estimated_1rm: estimated1RM,
            total_volume: totalVolume,
            best_set_weight: bestSetWeight,
            best_set_reps: bestSetReps
        )
    }
}
```

### 5.6 PersonalRecord

```swift
import Foundation
import SwiftData

@Model
final class PersonalRecord {

    @Attribute(.unique)
    var id: UUID

    /// PR type (1RM, rep_max, volume).
    var typeRaw: String

    /// The record value (kg for 1RM/rep_max, kg*reps for volume).
    var value: Double

    /// Date the PR was achieved.
    var date: Date

    /// The workout where this PR was set. Nil if imported.
    var workoutPlanID: UUID?

    /// Additional context (e.g., "8RM" for rep_max type).
    var context: String?

    // MARK: - Relationships

    /// The exercise this record belongs to. Nullified on delete
    /// (cascade from Exercise side will delete this PR first).
    @Relationship(deleteRule: .nullify)
    var exercise: Exercise?

    // MARK: - Computed

    @Transient
    var type: PRType {
        get { PRType(rawValue: typeRaw) ?? .oneRepMax }
        set { typeRaw = newValue.rawValue }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        type: PRType,
        value: Double,
        date: Date,
        workoutPlanID: UUID? = nil,
        context: String? = nil,
        exercise: Exercise? = nil
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.value = value
        self.date = date
        self.workoutPlanID = workoutPlanID
        self.context = context
        self.exercise = exercise
    }
}

// MARK: - DTO

extension PersonalRecord {

    struct DTO: Codable {
        let id: UUID
        let exercise_id: UUID?
        let type: String
        let value: Double
        let date: Date
        let workout_plan_id: UUID?
        let context: String?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            exercise_id: exercise?.id,
            type: typeRaw,
            value: value,
            date: date,
            workout_plan_id: workoutPlanID,
            context: context
        )
    }
}
```

### 5.7 RunSession

```swift
import Foundation
import SwiftData

@Model
final class RunSession {

    @Attribute(.unique)
    var id: UUID

    /// Date of the run.
    var date: Date

    /// Total distance in meters.
    var distanceMeters: Double

    /// Total duration in seconds.
    var durationSeconds: Int

    /// Average pace in seconds per kilometer.
    var avgPaceSecondsPerKm: Double?

    /// Per-km splits (JSON array of doubles: seconds per km).
    var splitsJSON: Data?

    /// Encoded polyline of the route. Nil if treadmill/no GPS.
    var routePolyline: String?

    /// Average heart rate during the run (bpm).
    var avgHR: Double?

    /// Maximum heart rate during the run (bpm).
    var maxHR: Double?

    /// Estimated calories burned.
    var calories: Double?

    /// Elevation gain in meters.
    var elevationGainMeters: Double?

    /// Cadence (steps per minute).
    var avgCadence: Double?

    // MARK: - Computed

    @Transient
    var distanceKm: Double {
        distanceMeters / 1000.0
    }

    @Transient
    var durationFormatted: String {
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    @Transient
    var splits: [Double] {
        get {
            guard let data = splitsJSON,
                  let decoded = try? JSONDecoder().decode([Double].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            splitsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    /// Average pace formatted as "M:SS /km".
    @Transient
    var avgPaceFormatted: String? {
        guard let pace = avgPaceSecondsPerKm else { return nil }
        let mins = Int(pace) / 60
        let secs = Int(pace) % 60
        return String(format: "%d:%02d /km", mins, secs)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        distanceMeters: Double,
        durationSeconds: Int,
        avgPaceSecondsPerKm: Double? = nil,
        splits: [Double] = [],
        routePolyline: String? = nil,
        avgHR: Double? = nil,
        maxHR: Double? = nil,
        calories: Double? = nil,
        elevationGainMeters: Double? = nil,
        avgCadence: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.avgPaceSecondsPerKm = avgPaceSecondsPerKm
        self.splitsJSON = try? JSONEncoder().encode(splits)
        self.routePolyline = routePolyline
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.calories = calories
        self.elevationGainMeters = elevationGainMeters
        self.avgCadence = avgCadence
    }
}

// MARK: - DTO

extension RunSession {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let distance_meters: Double
        let duration_seconds: Int
        let avg_pace_seconds_per_km: Double?
        let splits: [Double]
        let route_polyline: String?
        let avg_hr: Double?
        let max_hr: Double?
        let calories: Double?
        let elevation_gain_meters: Double?
        let avg_cadence: Double?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            distance_meters: distanceMeters,
            duration_seconds: durationSeconds,
            avg_pace_seconds_per_km: avgPaceSecondsPerKm,
            splits: splits,
            route_polyline: routePolyline,
            avg_hr: avgHR,
            max_hr: maxHR,
            calories: calories,
            elevation_gain_meters: elevationGainMeters,
            avg_cadence: avgCadence
        )
    }
}
```

---

## 6. Accountability Models

### 6.1 NonNegotiable

Template definition of a recurring non-negotiable task. Persists across days.

```swift
import Foundation
import SwiftData

@Model
final class NonNegotiable {

    @Attribute(.unique)
    var id: UUID

    /// Display name (e.g., "Study 2h", "Train", "Eat 3 Meals").
    var name: String

    /// Category type.
    var typeRaw: String

    /// SF Symbol name for the icon.
    var icon: String

    /// Target value (minutes for study, count for meals, etc.).
    var targetValue: Double

    /// How this non-negotiable is tracked.
    var trackingMethodRaw: String

    /// Which days this non-negotiable is active (bitmask).
    var activeDaysRaw: Int

    /// Display order in the list.
    var order: Int

    /// Whether this non-negotiable is currently active.
    var isActive: Bool

    /// Timestamp when created.
    var createdAt: Date

    // MARK: - Relationships

    /// All daily progress entries for this non-negotiable.
    @Relationship(deleteRule: .cascade, inverse: \NonNegotiableProgress.nonNegotiable)
    var progressEntries: [NonNegotiableProgress]?

    // MARK: - Computed

    @Transient
    var type: NonNegotiableType {
        get { NonNegotiableType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var trackingMethod: TrackingMethod {
        get { TrackingMethod(rawValue: trackingMethodRaw) ?? .manual }
        set { trackingMethodRaw = newValue.rawValue }
    }

    @Transient
    var activeDays: ActiveDays {
        get { ActiveDays(rawValue: activeDaysRaw) }
        set { activeDaysRaw = newValue.rawValue }
    }

    @Transient
    var isAutoTracked: Bool {
        trackingMethod != .manual
    }

    /// Integration source name for display badge.
    @Transient
    var integrationSourceName: String? {
        switch trackingMethod {
        case .autoWhoop: "WHOOP"
        case .autoNutritrack: "NUTRITRACK"
        case .autoHealthkit: "HEALTHKIT"
        case .timer: "TIMER"
        case .manual: nil
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        type: NonNegotiableType,
        icon: String? = nil,
        targetValue: Double,
        trackingMethod: TrackingMethod = .manual,
        activeDays: ActiveDays = .everyday,
        order: Int = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.typeRaw = type.rawValue
        self.icon = icon ?? type.defaultIcon
        self.targetValue = targetValue
        self.trackingMethodRaw = trackingMethod.rawValue
        self.activeDaysRaw = activeDays.rawValue
        self.order = order
        self.isActive = isActive
        self.createdAt = Date()
    }
}

// MARK: - DTO

extension NonNegotiable {

    struct DTO: Codable {
        let id: UUID
        let name: String
        let type: String
        let icon: String
        let target_value: Double
        let tracking_method: String
        let active_days: Int
        let order: Int
        let is_active: Bool
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            name: name,
            type: typeRaw,
            icon: icon,
            target_value: targetValue,
            tracking_method: trackingMethodRaw,
            active_days: activeDaysRaw,
            order: order,
            is_active: isActive,
            created_at: createdAt
        )
    }
}
```

### 6.2 DailyAccountability

One per day. Aggregates all non-negotiable progress for a single day.

```swift
import Foundation
import SwiftData

@Model
final class DailyAccountability {

    @Attribute(.unique)
    var id: UUID

    /// Calendar date (normalized to midnight).
    @Attribute(.unique)
    var date: Date

    /// Whether leisure (PS5) was unlocked today.
    var leisureUnlocked: Bool

    /// When leisure was unlocked. Nil if not yet unlocked.
    var unlockedAt: Date?

    /// Total study minutes today (sum of all study sessions).
    var totalStudyMinutes: Int

    /// Accountability score (0-100).
    var accountabilityScore: Int

    // MARK: - Relationships

    /// All non-negotiable progress entries for this day.
    @Relationship(deleteRule: .cascade, inverse: \NonNegotiableProgress.dailyAccountability)
    var nonNegotiableProgress: [NonNegotiableProgress]?

    /// All study sessions for this day.
    @Relationship(deleteRule: .cascade, inverse: \StudySession.dailyAccountability)
    var studySessions: [StudySession]?

    // MARK: - Computed

    /// Number of completed non-negotiables.
    @Transient
    var completedCount: Int {
        (nonNegotiableProgress ?? []).filter(\.isCompleted).count
    }

    /// Total non-negotiable count for today.
    @Transient
    var totalCount: Int {
        nonNegotiableProgress?.count ?? 0
    }

    /// Completion percentage (0.0-1.0).
    @Transient
    var completionPercentage: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    /// Whether all non-negotiables are complete.
    @Transient
    var allComplete: Bool {
        totalCount > 0 && completedCount == totalCount
    }

    /// Completed pomodoro sessions.
    @Transient
    var completedPomodoros: Int {
        (studySessions ?? []).reduce(0) { $0 + $1.completedPomodoros }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        leisureUnlocked: Bool = false,
        unlockedAt: Date? = nil,
        totalStudyMinutes: Int = 0,
        accountabilityScore: Int = 0
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.leisureUnlocked = leisureUnlocked
        self.unlockedAt = unlockedAt
        self.totalStudyMinutes = totalStudyMinutes
        self.accountabilityScore = accountabilityScore
    }
}

// MARK: - DTO

extension DailyAccountability {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let leisure_unlocked: Bool
        let unlocked_at: Date?
        let total_study_minutes: Int
        let accountability_score: Int
        let non_negotiable_progress: [NonNegotiableProgress.DTO]?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            leisure_unlocked: leisureUnlocked,
            unlocked_at: unlockedAt,
            total_study_minutes: totalStudyMinutes,
            accountability_score: accountabilityScore,
            non_negotiable_progress: nonNegotiableProgress?.map { $0.toDTO() }
        )
    }
}
```

### 6.3 NonNegotiableProgress

Daily progress for a single non-negotiable. Junction between DailyAccountability and NonNegotiable.

```swift
import Foundation
import SwiftData

@Model
final class NonNegotiableProgress {

    @Attribute(.unique)
    var id: UUID

    /// Date for this progress entry.
    var date: Date

    /// Current value (minutes studied, meals logged, etc.).
    var currentValue: Double

    /// Target value (copied from NonNegotiable at day start, may differ if adjusted).
    var targetValue: Double

    /// Whether this non-negotiable is completed.
    var isCompleted: Bool

    /// Timestamp when completed. Nil if not completed.
    var completedAt: Date?

    /// Source data for auto-tracked items (JSON). Contains API response excerpts.
    /// Example: {"whoop_workout_id": "abc123", "duration_minutes": 45}
    var sourceDataJSON: Data?

    // MARK: - Relationships

    /// The non-negotiable template this progress tracks.
    /// Nullified if the NonNegotiable is deleted (cascade from parent deletes this first).
    @Relationship(deleteRule: .nullify)
    var nonNegotiable: NonNegotiable?

    /// The daily accountability record this belongs to.
    /// Nullified if the DailyAccountability is deleted (cascade from parent deletes this first).
    @Relationship(deleteRule: .nullify)
    var dailyAccountability: DailyAccountability?

    // MARK: - Computed

    /// Progress as a percentage (0.0-1.0).
    @Transient
    var progressPercentage: Double {
        guard targetValue > 0 else { return 0 }
        return min(currentValue / targetValue, 1.0)
    }

    @Transient
    var sourceData: [String: Any]? {
        guard let data = sourceDataJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        currentValue: Double = 0,
        targetValue: Double,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        sourceDataJSON: Data? = nil,
        nonNegotiable: NonNegotiable? = nil,
        dailyAccountability: DailyAccountability? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.currentValue = currentValue
        self.targetValue = targetValue
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.sourceDataJSON = sourceDataJSON
        self.nonNegotiable = nonNegotiable
        self.dailyAccountability = dailyAccountability
    }
}

// MARK: - DTO

extension NonNegotiableProgress {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let non_negotiable_id: UUID?
        let current_value: Double
        let target_value: Double
        let is_completed: Bool
        let completed_at: Date?
        let source_data: String? // JSON string
    }

    func toDTO() -> DTO {
        let sourceString: String? = sourceDataJSON.flatMap { String(data: $0, encoding: .utf8) }
        return DTO(
            id: id,
            date: date,
            non_negotiable_id: nonNegotiable?.id,
            current_value: currentValue,
            target_value: targetValue,
            is_completed: isCompleted,
            completed_at: completedAt,
            source_data: sourceString
        )
    }
}
```

### 6.4 StudySession

```swift
import Foundation
import SwiftData

@Model
final class StudySession {

    @Attribute(.unique)
    var id: UUID

    /// When the session started.
    var startTime: Date

    /// When the session ended. Nil if in progress.
    var endTime: Date?

    /// Total duration in minutes. Calculated from start/end or timer.
    var durationMinutes: Int

    /// Subject or topic being studied (free text).
    var subject: String?

    /// Session type.
    var sessionTypeRaw: String

    /// Focus score (0-100). Self-rated or derived from distraction count.
    var focusScore: Int?

    /// Number of times the user was distracted (left timer screen, etc.).
    var distractions: Int

    /// Number of completed pomodoro cycles in this session.
    var completedPomodoros: Int

    // MARK: - Relationships

    /// The daily accountability record this session belongs to.
    /// Nullified if the DailyAccountability is deleted (cascade from parent deletes this first).
    @Relationship(deleteRule: .nullify)
    var dailyAccountability: DailyAccountability?

    // MARK: - Computed

    @Transient
    var sessionType: StudySessionType {
        get { StudySessionType(rawValue: sessionTypeRaw) ?? .pomodoro }
        set { sessionTypeRaw = newValue.rawValue }
    }

    @Transient
    var isInProgress: Bool {
        endTime == nil
    }

    /// Duration formatted as "Xh Ym".
    @Transient
    var durationFormatted: String {
        let hours = durationMinutes / 60
        let mins = durationMinutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }

    /// Computed focus score from distraction count if not self-rated.
    @Transient
    var effectiveFocusScore: Int {
        if let fs = focusScore { return fs }
        // Heuristic: start at 100, lose 10 per distraction, floor at 0
        return max(0, 100 - (distractions * 10))
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        durationMinutes: Int = 0,
        subject: String? = nil,
        sessionType: StudySessionType = .pomodoro,
        focusScore: Int? = nil,
        distractions: Int = 0,
        completedPomodoros: Int = 0,
        dailyAccountability: DailyAccountability? = nil
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.durationMinutes = durationMinutes
        self.subject = subject
        self.sessionTypeRaw = sessionType.rawValue
        self.focusScore = focusScore
        self.distractions = distractions
        self.completedPomodoros = completedPomodoros
        self.dailyAccountability = dailyAccountability
    }
}

// MARK: - DTO

extension StudySession {

    struct DTO: Codable {
        let id: UUID
        let start_time: Date
        let end_time: Date?
        let duration_minutes: Int
        let subject: String?
        let session_type: String
        let focus_score: Int?
        let distractions: Int
        let completed_pomodoros: Int
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            start_time: startTime,
            end_time: endTime,
            duration_minutes: durationMinutes,
            subject: subject,
            session_type: sessionTypeRaw,
            focus_score: focusScore,
            distractions: distractions,
            completed_pomodoros: completedPomodoros
        )
    }
}
```

### 6.5 Streak

```swift
import Foundation
import SwiftData

@Model
final class Streak {

    @Attribute(.unique)
    var id: UUID

    /// Streak category.
    var typeRaw: String

    /// Current consecutive day count.
    var currentCount: Int

    /// All-time longest streak.
    var longestCount: Int

    /// Date of last completed day (to detect breaks).
    var lastCompletedDate: Date?

    /// Number of streak freezes used.
    var freezesUsed: Int

    /// Number of streak freezes available.
    var freezesAvailable: Int

    // MARK: - Computed

    @Transient
    var type: StreakType {
        get { StreakType(rawValue: typeRaw) ?? .overall }
        set { typeRaw = newValue.rawValue }
    }

    /// Whether the streak is currently active (last completed was yesterday or today).
    @Transient
    var isActive: Bool {
        guard let lastDate = lastCompletedDate else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastDay = calendar.startOfDay(for: lastDate)
        return lastDay >= yesterday
    }

    /// Whether a freeze is available to protect the streak.
    @Transient
    var canFreeze: Bool {
        freezesAvailable > freezesUsed
    }

    // MARK: - Methods

    /// Increments the streak for today.
    func recordCompletion(for date: Date = Date()) {
        let today = Calendar.current.startOfDay(for: date)

        guard lastCompletedDate != today else { return } // already recorded

        if isActive {
            currentCount += 1
        } else {
            currentCount = 1
        }

        if currentCount > longestCount {
            longestCount = currentCount
        }

        lastCompletedDate = today
    }

    /// Breaks the streak (resets to 0).
    func breakStreak() {
        currentCount = 0
    }

    /// Uses a freeze to protect the streak for one day.
    func useFreeze() -> Bool {
        guard canFreeze else { return false }
        freezesUsed += 1
        lastCompletedDate = Calendar.current.startOfDay(for: Date())
        return true
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        type: StreakType,
        currentCount: Int = 0,
        longestCount: Int = 0,
        lastCompletedDate: Date? = nil,
        freezesUsed: Int = 0,
        freezesAvailable: Int = 2
    ) {
        self.id = id
        self.typeRaw = type.rawValue
        self.currentCount = currentCount
        self.longestCount = longestCount
        self.lastCompletedDate = lastCompletedDate
        self.freezesUsed = freezesUsed
        self.freezesAvailable = freezesAvailable
    }
}

// MARK: - DTO

extension Streak {

    struct DTO: Codable {
        let id: UUID
        let type: String
        let current_count: Int
        let longest_count: Int
        let last_completed_date: Date?
        let freezes_used: Int
        let freezes_available: Int
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            type: typeRaw,
            current_count: currentCount,
            longest_count: longestCount,
            last_completed_date: lastCompletedDate,
            freezes_used: freezesUsed,
            freezes_available: freezesAvailable
        )
    }
}
```

---

## 7. Recovery Models

### 7.1 DailyRecovery

Comprehensive daily recovery data, primarily sourced from Whoop.

```swift
import Foundation
import SwiftData

// PERFORMANCE NOTE: DailyRecovery has ~28 stored properties. Same consideration as
// DailySnapshot — acceptable for a model with ~365 rows/year, but monitor fetch times.
// If sleep detail data is rarely accessed, consider extracting sleep stage fields
// (deepSleepMin, remSleepMin, lightSleepMin, awakeMin) into a separate SleepDetail model.
@Model
final class DailyRecovery {

    @Attribute(.unique)
    var id: UUID

    /// Calendar date (normalized to midnight).
    @Attribute(.unique)
    var date: Date

    // MARK: - Recovery

    /// Overall recovery score (0-100).
    var recoveryScore: Double

    /// Recovery zone derived from score.
    var recoveryZoneRaw: String

    // MARK: - HRV & Heart Rate

    /// HRV RMSSD in milliseconds.
    var hrvRmssd: Double?

    /// Resting heart rate in bpm.
    var restingHR: Double?

    /// Blood oxygen saturation percentage.
    var spo2: Double?

    /// Skin temperature deviation in Celsius.
    var skinTemp: Double?

    // MARK: - Sleep

    /// Total sleep hours.
    var sleepHours: Double?

    /// Sleep performance score (0-100).
    var sleepScore: Double?

    /// Sleep efficiency percentage (time asleep / time in bed).
    var sleepEfficiency: Double?

    /// Sleep consistency score (0-100).
    var sleepConsistency: Double?

    /// Deep (slow wave) sleep minutes.
    var deepSleepMin: Int?

    /// REM sleep minutes.
    var remSleepMin: Int?

    /// Light sleep minutes.
    var lightSleepMin: Int?

    /// Awake minutes during sleep period.
    var awakeMin: Int?

    /// Baseline sleep needed in hours (Whoop).
    var sleepNeededBaseline: Double?

    /// Sleep debt in hours (positive = debt, negative = surplus).
    var sleepDebt: Double?

    // MARK: - Respiratory

    /// Respiratory rate in breaths per minute.
    var respiratoryRate: Double?

    // MARK: - Strain & Activity

    /// Day strain (Whoop 0-21 scale).
    var strain: Double?

    /// Average heart rate throughout the day.
    var avgHR: Double?

    /// Maximum heart rate during the day.
    var maxHR: Double?

    /// Total calories burned (BMR + active).
    var caloriesBurned: Double?

    // MARK: - Relationships

    /// The prescription generated from this recovery data.
    @Relationship(deleteRule: .cascade, inverse: \DailyPrescription.dailyRecovery)
    var prescription: DailyPrescription?

    // MARK: - Computed

    @Transient
    var recoveryZone: RecoveryZone {
        get { RecoveryZone(rawValue: recoveryZoneRaw) ?? RecoveryZone(score: recoveryScore) }
        set { recoveryZoneRaw = newValue.rawValue }
    }

    /// Total sleep stage minutes.
    @Transient
    var totalSleepStageMinutes: Int {
        (deepSleepMin ?? 0) + (remSleepMin ?? 0) + (lightSleepMin ?? 0)
    }

    /// Deep sleep percentage of total sleep.
    @Transient
    var deepSleepPercentage: Double? {
        guard let deep = deepSleepMin, totalSleepStageMinutes > 0 else { return nil }
        return Double(deep) / Double(totalSleepStageMinutes) * 100
    }

    /// REM sleep percentage of total sleep.
    @Transient
    var remSleepPercentage: Double? {
        guard let rem = remSleepMin, totalSleepStageMinutes > 0 else { return nil }
        return Double(rem) / Double(totalSleepStageMinutes) * 100
    }

    /// Whether sleep debt is critical (>= 4 hours).
    @Transient
    var isSleepDebtCritical: Bool {
        (sleepDebt ?? 0) >= 4.0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        recoveryScore: Double,
        hrvRmssd: Double? = nil,
        restingHR: Double? = nil,
        spo2: Double? = nil,
        skinTemp: Double? = nil,
        sleepHours: Double? = nil,
        sleepScore: Double? = nil,
        sleepEfficiency: Double? = nil,
        sleepConsistency: Double? = nil,
        deepSleepMin: Int? = nil,
        remSleepMin: Int? = nil,
        lightSleepMin: Int? = nil,
        awakeMin: Int? = nil,
        sleepNeededBaseline: Double? = nil,
        sleepDebt: Double? = nil,
        respiratoryRate: Double? = nil,
        strain: Double? = nil,
        avgHR: Double? = nil,
        maxHR: Double? = nil,
        caloriesBurned: Double? = nil
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.recoveryScore = recoveryScore
        self.recoveryZoneRaw = RecoveryZone(score: recoveryScore).rawValue
        self.hrvRmssd = hrvRmssd
        self.restingHR = restingHR
        self.spo2 = spo2
        self.skinTemp = skinTemp
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.sleepEfficiency = sleepEfficiency
        self.sleepConsistency = sleepConsistency
        self.deepSleepMin = deepSleepMin
        self.remSleepMin = remSleepMin
        self.lightSleepMin = lightSleepMin
        self.awakeMin = awakeMin
        self.sleepNeededBaseline = sleepNeededBaseline
        self.sleepDebt = sleepDebt
        self.respiratoryRate = respiratoryRate
        self.strain = strain
        self.avgHR = avgHR
        self.maxHR = maxHR
        self.caloriesBurned = caloriesBurned
    }
}

// MARK: - DTO

extension DailyRecovery {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let recovery_score: Double
        let recovery_zone: String
        let hrv_rmssd: Double?
        let resting_hr: Double?
        let spo2: Double?
        let skin_temp: Double?
        let sleep_hours: Double?
        let sleep_score: Double?
        let sleep_efficiency: Double?
        let sleep_consistency: Double?
        let deep_sleep_min: Int?
        let rem_sleep_min: Int?
        let light_sleep_min: Int?
        let awake_min: Int?
        let sleep_needed_baseline: Double?
        let sleep_debt: Double?
        let respiratory_rate: Double?
        let strain: Double?
        let avg_hr: Double?
        let max_hr: Double?
        let calories_burned: Double?
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            recovery_score: recoveryScore,
            recovery_zone: recoveryZoneRaw,
            hrv_rmssd: hrvRmssd,
            resting_hr: restingHR,
            spo2: spo2,
            skin_temp: skinTemp,
            sleep_hours: sleepHours,
            sleep_score: sleepScore,
            sleep_efficiency: sleepEfficiency,
            sleep_consistency: sleepConsistency,
            deep_sleep_min: deepSleepMin,
            rem_sleep_min: remSleepMin,
            light_sleep_min: lightSleepMin,
            awake_min: awakeMin,
            sleep_needed_baseline: sleepNeededBaseline,
            sleep_debt: sleepDebt,
            respiratory_rate: respiratoryRate,
            strain: strain,
            avg_hr: avgHR,
            max_hr: maxHR,
            calories_burned: caloriesBurned
        )
    }
}
```

### 7.2 DailyPrescription

```swift
import Foundation
import SwiftData

@Model
final class DailyPrescription {

    @Attribute(.unique)
    var id: UUID

    /// Calendar date.
    var date: Date

    /// Training recommendation headline.
    var trainingRec: String

    /// Detailed training recommendation.
    var trainingDetail: String?

    /// Nutrition recommendations (JSON array of strings).
    var nutritionRecsJSON: Data?

    /// Recommended bedtime (full Date, time portion is what matters).
    var bedtimeTarget: Date?

    /// Caffeine cutoff time (full Date, time portion is what matters).
    var caffeineCutoff: Date?

    /// Hydration target in milliliters.
    var hydrationTargetMl: Int?

    /// Warning messages (JSON array of strings).
    var warningsJSON: Data?

    /// Whether the user followed the prescription. Nil = not yet rated.
    var wasFollowed: Bool?

    // MARK: - Relationships

    /// The recovery data that generated this prescription.
    /// Nullified if the DailyRecovery is deleted (cascade from parent deletes this first).
    @Relationship(deleteRule: .nullify)
    var dailyRecovery: DailyRecovery?

    // MARK: - Computed

    @Transient
    var nutritionRecs: [String] {
        get {
            guard let data = nutritionRecsJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
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
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
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

    /// Caffeine cutoff formatted as "HH:mm".
    @Transient
    var caffeineCutoffFormatted: String? {
        guard let cutoff = caffeineCutoff else { return nil }
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
        self.nutritionRecsJSON = try? JSONEncoder().encode(nutritionRecs)
        self.bedtimeTarget = bedtimeTarget
        self.caffeineCutoff = caffeineCutoff
        self.hydrationTargetMl = hydrationTargetMl
        self.warningsJSON = try? JSONEncoder().encode(warnings)
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
```

### 7.3 RecoveryInsight

AI-generated or algorithm-detected insights.

```swift
import Foundation
import SwiftData

@Model
final class RecoveryInsight {

    @Attribute(.unique)
    var id: UUID

    /// Date this insight was generated.
    var date: Date

    /// Insight category.
    var typeRaw: String

    /// Short headline (e.g., "HRV Dropping 3 Days Straight").
    var title: String

    /// Detailed explanation.
    var body: String

    /// Supporting data points (JSON). Structure varies by insight type.
    /// Example: [{"date": "2026-03-22", "hrv": 45}, {"date": "2026-03-23", "hrv": 38}]
    var dataPointsJSON: Data?

    /// Confidence level (0.0-1.0). How confident the algorithm is in this insight.
    var confidence: Double

    /// Whether the user dismissed this insight.
    var wasDismissed: Bool

    /// Timestamp when dismissed. Nil if not dismissed.
    var dismissedAt: Date?

    // MARK: - Computed

    @Transient
    var type: RecoveryInsightType {
        get { RecoveryInsightType(rawValue: typeRaw) ?? .recommendation }
        set { typeRaw = newValue.rawValue }
    }

    @Transient
    var dataPoints: [[String: Any]]? {
        guard let data = dataPointsJSON else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    /// Whether this insight is high-confidence (>= 0.7).
    @Transient
    var isHighConfidence: Bool {
        confidence >= 0.7
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        type: RecoveryInsightType,
        title: String,
        body: String,
        dataPointsJSON: Data? = nil,
        confidence: Double,
        wasDismissed: Bool = false
    ) {
        self.id = id
        self.date = date
        self.typeRaw = type.rawValue
        self.title = title
        self.body = body
        self.dataPointsJSON = dataPointsJSON
        self.confidence = confidence
        self.wasDismissed = wasDismissed
    }
}

// MARK: - DTO

extension RecoveryInsight {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let type: String
        let title: String
        let body: String
        let data_points: String? // JSON string
        let confidence: Double
        let was_dismissed: Bool
    }

    func toDTO() -> DTO {
        let dpString: String? = dataPointsJSON.flatMap { String(data: $0, encoding: .utf8) }
        return DTO(
            id: id,
            date: date,
            type: typeRaw,
            title: title,
            body: body,
            data_points: dpString,
            confidence: confidence,
            was_dismissed: wasDismissed
        )
    }
}
```

---

## 8. Arena Models

### 8.1 XPEvent

```swift
import Foundation
import SwiftData

@Model
final class XPEvent {

    @Attribute(.unique)
    var id: UUID

    /// Date the XP was earned (normalized to day).
    var date: Date

    /// Source of the XP event.
    var sourceRaw: String

    /// XP amount (positive for earnings, negative for penalties).
    var amount: Int

    /// Human-readable description (e.g., "Completed Push Day workout").
    var eventDescription: String

    /// Timestamp of when this event was created.
    var createdAt: Date

    // MARK: - Computed

    @Transient
    var source: XPSource {
        get { XPSource(rawValue: sourceRaw) ?? .workout }
        set { sourceRaw = newValue.rawValue }
    }

    @Transient
    var isPenalty: Bool {
        amount < 0
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date,
        source: XPSource,
        amount: Int,
        description: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.sourceRaw = source.rawValue
        self.amount = amount
        self.eventDescription = description
        self.createdAt = createdAt
    }
}

// MARK: - DTO

extension XPEvent {

    struct DTO: Codable {
        let id: UUID
        let date: Date
        let source: String
        let amount: Int
        let description: String
        let created_at: Date
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            date: date,
            source: sourceRaw,
            amount: amount,
            description: eventDescription,
            created_at: createdAt
        )
    }
}
```

### 8.2 Achievement

```swift
import Foundation
import SwiftData

@Model
final class Achievement {

    @Attribute(.unique)
    var id: UUID

    /// Unique badge identifier (e.g., "first_workout", "7_day_streak").
    @Attribute(.unique)
    var badgeID: String

    /// Display name.
    var name: String

    /// Badge description / how to earn it.
    var achievementDescription: String

    /// Category for grouping in the UI.
    var categoryRaw: String

    /// Rarity tier.
    var rarityRaw: String

    /// XP reward for earning this achievement.
    var xpReward: Int

    /// When the achievement was earned. Nil if not yet earned.
    var earnedAt: Date?

    /// Whether this achievement is hidden until earned.
    var isHidden: Bool

    // MARK: - Computed

    @Transient
    var category: AchievementCategory {
        get { AchievementCategory(rawValue: categoryRaw) ?? .milestone }
        set { categoryRaw = newValue.rawValue }
    }

    @Transient
    var rarity: AchievementRarity {
        get { AchievementRarity(rawValue: rarityRaw) ?? .common }
        set { rarityRaw = newValue.rawValue }
    }

    @Transient
    var isEarned: Bool {
        earnedAt != nil
    }

    /// Effective XP reward (base * rarity multiplier).
    @Transient
    var effectiveXPReward: Int {
        Int(Double(xpReward) * rarity.xpMultiplier)
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        badgeID: String,
        name: String,
        description: String,
        category: AchievementCategory,
        rarity: AchievementRarity,
        xpReward: Int,
        earnedAt: Date? = nil,
        isHidden: Bool = false
    ) {
        self.id = id
        self.badgeID = badgeID
        self.name = name
        self.achievementDescription = description
        self.categoryRaw = category.rawValue
        self.rarityRaw = rarity.rawValue
        self.xpReward = xpReward
        self.earnedAt = earnedAt
        self.isHidden = isHidden
    }
}

// MARK: - DTO

extension Achievement {

    struct DTO: Codable {
        let id: UUID
        let badge_id: String
        let name: String
        let description: String
        let category: String
        let rarity: String
        let xp_reward: Int
        let earned_at: Date?
        let is_hidden: Bool
    }

    func toDTO() -> DTO {
        DTO(
            id: id,
            badge_id: badgeID,
            name: name,
            description: achievementDescription,
            category: categoryRaw,
            rarity: rarityRaw,
            xp_reward: xpReward,
            earned_at: earnedAt,
            is_hidden: isHidden
        )
    }
}
```

### 8.3 ChallengeLocal

Local mirror of server-side challenges the user is participating in.

```swift
import Foundation
import SwiftData

@Model
final class ChallengeLocal {

    @Attribute(.unique)
    var id: UUID

    /// Server-side challenge ID.
    var serverID: UUID?

    /// Challenge name.
    var name: String

    /// Metric being tracked (e.g., "study_minutes", "xp", "workouts").
    var metric: String

    /// Challenge start date.
    var startDate: Date

    /// Challenge end date.
    var endDate: Date

    /// User's current score in this challenge.
    var myScore: Double

    /// Whether the challenge is currently active.
    var isActive: Bool

    /// Challenge description.
    var challengeDescription: String?

    /// Number of participants (cached from server).
    var participantCount: Int?

    /// User's current rank (cached from server).
    var myRank: Int?

    // MARK: - Computed

    /// Days remaining in the challenge.
    @Transient
    var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
    }

    /// Whether the challenge has ended.
    @Transient
    var hasEnded: Bool {
        Date() > endDate
    }

    /// Whether the challenge has started.
    @Transient
    var hasStarted: Bool {
        Date() >= startDate
    }

    /// Total duration in days.
    @Transient
    var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
    }

    /// Progress through the challenge timeline (0.0-1.0).
    @Transient
    var timelineProgress: Double {
        guard hasStarted else { return 0 }
        guard !hasEnded else { return 1 }
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
```

---

## 9. Sync Models

### 9.1 SyncState

Tracks the last sync state per entity type. One record per entity type.

```swift
import Foundation
import SwiftData

@Model
final class SyncState {

    @Attribute(.unique)
    var id: UUID

    /// Entity type name (e.g., "DailySnapshot", "WorkoutPlan").
    @Attribute(.unique)
    var entityType: String

    /// Last successful sync timestamp.
    var lastSyncedAt: Date?

    /// Server version token for delta sync.
    var lastServerVersion: String?

    /// Number of local changes pending sync.
    var pendingChangesCount: Int

    // MARK: - Computed

    /// Whether there are pending changes to push.
    @Transient
    var hasPendingChanges: Bool {
        pendingChangesCount > 0
    }

    /// How long since last sync.
    @Transient
    var timeSinceLastSync: TimeInterval? {
        lastSyncedAt.map { Date().timeIntervalSince($0) }
    }

    /// Whether data is stale (>15 minutes since last sync).
    @Transient
    var isStale: Bool {
        guard let interval = timeSinceLastSync else { return true }
        return interval > 900 // 15 minutes
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        entityType: String,
        lastSyncedAt: Date? = nil,
        lastServerVersion: String? = nil,
        pendingChangesCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.lastSyncedAt = lastSyncedAt
        self.lastServerVersion = lastServerVersion
        self.pendingChangesCount = pendingChangesCount
    }
}
```

### 9.2 PendingSync

Queue of changes waiting to be pushed to the server.

```swift
import Foundation
import SwiftData

@Model
final class PendingSync {

    @Attribute(.unique)
    var id: UUID

    /// Entity type name (e.g., "WorkoutPlan").
    var entityType: String

    /// ID of the entity being synced.
    var entityID: UUID

    /// The sync action.
    var actionRaw: String

    /// Serialized payload (JSON data of the entity DTO).
    var payload: Data?

    /// When this pending sync was created.
    var createdAt: Date

    /// Number of sync attempts so far.
    var retryCount: Int

    /// Last error message if sync failed.
    var lastError: String?

    /// Next retry time (exponential backoff).
    var nextRetryAt: Date?

    // MARK: - Computed

    @Transient
    var action: SyncAction {
        get { SyncAction(rawValue: actionRaw) ?? .update }
        set { actionRaw = newValue.rawValue }
    }

    /// Whether this item should be retried now.
    @Transient
    var isReadyForRetry: Bool {
        guard let nextRetry = nextRetryAt else { return true }
        return Date() >= nextRetry
    }

    /// Whether this item has exceeded max retries (5).
    @Transient
    var isExhausted: Bool {
        retryCount >= 5
    }

    // MARK: - Methods

    /// Records a failed attempt and schedules next retry with exponential backoff.
    func recordFailure(error: String) {
        retryCount += 1
        lastError = error
        // Exponential backoff: 30s, 2m, 8m, 32m, 2h
        let delay = TimeInterval(30 * pow(4.0, Double(retryCount - 1)))
        nextRetryAt = Date().addingTimeInterval(min(delay, 7200))
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        entityType: String,
        entityID: UUID,
        action: SyncAction,
        payload: Data? = nil,
        createdAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.actionRaw = action.rawValue
        self.payload = payload
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
```

---

## 10. Integration State Models

### 10.1 WhoopConnection

```swift
import Foundation
import SwiftData

@Model
final class WhoopConnection {

    @Attribute(.unique)
    var id: UUID

    /// Whether Whoop is currently connected.
    var isConnected: Bool

    /// Last successful data sync from Whoop.
    var lastSyncAt: Date?

    /// When the current OAuth token expires.
    var tokenExpiresAt: Date?

    /// Whoop user ID (from their API).
    var whoopUserID: String?

    /// Connection status message for display.
    var statusMessage: String?

    // MARK: - Computed

    /// Whether the token has expired or is about to (within 5 minutes).
    @Transient
    var isTokenExpired: Bool {
        guard let expires = tokenExpiresAt else { return true }
        return Date().addingTimeInterval(300) >= expires
    }

    /// Time since last sync, formatted.
    @Transient
    var lastSyncFormatted: String? {
        guard let lastSync = lastSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        isConnected: Bool = false,
        lastSyncAt: Date? = nil,
        tokenExpiresAt: Date? = nil,
        whoopUserID: String? = nil,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.isConnected = isConnected
        self.lastSyncAt = lastSyncAt
        self.tokenExpiresAt = tokenExpiresAt
        self.whoopUserID = whoopUserID
        self.statusMessage = statusMessage
    }
}
```

### 10.2 NutriTrackConnection

```swift
import Foundation
import SwiftData

@Model
final class NutriTrackConnection {

    @Attribute(.unique)
    var id: UUID

    /// Whether NutriTrack is currently connected.
    var isConnected: Bool

    /// Base URL of the NutriTrack server.
    var serverURL: String?

    /// Last successful data sync from NutriTrack.
    var lastSyncAt: Date?

    /// Connection status message for display.
    var statusMessage: String?

    // MARK: - Computed

    @Transient
    var lastSyncFormatted: String? {
        guard let lastSync = lastSyncAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: lastSync, relativeTo: Date())
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        isConnected: Bool = false,
        serverURL: String? = nil,
        lastSyncAt: Date? = nil,
        statusMessage: String? = nil
    ) {
        self.id = id
        self.isConnected = isConnected
        self.serverURL = serverURL
        self.lastSyncAt = lastSyncAt
        self.statusMessage = statusMessage
    }
}
```

### 10.3 HealthKitState

```swift
import Foundation
import SwiftData

@Model
final class HealthKitState {

    @Attribute(.unique)
    var id: UUID

    /// JSON array of authorized read type identifiers.
    var authorizedReadTypesJSON: Data?

    /// JSON array of authorized write type identifiers.
    var authorizedWriteTypesJSON: Data?

    /// Last time background delivery processed new data.
    var lastBackgroundDelivery: Date?

    /// Whether HealthKit authorization has been requested.
    var authorizationRequested: Bool

    // MARK: - Computed

    @Transient
    var authorizedReadTypes: [String] {
        get {
            guard let data = authorizedReadTypesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            authorizedReadTypesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    @Transient
    var authorizedWriteTypes: [String] {
        get {
            guard let data = authorizedWriteTypesJSON,
                  let decoded = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return decoded
        }
        set {
            authorizedWriteTypesJSON = try? JSONEncoder().encode(newValue)
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        authorizedReadTypes: [String] = [],
        authorizedWriteTypes: [String] = [],
        lastBackgroundDelivery: Date? = nil,
        authorizationRequested: Bool = false
    ) {
        self.id = id
        self.authorizedReadTypesJSON = try? JSONEncoder().encode(authorizedReadTypes)
        self.authorizedWriteTypesJSON = try? JSONEncoder().encode(authorizedWriteTypes)
        self.lastBackgroundDelivery = lastBackgroundDelivery
        self.authorizationRequested = authorizationRequested
    }
}
```

---

## 11. Query Patterns Per Screen

### IMPORTANT: `#Predicate` and `@Query` in iOS 17

> **SwiftData `@Query` with `#Predicate` cannot capture local variables** in iOS 17.
> The predicate expression is evaluated at compile time when used with `@Query`.
> You CANNOT do this:
> ```swift
> let today = Calendar.current.startOfDay(for: Date())
> @Query(filter: #Predicate<DailySnapshot> { $0.date == today }) // COMPILER ERROR
> var snapshots: [DailySnapshot]
> ```
>
> **Correct patterns:**
> 1. **`FetchDescriptor` with runtime predicate** (preferred for dynamic dates) -- the predicate
>    is evaluated eagerly when constructing the descriptor, so local variable capture works.
> 2. **`@Query` with a static predicate** (only for non-date filters like `isActive == true`).
> 3. **Fetch all and filter in-memory** (acceptable for small result sets).

### 11.1 Dashboard (DashboardView)

```swift
// Today's snapshot -- use FetchDescriptor (date is dynamic)
func fetchTodaySnapshot(context: ModelContext) throws -> DailySnapshot? {
    let today = Calendar.current.startOfDay(for: Date())
    var descriptor = FetchDescriptor<DailySnapshot>(
        predicate: #Predicate { $0.date == today },
        sortBy: [SortDescriptor(\.date)]
    )
    descriptor.fetchLimit = 1
    return try context.fetch(descriptor).first
}

// Last 7 days for sparklines
func fetchWeekSnapshots(context: ModelContext) throws -> [DailySnapshot] {
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    let descriptor = FetchDescriptor<DailySnapshot>(
        predicate: #Predicate { $0.date >= sevenDaysAgo },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
}
```

### 11.2 Today's Workout (TodayWorkoutView)

```swift
// Today's workout plan -- FetchDescriptor with prefetching
func fetchTodayWorkout(context: ModelContext) throws -> WorkoutPlan? {
    let today = Calendar.current.startOfDay(for: Date())
    var descriptor = FetchDescriptor<WorkoutPlan>(
        predicate: #Predicate { $0.date == today }
    )
    descriptor.fetchLimit = 1
    descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
    return try context.fetch(descriptor).first
}
// Access .orderedExercises on the result to get exercises + sets.
```

### 11.3 Week Plan (WeekPlanView)

```swift
// This week's workout plans (Monday-Sunday)
func fetchWeekPlans(context: ModelContext) throws -> [WorkoutPlan] {
    let calendar = Calendar.current
    let startOfWeek = calendar.date(from: calendar.dateComponents(
        [.yearForWeekOfYear, .weekOfYear], from: Date()))!
    let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
    let descriptor = FetchDescriptor<WorkoutPlan>(
        predicate: #Predicate { $0.date >= startOfWeek && $0.date < endOfWeek },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
}
```

### 11.4 Exercise Progress (ProgressChartsView)

```swift
// History for a specific exercise (last 90 days)
// SwiftData does not support predicate across relationships in iOS 17.
// Strategy: fetch by date range, then filter in-memory by exercise ID.
func fetchExerciseHistory(
    exerciseID: UUID,
    context: ModelContext
) throws -> [ExerciseHistory] {
    let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    let descriptor = FetchDescriptor<ExerciseHistory>(
        predicate: #Predicate { $0.date >= ninetyDaysAgo },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
        .filter { $0.exercise?.id == exerciseID }
}
```

### 11.5 Exercise Library (ExerciseLibraryView)

```swift
// All exercises, sorted by name. @Query is fine -- no dynamic predicate.
@Query(sort: \Exercise.name)
var allExercises: [Exercise]

// Filtered by muscle group (in-view filter, not in predicate):
// allExercises.filter { $0.muscleGroup == selectedGroup }
```

### 11.6 Lockdown Main (LockdownView)

```swift
// Today's accountability -- use FetchDescriptor (dynamic date)
func fetchTodayAccountability(context: ModelContext) throws -> DailyAccountability? {
    let today = Calendar.current.startOfDay(for: Date())
    var descriptor = FetchDescriptor<DailyAccountability>(
        predicate: #Predicate { $0.date == today }
    )
    descriptor.fetchLimit = 1
    descriptor.relationshipKeyPathsForPrefetching = [\.nonNegotiableProgress]
    return try context.fetch(descriptor).first
}

// Active non-negotiables -- @Query is fine (static boolean filter)
@Query(filter: #Predicate<NonNegotiable> { $0.isActive == true },
       sort: \NonNegotiable.order)
var activeNonNegotiables: [NonNegotiable]
```

### 11.7 Focus Timer (FocusTimerView)

```swift
// Today's study sessions -- FetchDescriptor (dynamic date)
func fetchTodayStudySessions(context: ModelContext) throws -> [StudySession] {
    let today = Calendar.current.startOfDay(for: Date())
    let descriptor = FetchDescriptor<StudySession>(
        predicate: #Predicate { $0.startTime >= today },
        sortBy: [SortDescriptor(\.startTime)]
    )
    return try context.fetch(descriptor)
}
```

### 11.8 Streak Calendar (StreakCalendarView)

```swift
// All streaks -- @Query is fine (no dynamic filter)
@Query(sort: \Streak.typeRaw)
var allStreaks: [Streak]

// Daily accountability for heatmap (last 90 days) -- FetchDescriptor
func fetchAccountabilityHeatmap(context: ModelContext) throws -> [DailyAccountability] {
    let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
    let descriptor = FetchDescriptor<DailyAccountability>(
        predicate: #Predicate { $0.date >= ninetyDaysAgo },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
}
```

### 11.9 Recovery Today (RecoveryTodayView)

```swift
// Today's recovery -- FetchDescriptor with prescription prefetch
func fetchTodayRecovery(context: ModelContext) throws -> DailyRecovery? {
    let today = Calendar.current.startOfDay(for: Date())
    var descriptor = FetchDescriptor<DailyRecovery>(
        predicate: #Predicate { $0.date == today }
    )
    descriptor.fetchLimit = 1
    descriptor.relationshipKeyPathsForPrefetching = [\.prescription]
    return try context.fetch(descriptor).first
}

// Last 7 days for trend sparklines
func fetchWeekRecovery(context: ModelContext) throws -> [DailyRecovery] {
    let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
    let descriptor = FetchDescriptor<DailyRecovery>(
        predicate: #Predicate { $0.date >= sevenDaysAgo },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
}
```

### 11.10 Recovery Trends (RecoveryTrendsView)

```swift
// 30 or 90 day recovery history -- FetchDescriptor
func fetchRecoveryTrend(days: Int, context: ModelContext) throws -> [DailyRecovery] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    let descriptor = FetchDescriptor<DailyRecovery>(
        predicate: #Predicate { $0.date >= cutoff },
        sortBy: [SortDescriptor(\.date)]
    )
    return try context.fetch(descriptor)
}

// Active insights (not dismissed) -- @Query is fine (static boolean filter)
@Query(filter: #Predicate<RecoveryInsight> { $0.wasDismissed == false },
       sort: \RecoveryInsight.date, order: .reverse)
var activeInsights: [RecoveryInsight]
```

### 11.11 Arena Main (ArenaView)

```swift
// Today's XP events -- FetchDescriptor
func fetchTodayXP(context: ModelContext) throws -> [XPEvent] {
    let today = Calendar.current.startOfDay(for: Date())
    let descriptor = FetchDescriptor<XPEvent>(
        predicate: #Predicate { $0.date == today },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    return try context.fetch(descriptor)
}

// PERFORMANCE WARNING: Do NOT fetch all XP events to sum them.
// Cache the total XP in UserProfile.totalXP (Int) and update it
// incrementally when new XPEvents are created. Fetching all events
// scales linearly with app lifetime and will degrade after 1+ year.
```

### 11.12 Achievements (AchievementsView)

```swift
// All achievements -- @Query is fine (static, small dataset ~100)
@Query(sort: \Achievement.categoryRaw)
var allAchievements: [Achievement]

// Earned achievements -- static predicate
@Query(filter: #Predicate<Achievement> { $0.earnedAt != nil },
       sort: \Achievement.earnedAt, order: .reverse)
var earnedAchievements: [Achievement]
```

### 11.13 Challenges (ChallengesView)

```swift
// Active challenges -- @Query with static boolean filter
@Query(filter: #Predicate<ChallengeLocal> { $0.isActive == true },
       sort: \ChallengeLocal.endDate)
var activeChallenges: [ChallengeLocal]
```

---

## 12. Indexes & Performance

### 12.1 Index Declarations

> **Note:** The `#Index` macro requires iOS 18+ / macOS 15+. For iOS 17 targets,
> `@Attribute(.unique)` provides implicit indexing. Date fields marked `@Attribute(.unique)`
> (like `DailySnapshot.date`) are already indexed. For non-unique fields, SwiftData in
> iOS 17 does not support explicit index declarations -- rely on `@Attribute(.unique)`
> where applicable and keep fetch predicates simple. When the deployment target moves
> to iOS 18, add `#Index` macros as shown below.

**iOS 18+ Index declarations (add when deployment target is raised):**

```swift
// Add these to the VersionedSchema or at file level alongside model declarations.
// #Index requires iOS 18+. DO NOT add these for iOS 17 targets.

// Date-based indexes (primary query pattern)
#Index<DailySnapshot>([\.date])
#Index<DailyRecovery>([\.date])
#Index<DailyAccountability>([\.date])
#Index<DailyPrescription>([\.date])
#Index<WorkoutPlan>([\.date])
#Index<ExerciseHistory>([\.date])
#Index<XPEvent>([\.date])
#Index<StudySession>([\.startTime])
#Index<RunSession>([\.date])
#Index<PersonalRecord>([\.date])

// Status/filter indexes
#Index<NonNegotiable>([\.isActive])
#Index<Exercise>([\.muscleGroupRaw])
#Index<Exercise>([\.name])
#Index<Achievement>([\.earnedAt])
#Index<ChallengeLocal>([\.isActive])
#Index<PendingSync>([\.entityType])
```

**Index justification table:**

| Model | Indexed Property | Justification |
|-------|-----------------|---------------|
| `DailySnapshot` | `date` (unique) | Every dashboard load queries by date |
| `DailyRecovery` | `date` (unique) | Recovery tab queries by date |
| `DailyAccountability` | `date` (unique) | Lockdown tab queries by date |
| `DailyPrescription` | `date` | Recovery prescription lookup by date |
| `WorkoutPlan` | `date` | Training tab queries by date |
| `ExerciseHistory` | `date` | Progress charts query date ranges |
| `XPEvent` | `date` | Arena daily XP aggregation |
| `StudySession` | `startTime` | Focus timer history queries |
| `RunSession` | `date` | Run history queries |
| `PersonalRecord` | `date` | PR timeline |
| `NonNegotiable` | `isActive` | Active non-negotiable filter |
| `Exercise` | `muscleGroupRaw` | Exercise library filter by muscle group |
| `Exercise` | `name` | Exercise search |
| `Achievement` | `earnedAt` | Earned vs unearned filter |
| `Achievement` | `badgeID` (unique) | Badge lookup by ID |
| `ChallengeLocal` | `isActive` | Active challenges filter |
| `PendingSync` | `entityType` | Batch sync by entity type |
| `SyncState` | `entityType` (unique) | Sync state lookup |

### 12.2 Prefetching Strategy

For relationship-heavy queries, use SwiftData's `fetchDescriptor` with relationship prefetching:

```swift
// Prefetch exercises when loading today's workout.
// NOTE: relationshipKeyPathsForPrefetching only accepts direct relationship
// keypaths -- you CANNOT chain through relationships like \.exercises?.first?.sets.
// Prefetch the first level; nested relationships (PlannedExercise -> PlannedSet)
// are fetched on demand when accessed.
let today = Calendar.current.startOfDay(for: Date())
var descriptor = FetchDescriptor<WorkoutPlan>(
    predicate: #Predicate { $0.date == today }
)
descriptor.relationshipKeyPathsForPrefetching = [\.exercises]
descriptor.fetchLimit = 1
```

### 12.3 Batch Sizes

| Screen | Model | Recommended Batch | Notes |
|--------|-------|------------------|-------|
| Exercise Library | `Exercise` | 50 | LazyVStack with on-demand loading |
| XP Event History | `XPEvent` | 30 | Paginated feed |
| Recovery Trends | `DailyRecovery` | 90 | Full 90-day load is acceptable (~90 rows) |
| Streak Calendar | `DailyAccountability` | 90 | Heatmap needs full range |
| Workout History | `WorkoutPlan` | 20 | Scrollable list |
| Achievement Grid | `Achievement` | All | Total badge count is fixed (~50-100) |

### 12.4 Performance Guidelines

1. **Date normalization**: All date properties used for lookup are normalized to `startOfDay` at insert time. This ensures predicate equality works without time component interference.

2. **Avoid fetching full graphs**: When displaying lists (e.g., workout history), only access top-level properties. Drill into relationships only on detail views.

3. **Background aggregation**: For expensive computations like total XP, 30-day averages, and trend calculations, run on a background `ModelContext` and cache results.

4. **JSON properties**: Properties stored as `Data` (JSON) are not indexed or queryable. Keep them for display-only data that does not need filtering.

---

## 13. Sync Conflict Resolution

### 13.1 General Strategy

Tempo uses **last-writer-wins with server authority** for most models. The sync flow:

1. Client pushes local changes (from `PendingSync` queue) to server.
2. Server applies changes and returns the canonical version.
3. Client pulls server state and overwrites local if server `updated_at` is newer.

### 13.2 Per-Model Strategy

| Model | Conflict Strategy | Rationale |
|-------|------------------|-----------|
| `UserProfile` | **Server wins** | Profile is editable from multiple devices (future). Server is source of truth. |
| `UserSettings` | **Server wins** | Same as profile. |
| `DailySnapshot` | **Merge by field** | Each field has an independent source (Whoop, NutriTrack, HealthKit, local). Non-nil values from either side are kept; if both sides have a value, the one with the latest `updated_at` wins. |
| `WorkoutPlan` | **Client wins** | Workouts are logged on-device during a gym session. The phone in-hand always has the most accurate data. Server stores a backup. |
| `PlannedExercise` / `PlannedSet` | **Client wins** | Same as WorkoutPlan — logged locally. |
| `Exercise` | **Server wins for seed data, client wins for custom** | Seed exercises are maintained server-side. Custom exercises are client-authoritative. |
| `ExerciseHistory` / `PersonalRecord` | **Client wins** | Derived from workout logging which is client-side. |
| `RunSession` | **Client wins** | GPS and HR data captured on device. |
| `NonNegotiable` | **Client wins** | User configures these locally. |
| `DailyAccountability` / `NonNegotiableProgress` | **Merge by field** | Some fields are auto-tracked (server may push Whoop data), others are local. |
| `StudySession` | **Client wins** | Timer runs on device. |
| `Streak` | **Server wins** | Server maintains authoritative streak count to prevent manipulation. |
| `DailyRecovery` | **Server wins** | Whoop data flows through the server proxy. |
| `DailyPrescription` | **Server wins** | Generated by server-side engine. |
| `RecoveryInsight` | **Server wins** | Generated by server-side AI. |
| `XPEvent` | **Server wins** | XP is calculated and validated server-side. |
| `Achievement` | **Server wins** | Earned status validated server-side. |
| `ChallengeLocal` | **Server wins** | Challenges are server-authoritative. |

### 13.3 Merge Implementation

```swift
/// Merge strategy for DailySnapshot.
/// Each field is updated independently — non-nil values from the newer source win.
func mergeDailySnapshot(local: DailySnapshot, remote: DailySnapshot.DTO) {
    // Whoop fields: server is authoritative (data flows through backend proxy)
    local.recoveryScore = remote.recovery_score ?? local.recoveryScore
    local.hrv = remote.hrv ?? local.hrv
    local.rhr = remote.rhr ?? local.rhr
    local.sleepHours = remote.sleep_hours ?? local.sleepHours
    local.sleepScore = remote.sleep_score ?? local.sleepScore
    local.strain = remote.strain ?? local.strain

    // NutriTrack fields: server is authoritative
    local.caloriesConsumed = remote.calories_consumed ?? local.caloriesConsumed
    local.calorieTarget = remote.calorie_target ?? local.calorieTarget
    local.proteinActual = remote.protein_actual ?? local.proteinActual
    local.carbsActual = remote.carbs_actual ?? local.carbsActual
    local.fatActual = remote.fat_actual ?? local.fatActual
    local.proteinTarget = remote.protein_target ?? local.proteinTarget
    local.carbsTarget = remote.carbs_target ?? local.carbsTarget
    local.fatTarget = remote.fat_target ?? local.fatTarget
    local.mealsLogged = max(local.mealsLogged, remote.meals_logged)
    local.mealsPlanned = remote.meals_planned

    // Local fields: client is authoritative (only update if server has newer data)
    if remote.updated_at > local.updatedAt {
        local.studyMinutes = remote.study_minutes
        local.workoutCompleted = remote.workout_completed
        local.workoutTypeRaw = remote.workout_type
        local.dailyScore = remote.daily_score
        local.nonNegotiablesCompleted = remote.non_negotiables_completed
        local.nonNegotiablesTotal = remote.non_negotiables_total
    }

    // HealthKit fields: client is authoritative (HealthKit is local)
    // Only accept server values if local has no data
    local.steps = local.steps ?? remote.steps
    local.activeCalories = local.activeCalories ?? remote.active_calories

    local.updatedAt = max(local.updatedAt, remote.updated_at)
}
```

---

## 14. Data Lifecycle & Cleanup

### 14.1 Retention Policies

| Model | Retention | Cleanup Strategy |
|-------|-----------|-----------------|
| `DailySnapshot` | **Forever** | Never deleted. Core historical data. |
| `DailyRecovery` | **Forever** | Never deleted. Trend analysis needs long history. |
| `WorkoutPlan` | **Forever** | Never deleted. Progress tracking needs full history. |
| `PlannedExercise` / `PlannedSet` | **Cascade from WorkoutPlan** | Deleted only if parent workout is deleted. |
| `Exercise` | **Forever** | Seed data + custom exercises persist. |
| `ExerciseHistory` | **Forever** | Progress charts need full history. |
| `PersonalRecord` | **Forever** | PRs are never deleted. |
| `RunSession` | **Forever** | Run history persists. |
| `NonNegotiable` | **Soft delete (isActive=false)** | Deactivated, never hard-deleted. Progress entries reference them. |
| `DailyAccountability` | **Forever** | Streak calendar needs full history. |
| `NonNegotiableProgress` | **Forever** | Referenced by accountability history. |
| `StudySession` | **Forever** | Study analytics need full history. |
| `Streak` | **Forever** | Small data, no cleanup needed. |
| `DailyPrescription` | **1 year** | Prescriptions older than 365 days are deleted. |
| `RecoveryInsight` | **90 days** | Insights older than 90 days or dismissed > 30 days ago are deleted. |
| `XPEvent` | **Forever** | Total XP depends on the sum of all events. |
| `Achievement` | **Forever** | Badge collection persists. |
| `ChallengeLocal` | **90 days after end** | Completed challenges cleaned up 90 days after `endDate`. |
| `PendingSync` | **7 days** | Failed syncs older than 7 days with max retries are deleted. |
| `SyncState` | **Forever** | One record per entity type — tiny footprint. |
| `WhoopConnection` | **Forever** | Single record. |
| `NutriTrackConnection` | **Forever** | Single record. |
| `HealthKitState` | **Forever** | Single record. |

### 14.2 Cleanup Implementation

```swift
/// Run daily (e.g., on app launch or background refresh).
actor DataCleanupService {

    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func performCleanup() async throws {
        let context = ModelContext(modelContainer)

        let now = Date()
        let calendar = Calendar.current

        // 1. Delete prescriptions older than 1 year
        let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now)!
        let oldPrescriptions = try context.fetch(
            FetchDescriptor<DailyPrescription>(
                predicate: #Predicate { $0.date < oneYearAgo }
            )
        )
        for p in oldPrescriptions { context.delete(p) }

        // 2. Delete insights older than 90 days OR dismissed > 30 days ago
        let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now)!
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let oldInsights = try context.fetch(
            FetchDescriptor<RecoveryInsight>(
                predicate: #Predicate {
                    $0.date < ninetyDaysAgo ||
                    ($0.wasDismissed == true && $0.dismissedAt != nil && $0.dismissedAt! < thirtyDaysAgo)
                }
            )
        )
        for i in oldInsights { context.delete(i) }

        // 3. Delete ended challenges older than 90 days
        let oldChallenges = try context.fetch(
            FetchDescriptor<ChallengeLocal>(
                predicate: #Predicate {
                    $0.endDate < ninetyDaysAgo && $0.isActive == false
                }
            )
        )
        for c in oldChallenges { context.delete(c) }

        // 4. Delete exhausted pending syncs older than 7 days
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        let exhaustedSyncs = try context.fetch(
            FetchDescriptor<PendingSync>(
                predicate: #Predicate {
                    $0.createdAt < sevenDaysAgo && $0.retryCount >= 5
                }
            )
        )
        for s in exhaustedSyncs { context.delete(s) }

        try context.save()
    }
}
```

---

## 15. Thread Safety & ModelContext Patterns

### 15.1 Core Principle

SwiftData `ModelContext` is **not thread-safe**. Each thread/actor must use its own `ModelContext`. The `@MainActor`-bound context from `modelContainer.mainContext` is used by SwiftUI views. Background operations (sync, cleanup, aggregation) must create their own contexts.

### 15.2 Access Patterns

```swift
// MARK: - Main Thread (SwiftUI Views)

// Views use @Query or @Environment(\.modelContext) — always main actor.
// NOTE: @Query with dynamic dates CANNOT capture local variables.
// Use FetchDescriptor in a service method or .onAppear, not @Query, for date-based filters.
struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @State private var todaySnapshot: DailySnapshot?

    var body: some View {
        // ... use todaySnapshot ...
        Text("Score: \(todaySnapshot?.dailyScore ?? 0)")
            .onAppear { loadSnapshot() }
    }

    private func loadSnapshot() {
        let today = Calendar.current.startOfDay(for: Date())
        var descriptor = FetchDescriptor<DailySnapshot>(
            predicate: #Predicate { $0.date == today }
        )
        descriptor.fetchLimit = 1
        todaySnapshot = try? context.fetch(descriptor).first
    }

    // Mutations happen on the main context:
    func updateSnapshot() {
        todaySnapshot?.dailyScore = 85
        try? context.save()
    }
}

// MARK: - Background Sync

actor SyncService {
    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func syncFromServer() async throws {
        // Create a NEW context for this background operation.
        // FetchDescriptor predicates CAN capture local variables (unlike @Query).
        let context = ModelContext(modelContainer)

        // Fetch data from server...
        let remoteDTOs = try await apiClient.fetchDailySnapshots()

        // Apply to local store
        for dto in remoteDTOs {
            let dtoDate = dto.date // capture as local let for predicate
            let existing = try context.fetch(
                FetchDescriptor<DailySnapshot>(
                    predicate: #Predicate { $0.date == dtoDate }
                )
            ).first

            if let existing {
                // Merge
                mergeDailySnapshot(local: existing, remote: dto)
            } else {
                // Insert new
                let snapshot = DailySnapshot(from: dto)
                context.insert(snapshot)
            }
        }

        try context.save()
        // Changes are automatically visible to other contexts via the shared store.
    }
}

// MARK: - Background Aggregation

actor AggregationService {
    let modelContainer: ModelContainer

    func computeDailyScore(for date: Date) async throws -> Int {
        let context = ModelContext(modelContainer)

        let snapshot = try context.fetch(
            FetchDescriptor<DailySnapshot>(
                predicate: #Predicate { $0.date == date }
            )
        ).first

        guard let snapshot else { return 0 }

        // Compute composite score...
        var score = 0
        score += snapshot.workoutCompleted ? 25 : 0
        score += Int(snapshot.studyCompliance * 25)
        score += Int(snapshot.nonNegotiableCompliance * 25)
        score += Int((snapshot.calorieCompliance ?? 0) * 25)

        snapshot.dailyScore = min(100, score)
        try context.save()

        return snapshot.dailyScore
    }
}
```

### 15.3 Concurrency Rules

1. **Never pass `@Model` objects across actor boundaries.** Pass IDs (UUID) and re-fetch in the target context.

2. **DTOs are Sendable.** All DTO structs are plain `Codable` structs with value types only. They can safely cross actor boundaries.

3. **Save frequently on background contexts.** Background contexts do not auto-save. Call `context.save()` after each batch of mutations.

4. **Observe `modelContainer` notifications** for cross-context change propagation. SwiftUI `@Query` handles this automatically for the main context.

---

## 16. Migration Strategy

### 16.1 V1 to V2 Migration Plan

V1 is the initial release schema. V2 will be needed when any of the following changes occur:

| Change Type | Example | Migration Type |
|-------------|---------|---------------|
| Add optional property | `DailySnapshot.examCountdown: Int?` | Lightweight (automatic) |
| Add property with default | `UserSettings.darkMode: Bool = true` | Lightweight (automatic) |
| Rename property | `sleepHours` -> `totalSleepHours` | Custom migration required |
| Remove property | Delete unused field | Lightweight (automatic) |
| Add new model | `MealLog` model | Lightweight (automatic) |
| Change relationship cardinality | 1-to-1 becomes 1-to-many | Custom migration required |
| Add unique constraint | New `@Attribute(.unique)` | Custom migration (need to deduplicate) |

### 16.2 Lightweight vs Custom

**Lightweight migrations** (handled by SwiftData automatically):
- Adding new optional properties
- Adding new properties with default values
- Adding new models
- Removing properties
- Removing models

**Custom migrations** (require `MigrationStage.custom`):
- Renaming properties
- Splitting/merging models
- Changing data types
- Adding unique constraints to existing data
- Data backfills

### 16.3 Custom Migration Template

```swift
enum TempoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TempoSchemaV1.self, TempoSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    // Lightweight migration (most v1->v2 changes):
    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: TempoSchemaV1.self,
        toVersion: TempoSchemaV2.self
    )

    // Custom migration example (uncomment when needed):
    /*
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: TempoSchemaV1.self,
        toVersion: TempoSchemaV2.self,
        willMigrate: { context in
            // Pre-migration: transform data in v1 format
            // e.g., backfill a new required field from existing data
            let snapshots = try context.fetch(FetchDescriptor<DailySnapshot>())
            for snapshot in snapshots {
                // Backfill new field from existing data
                snapshot.examCountdown = nil
            }
            try context.save()
        },
        didMigrate: { context in
            // Post-migration: clean up or validate v2 data
            // e.g., deduplicate records after adding a unique constraint
        }
    )
    */
}
```

### 16.4 Migration Testing

> **CRITICAL WARNING:** Never test migrations only against empty databases or freshly-seeded
> test data. SwiftData lightweight migrations can silently drop data when the actual stored
> data has edge cases (nil values in fields that become non-optional, duplicate values in
> fields that gain unique constraints, orphaned relationships, etc.).
>
> **You MUST test against a copy of REAL user data from a production build.** The test
> database should contain:
> - At least 30 days of DailySnapshot/DailyRecovery data (with some nil fields)
> - Workouts with deeply nested relationships (WorkoutPlan -> PlannedExercise -> PlannedSet)
> - Exercises with history and PRs
> - At least one of every model type populated
> - Edge cases: orphaned progress entries, streaks at 0, exhausted PendingSync records

Before every release that changes the schema:

1. Export the current production SQLite database from a test device (use Xcode's "Download Container" or a debug build that copies the database to a shared location).
2. Load it in a unit test using `ModelContainer` with the new schema + migration plan.
3. Verify all data is accessible and correct after migration.
4. Verify no data loss (count records before and after).
5. Verify all relationships are intact (fetch a WorkoutPlan and traverse to PlannedSet).
6. Run the test on BOTH simulator and a physical device (SQLite behavior can differ).

```swift
final class MigrationTests: XCTestCase {

    func testV1toV2Migration() throws {
        // Load v1 database from test fixtures
        let v1DatabaseURL = Bundle(for: type(of: self))
            .url(forResource: "TempoStore_v1", withExtension: "sqlite")!

        // Copy to a temp location (migration modifies in place)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        try FileManager.default.copyItem(at: v1DatabaseURL, to: tempURL)

        // Create container with migration plan
        let config = ModelConfiguration(url: tempURL)
        let container = try ModelContainer(
            for: Schema(TempoSchemaV2.models),
            migrationPlan: TempoMigrationPlan.self,
            configurations: [config]
        )

        // Verify data integrity
        let context = container.mainContext
        let snapshots = try context.fetch(FetchDescriptor<DailySnapshot>())
        XCTAssertFalse(snapshots.isEmpty, "Migration should preserve DailySnapshot records")

        // Verify new fields have expected defaults
        for snapshot in snapshots {
            // New optional fields should be nil
            // New fields with defaults should have the default value
        }
    }
}
```

---

## Appendix A: Complete Relationship Map

```
UserProfile (1) ──cascade── (0..1) UserSettings

DailySnapshot (standalone, 1 per day)

WorkoutPlan (1) ──cascade── (*) PlannedExercise
PlannedExercise (*) ──── (1) Exercise
PlannedExercise (1) ──cascade── (*) PlannedSet

Exercise (1) ──cascade── (*) PlannedExercise
Exercise (1) ──cascade── (*) ExerciseHistory
Exercise (1) ──cascade── (*) PersonalRecord

RunSession (standalone)

NonNegotiable (1) ──cascade── (*) NonNegotiableProgress

DailyAccountability (1) ──cascade── (*) NonNegotiableProgress
DailyAccountability (1) ──cascade── (*) StudySession

NonNegotiableProgress (*) ──── (1) NonNegotiable
NonNegotiableProgress (*) ──── (1) DailyAccountability

StudySession (*) ──── (1) DailyAccountability

Streak (standalone, 1 per StreakType)

DailyRecovery (1) ──cascade── (0..1) DailyPrescription

RecoveryInsight (standalone)

XPEvent (standalone)
Achievement (standalone)
ChallengeLocal (standalone)

SyncState (standalone, 1 per entity type)
PendingSync (standalone, queue)

WhoopConnection (singleton)
NutriTrackConnection (singleton)
HealthKitState (singleton)
```

## Appendix B: Delete Rule Summary

| Parent | Child | Rule | Effect |
|--------|-------|------|--------|
| `WorkoutPlan` | `PlannedExercise` | **Cascade** | Deleting a workout deletes all its exercises |
| `PlannedExercise` | `PlannedSet` | **Cascade** | Deleting a planned exercise deletes all its sets |
| `PlannedExercise` | `Exercise` | **Nullify** (implicit) | Deleting an exercise nullifies the reference in planned exercises |
| `Exercise` | `PlannedExercise` | **Cascade** | Deleting an exercise deletes all planned instances |
| `Exercise` | `ExerciseHistory` | **Cascade** | Deleting an exercise deletes its history |
| `Exercise` | `PersonalRecord` | **Cascade** | Deleting an exercise deletes its PRs |
| `NonNegotiable` | `NonNegotiableProgress` | **Cascade** | Deleting a non-negotiable deletes all progress entries |
| `DailyAccountability` | `NonNegotiableProgress` | **Cascade** | Deleting a day's accountability deletes its progress |
| `DailyAccountability` | `StudySession` | **Cascade** | Deleting a day's accountability deletes study sessions |
| `DailyRecovery` | `DailyPrescription` | **Cascade** | Deleting recovery data deletes its prescription |
| `UserProfile` | `UserSettings` | **Cascade** | Deleting a user profile deletes their settings |

> **Delete Rule Clarity:** Every optional relationship inverse (the "child side" — e.g.,
> `PlannedExercise.workoutPlan`, `PlannedSet.plannedExercise`, etc.) uses `.nullify` as
> its delete rule. This means if you somehow delete a child without going through the
> parent's cascade, the parent's reference is safely nullified rather than causing a crash.
> In practice, cascades from the parent side handle all deletions.

## Appendix C: Storage Estimate

| Model | Est. Records/Year | Est. Size/Record | Annual Size |
|-------|--------------------|------------------|-------------|
| `DailySnapshot` | 365 | ~500 bytes | ~180 KB |
| `DailyRecovery` | 365 | ~400 bytes | ~145 KB |
| `DailyAccountability` | 365 | ~200 bytes | ~73 KB |
| `NonNegotiableProgress` | 365 x 5 = 1,825 | ~150 bytes | ~274 KB |
| `WorkoutPlan` | ~200 | ~300 bytes | ~60 KB |
| `PlannedExercise` | ~1,200 | ~100 bytes | ~120 KB |
| `PlannedSet` | ~5,000 | ~150 bytes | ~750 KB |
| `Exercise` | ~300 (mostly static) | ~500 bytes | ~150 KB |
| `ExerciseHistory` | ~2,000 | ~100 bytes | ~200 KB |
| `PersonalRecord` | ~100 | ~100 bytes | ~10 KB |
| `StudySession` | ~700 | ~150 bytes | ~105 KB |
| `XPEvent` | ~3,000 | ~150 bytes | ~450 KB |
| `RunSession` | ~100 | ~1 KB (splits + polyline) | ~100 KB |
| **Total** | | | **~2.6 MB/year** |

The local database will stay well under 50 MB even after years of use. No pagination of local queries is necessary for the first several years.
