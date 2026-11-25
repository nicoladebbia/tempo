//
// PlanStatusTests.swift
// Tempo
//
// The Subscription page says what plan the user really has. These cover how the
// server's answer (what the gates use) and the App Store's answer (on this
// device) become that one plan, in every state.
//

@testable import Tempo
import XCTest

// MARK: - PlanStatusTests

final class PlanStatusTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86400
    private let monthly = SubscriptionProduct.monthly.rawValue

    // MARK: - The headline bug

    func testServerSaysPro_deviceSaysFree_isPro() {
        // An allowlisted or server-side Pro account used to read "Free".
        let status = PlanStatus.resolve(server: ServerPlan(isPro: true), device: .free)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.kind, .included)
        XCTAssertEqual(status.title, "Pro · Included")
        XCTAssertNil(status.action, "nothing to buy or manage when Pro comes with the account")
        XCTAssertNil(status.notice)
    }

    func testServerSubscription_withNothingOnDevice_showsTheServersDates() {
        let end = now.addingTimeInterval(9 * day)
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true, productId: monthly, expiresAt: end), device: .free
        )
        XCTAssertEqual(status.kind, .active)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.date, end)
        XCTAssertEqual(status.dateLabel, "Active until", "the server can't say whether it renews")
        XCTAssertEqual(status.productName, "Monthly")
        XCTAssertEqual(status.countdownUnit(days: 9), "days of Pro left", "it must not promise a renewal the server doesn't know about")
    }

    func testFreeEverywhere_isFreeWithPaywall() {
        let status = PlanStatus.resolve(server: ServerPlan(isPro: false), device: .free)
        XCTAssertFalse(status.isPro)
        XCTAssertEqual(status.kind, .free)
        XCTAssertEqual(status.title, "Free")
        XCTAssertEqual(status.action, .showPaywall)
    }

    func testServerNotAnsweredYet_fallsBackToTheDevice() {
        XCTAssertEqual(PlanStatus.resolve(server: nil, device: .free).kind, .free)
        let trial = SubscriptionState.trial(startDate: now, endDate: now.addingTimeInterval(7 * day))
        XCTAssertEqual(PlanStatus.resolve(server: nil, device: trial).kind, .trial)
    }

    // MARK: - Each state

    func testTrial() {
        let start = now.addingTimeInterval(-2 * day)
        let end = now.addingTimeInterval(5 * day)
        let status = PlanStatus.resolve(server: ServerPlan(isPro: true), device: .trial(startDate: start, endDate: end))
        XCTAssertEqual(status.kind, .trial)
        XCTAssertEqual(status.title, "Pro · Trial")
        XCTAssertEqual(status.dateLabel, "Trial ends")
        XCTAssertEqual(status.daysLeft(now: now), 5)
        XCTAssertEqual(status.countdownUnit(days: 5), "days of trial left")
        let progress = try? XCTUnwrap(status.trialProgress(now: now))
        XCTAssertEqual(progress ?? 0, 2.0 / 7.0, accuracy: 0.001)
    }

    func testActiveRenewing() {
        let end = now.addingTimeInterval(12 * day)
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true),
            device: .active(productId: monthly, expirationDate: end, isAutoRenewing: true)
        )
        XCTAssertEqual(status.kind, .active)
        XCTAssertEqual(status.title, "Pro")
        XCTAssertEqual(status.dateLabel, "Renews")
        XCTAssertEqual(status.countdownUnit(days: 12), "days to renewal")
        XCTAssertEqual(status.action, .manageInAppStore)
    }

    func testCancelled_renewalOff_staysProUntilTheEnd() {
        let end = now.addingTimeInterval(4 * day)
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true),
            device: .active(productId: monthly, expirationDate: end, isAutoRenewing: false)
        )
        XCTAssertEqual(status.kind, .cancelled)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.title, "Pro · Ends soon")
        XCTAssertEqual(status.dateLabel, "Ends")
        XCTAssertEqual(status.date, end)
        XCTAssertEqual(status.countdownUnit(days: 1), "day until it ends")
        XCTAssertEqual(status.actionTitle, "Turn renewal back on")
    }

    func testGracePeriod_staysProAndAsksToFixPayment() {
        let end = now.addingTimeInterval(6 * day)
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true),
            device: .gracePeriod(productId: monthly, graceEndDate: end)
        )
        XCTAssertEqual(status.kind, .grace)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.dateLabel, "Fix it by")
        XCTAssertEqual(status.actionTitle, "Update payment method")
        XCTAssertEqual(status.action, .manageInAppStore)
    }

    func testExpired_isNotProAndOffersToSubscribeAgain() {
        let ended = now.addingTimeInterval(-3 * day)
        for device in [
            SubscriptionState.expired(lastProductId: monthly, expiredAt: ended),
            SubscriptionState.churned(lastProductId: monthly, expiredAt: ended),
        ] {
            let status = PlanStatus.resolve(server: ServerPlan(isPro: false), device: device)
            XCTAssertEqual(status.kind, .expired)
            XCTAssertFalse(status.isPro)
            XCTAssertEqual(status.title, "Expired")
            XCTAssertEqual(status.dateLabel, "Ended")
            XCTAssertEqual(status.action, .showPaywall)
            XCTAssertNil(status.daysLeft().flatMap { status.countdownUnit(days: $0) })
        }
    }

    func testExpiredOnDevice_butServerStillSaysPro_isPro() {
        // The gates decide: an allowlisted account with a lapsed purchase is Pro.
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true),
            device: .expired(lastProductId: monthly, expiredAt: now.addingTimeInterval(-day))
        )
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.kind, .included)
    }

    // MARK: - Disagreement

    func testDevicePro_serverSaysNot_warnsTheUser() {
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: false),
            device: .active(productId: monthly, expirationDate: now.addingTimeInterval(20 * day), isAutoRenewing: true)
        )
        XCTAssertTrue(status.isPro, "the purchase is real, so the plan is shown")
        XCTAssertNotNil(status.notice, "but the gates won't open until the server agrees, and the page says so")
    }

    func testAgreement_hasNoNotice() {
        let status = PlanStatus.resolve(
            server: ServerPlan(isPro: true),
            device: .active(productId: monthly, expirationDate: now.addingTimeInterval(20 * day), isAutoRenewing: true)
        )
        XCTAssertNil(status.notice)
    }

    // MARK: - Countdown maths

    func testDaysLeft_roundsUpAndNeverGoesNegative() {
        let soon = PlanStatus.resolve(
            server: nil,
            device: .trial(startDate: now.addingTimeInterval(-6 * day), endDate: now.addingTimeInterval(0.2 * day))
        )
        XCTAssertEqual(soon.daysLeft(now: now), 1)
        let over = PlanStatus.resolve(
            server: nil,
            device: .trial(startDate: now.addingTimeInterval(-8 * day), endDate: now.addingTimeInterval(-day))
        )
        XCTAssertEqual(over.daysLeft(now: now), 0)
        XCTAssertEqual(PlanStatus.resolve(server: nil, device: .free).daysLeft(now: now), nil)
    }

    func testServerPlan_readsTheMeResponse() throws {
        let json = """
        {"id":"u","display_name":"A","username":"a","timezone":"UTC","xp_total":0,"level":1,"streak_days":0,
         "is_pro":true,"product_id":"app.tempo.Tempo.pro.annual","subscription_expires_at":"2026-12-24T10:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let me = try decoder.decode(UserMeResponseDTO.self, from: Data(json.utf8))
        let plan = ServerPlan(me)
        XCTAssertTrue(plan.isPro)
        XCTAssertEqual(plan.productId, "app.tempo.Tempo.pro.annual")
        XCTAssertNotNil(plan.expiresAt)
    }
}

// MARK: - StoreEntitlementTests

final class StoreEntitlementTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 86400
    private let product = SubscriptionProduct.annual.rawValue

    private func entitlement(
        expires: TimeInterval?, intro: Bool = false, renewal: StoreEntitlement.Renewal
    ) -> StoreEntitlement {
        StoreEntitlement(
            productId: product,
            purchaseDate: now.addingTimeInterval(-2 * day),
            expirationDate: expires.map { now.addingTimeInterval($0) },
            isIntroOffer: intro,
            renewal: renewal
        )
    }

    func testIntroOffer_isATrial() {
        let state = SubscriptionState.resolve(entitlement(expires: 5 * day, intro: true, renewal: .willRenew), now: now)
        XCTAssertEqual(state, .trial(startDate: now.addingTimeInterval(-2 * day), endDate: now.addingTimeInterval(5 * day)))
    }

    func testRenewing_isActiveAutoRenewing() {
        let state = SubscriptionState.resolve(entitlement(expires: 20 * day, renewal: .willRenew), now: now)
        XCTAssertEqual(state, .active(productId: product, expirationDate: now.addingTimeInterval(20 * day), isAutoRenewing: true))
    }

    func testUnknownRenewal_isTreatedAsRenewing() {
        guard case let .active(_, _, renews) = SubscriptionState.resolve(entitlement(expires: 20 * day, renewal: .unknown), now: now) else {
            return XCTFail("expected active")
        }
        XCTAssertTrue(renews)
    }

    func testRenewalOff_isActiveNotAutoRenewing() {
        guard case let .active(_, _, renews) = SubscriptionState.resolve(entitlement(expires: 4 * day, renewal: .willNotRenew), now: now)
        else {
            return XCTFail("expected active")
        }
        XCTAssertFalse(renews)
    }

    func testTrialWithRenewalOff_isStillATrial() {
        let state = SubscriptionState.resolve(entitlement(expires: 3 * day, intro: true, renewal: .willNotRenew), now: now)
        guard case .trial = state else {
            return XCTFail("expected trial, got \(state)")
        }
    }

    func testGracePeriod_keepsProEvenThoughThePeriodEnded() {
        let state = SubscriptionState.resolve(
            entitlement(expires: -day, renewal: .gracePeriod(until: now.addingTimeInterval(6 * day))),
            now: now
        )
        XCTAssertEqual(state, .gracePeriod(productId: product, graceEndDate: now.addingTimeInterval(6 * day)))
        XCTAssertTrue(state.isPro)
    }

    func testGracePeriodWithoutADate_fallsBackToTheExpiry() {
        let state = SubscriptionState.resolve(entitlement(expires: 2 * day, renewal: .gracePeriod(until: nil)), now: now)
        XCTAssertEqual(state, .gracePeriod(productId: product, graceEndDate: now.addingTimeInterval(2 * day)))
    }

    func testBillingRetry_isNotPro() {
        let state = SubscriptionState.resolve(entitlement(expires: -2 * day, renewal: .billingRetry), now: now)
        XCTAssertFalse(state.isPro)
        guard case .expired = state else {
            return XCTFail("expected expired, got \(state)")
        }
    }

    func testRevoked_isNotProEvenBeforeTheEnd() {
        let state = SubscriptionState.resolve(entitlement(expires: 10 * day, renewal: .revoked), now: now)
        XCTAssertFalse(state.isPro)
    }

    func testPastExpiry_isExpiredThenChurned() {
        let recent = SubscriptionState.resolve(entitlement(expires: -5 * day, renewal: .expired), now: now)
        guard case .expired = recent else {
            return XCTFail("expected expired, got \(recent)")
        }
        let old = SubscriptionState.resolve(entitlement(expires: -45 * day, renewal: .expired), now: now)
        guard case .churned = old else {
            return XCTFail("expected churned, got \(old)")
        }
    }

    func testNoExpiryAndNoRenewalInfo_isNotPro() {
        XCTAssertFalse(SubscriptionState.resolve(entitlement(expires: nil, renewal: .unknown), now: now).isPro)
    }

    func testPastExpiry_withoutRenewalInfo_isNotPro() {
        XCTAssertFalse(SubscriptionState.resolve(entitlement(expires: -day, renewal: .unknown), now: now).isPro)
    }

    #if DEBUG
        func testDebugSamples_coverEveryStateAndRejectUnknownNames() {
            for name in ["free", "trial", "active", "cancelled", "grace", "expired"] {
                XCTAssertNotNil(SubscriptionState.debugSample(named: name), name)
            }
            XCTAssertNil(SubscriptionState.debugSample(named: "bogus"))
            XCTAssertTrue(SubscriptionState.debugSample(named: "grace")?.isPro ?? false)
            XCTAssertFalse(SubscriptionState.debugSample(named: "expired")?.isPro ?? true)
        }
    #endif
}

// MARK: - PlanModelTests

@MainActor
final class PlanModelTests: XCTestCase {
    private struct Offline: Error {}

    func testRefresh_storesTheServersAnswer() async {
        let model = PlanModel()
        XCTAssertEqual(model.load, .idle)
        await model.refresh { ServerPlan(isPro: true) }
        XCTAssertEqual(model.load, .loaded)
        XCTAssertEqual(model.status(device: .free).kind, .included)
    }

    func testFailedRefresh_keepsTheLastAnswer() async {
        let model = PlanModel()
        await model.refresh { ServerPlan(isPro: true) }
        await model.refresh { throw Offline() }
        XCTAssertEqual(model.load, .failed)
        XCTAssertEqual(model.server, ServerPlan(isPro: true), "a Pro account must not flip to Free when the network drops")
    }

    func testFailedFirstRefresh_fallsBackToTheDevice() async {
        let model = PlanModel()
        await model.refresh { throw Offline() }
        XCTAssertEqual(model.load, .failed)
        XCTAssertNil(model.server)
        XCTAssertEqual(model.status(device: .free).kind, .free)
    }
}
