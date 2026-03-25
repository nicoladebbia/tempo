import Vapor
import Fluent

// MARK: - XP Controller
// Per BACKEND_API.md Section 10.1-10.4 — XP event recording, today's XP, history, level info.

struct XPController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.post("events", use: recordEvents)
        routes.get("today", use: today)
        routes.get("history", use: history)
        routes.get("level", use: level)
    }

    // MARK: - POST /v1/xp/events
    // Per BACKEND_API.md Section 10.1 — Record XP events (batch, server-calculated points).
    // Security: Server calculates XP from source + type. Client cannot set points directly.
    // Idempotent: duplicate (user_id, source, reference_id) tuples are skipped.

    @Sendable
    func recordEvents(req: Request) async throws -> Envelope<XPRecordResponseDTO> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(XPRecordRequestDTO.self)

        guard !body.events.isEmpty, body.events.count <= 50 else {
            throw Abort(.badRequest, reason: "Events array must contain 1-50 items.")
        }

        // Get user for streak multiplier
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let streakMultiplier = Self.streakMultiplier(for: user.streakDays)
        var eventsRecorded = 0
        var eventsSkipped = 0
        var totalXPEarned = 0

        for event in body.events {
            // Validate event type
            guard let baseXP = Self.calculateBaseXP(type: event.type, source: event.source) else {
                eventsSkipped += 1
                continue
            }

            // Check for duplicate (source + reference_id) via metadata
            if let refID = event.referenceID {
                // Query all events for this user+source and check metadata in-memory
                let candidates = try await XPEvent.query(on: req.db)
                    .filter(\.$user.$id == userID)
                    .filter(\.$source == event.source)
                    .all()
                let isDuplicate = candidates.contains { $0.metadata?["reference_id"] == refID }
                if isDuplicate {
                    eventsSkipped += 1
                    continue
                }
            }

            var metadata: [String: String] = event.metadata ?? [:]
            if let refID = event.referenceID {
                metadata["reference_id"] = refID
            }
            metadata["type"] = event.type

            let xpEvent = XPEvent(
                userID: userID,
                source: event.source,
                baseXP: baseXP,
                streakMultiplier: streakMultiplier,
                metadata: metadata.isEmpty ? nil : metadata
            )
            try await xpEvent.save(on: req.db)

            totalXPEarned += xpEvent.multipliedXP
            eventsRecorded += 1
        }

        // Update user XP total and level
        if totalXPEarned > 0 {
            user.xpTotal += totalXPEarned
            let newLevel = User.levelForXP(user.xpTotal)
            let levelChanged = newLevel != user.level
            user.level = newLevel
            try await user.save(on: req.db)

            return Envelope(
                data: XPRecordResponseDTO(
                    eventsRecorded: eventsRecorded,
                    eventsSkipped: eventsSkipped,
                    xpEarned: totalXPEarned,
                    xpTotal: user.xpTotal,
                    level: user.level,
                    levelChanged: levelChanged,
                    nextLevelXP: Self.xpForNextLevel(user.level)
                ),
                requestID: req.requestID
            )
        }

        return Envelope(
            data: XPRecordResponseDTO(
                eventsRecorded: eventsRecorded,
                eventsSkipped: eventsSkipped,
                xpEarned: 0,
                xpTotal: user.xpTotal,
                level: user.level,
                levelChanged: false,
                nextLevelXP: Self.xpForNextLevel(user.level)
            ),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/xp/today
    // Per BACKEND_API.md Section 10.2 — Today's XP breakdown.

    @Sendable
    func today(req: Request) async throws -> Envelope<XPTodayDTO> {
        let userID = try req.auth.requireUserID()

        let calendar = Calendar(identifier: .iso8601)
        let startOfDay = calendar.startOfDay(for: Date())

        let events = try await XPEvent.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$createdAt >= startOfDay)
            .sort(\.$createdAt, .descending)
            .all()

        let totalXP = events.reduce(0) { $0 + $1.multipliedXP }
        let breakdown = Dictionary(grouping: events, by: { $0.metadata?["type"] ?? $0.source })
            .map { XPBreakdownItem(source: $0.key, xp: $0.value.reduce(0) { $0 + $1.multipliedXP }, count: $0.value.count) }

        return Envelope(
            data: XPTodayDTO(
                totalXP: totalXP,
                eventCount: events.count,
                breakdown: breakdown
            ),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/xp/history
    // Per BACKEND_API.md Section 10.3 — XP history with pagination.

    @Sendable
    func history(req: Request) async throws -> Envelope<[XPEventDTO]> {
        let userID = try req.auth.requireUserID()
        let pagination = try req.query.decode(PaginationQuery.self)
        let limit = min(pagination.limit ?? 25, 100)

        var query = XPEvent.query(on: req.db)
            .filter(\.$user.$id == userID)
            .sort(\.$createdAt, .descending)
            .limit(limit + 1)

        if let cursor = pagination.cursor, let cursorDate = ISO8601DateFormatter().date(from: cursor) {
            query = query.filter(\.$createdAt < cursorDate)
        }

        let events = try await query.all()
        let hasMore = events.count > limit
        let results = Array(events.prefix(limit))

        let dtos = results.map { event in
            XPEventDTO(
                id: event.id?.uuidString ?? "",
                source: event.source,
                type: event.metadata?["type"] ?? event.source,
                baseXP: event.baseXP,
                multipliedXP: event.multipliedXP,
                streakMultiplier: event.streakMultiplier,
                createdAt: event.createdAt ?? Date()
            )
        }

        return Envelope(
            data: dtos,
            pagination: PaginationMeta(
                cursor: hasMore ? results.last?.createdAt?.iso8601 : nil,
                hasMore: hasMore,
                count: results.count
            ),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/xp/level
    // Per BACKEND_API.md Section 10.4 — Level info with thresholds.

    @Sendable
    func level(req: Request) async throws -> Envelope<LevelInfoDTO> {
        let userID = try req.auth.requireUserID()

        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let currentLevelXP = Self.xpForLevel(user.level)
        let nextLevelXP = Self.xpForNextLevel(user.level)
        let progress = user.xpTotal - currentLevelXP
        let needed = nextLevelXP - currentLevelXP
        let percentage = needed > 0 ? (Double(progress) / Double(needed)) * 100.0 : 100.0

        return Envelope(
            data: LevelInfoDTO(
                level: user.level,
                title: Self.levelTitle(user.level),
                xpTotal: user.xpTotal,
                xpForCurrentLevel: currentLevelXP,
                xpForNextLevel: nextLevelXP,
                xpProgress: progress,
                xpNeeded: max(0, needed - progress),
                progressPercentage: min(100.0, percentage)
            ),
            requestID: req.requestID
        )
    }

    // MARK: - XP Calculation

    /// Per BACKEND_API.md Section 10.1 — Server-side point calculation.
    static func calculateBaseXP(type: String, source: String) -> Int? {
        switch type {
        case "workout_logged": return 50 // Default; real calc would use strain from Whoop
        case "sleep_target_met": return 40
        case "recovery_checked": return 10
        case "meal_logged": return 15
        case "nutrition_target_met": return 50
        case "study_session": return 40 // Default; real calc would use duration
        case "streak_maintained": return 25
        case "streak_milestone": return 100
        case "challenge_joined": return 10
        case "challenge_won": return 200
        case "friend_added": return 5
        case "insight_viewed": return 10
        case "achievement_unlocked": return 50
        default: return nil
        }
    }

    /// Streak multiplier: +2% per streak day, capped at 50% bonus (25 days).
    static func streakMultiplier(for streakDays: Int) -> Double {
        1.0 + min(0.50, Double(streakDays) * 0.02)
    }

    // MARK: - Level Thresholds
    // Per BACKEND_API.md Section 10.4 — Level system.

    static let levelThresholds: [(level: Int, title: String, xp: Int)] = [
        (1, "Rookie", 0),
        (2, "Beginner", 100),
        (3, "Starter", 500),
        (4, "Consistent", 1_000),
        (5, "Dedicated", 2_500),
        (6, "Driven", 5_000),
        (7, "Focused", 7_500),
        (8, "Optimizer", 10_000),
        (9, "Elite", 15_000),
        (10, "Master", 25_000),
        (11, "Legend", 50_000),
        (12, "Transcendent", 100_000),
    ]

    static func levelTitle(_ level: Int) -> String {
        levelThresholds.first(where: { $0.level == level })?.title ?? "Rookie"
    }

    static func xpForLevel(_ level: Int) -> Int {
        levelThresholds.first(where: { $0.level == level })?.xp ?? 0
    }

    static func xpForNextLevel(_ level: Int) -> Int {
        let nextLevel = level + 1
        return levelThresholds.first(where: { $0.level == nextLevel })?.xp ?? levelThresholds.last?.xp ?? 100_000
    }
}

// MARK: - DTOs

struct XPRecordRequestDTO: Content {
    let events: [XPEventInput]

    struct XPEventInput: Content {
        let type: String
        let source: String
        let referenceID: String?
        let occurredAt: String?
        let metadata: [String: String]?

        enum CodingKeys: String, CodingKey {
            case type, source, metadata
            case referenceID = "reference_id"
            case occurredAt = "occurred_at"
        }
    }
}

struct XPRecordResponseDTO: Content {
    let eventsRecorded: Int
    let eventsSkipped: Int
    let xpEarned: Int
    let xpTotal: Int
    let level: Int
    let levelChanged: Bool
    let nextLevelXP: Int

    enum CodingKeys: String, CodingKey {
        case eventsRecorded = "events_recorded"
        case eventsSkipped = "events_skipped"
        case xpEarned = "xp_earned"
        case xpTotal = "xp_total"
        case level
        case levelChanged = "level_changed"
        case nextLevelXP = "next_level_xp"
    }
}

struct XPTodayDTO: Content {
    let totalXP: Int
    let eventCount: Int
    let breakdown: [XPBreakdownItem]

    enum CodingKeys: String, CodingKey {
        case totalXP = "total_xp"
        case eventCount = "event_count"
        case breakdown
    }
}

struct XPBreakdownItem: Content {
    let source: String
    let xp: Int
    let count: Int
}

struct XPEventDTO: Content {
    let id: String
    let source: String
    let type: String
    let baseXP: Int
    let multipliedXP: Int
    let streakMultiplier: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, source, type
        case baseXP = "base_xp"
        case multipliedXP = "multiplied_xp"
        case streakMultiplier = "streak_multiplier"
        case createdAt = "created_at"
    }
}

struct LevelInfoDTO: Content {
    let level: Int
    let title: String
    let xpTotal: Int
    let xpForCurrentLevel: Int
    let xpForNextLevel: Int
    let xpProgress: Int
    let xpNeeded: Int
    let progressPercentage: Double

    enum CodingKeys: String, CodingKey {
        case level, title
        case xpTotal = "xp_total"
        case xpForCurrentLevel = "xp_for_current_level"
        case xpForNextLevel = "xp_for_next_level"
        case xpProgress = "xp_progress"
        case xpNeeded = "xp_needed"
        case progressPercentage = "progress_percentage"
    }
}

// MARK: - Date ISO8601 Extension

private extension Date {
    var iso8601: String {
        ISO8601DateFormatter().string(from: self)
    }
}
