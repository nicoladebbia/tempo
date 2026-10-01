import Fluent
import SQLKit
import Vapor

// MARK: - Personas (server side)

//
// POST /v1/test/persona {name, persona} → {persona, xp_events, receipts, xp_total, streak_days, pro}
//
// The server half of a "person with history" (sim.sh --scenario <persona>
// seeds the on-device half: workouts, meals, recovery). Here: the
// subscription, weeks of XP events (backdated, so XP today/leaderboard/weekly
// numbers are real), grocery receipts, streak and level. Re-running replaces
// the previous seed. Dates follow the test clock.

extension TestModeController {
    func bootPersona(routes: RoutesBuilder) {
        routes.post("persona", use: seedPersona)
        routes.get("shared", use: sharedLists)
    }

    struct Persona: Sendable {
        let subscription: SubscriptionState
        let subscriptionDays: Double?
        /// Weeks of history.
        let weeks: Int
        /// Days ago the history stops (0 = still going today).
        let stoppedDaysAgo: Int
        /// ISO weekdays (1 = Monday) with a workout.
        let trainingDays: Set<Int>
        /// Days ago training stopped (injury); nil = didn't.
        let trainingStoppedDaysAgo: Int?
        let mealsPerDay: Int
        /// Every Nth day has no meals logged (0 = never misses).
        let missEvery: Int
        let studySessionsPerDay: Int
        let streakDays: Int
        let store: String
        let basket: [(name: String, display: String, quantity: Double, unit: String, price: Double)]
    }

    static let personas: [String: Persona] = [
        "athlete": Persona(
            subscription: .active, subscriptionDays: nil, weeks: 8, stoppedDaysAgo: 0,
            trainingDays: [1, 2, 4, 5], trainingStoppedDaysAgo: nil, mealsPerDay: 4, missEvery: 20,
            studySessionsPerDay: 0, streakDays: 56, store: "Publix",
            basket: [
                ("chicken breast", "Chicken Breast", 1.2, "kg", 10.8), ("white rice", "Jasmine Rice", 2, "kg", 4.5),
                ("oats", "Rolled Oats", 1, "kg", 3.2), ("eggs", "Large Eggs", 12, "pieces", 3.9),
                ("greek yogurt", "Greek Yogurt 0%", 1, "kg", 5.6), ("broccoli", "Broccoli Crowns", 0.5, "kg", 2.1),
            ]
        ),
        "picky-vegan": Persona(
            subscription: .trial, subscriptionDays: 4, weeks: 3, stoppedDaysAgo: 0,
            trainingDays: [1, 3, 5], trainingStoppedDaysAgo: nil, mealsPerDay: 4, missEvery: 9,
            studySessionsPerDay: 0, streakDays: 21, store: "Whole Foods",
            basket: [
                ("lentils", "Red Lentils", 1, "kg", 3.4), ("chickpeas", "Chickpeas (canned)", 4, "cans", 4.0),
                ("seitan", "Seitan", 0.4, "kg", 6.5), ("quinoa", "Quinoa", 1, "kg", 6.9),
                ("spinach", "Baby Spinach", 0.3, "kg", 3.5), ("oat milk", "Oat Milk", 2, "l", 5.0),
            ]
        ),
        "exam-week": Persona(
            subscription: .active, subscriptionDays: nil, weeks: 6, stoppedDaysAgo: 0,
            trainingDays: [1, 3, 5, 6], trainingStoppedDaysAgo: 5, mealsPerDay: 3, missEvery: 6,
            studySessionsPerDay: 3, streakDays: 30, store: "Trader Joe's",
            basket: [
                ("pasta", "Penne", 1, "kg", 2.5), ("eggs", "Eggs", 12, "pieces", 3.5),
                ("instant coffee", "Instant Coffee", 1, "jars", 7.0), ("bananas", "Bananas", 6, "pieces", 1.6),
                ("peanut butter", "Peanut Butter", 1, "jars", 3.0),
            ]
        ),
        "injured": Persona(
            subscription: .active, subscriptionDays: nil, weeks: 6, stoppedDaysAgo: 0,
            trainingDays: [1, 2, 4, 5], trainingStoppedDaysAgo: 4, mealsPerDay: 4, missEvery: 15,
            studySessionsPerDay: 0, streakDays: 42, store: "Publix",
            basket: [
                ("salmon", "Atlantic Salmon", 0.6, "kg", 13.0), ("sweet potato", "Sweet Potatoes", 1.5, "kg", 3.8),
                ("greek yogurt", "Greek Yogurt", 1, "kg", 5.6), ("berries", "Mixed Berries", 0.5, "kg", 5.0),
            ]
        ),
        "lapsed-pro": Persona(
            subscription: .expired, subscriptionDays: 21, weeks: 10, stoppedDaysAgo: 21,
            trainingDays: [1, 3, 5], trainingStoppedDaysAgo: nil, mealsPerDay: 3, missEvery: 10,
            studySessionsPerDay: 0, streakDays: 0, store: "Kroger",
            basket: [
                ("chicken thighs", "Chicken Thighs", 1, "kg", 7.5), ("white rice", "White Rice", 2, "kg", 3.9),
                ("frozen vegetables", "Frozen Stir-Fry Veg", 1, "kg", 4.2),
            ]
        ),
    ]

