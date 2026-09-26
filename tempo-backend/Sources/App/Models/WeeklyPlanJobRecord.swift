import Fluent
import Foundation
import Vapor

// MARK: - WeeklyPlanJobRecord

//
// Server-side "build next week" job row. iOS POSTs a rendered prompt + per-day
// macro targets, gets back a job id immediately, and the actual Claude call +
// nutrition resolution + macro solve happen in the `WeeklyPlanJob` queue job
// with the app closed. A "plan ready" push fires when it's done.
//
// Named `...Record` (not `WeeklyPlanJob`) to avoid colliding with the
// `WeeklyPlanJob` AsyncJob type that processes rows of this model.
//
// One row per (user, weekStart) attempt. `requestJSON` holds the original
// system/prompt/targets/timezone so the job (and a retry) doesn't need the
// request body again. `planJSON` holds the final, solved plan in the same
// shape iOS sent up, plus the new per-food `source`/`approx`/`fdcId` fields.

final class WeeklyPlanJobRecord: Model, Content, @unchecked Sendable {
    static let schema = "weekly_plan_jobs"

    enum Status: String, Codable, Sendable {
        case queued
        case running
        case ready
        case failed
    }

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "week_start")
    var weekStart: String

    @Field(key: "status")
    var status: String

    @Field(key: "request_json")
    var requestJSON: String

    @OptionalField(key: "plan_json")
    var planJSON: String?

    @OptionalField(key: "error")
    var error: String?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "completed_at")
    var completedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        userID: String,
        weekStart: String,
        status: Status = .queued,
        requestJSON: String
    ) {
        self.id = id
        self.userID = userID
        self.weekStart = weekStart
        self.status = status.rawValue
        self.requestJSON = requestJSON
    }

    var statusEnum: Status {
        get { Status(rawValue: status) ?? .failed }
        set { status = newValue.rawValue }
    }

    /// A queued/running job older than this is presumed dead (worker crash,
    /// restart mid-job) and gets reported + persisted as failed on next read.
    static let staleAfter: TimeInterval = 15 * 60
}
