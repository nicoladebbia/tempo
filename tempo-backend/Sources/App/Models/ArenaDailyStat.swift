import Fluent
import Vapor

// MARK: - Arena Daily Stat

//
// One row per user per local day: what the user's app measured that day.
// The app is the source of truth for XP (its local XP rows), so it pushes the
// day totals here (PUT /v1/arena/stats) and the server only adds them up:
// the friends leaderboard (weekly XP) and challenge standings (XP, workouts,
// study minutes over the challenge's days). Days are the user's own calendar
// days as "YYYY-MM-DD" strings, so no timezone maths happens server-side and
// re-pushing a day replaces it (idempotent, no duplicates).

final class ArenaDailyStat: Model, @unchecked Sendable {
    static let schema = "arena_daily_stats"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "user_id")
    var userID: String

    /// "YYYY-MM-DD" in the user's own calendar.
    @Field(key: "day")
    var day: String

    @Field(key: "xp")
    var xp: Int

    @Field(key: "workouts")
    var workouts: Int

    @Field(key: "study_minutes")
    var studyMinutes: Int

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: String, day: String, xp: Int, workouts: Int, studyMinutes: Int) {
        self.userID = userID
        self.day = day
        self.xp = xp
        self.workouts = workouts
        self.studyMinutes = studyMinutes
    }
}
