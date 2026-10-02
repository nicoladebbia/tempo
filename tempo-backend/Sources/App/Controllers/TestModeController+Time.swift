import Fluent
import Vapor

// MARK: - Time travel + run jobs now

//
// GET    /v1/test/clock   → {now, offset_seconds}
// POST   /v1/test/clock   {set?: ISO date, advance_seconds?, reset?}
// POST   /v1/test/jobs/run {job, name?, force?} → {job, now, affected}
//
// The clock moves `app.now` (business logic: which day/week, whether a
// subscription has lapsed, job windows). JWT expiry, rate limits and caches
// stay on the real clock. The scheduled jobs never run on their own on the
// test server — `jobs/run` runs one pass, at the shifted time.

extension TestModeController {
    func bootTime(routes: RoutesBuilder) {
        routes.get("clock", use: clock)
        routes.post("clock", use: setClock)
        routes.post("jobs", "run", use: runJob)
    }

    struct ClockResponse: Content {
        let now: Date
        let offsetSeconds: Double
    }

    struct ClockRequest: Content {
        var set: Date?
        var advanceSeconds: Double?
        var reset: Bool?
    }

    func clock(_ req: Request) async throws -> ClockResponse {
        let state = try Self.state(req)
        return ClockResponse(now: req.now, offsetSeconds: state.clockOffset)
    }

    func setClock(_ req: Request) async throws -> ClockResponse {
        let state = try Self.state(req)
        let body = try req.content.decode(ClockRequest.self)
        if body.reset == true {
            state.clockOffset = 0
        } else if let target = body.set {
            state.clockOffset = target.timeIntervalSinceNow
        } else if let seconds = body.advanceSeconds {
            state.clockOffset += seconds
        } else {
            throw Abort(.badRequest, reason: "Send set, advance_seconds or reset.")
        }
        // Pro status is cached for 5 min — recompute it at the new time.
        for user in try await User.query(on: req.db).filter(\.$appleUserID =~ "test:").all() {
            if let id = user.id {
                await req.invalidateSubscriptionCache(userID: id)
            }
        }
        req.logger.warning("[test-mode] clock now \(req.now) (offset \(Int(state.clockOffset)) s)")
        return ClockResponse(now: req.now, offsetSeconds: state.clockOffset)
    }

    enum JobName: String, Codable, CaseIterable {
        case morningBriefing = "morning-briefing"
        case weeklySummary = "weekly-summary"
        case drillSergeant = "drill-sergeant"
        case leaderboardRefresh = "leaderboard-refresh"
        case notificationsCleanup = "notifications-cleanup"
    }

    struct JobRequest: Content {
        let job: String
        /// Test login name; nil = every user (as the real schedule would).
        var name: String?
        /// Morning briefing: ignore the 08:15–08:45 window and the once-a-day check.
        var force: Bool?
    }

    struct JobResponse: Content {
        let job: String
        let now: Date
        /// Users the pass acted on (nil when the job isn't per-user).
        let affected: Int?
    }

    func runJob(_ req: Request) async throws -> JobResponse {
        _ = try Self.state(req)
        let body = try req.content.decode(JobRequest.self)
        guard let job = JobName(rawValue: body.job) else {
            let names = JobName.allCases.map(\.rawValue).joined(separator: ", ")
            throw Abort(.badRequest, reason: "Unknown job '\(body.job)'. Jobs: \(names).")
        }
        var userID: String?
        if let name = body.name {
            guard let user = try await User.query(on: req.db)
                .filter(\.$appleUserID == Self.appleUserID(for: name)).first()
            else {
                throw Abort(.notFound, reason: "No test user '\(name)'.")
            }
            userID = try user.requireID()
        }
        let app = req.application
        let now = req.now
        let affected: Int?
        switch job {
        case .morningBriefing:
            affected = try await MorningBriefingJob().send(app: app, now: now, userID: userID, force: body.force ?? false)
        case .weeklySummary:
            affected = try await WeeklySummaryJob().generate(app: app, now: now, userID: userID)
        case .drillSergeant:
            affected = try await DrillSergeantBatchJob().generate(app: app, now: now, userID: userID)
        case .leaderboardRefresh:
            try await LeaderboardRefreshJob().refresh(app: app)
            affected = nil
        case .notificationsCleanup:
            try await ProcessedNotificationsCleanupJob().purge(app: app, now: now)
            affected = nil
        }
        req.logger.info("[test-mode] ran \(job.rawValue) at \(now) → \(affected.map(String.init) ?? "done")")
        return JobResponse(job: job.rawValue, now: now, affected: affected)
    }
}
