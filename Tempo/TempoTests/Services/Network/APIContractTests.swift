//
// APIContractTests.swift
// Tempo
//
// App <-> server contract: decodes the JSON the SERVER really sends
// (contracts/golden/*.json, written by the backend's ContractGoldenTests)
// with the app's real DTOs, through APIClient's own decode path. A key the
// server renamed, or one the app spells differently, fails here instead of
// silently on a phone. Also asserts key fields are non-default, so a
// missing optional key can't pass unnoticed.
//
// A failure here is a real bug. Don't change the assertion to match: fix the
// DTO or the server, or (if it's a known bug) wrap it in XCTExpectFailure
// with a description. See contracts/README.md.
//

@testable import Tempo
import UserNotifications
import XCTest

final class APIContractTests: XCTestCase {
    // MARK: - Helpers

    /// Every golden file, so a new route can't be added server-side without an iOS test.
    private static let covered: Set<String> = [
        "auth-apple", "auth-refresh",
        "user-me-get", "user-me-delete", "user-ai-consent", "user-accept-tos", "user-daily-plan-profile-put",
        "devices-register", "devices-delete",
        "insights-training-program", "nutrition-ai-meal-timing", "insights-study-schedule",
        "supplements-lookup", "supplements-picks-verified", "supplements-picks-unverified",
        "grocery-shared-put", "grocery-shared-get", "grocery-shared-revoke", "grocery-instacart-cart",
        "exercise-images-post",
        "program-import-transcribe", "program-import-structure", "program-import-quota", "program-import-feedback",
        "nutrition-ai-coach-chat", "nutrition-ai-coach-chat-text",
        "nutrition-ai-proxy-text", "nutrition-ai-proxy-vision",
        "nutrition-ai-explain-adjustment", "nutrition-ai-suggest-meal",
        "nutrition-receipts-structure", "nutrition-receipt-aliases-confirm",
        "nutrition-weekly-plans-post", "nutrition-weekly-plans-get",
        "nutrition-weekly-plans-latest", "nutrition-weekly-plans-latest-none",
        "foods-search",
        "push-meal_plan_ready", "push-recovery_morning", "push-general",
    ]

