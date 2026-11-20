import Fluent
import Foundation
import Vapor

// MARK: - Wire types

/// Reads an ISO 8601 date with or without milliseconds, the same way on every platform (the app-wide `.iso8601`
/// decoder is stricter on some builds, and WHOOP and the push both send milliseconds).
enum CoachDateCoding {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>, forKey key: K) throws -> Date {
        if let text = try? container.decode(String.self, forKey: key) {
            guard let date = CoachSessionRules.parseWhoopDate(text) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not an ISO 8601 date")
            }
            return date
        }
        return try container.decode(Date.self, forKey: key)
    }
}

struct CoachWeighInDTO: Content, Equatable, Sendable {
    let time: Date
    let kg: Double
    /// "withings" or "manual".
    let source: String

    init(time: Date, kg: Double, source: String) {
        self.time = time
        self.kg = kg
        self.source = source
    }

    private enum Keys: String, CodingKey { case time, kg, source }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        time = try CoachDateCoding.decode(c, forKey: .time)
        kg = try c.decode(Double.self, forKey: .kg)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "manual"
    }
}

struct CoachRecoveryRequest: Content, Sendable {
    let sessionId: String
    // JSON keys are snake_case on the wire: the app-wide encoder/decoder converts them (configure.swift), so no CodingKeys here.
    /// Start of the session as the app received it from `/coach/sessions/recent`; used to find it again.
    let sessionStart: Date
    let weighIns: [CoachWeighInDTO]
    let drankLiters: Double?
    let urineLiters: Double?
    let hoursUntilNextHardSession: Double?
    /// Coarse location for the weather lookup. Rounded to ~11 km before it leaves the server.
    let latitude: Double?
    let longitude: Double?
    /// Used for the macro targets when no usable weigh-in exists yet.
    let bodyMassKg: Double?
    /// From the user's own 3-readings scale test (see `ScaleCalibration`).
    let scaleRepeatabilitySdKg: Double?

}

struct CoachSweatDTO: Content, Equatable, Sendable {
    let massLostKg: Double
    let percentBodyMassLost: Double
    let sweatLitersRaw: Double?
    let sweatLitersLow: Double?
    let sweatLitersMid: Double?
    let sweatLitersHigh: Double?
    let isLowerBound: Bool
    /// "tight" (both weigh-ins within 30 min of the session) or "loose".
    let protocolQuality: String?
    /// Half-width of the 95% interval around the sweat estimate, as a percent of it.
    let marginOfErrorPercent: Double?
    let meetsFivePercentTarget: Bool
    let assumptions: [String]

}

struct CoachPlanDTO: Content, Equatable, Sendable {
    /// nil when there is no measured sweat (so no fluid or sodium advice).
    let drinkLiters: Double?
    let sodiumMgLow: Double?
    let sodiumMgHigh: Double?
    let sodiumMgPlan: Double?
    let carbsGrams: Double
    let carbWindowHours: Double
    let proteinGrams: Double
    let leucineMgLow: Double
    let leucineMgHigh: Double
    let reasons: [String]
    let evidence: [String]

}

struct CoachRecoveryResponse: Content, Equatable, Sendable {
    /// "ready", "needs_weigh_in" or "implausible".
    let status: String
    let session: CoachSession
    /// Which weigh-ins are still missing: "pre_weigh_in", "post_weigh_in".
    let missing: [String]
    let preWeighIn: CoachWeighInDTO?
    let postWeighIn: CoachWeighInDTO?
    let sweat: CoachSweatDTO?
    let plan: CoachPlanDTO?
    let notes: [String]

}

// MARK: - Engine (pure)

enum CoachRecoveryEngine {
    static let maxWeighIns = 200
    static let validMassKg = 20.0 ... 400.0

    enum ValidationError: Error, Equatable {
        case tooManyWeighIns
        case weightOutOfRange
        case fluidOutOfRange
    }

