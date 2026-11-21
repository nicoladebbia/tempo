//
// RecoveryCoachModelTests.swift
// Tempo
//

@testable import Tempo
import XCTest

private final class FakeCoachAPI: RecoveryCoachAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [CoachRecoveryRequest] = []
    var sessions: Result<[CoachSession], Error> = .success([])
    var recovery: Result<CoachRecoveryResponse, Error> = .failure(APIError.timeout)

    var requests: [CoachRecoveryRequest] { lock.withLock { _requests } }

    private var _fetches = 0
    var fetches: Int { lock.withLock { _fetches } }
    /// Runs inside the first fetch, before it answers (e.g. a WHOOP share landing mid-flight).
    var duringFirstFetch: (@MainActor () async -> Void)?

    func recentSessions() async throws -> [CoachSession] {
        let n = lock.withLock { _fetches += 1; return _fetches }
        let answer = sessions // the server answers as of when the request reached it
        if n == 1, let duringFirstFetch { await duringFirstFetch() }
        return try answer.get()
    }

    func recovery(_ request: CoachRecoveryRequest) async throws -> CoachRecoveryResponse {
        lock.withLock { _requests.append(request) }
        return try recovery.get()
    }
}

@MainActor
final class RecoveryCoachModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session() -> CoachSession {
        let end = now.addingTimeInterval(-20 * 60)
        return CoachSession(
            id: "s1", start: end.addingTimeInterval(-80 * 60), end: end, sportName: "soccer",
            strain: 14.8, kilojoules: 3500, averageHeartRate: 150, percentRecorded: 100
        )
    }

    private func response(_ json: String) throws -> CoachRecoveryResponse {
        try JSONDecoder().decode(CoachRecoveryResponse.self, from: Data(json.utf8))
    }

    private func make(api: FakeCoachAPI, health: MockHealthKitService = MockHealthKitService(), waterMl: Int = 0)
        -> (RecoveryCoachModel, RecoveryCoachStore) {
        let store = RecoveryCoachStore(defaults: UserDefaults(suiteName: "coach-m-\(UUID().uuidString)")!, key: "k")
        let n = now
        return (RecoveryCoachModel(api: api, healthKit: health, store: store, waterMl: { _, _ in waterMl }, now: { n }), store)
    }

    private let needs = #"{"status":"needs_weigh_in","missing":["post_weigh_in"],"notes":[],"plan":{"carbs_grams":120,"carb_window_hours":2,"protein_grams":20,"reasons":[],"evidence":[]}}"#
    private let ready = """
    {"status":"ready","missing":[],"notes":[],
     "sweat":{"mass_lost_kg":1.2,"percent_body_mass_lost":1.5,"sweat_liters_raw":1.7,"sweat_liters_low":1.5,"sweat_liters_mid":1.56,"sweat_liters_high":1.6,"is_lower_bound":true,"protocol_quality":"tight","margin_of_error_percent":11,"meets_five_percent_target":false,"assumptions":[]},
     "plan":{"carbs_grams":120,"carb_window_hours":2,"protein_grams":20,"reasons":[],"evidence":[]}}
    """

    func testNothingKnownSendsNilFluidsAndHealthWeights() async throws {
        let api = FakeCoachAPI()
        let s = session()
        api.sessions = .success([s])
        api.recovery = .success(try response(needs))
        let health = MockHealthKitService()
        health.bodyMassSamples = [HealthWeightSample(time: s.start.addingTimeInterval(-600), kg: 78, sourceName: "Withings")]
        let (model, _) = make(api: api, health: health)
        await model.refresh()
        let req = try XCTUnwrap(api.requests.first)
        XCTAssertNil(req.drankLiters)
        XCTAssertEqual(req.sessionId, "s1")
        XCTAssertEqual(req.weighIns.map(\.source), ["withings"])
        XCTAssertEqual(model.startHere?.title, "Weigh yourself now")
        XCTAssertEqual(model.phase, .idle)
    }

    /// The server answers 404 while it has no WHOOP access yet (the phone shares it after its WHOOP check).
    /// That is "nothing to weigh", not an error screen.
    func testServerWithoutWhoopAccessIsQuietNotAnError() async throws {
        let api = FakeCoachAPI()
        api.sessions = .failure(APIError.notFound)
        let (model, _) = make(api: api)
        await model.refresh()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.hasSession)
        XCTAssertTrue(api.requests.isEmpty)
        XCTAssertTrue(model.awaitingWhoopAccess, "the app refreshes again once WHOOP access is shared")

        api.sessions = .success([])
        await model.refresh()
        XCTAssertFalse(model.awaitingWhoopAccess)
    }

    func testA404ThatArrivesAfterTheWhoopShareAsksAgain() async {
        let api = FakeCoachAPI()
        api.sessions = .failure(APIError.notFound)
        let (model, _) = make(api: api)
        api.duringFirstFetch = { [weak model] in
            // The share lands while the launch fetch is still out; its 404 predates the share.
            api.sessions = .success([])
            await model?.whoopAccessShared()
        }
        await model.refresh()
        XCTAssertEqual(api.fetches, 2)
        XCTAssertFalse(model.awaitingWhoopAccess)
    }

    func testAShareAfterA404ReloadsAndAnIdleShareDoesNothing() async {
        let api = FakeCoachAPI()
        let (model, _) = make(api: api)
        await model.whoopAccessShared()
        XCTAssertEqual(api.fetches, 0, "not waiting: an hourly renewal fetches nothing")

        api.sessions = .failure(APIError.notFound)
        await model.refresh()
        api.sessions = .success([])
        await model.whoopAccessShared()
        XCTAssertEqual(api.fetches, 2)
        XCTAssertFalse(model.awaitingWhoopAccess)
    }

    func testBodyMassFallsBackToHealthWhenNoWeighInInWindow() async throws {
        let api = FakeCoachAPI()
        api.sessions = .success([session()])
        api.recovery = .success(try response(needs))
        let (model, _) = make(api: api)
        await model.refresh()
        XCTAssertTrue(try XCTUnwrap(api.requests.first).weighIns.isEmpty)
        XCTAssertEqual(api.requests.first?.bodyMassKg, 75.2) // MockHealthKitService.fetchBodyComposition
    }

    func testQuickAnswerAndWaterLogsAreSummed() async throws {
        let api = FakeCoachAPI()
        api.sessions = .success([session()])
        api.recovery = .success(try response(ready))
        let (model, store) = make(api: api, waterMl: 250)
        store.recordQuickAnswer(sessionID: "s1", bottles: 1, now: now)
        await model.refresh()
        XCTAssertEqual(try XCTUnwrap(api.requests.first?.drankLiters), 1.0, accuracy: 0.0001)
        XCTAssertNil(model.startHere)
    }

    func testOfflineKeepsLastResultAndFlagsIt() async throws {
        let api = FakeCoachAPI()
        api.sessions = .success([session()])
        api.recovery = .success(try response(ready))
        let (model, _) = make(api: api)
        await model.refresh()
        XCTAssertFalse(model.isOfflineResult)
        api.sessions = .failure(APIError.timeout)
        api.recovery = .failure(APIError.timeout)
        await model.refresh()
        XCTAssertTrue(model.isOfflineResult)
        XCTAssertEqual(model.result?.status, .ready)
        XCTAssertEqual(model.phase, .idle)
    }

    func testErrorWithNothingCachedFails() async {
        let api = FakeCoachAPI()
        api.sessions = .failure(APIError.timeout)
        let (model, _) = make(api: api)
        await model.refresh()
        guard case .failed = model.phase else { return XCTFail("expected failed, got \(model.phase)") }
        XCTAssertFalse(model.hasSession)
    }

    func testNoSessionsMeansIdleAndHidden() async {
        let api = FakeCoachAPI()
        let (model, _) = make(api: api)
        await model.refresh()
        XCTAssertFalse(model.hasSession)
        XCTAssertEqual(model.phase, .idle)
    }

    func testManualWeighInIsSentAndRecomputes() async throws {
        let api = FakeCoachAPI()
        let s = session()
        api.sessions = .success([s])
        api.recovery = .success(try response(needs))
        let (model, _) = make(api: api)
        await model.refresh()
        await model.addManualWeighIn(kg: 77, at: s.end.addingTimeInterval(300))
        XCTAssertEqual(api.requests.count, 2)
        XCTAssertEqual(api.requests.last?.weighIns.map(\.kg), [77])
        XCTAssertEqual(api.requests.last?.weighIns.first?.source, "manual")
    }

    func testRemovingAManualWeighInSendsTheRestAgain() async throws {
        let api = FakeCoachAPI()
        let s = session()
        api.sessions = .success([s])
        api.recovery = .success(try response(needs))
        let (model, _) = make(api: api)
        await model.refresh()
        await model.addManualWeighIn(kg: 99, at: s.end.addingTimeInterval(300))
        await model.removeManualWeighIn(at: s.end.addingTimeInterval(300))
        XCTAssertTrue(try XCTUnwrap(api.requests.last).weighIns.isEmpty)
    }

    func testClearFluidRemovesTheQuickAnswerToo() async throws {
        let api = FakeCoachAPI()
        api.sessions = .success([session()])
        api.recovery = .success(try response(ready))
        let (model, store) = make(api: api)
        store.recordQuickAnswer(sessionID: "s1", bottles: 1, now: now)
        await model.refresh()
        XCTAssertNotNil(api.requests.last?.drankLiters)
        await model.clearFluid()
        XCTAssertNil(api.requests.last?.drankLiters)
        XCTAssertNil(store.read().quickAnswers["s1"])
    }

    func testChangingTheBottleSizeRepricesAnEarlierAnswer() async throws {
        let api = FakeCoachAPI()
        api.sessions = .success([session()])
        api.recovery = .success(try response(ready))
        let (model, store) = make(api: api)
        store.recordQuickAnswer(sessionID: "s1", bottles: 1, now: now) // 750 mL at the time
        await model.refresh()
        XCTAssertEqual(try XCTUnwrap(api.requests.last?.drankLiters), 0.75, accuracy: 0.0001)
        model.setBottleMl(500)
        await model.recompute()
        XCTAssertEqual(try XCTUnwrap(api.requests.last?.drankLiters), 0.5, accuracy: 0.0001)
    }

    func testRefreshKeepsTheScreensSessionWhenANewerOneNeedsAttention() async throws {
        let api = FakeCoachAPI()
        let a = session()
        let newer = CoachSession(
            id: "newer", start: a.start.addingTimeInterval(30 * 60), end: a.end.addingTimeInterval(30 * 60),
            sportName: nil, strain: nil, kilojoules: nil, averageHeartRate: nil, percentRecorded: nil
        )
        api.sessions = .success([a, newer])
        api.recovery = .success(try response(needs))
        let (model, _) = make(api: api)
        await model.refresh(requestedID: "s1")
        await model.refresh(requestedID: model.session?.id)
        XCTAssertEqual(model.session?.id, "s1")
    }

    func testRequestedSessionWinsOverLatest() async throws {
        let api = FakeCoachAPI()
        let a = session()
        let older = CoachSession(
            id: "old", start: a.start.addingTimeInterval(-6 * 3600), end: a.end.addingTimeInterval(-6 * 3600),
            sportName: nil, strain: nil, kilojoules: nil, averageHeartRate: nil, percentRecorded: nil
        )
        api.sessions = .success([a, older])
        api.recovery = .success(try response(needs))
        let (model, _) = make(api: api)
        await model.refresh(requestedID: "old")
        XCTAssertEqual(model.session?.id, "old")
        XCTAssertEqual(api.requests.first?.sessionId, "old")
    }

    func testWeighInSheetParsing() {
        XCTAssertEqual(try XCTUnwrap(ManualWeighInSheet.kg(from: "78,4", useLb: false)), 78.4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(ManualWeighInSheet.kg(from: "172", useLb: true)), 78.0, accuracy: 0.05)
        XCTAssertNil(ManualWeighInSheet.kg(from: "12", useLb: false))
        XCTAssertNil(ManualWeighInSheet.kg(from: "abc", useLb: false))
        XCTAssertNil(ManualWeighInSheet.kg(from: "", useLb: true))
    }
}