    private func goldenData(_ slug: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: slug, withExtension: "json", subdirectory: "golden"),
            "contracts/golden/\(slug).json is not in the test bundle",
            file: file, line: line
        )
        return try Data(contentsOf: url)
    }

    /// Decodes exactly like `APIClient` (same decoder, same envelope unwrap).
    private func decode<T: Decodable & Sendable>(
        _ slug: String, as _: T.Type = T.self, envelope: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> T {
        let data = try goldenData(slug, file: file, line: line)
        do {
            return try APIClient.decodeBody(data, as: T.self, expectsEnvelope: envelope)
        } catch {
            // APIClient flattens the error to a string; re-decode to show WHICH key broke.
            let detail: String
            do {
                if envelope {
                    _ = try APIClient.makeDecoder().decode(APIEnvelope<T>.self, from: data)
                } else {
                    _ = try APIClient.makeDecoder().decode(T.self, from: data)
                }
                detail = "\(error)"
            } catch let inner {
                detail = "\(inner)"
            }
            XCTFail("\(slug).json no longer decodes as \(T.self): \(detail)", file: file, line: line)
            throw error
        }
    }

    private func date(_ iso: String = "2026-01-01T00:00:00Z") throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    /// Decodes `APIEnvelope<EmptyResponse>`: routes whose body the app ignores still have to be `{ok:true}`.
    private func assertEnvelopeOK(_ slug: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let envelope = try APIClient.makeDecoder().decode(APIEnvelope<EmptyResponse>.self, from: goldenData(slug))
        XCTAssertTrue(envelope.ok, file: file, line: line)
    }

    func testEveryGoldenFileHasAnIOSContractTest() throws {
        let bundle = Bundle(for: Self.self)
        let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "golden") ?? []
        let onDisk = Set(urls.map { $0.deletingPathExtension().lastPathComponent })
        XCTAssertFalse(onDisk.isEmpty, "no golden files in the test bundle: is contracts/golden a TempoTests resource?")
        XCTAssertEqual(onDisk.subtracting(Self.covered), [], "golden files with no iOS test: add one to APIContractTests")
        XCTAssertEqual(Self.covered.subtracting(onDisk), [], "iOS tests for goldens the server test no longer writes")
    }

    // MARK: - Auth + user

    func testAuthApple() throws {
        let r: AuthTokenResponse = try decode("auth-apple", envelope: false)
        XCTAssertFalse(r.accessToken.isEmpty)
        XCTAssertFalse(r.refreshToken.isEmpty)
        XCTAssertEqual(r.tokenType, "Bearer")
        XCTAssertEqual(r.expiresIn, 900)
    }

    func testAuthRefresh() throws {
        let r: AuthTokenResponse = try decode("auth-refresh", envelope: false)
        XCTAssertFalse(r.accessToken.isEmpty)
        XCTAssertTrue(r.refreshToken.hasPrefix("rt_"))
        XCTAssertEqual(r.tokenType, "Bearer")
        XCTAssertEqual(r.expiresIn, 900)
    }

    func testUserMe() throws {
        let r: UserMeResponseDTO = try decode("user-me-get")
        XCTAssertTrue(r.id.hasPrefix("usr_"))
        XCTAssertFalse(r.displayName.isEmpty)
        XCTAssertFalse(r.username.isEmpty)
        XCTAssertEqual(r.timezone, "America/New_York")
        XCTAssertTrue(r.isPro)
        XCTAssertEqual(r.productId, "tempo_pro_monthly")
        XCTAssertEqual(r.subscriptionExpiresAt, try date())
        XCTAssertEqual(r.aiConsentAt, try date())
        XCTAssertEqual(r.tosAcceptedAt, try date())
        XCTAssertEqual(r.level, 1)
    }

    func testAccountDeletion() throws {
        let r: AccountDeletionResponseDTO = try decode("user-me-delete")
        XCTAssertEqual(r.deletedAt, try date())
    }

    func testAIConsent() throws {
        let r: AIConsentResponseDTO = try decode("user-ai-consent")
        XCTAssertEqual(r.aiConsentAt, try date())
    }

    func testAcceptToS() throws {
        let r: AcceptToSResponseDTO = try decode("user-accept-tos")
        XCTAssertEqual(r.tosAcceptedAt, try date())
    }

    func testDailyPlanProfilePutIsAnOKEnvelope() throws {
        try assertEnvelopeOK("user-daily-plan-profile-put")
    }

    // MARK: - Devices

    func testDeviceRegister() throws {
        let r: DeviceTokenRegisterResponseDTO = try decode("devices-register")
        XCTAssertFalse(r.id.isEmpty)
        XCTAssertTrue(r.registered)
    }

    func testDeviceDeleteIsAnOKEnvelope() throws {
        try assertEnvelopeOK("devices-delete")
    }

    // MARK: - Insights

    func testTrainingProgram() throws {
        let r: DayPlanTrainingProgramResponse = try decode("insights-training-program")
        XCTAssertFalse(r.rationale.isEmpty)
        let days = try XCTUnwrap(r.days, "server sends `days` but the app read none")
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].day, "monday")
        XCTAssertEqual(days[0].workoutType, "push")
        XCTAssertEqual(days[0].volumeAdjustment, 1.0, accuracy: 0.001)
    }

    func testMealTiming() throws {
        let r: DayPlanMealTimingResponse = try decode("nutrition-ai-meal-timing")
        XCTAssertEqual(r.suggestedTime, "13:30")
        XCTAssertFalse(r.note.isEmpty)
    }

    func testStudySchedule() throws {
        let r: DayPlanStudyScheduleResponse = try decode("insights-study-schedule")
        XCTAssertFalse(r.rationale.isEmpty)
    }

    // MARK: - Supplements

    func testSupplementLookup() throws {
        let r: SupplementLookupDTO = try decode("supplements-lookup")
        XCTAssertEqual(r.upc, "012345678905")
        XCTAssertEqual(r.brand, "Test Labs")
        XCTAssertEqual(r.kind, "creatine")
        XCTAssertNotNil(r.dosePerServing)
        XCTAssertEqual(r.servingsPerContainer, 100)
        XCTAssertNotNil(r.proteinGramsPerServing)
        XCTAssertFalse(r.certifications.isEmpty)
        XCTAssertEqual(r.source, "dsld")
    }

    func testSupplementPicksVerified() throws {
        let r: SupplementPicksDTO = try decode("supplements-picks-verified")
        XCTAssertEqual(r.kind, "creatine")
        XCTAssertTrue(r.verified)
        XCTAssertNotNil(r.lookFor)
        let pick = try XCTUnwrap(r.picks.first)
        XCTAssertFalse(pick.brand.isEmpty)
        XCTAssertFalse(pick.why.isEmpty)
        XCTAssertNotNil(pick.approxPricePerServingUSD, "price key drifted between server and app")
        XCTAssertNotNil(pick.priceAsOf)
        XCTAssertFalse(pick.buyLinks.isEmpty)
    }

    func testSupplementPicksUnverified() throws {
        let r: SupplementPicksDTO = try decode("supplements-picks-unverified")
        XCTAssertFalse(r.verified)
        let pick = try XCTUnwrap(r.picks.first)
        XCTAssertEqual(pick.approxPricePerServingUSD, 0.89)
        XCTAssertEqual(pick.priceAsOf, "2026-09")
        XCTAssertEqual(pick.form, "powder")
        XCTAssertEqual(pick.buyLinks.first?.label, "Amazon")
        XCTAssertNotNil(r.lookFor)
    }

    // MARK: - Grocery + exercise images

    private func assertShare(_ r: GroceryShareDTO, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(r.token.count, 40, file: file, line: line)
        XCTAssertTrue(r.url.contains(r.token), file: file, line: line)
        XCTAssertEqual(r.title, "Week list", file: file, line: line)
        XCTAssertEqual(r.store, "Publix", file: file, line: line)
        XCTAssertEqual(r.expiresAt, try date(), file: file, line: line)
        XCTAssertFalse(r.revoked, file: file, line: line)
        let item = try XCTUnwrap(r.items.first, file: file, line: line)
        XCTAssertEqual(item.name, "Oats", file: file, line: line)
        XCTAssertEqual(item.quantity, 2.5, file: file, line: line)
        XCTAssertEqual(item.unit, "kg", file: file, line: line)
        XCTAssertEqual(item.category, "pantry", file: file, line: line)
        XCTAssertTrue(item.checked, file: file, line: line)
        XCTAssertEqual(item.updatedAt, try date(), file: file, line: line)
    }

    func testGroceryShareUpsert() throws {
        try assertShare(decode("grocery-shared-put"))
    }

    func testGroceryShareGet() throws {
        try assertShare(decode("grocery-shared-get"))
    }

    func testGroceryShareRevokeIsAnOKEnvelope() throws {
        try assertEnvelopeOK("grocery-shared-revoke")
    }

    func testInstacartCart() throws {
        let r: InstacartCartResponseDTO = try decode("grocery-instacart-cart")
        XCTAssertTrue(r.url.hasPrefix("https://"))
    }

    func testExerciseImage() throws {
        let r: ExerciseImageGenerateResponseDTO = try decode("exercise-images-post")
        XCTAssertEqual(r.slug, "barbell-squat")
        XCTAssertTrue(r.url.hasSuffix("/v1/exercise-images/barbell-squat"))
        XCTAssertEqual(r.status, "ready")
    }

    // MARK: - Program import

    func testProgramImportTranscribe() throws {
        let r: ProgramImportTranscribeResponseDTO = try decode("program-import-transcribe")
        XCTAssertEqual(r.pages.count, 2)
        XCTAssertFalse(r.pages[0].isEmpty)
    }

    func testProgramImportStructure() throws {
        let r: ProgramImportStructureResponseDTO = try decode("program-import-structure")
        XCTAssertFalse(r.text.isEmpty)
    }

    func testProgramImportQuota() throws {
        let r: ProgramImportQuotaResponseDTO = try decode("program-import-quota")
        XCTAssertFalse(r.isPro)
        XCTAssertEqual(r.limit, 2)
        XCTAssertEqual(r.remaining, 2)
        XCTAssertEqual(r.used, 0)
        XCTAssertEqual(r.resetsAt, try date())
    }

    func testProgramImportFeedback() throws {
        let r: ProgramFeedbackResponseDTO = try decode("program-import-feedback")
        XCTAssertFalse(r.text.isEmpty)
    }

    // MARK: - Coach + nutrition AI

    func testCoachChatToolUse() throws {
        let r: CoachChatProxyResponse = try decode("nutrition-ai-coach-chat")
        XCTAssertEqual(r.stopReason, "tool_use", "stop_reason key drifted between server and app")
        XCTAssertEqual(r.usage.inputTokens, 1200)
        XCTAssertEqual(r.usage.outputTokens, 85)
        XCTAssertEqual(r.model, "claude-haiku-4-5")
        XCTAssertEqual(r.content.count, 2)
        guard case let .text(text) = r.content[0] else { return XCTFail("block 0 should be text") }
        XCTAssertEqual(text, "Logging that.")
        guard case let .toolUse(id, name, inputJSON) = r.content[1] else { return XCTFail("block 1 should be tool_use") }
        XCTAssertEqual(id, "toolu_01")
        XCTAssertEqual(name, "log_meal")
        let input = try XCTUnwrap(JSONSerialization.jsonObject(with: inputJSON) as? [String: Any])
        XCTAssertEqual(input["food"] as? String, "oats")
        XCTAssertEqual(input["grams"] as? Int, 80)
    }

    func testCoachChatText() throws {
        let r: CoachChatProxyResponse = try decode("nutrition-ai-coach-chat-text")
        XCTAssertEqual(r.stopReason, "end_turn")
        guard case let .text(text) = try XCTUnwrap(r.content.first) else { return XCTFail("should be text") }
        XCTAssertFalse(text.isEmpty)
    }

    func testNutritionProxyText() throws {
        let r: NutritionProxyTextResponse = try decode("nutrition-ai-proxy-text")
        XCTAssertFalse(r.text.isEmpty)
    }

    func testNutritionProxyVision() throws {
        let r: NutritionProxyTextResponse = try decode("nutrition-ai-proxy-vision")
        XCTAssertFalse(r.text.isEmpty)
    }

    func testExplainAdjustment() throws {
        let r: NutritionAIExplainResponse = try decode("nutrition-ai-explain-adjustment")
        XCTAssertFalse(r.message.isEmpty)
    }

    func testSuggestMeal() throws {
        let r: NutritionAISuggestResponse = try decode("nutrition-ai-suggest-meal")
        XCTAssertFalse(r.message.isEmpty)
    }

    // MARK: - Receipts

    func testReceiptStructure() throws {
        let r: ReceiptStructuringResponse = try decode("nutrition-receipts-structure")
        XCTAssertEqual(r.store, "Publix")
        XCTAssertNotNil(r.purchaseDate)
        XCTAssertEqual(r.totalAmount, 41.27)
        XCTAssertEqual(r.taxAmount, 1.12)
        XCTAssertEqual(r.paymentMethod, "VISA")
        XCTAssertEqual(r.confidence, 0.91)
        XCTAssertEqual(r.provider, "haiku_vision")
        XCTAssertNotNil(r.notes)
        XCTAssertEqual(r.subtotalAmount, 40.15)
        XCTAssertEqual(r.savingsAmount, 6.5)
        XCTAssertEqual(r.couponTotal, 2.0)
        XCTAssertEqual(r.currency, "USD")
        XCTAssertEqual(r.storeChain, "publix")
        let item = try XCTUnwrap(r.lineItems.first)
        XCTAssertEqual(item.rawText, "PBX CHKN BRST")
        XCTAssertEqual(item.canonicalFoodName, "chicken breast")
        XCTAssertEqual(item.displayName, "Chicken Breast")
        XCTAssertEqual(item.quantity, 1.2)
        XCTAssertEqual(item.unit, "kg")
        XCTAssertEqual(item.quantityGrams, 1200)
        XCTAssertEqual(item.unitPrice, 7.99)
        XCTAssertEqual(item.totalPrice, 9.59)
        XCTAssertEqual(item.pricePerKg, 7.99)
        XCTAssertTrue(item.onSale)
        XCTAssertEqual(item.saleNote, "BOGO")
        XCTAssertEqual(item.confidence, 0.93)
        XCTAssertEqual(item.isNonFood, false)
        XCTAssertEqual(item.isFee, false)
        XCTAssertEqual(item.taxFlag, "F")
        XCTAssertEqual(item.categoryHint, "MEAT")
        XCTAssertEqual(item.lineDiscount, 1.5)
    }

    func testReceiptAliasConfirm() throws {
        let r: ReceiptAliasConfirmResponse = try decode("nutrition-receipt-aliases-confirm")
        XCTAssertEqual(r.expandedName, "Publix chicken breast")
        XCTAssertEqual(r.canonicalFoodName, "chicken breast")
        XCTAssertEqual(r.barcode, "0123456789012")
        // The golden confirms a brand-new alias once: counted, not yet trusted.
        XCTAssertEqual(r.confirmationCount, 1)
        XCTAssertFalse(r.isTrusted)
    }

    // MARK: - Foods

    func testFoodSearch() throws {
        let r: FoodSearchResponseDTO = try decode("foods-search")
        let food = try XCTUnwrap(r.foods.first)
        XCTAssertEqual(food.fdcID, 900_007)
        XCTAssertTrue(food.name.hasPrefix("Chicken Breast"))
        XCTAssertEqual(food.dataType, "Foundation")
        XCTAssertEqual(food.kcal, 165)
        XCTAssertEqual(food.protein, 31)
        XCTAssertEqual(food.fat, 3.6, accuracy: 0.001)
    }

    // MARK: - Weekly plan

    func testWeeklyPlanCreate() throws {
        let r: WeeklyPlanJobDTO = try decode("nutrition-weekly-plans-post")
        XCTAssertFalse(r.id.isEmpty)
        XCTAssertEqual(r.status, .queued)
        XCTAssertEqual(r.weekStart, "2026-09-28")
        XCTAssertNil(r.plan)
    }

    private func assertReadyPlan(_ r: WeeklyPlanJobDTO, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertFalse(r.id.isEmpty, file: file, line: line)
        XCTAssertEqual(r.weekStart, "2026-09-28", file: file, line: line)
        XCTAssertEqual(r.status, .ready, file: file, line: line)
        let plan = try XCTUnwrap(r.plan, "ready job has no plan", file: file, line: line)
        XCTAssertEqual(plan.days.count, 7, file: file, line: line)
        let day = plan.days[0]
        XCTAssertEqual(day.dayType, "strength", file: file, line: line)
        let meal = try XCTUnwrap(day.meals.first, file: file, line: line)
        XCTAssertEqual(meal.mealName, "Breakfast", file: file, line: line)
        XCTAssertEqual(meal.scheduledTime, "07:30", file: file, line: line)
        let food = try XCTUnwrap(meal.foods.first, file: file, line: line)
        XCTAssertFalse(food.name.isEmpty, file: file, line: line)
        XCTAssertGreaterThan(food.quantityGrams, 0, file: file, line: line)
        XCTAssertGreaterThan(food.calories, 0, file: file, line: line)
        XCTAssertGreaterThan(food.proteinG, 0, file: file, line: line)
        XCTAssertNotNil(food.source, file: file, line: line)
    }

    func testWeeklyPlanGetByID() throws {
        try assertReadyPlan(decode("nutrition-weekly-plans-get"))
    }

    func testWeeklyPlanLatest() throws {
        let r: WeeklyPlanJobDTO? = try decode("nutrition-weekly-plans-latest")
        try assertReadyPlan(XCTUnwrap(r))
    }

    func testWeeklyPlanLatestWithNoJobIsNil() throws {
        let r: WeeklyPlanJobDTO? = try decode("nutrition-weekly-plans-latest-none")
        XCTAssertNil(r)
    }

    // MARK: - Push payloads

    /// What iOS hands the delegate for a remote push: the whole APNs JSON as
    /// `userInfo` and `aps.category` as the category (TempoNotificationDelegate
    /// reads `content.userInfo["type"]` and `content.categoryIdentifier`).
    private func pushContent(_ slug: String) throws -> (content: UNMutableNotificationContent, aps: [String: Any]) {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: goldenData(slug)) as? [String: Any])
        let aps = try XCTUnwrap(json["aps"] as? [String: Any])
        let content = UNMutableNotificationContent()
        content.userInfo = json
        content.categoryIdentifier = (aps["category"] as? String) ?? ""
        if let alert = aps["alert"] as? [String: Any] {
            content.title = (alert["title"] as? String) ?? ""
            content.body = (alert["body"] as? String) ?? ""
        }
        return (content, aps)
    }

    func testPushMealPlanReady() throws {
        let (content, aps) = try pushContent("push-meal_plan_ready")
        XCTAssertFalse(content.title.isEmpty)
        XCTAssertFalse(content.body.isEmpty)
        XCTAssertEqual(aps["interruption-level"] as? String, "time-sensitive")
        // The delegate's category switch.
        XCTAssertEqual(content.categoryIdentifier, WeeklyPlanReminder.readyCategoryID)
        // The delegate's fallback: `content.userInfo["type"] as? String == "meal_plan_ready"`.
        // KNOWN BUG: the server (TempoNotificationPayload) nests custom keys under `data`, so
        // `userInfo["type"]` is nil and tapping the "plan ready" push never opens Nutrition /
        // syncs the plan (the MEAL_PLAN_READY category case still does). Fix the server payload
        // (put keys at the top level) or read `userInfo["data"]["type"]` in the delegate, then
        // delete this XCTExpectFailure.
        XCTExpectFailure("push `type` is nested under `data`, delegate reads userInfo[\"type\"]") {
            XCTAssertEqual(content.userInfo["type"] as? String, "meal_plan_ready")
        }
        XCTAssertEqual((content.userInfo["data"] as? [String: Any])?["type"] as? String, "meal_plan_ready")
    }

    func testPushRecoveryMorning() throws {
        let (content, aps) = try pushContent("push-recovery_morning")
        XCTAssertEqual(content.title, "TEMPO")
        XCTAssertFalse(content.body.isEmpty)
        XCTAssertEqual(content.categoryIdentifier, "MORNING_BRIEFING")
        XCTAssertEqual(aps["interruption-level"] as? String, "time-sensitive")
    }

    func testPushGeneral() throws {
        let (content, aps) = try pushContent("push-general")
        XCTAssertEqual(content.title, "TEMPO")
        XCTAssertFalse(content.body.isEmpty)
        XCTAssertEqual(content.categoryIdentifier, "GENERAL")
        XCTAssertEqual(aps["interruption-level"] as? String, "active")
    }
}