    struct PersonaRequest: Content {
        let name: String
        let persona: String
    }

    struct PersonaResponse: Content {
        let persona: String
        let xpEvents: Int
        let receipts: Int
        let xpTotal: Int
        let streakDays: Int
        let pro: Bool
    }

    func seedPersona(_ req: Request) async throws -> PersonaResponse {
        _ = try Self.state(req)
        let body = try req.content.decode(PersonaRequest.self)
        guard let persona = Self.personas[body.persona] else {
            let names = Self.personas.keys.sorted().joined(separator: ", ")
            throw Abort(.badRequest, reason: "Unknown persona '\(body.persona)'. Personas: \(names).")
        }
        guard let user = try await User.query(on: req.db)
            .filter(\.$appleUserID == Self.appleUserID(for: body.name)).first()
        else {
            throw Abort(.notFound, reason: "No test user '\(body.name)' — sign in first (sim.sh qa --local --as \(body.name)).")
        }
        let userID = try user.requireID()
        guard let sql = req.db as? SQLDatabase else { throw Abort(.internalServerError, reason: "Needs Postgres.") }

        // Replace any earlier seed.
        try await XPEvent.query(on: req.db).filter(\.$user.$id == userID).delete()
        let oldReceipts = try await Receipt.query(on: req.db).filter(\.$userID == userID).all()
        for receipt in oldReceipts {
            try await ReceiptLineItem.query(on: req.db).filter(\.$receipt.$id == receipt.requireID()).delete()
            try await receipt.delete(on: req.db)
        }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: user.timezone) ?? .current
        let today = calendar.startOfDay(for: req.now)
        let firstDay = persona.weeks * 7 + persona.stoppedDaysAgo - 1

