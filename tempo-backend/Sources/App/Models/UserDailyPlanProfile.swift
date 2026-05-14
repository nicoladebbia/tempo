import Fluent
import Foundation
import Vapor

// MARK: - UserDailyPlanProfile
//
// Backend mirror of the iOS SwiftData model. Stored 1:1 with users — receiving
// the onboarding payload from iOS materialises one row here. Per
// docs/INTELLIGENCE_REMEDIATION_PLAN.md §8.
//
// Class + work blocks are stored as JSON on this row (not separate tables)
// because they're only ever read together with the profile and the schema
// expense of two more join tables wouldn't pay back. If we later need to
// query by class (e.g. "show users in STAT 101"), split them out.

final class UserDailyPlanProfile: Model, Content, @unchecked Sendable {
    static let schema = "user_daily_plan_profiles"

    @ID(custom: "id")
    var id: UUID?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "wake_time_minutes")
    var wakeTimeMinutes: Int

    @Field(key: "sleep_target_hours")
    var sleepTargetHours: Double

    @Field(key: "chronotype")
    var chronotype: String

    @Field(key: "training_time_preference")
    var trainingTimePreference: String

    @Field(key: "eating_window_preset")
    var eatingWindowPreset: String

    @Field(key: "eating_window_start_minutes")
    var eatingWindowStartMinutes: Int

    @Field(key: "eating_window_end_minutes")
    var eatingWindowEndMinutes: Int

    @Field(key: "breakfast_skipped")
    var breakfastSkipped: Bool

    @Field(key: "post_workout_mandatory")
    var postWorkoutMandatory: Bool

    @Field(key: "study_session_length_minutes")
    var studySessionLengthMinutes: Int

    @Field(key: "weekend_differential")
    var weekendDifferential: String

    @OptionalField(key: "term_start_date")
    var termStartDate: Date?

    @OptionalField(key: "term_end_date")
    var termEndDate: Date?

    /// JSON-encoded `[StoredClassBlock]`. See `decodeClassBlocks` for accessors.
    @Field(key: "class_blocks_json")
    var classBlocksJSON: String

    /// JSON-encoded `[StoredWorkBlock]`.
    @Field(key: "work_blocks_json")
    var workBlocksJSON: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        userID: String,
        wakeTimeMinutes: Int,
        sleepTargetHours: Double,
        chronotype: String,
        trainingTimePreference: String,
        eatingWindowPreset: String,
        eatingWindowStartMinutes: Int,
        eatingWindowEndMinutes: Int,
        breakfastSkipped: Bool,
        postWorkoutMandatory: Bool,
        studySessionLengthMinutes: Int,
        weekendDifferential: String,
        termStartDate: Date?,
        termEndDate: Date?,
        classBlocksJSON: String,
        workBlocksJSON: String
    ) {
        self.id = UUID()
        self.$user.id = userID
        self.wakeTimeMinutes = wakeTimeMinutes
        self.sleepTargetHours = sleepTargetHours
        self.chronotype = chronotype
        self.trainingTimePreference = trainingTimePreference
        self.eatingWindowPreset = eatingWindowPreset
        self.eatingWindowStartMinutes = eatingWindowStartMinutes
        self.eatingWindowEndMinutes = eatingWindowEndMinutes
        self.breakfastSkipped = breakfastSkipped
        self.postWorkoutMandatory = postWorkoutMandatory
        self.studySessionLengthMinutes = studySessionLengthMinutes
        self.weekendDifferential = weekendDifferential
        self.termStartDate = termStartDate
        self.termEndDate = termEndDate
        self.classBlocksJSON = classBlocksJSON
        self.workBlocksJSON = workBlocksJSON
    }
}

// MARK: - Inline block payloads

struct StoredClassBlock: Codable {
    let weekday: Int
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let courseCode: String
    let courseName: String?
    let location: String?
}

struct StoredWorkBlock: Codable {
    let weekday: Int
    let startMinuteOfDay: Int
    let endMinuteOfDay: Int
    let label: String
}