    /// Everything the endpoint does after the session and weather are known. No I/O, so every branch is testable.
    static func compute(session: CoachSession, request: CoachRecoveryRequest, weather: WeatherConditions?) throws -> CoachRecoveryResponse {
        guard request.weighIns.count <= maxWeighIns else { throw ValidationError.tooManyWeighIns }
        guard request.weighIns.allSatisfy({ validMassKg.contains($0.kg) }) else { throw ValidationError.weightOutOfRange }
        if let b = request.bodyMassKg, !validMassKg.contains(b) { throw ValidationError.weightOutOfRange }
        if let d = request.drankLiters, !(0 ... 20).contains(d) { throw ValidationError.fluidOutOfRange }
        if let u = request.urineLiters, !(0 ... 5).contains(u) { throw ValidationError.fluidOutOfRange }

        let weighIns = request.weighIns.map { WeighIn(time: $0.time, kg: $0.kg, source: WeighIn.Source(rawValue: $0.source) ?? .manual) }
        let summary = session.trainingSummary(weather: weather)
        var scale = ScaleSpec()
        if let sd = request.scaleRepeatabilitySdKg, sd >= 0, sd < 1 {
            scale = ScaleSpec(resolutionKg: scale.resolutionKg, repeatabilitySDKg: sd, isMeasured: true)
        }
        let sweat = SweatBalance.estimate(
            session: summary, weighIns: weighIns,
            fluids: SessionFluids(drankLiters: request.drankLiters, urineLiters: request.urineLiters), scale: scale
        )

        var missing: [String] = []
        if sweat.quality == .needsWeighIn {
            if sweat.pre == nil { missing.append("pre_weigh_in") }
            if sweat.post == nil { missing.append("post_weigh_in") }
            // Both found but out of order (e.g. one reading used as pre and post): ask for the post one again.
            if missing.isEmpty { missing.append("post_weigh_in") }
        }

        // Body mass for the macro targets: the pre weigh-in, else the post one, else what the app sent.
        let bodyMass = sweat.pre?.kg ?? sweat.post?.kg ?? request.bodyMassKg
        let plan: CoachPlanDTO? = bodyMass.map { kg in
            let p = RecoveryPlanner.prescribe(session: summary, sweat: sweat, bodyMassKg: kg,
                                              hoursUntilNextHardSession: request.hoursUntilNextHardSession)
            return CoachPlanDTO(
                drinkLiters: p.fluid?.drinkLiters, sodiumMgLow: p.fluid?.sodiumMgLow, sodiumMgHigh: p.fluid?.sodiumMgHigh,
                sodiumMgPlan: p.fluid?.sodiumMgPlan, carbsGrams: p.macros.carbsGrams, carbWindowHours: p.macros.carbWindowHours,
                proteinGrams: p.macros.proteinGrams, leucineMgLow: p.macros.proteinLeucineMgLow, leucineMgHigh: p.macros.proteinLeucineMgHigh,
                reasons: p.reasons, evidence: p.evidenceNotes
            )
        }

        let sweatDTO: CoachSweatDTO? = sweat.massLostKg.map { lost in
            CoachSweatDTO(
                massLostKg: lost, percentBodyMassLost: sweat.percentBodyMassLost ?? 0, sweatLitersRaw: sweat.sweatLitersRaw,
                sweatLitersLow: sweat.sweatLitersLow, sweatLitersMid: sweat.sweatLitersMid, sweatLitersHigh: sweat.sweatLitersHigh,
                isLowerBound: sweat.isLowerBound, protocolQuality: sweat.protocolQuality?.rawValue,
                marginOfErrorPercent: sweat.uncertainty?.relativeError95Percent,
                meetsFivePercentTarget: sweat.uncertainty?.meetsFivePercentTarget ?? false,
                assumptions: sweat.uncertainty?.assumptions ?? []
            )
        }

        let status: String
        switch sweat.quality {
        case .measured: status = "ready"
        case .needsWeighIn: status = "needs_weigh_in"
        case .implausible: status = "implausible"
        }

        func dto(_ w: WeighIn?) -> CoachWeighInDTO? { w.map { CoachWeighInDTO(time: $0.time, kg: $0.kg, source: $0.source.rawValue) } }
        return CoachRecoveryResponse(
            status: status, session: session, missing: missing, preWeighIn: dto(sweat.pre), postWeighIn: dto(sweat.post),
            sweat: sweatDTO, plan: plan, notes: sweat.notes
        )
    }
}

// MARK: - Controller

struct CoachRecoveryController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("sessions", "recent", use: recentSessions)
        routes.post("recovery", use: recovery)
    }

    /// GET /v1/coach/sessions/recent: finished WHOOP workouts of the last 48 h that are big enough to weigh.
    func recentSessions(_ req: Request) async throws -> Envelope<[CoachSession]> {
        let userID = try req.auth.requireUserID()
        let now = req.now
        let sessions = try await req.application.coachWorkoutSource
            .sessions(for: userID, from: now.addingTimeInterval(-48 * 3600), to: now, on: req)
            .filter(CoachSessionRules.qualifies)
            .sorted { $0.end > $1.end }
        return Envelope(data: sessions, requestID: req.requestID)
    }

    /// POST /v1/coach/recovery: sweat estimate and recovery plan for one session.
    func recovery(_ req: Request) async throws -> Envelope<CoachRecoveryResponse> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(CoachRecoveryRequest.self)

        let found = try await req.application.coachWorkoutSource.sessions(
            for: userID, from: body.sessionStart.addingTimeInterval(-3600), to: body.sessionStart.addingTimeInterval(12 * 3600), on: req
        )
        guard let session = found.first(where: { $0.id == body.sessionId }) else {
            throw Abort(.notFound, reason: "That WHOOP workout was not found.")
        }

        // Weather is a refinement worth about 1% of the result: never let it fail the request.
        var weather: WeatherConditions?
        if let lat = body.latitude, let lon = body.longitude, abs(lat) <= 90, abs(lon) <= 180 {
            weather = try? await req.application.weatherProvider.conditions(
                latitude: lat, longitude: lon, from: session.start, to: session.end, on: req
            )
        }

        do {
            let result = try CoachRecoveryEngine.compute(session: session, request: body, weather: weather)
            return Envelope(data: result, requestID: req.requestID)
        } catch let error as CoachRecoveryEngine.ValidationError {
            switch error {
            case .tooManyWeighIns: throw Abort(.badRequest, reason: "Too many weigh-ins.")
            case .weightOutOfRange: throw Abort(.unprocessableEntity, reason: "A weight is outside 20-400 kg.")
            case .fluidOutOfRange: throw Abort(.unprocessableEntity, reason: "A fluid amount is out of range.")
            }
        }
    }
}