        // XP: one row per thing done, at a plausible time of that day.
        var rows: [(source: String, xp: Int, at: Date)] = []
        for daysAgo in stride(from: firstDay, through: persona.stoppedDaysAgo, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let at = { (hour: Int, minute: Int) in
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            }
            let index = firstDay - daysAgo
            let weekday = calendar.component(.weekday, from: day)
            let isoWeekday = weekday == 1 ? 7 : weekday - 1
            if persona.missEvery == 0 || index % persona.missEvery != persona.missEvery - 1 {
                for meal in 0 ..< persona.mealsPerDay {
                    rows.append(("meal_logged", 15, at(8 + meal * 4, 15)))
                }
                rows.append(("nutrition_target_met", 50, at(21, 0)))
            }
            let trainingStopped = persona.trainingStoppedDaysAgo.map { daysAgo < $0 } ?? false
            if persona.trainingDays.contains(isoWeekday), !trainingStopped {
                rows.append(("workout_logged", 50, at(17, 45)))
            }
            for session in 0 ..< persona.studySessionsPerDay {
                rows.append(("study_session", 40, at(10 + session * 3, 0)))
            }
            rows.append(("recovery_checked", 10, at(7, 30)))
            if persona.streakDays > 0, daysAgo < persona.streakDays, index % 7 == 6 {
                rows.append(("streak_maintained", 25, at(21, 5)))
            }
        }
        // Insert with created_at set (Fluent's @Timestamp would stamp "now").
        for chunk in stride(from: 0, to: rows.count, by: 200) {
            var insert = sql.insert(into: XPEvent.schema)
                .columns("id", "user_id", "source", "base_xp", "multiplied_xp", "streak_multiplier", "flagged", "created_at")
            for row in rows[chunk ..< min(chunk + 200, rows.count)] {
                insert = insert.values(
                    SQLBind(UUID()), SQLBind(userID), SQLBind(row.source), SQLBind(row.xp), SQLBind(row.xp),
                    SQLBind(1.0), SQLBind(false), SQLBind(row.at)
                )
            }
            try await insert.run()
        }

        // A weekly shop on Sundays.
        var receipts = 0
        for week in 0 ..< persona.weeks {
            let daysAgo = persona.stoppedDaysAgo + week * 7 + 1
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let at = calendar.date(bySettingHour: 11, minute: 30, second: 0, of: day)
            else { continue }
            let total = persona.basket.reduce(0) { $0 + $1.price }
            let receipt = Receipt(userID: userID, store: persona.store, purchaseDate: at, totalAmount: total, ocrStatus: "complete")
            receipt.createdAt = at
            receipt.updatedAt = at
            receipt.userReviewed = true
            try await receipt.save(on: req.db)
            for item in persona.basket {
                let line = ReceiptLineItem(
                    receiptID: try receipt.requireID(), rawText: item.display.uppercased(),
                    canonicalFoodName: item.name, displayName: item.display, quantity: item.quantity,
                    unit: item.unit, totalPrice: item.price, confidence: 0.95
                )
                line.userConfirmed = true
                line.createdAt = at
                try await line.save(on: req.db)
            }
            receipts += 1
        }

        user.xpTotal = rows.reduce(0) { $0 + $1.xp }
        user.level = User.levelForXP(user.xpTotal)
        user.streakDays = persona.streakDays
        try await user.save(on: req.db)

        try await Self.applySubscription(persona.subscription, days: persona.subscriptionDays, userID: userID, on: req)
        try? await LeaderboardRefreshJob().refresh(app: req.application)

        return PersonaResponse(
            persona: body.persona,
            xpEvents: rows.count,
            receipts: receipts,
            xpTotal: user.xpTotal,
            streakDays: user.streakDays,
            pro: try await ProEntitlement.isUserPro(userID: userID, on: req)
        )
    }
}

// MARK: - Shared grocery lists

//
// GET /v1/test/shared?name= → the user's live share links, to open as the
// shopper (scripts/testenv.sh shared <name>; sim.sh --sim b open <url>).

extension TestModeController {
    struct SharedListInfo: Content {
        let title: String
        let url: String
        let items: Int
        let expiresAt: Date
    }

    func sharedLists(_ req: Request) async throws -> [SharedListInfo] {
        _ = try Self.state(req)
        guard let id = try await Self.userFilter(req), id != "__none__" else {
            throw Abort(.notFound, reason: "No such test user.")
        }
        let base = GroceryShareController.publicBaseURL(req: req)
        return try await SharedGroceryList.query(on: req.db)
            .filter(\.$userID == id)
            .filter(\.$revoked == false)
            .sort(\.$createdAt, .descending)
            .all()
            .map { list in
                SharedListInfo(
                    title: list.title,
                    url: "\(base)/g/\(list.token)",
                    items: list.decodedItems().count,
                    expiresAt: list.expiresAt
                )
            }
    }
}
