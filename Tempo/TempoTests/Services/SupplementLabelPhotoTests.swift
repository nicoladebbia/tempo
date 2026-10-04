//
// SupplementLabelPhotoTests.swift
// Tempo
//
// Supplement coverage: new wire fields (with and without), source-prefixed
// ids, the label-photo image prep, the catalog submission mapping from the
// review form, and the label flow's state machine for every outcome.
//

@testable import Tempo
import UIKit
import XCTest

// MARK: - Mock service

@MainActor
private final class MockLabelService: SupplementLookupServicing {
    var readResult: Result<SupplementLookupDTO, Error> = .failure(APIError.notFound)
    var submitResult: Result<SupplementLookupDTO, Error> = .failure(APIError.networkError("x"))
    private(set) var readCalls: [(base64: String, media: String, upc: String?)] = []
    private(set) var submissions: [SupplementCatalogSubmission] = []

    func lookUp(upc _: String) async throws -> SupplementLookupDTO { throw APIError.notFound }

    func readLabel(imageBase64: String, mediaType: String, upc: String?) async throws -> SupplementLookupDTO {
        readCalls.append((imageBase64, mediaType, upc))
        return try readResult.get()
    }

    func submitToCatalog(_ submission: SupplementCatalogSubmission) async throws -> SupplementLookupDTO {
        submissions.append(submission)
        return try submitResult.get()
    }
}

private func sampleDTO(upc: String = "") -> SupplementLookupDTO {
    SupplementLookupDTO(
        upc: upc, brand: "Acme", name: "Whey", kind: "protein", dosePerServing: "1 scoop (30 g)",
        servingsPerContainer: 30, proteinGramsPerServing: 24, certifications: [], source: "label_photo"
    )
}

private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
        for i in 0 ..< 40 {
            UIColor(hue: CGFloat(i) / 40, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: height / 40 * CGFloat(i), width: width, height: height / 40))
        }
    }
}

// MARK: - DTO + ids

final class SupplementWireTests: XCTestCase {
    func testDecodesNewFields() throws {
        let json = #"{"upc":"1","name":"x","kind":"other","certifications":[],"source":"tempo","community_confirmations":3}"#
        let dto = try JSONDecoder().decode(SupplementLookupDTO.self, from: Data(json.utf8))
        XCTAssertEqual(dto.source, "tempo")
        XCTAssertEqual(dto.communityConfirmations, 3)
        XCTAssertEqual(SupplementEditSheet.sourceLine(dto), "Added by Tempo users · confirmed by 3. Check it against your label.")
    }

    func testDecodesWithoutNewFields() throws {
        let json = #"{"upc":"1","name":"x","kind":"other","certifications":[],"source":"dsld"}"#
        let dto = try JSONDecoder().decode(SupplementLookupDTO.self, from: Data(json.utf8))
        XCTAssertNil(dto.communityConfirmations)
        let hit = #"[{"id":"181813","name":"Mg","kind":"vitamin","on_market":true}]"#
        let hits = try JSONDecoder().decode([SupplementSearchHit].self, from: Data(hit.utf8))
        XCTAssertNil(hits[0].source)
        XCTAssertEqual(hits[0].origin, .nih, "legacy numeric id is DSLD")
    }

    func testPrefixedIdsAndOrigins() throws {
        let json = """
        [{"id":"dsld:123","name":"A","kind":"other","on_market":true,"source":"dsld"},
         {"id":"off:0123456789012","name":"B","kind":"protein","on_market":true,"source":"openfoodfacts"},
         {"id":"tempo:7B2F0C1E-0000-4000-8000-000000000001","name":"C","kind":"other","on_market":true,"source":"tempo"}]
        """
        let hits = try JSONDecoder().decode([SupplementSearchHit].self, from: Data(json.utf8))
        XCTAssertEqual(hits.map(\.origin), [.nih, .openFoodFacts, .tempo])
        XCTAssertEqual(hits.map(\.origin.badge), ["NIH", "Open Food Facts", "Tempo users"])
        XCTAssertEqual(APIEndpoint<SupplementLookupDTO>.supplementLabel(id: hits[1].id).path, "/v1/supplements/label/off:0123456789012")
        XCTAssertEqual(APIEndpoint<SupplementLookupDTO>.supplementLabel(id: "123").path, "/v1/supplements/label/123")
        XCTAssertEqual(
            APIEndpoint<SupplementLookupDTO>.supplementLabel(id: "tempo:AB-12/../x").path,
            "/v1/supplements/label/tempo:AB-12x"
        )
    }

    func testWithUPCKeepsConfirmations() {
        let dto = SupplementLookupDTO(
            upc: "", brand: nil, name: "n", kind: "other", dosePerServing: nil, servingsPerContainer: nil,
            proteinGramsPerServing: nil, certifications: [], source: "tempo", communityConfirmations: 2
        )
        XCTAssertEqual(dto.withUPC("123").communityConfirmations, 2)
    }

    func testRequestBodiesUseSnakeCase() throws {
        let body = try JSONEncoder().encode(SupplementReadLabelRequest(imageBase64: "QQ==", mediaType: "image/jpeg", upc: "123"))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(obj["image_base64"] as? String, "QQ==")
        XCTAssertEqual(obj["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(obj["upc"] as? String, "123")
    }
}

// MARK: - Image + submission

@MainActor
final class SupplementLabelImageTests: XCTestCase {
    func testLargePhotoIsDownscaledAndSmall() throws {
        let data = try XCTUnwrap(SupplementLabelImage.jpeg(from: solidImage(width: 4032, height: 3024)))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertLessThanOrEqual(max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale), 1600)
        XCTAssertLessThan(data.count, 1_500_000)
    }

    func testSmallPhotoIsNotUpscaled() throws {
        let data = try XCTUnwrap(SupplementLabelImage.jpeg(from: solidImage(width: 800, height: 600)))
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(decoded.size.width * decoded.scale, 800, accuracy: 1)
    }

    func testSubmissionMapsTheReviewedForm() throws {
        let draft = Supplement(name: "  Whey Isolate ", kind: .protein, dosePerServing: "1 scoop (30 g)", proteinGramsPerServing: 24)
        draft.brand = "Acme"
        draft.upc = "748927028669"
        draft.servingsPerContainer = 30
        draft.caloriesPerServing = 120
        draft.ingredientsSummary = "Whey protein 24 g\n\n Lecithin 1 g "
        let sub = try XCTUnwrap(SupplementCatalogSubmission(draft: draft, origin: .labelPhoto))
        XCTAssertEqual(sub.name, "Whey Isolate")
        XCTAssertEqual(sub.upc, "748927028669")
        XCTAssertEqual(sub.kind, "protein")
        XCTAssertEqual(sub.proteinGramsPerServing, 24)
        XCTAssertNil(sub.carbsGramsPerServing, "unset macros are omitted")
        XCTAssertEqual(sub.ingredients, ["Whey protein 24 g", "Lecithin 1 g"])
        XCTAssertEqual(sub.origin, "label_photo")

        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sub)) as? [String: Any])
        XCTAssertEqual(obj["dose_per_serving"] as? String, "1 scoop (30 g)")
        XCTAssertEqual(obj["servings_per_container"] as? Double, 30)
        XCTAssertNil(obj["fat_grams_per_serving"])
    }

    func testExplicitZeroMacrosAreSent() throws {
        let draft = Supplement(name: "Creatine", kind: .creatine)
        draft.carbsGramsPerServing = 0
        draft.fatGramsPerServing = 0
        let sub = try XCTUnwrap(SupplementCatalogSubmission(draft: draft, origin: .manual))
        XCTAssertEqual(sub.fatGramsPerServing, 0)
        XCTAssertEqual(sub.carbsGramsPerServing, 0)
        XCTAssertNil(sub.caloriesPerServing)
    }

    func testAIPostsNeverAutoRetry() {
        XCTAssertTrue(APIEndpoint<SupplementLookupDTO>.supplementReadLabel().disablesRetry)
        XCTAssertTrue(APIEndpoint<SupplementLookupDTO>.supplementCatalogSubmit().disablesRetry)
        XCTAssertFalse(APIEndpoint<SupplementLookupDTO>.supplementLabel(id: "dsld:1").disablesRetry)
    }

    func testNoNameMeansNoSubmission() {
        XCTAssertNil(SupplementCatalogSubmission(draft: Supplement(name: "  ", kind: .other), origin: .manual))
    }

    func testOriginRules() {
        XCTAssertEqual(SupplementCatalogSubmitter.origin(prefillSource: "label_photo", hadBarcode: false), .labelPhoto)
        XCTAssertEqual(SupplementCatalogSubmitter.origin(prefillSource: nil, hadBarcode: true), .manual)
        XCTAssertNil(SupplementCatalogSubmitter.origin(prefillSource: nil, hadBarcode: false))
        XCTAssertNil(SupplementCatalogSubmitter.origin(prefillSource: "dsld", hadBarcode: true))
        XCTAssertNil(SupplementCatalogSubmitter.origin(prefillSource: "tempo", hadBarcode: true))
    }

    func testSubmitterSwallowsErrorsAndReportsSuccess() async {
        let service = MockLabelService()
        let draft = Supplement(name: "Whey", kind: .protein)
        let failed = await SupplementCatalogSubmitter.submit(draft: draft, origin: .manual, using: service)
        XCTAssertFalse(failed)
        XCTAssertEqual(service.submissions.count, 1)
        service.submitResult = .success(sampleDTO())
        let ok = await SupplementCatalogSubmitter.submit(draft: draft, origin: .manual, using: service)
        XCTAssertTrue(ok)
    }
}

// MARK: - Flow state machine

@MainActor
final class SupplementLabelPhotoModelTests: XCTestCase {
    private let image = solidImage(width: 400, height: 300)

    func testSuccessCarriesTheScannedUPC() async {
        let service = MockLabelService()
        service.readResult = .success(sampleDTO())
        let model = SupplementLabelPhotoModel(service: service, upc: "748927028669")
        XCTAssertEqual(model.state, .idle)
        await model.read(image: image)
        guard case let .done(dto) = model.state else { return XCTFail("expected done, got \(model.state)") }
        XCTAssertEqual(dto.upc, "748927028669")
        XCTAssertEqual(service.readCalls.first?.upc, "748927028669")
        XCTAssertEqual(service.readCalls.first?.media, "image/jpeg")
        XCTAssertFalse(service.readCalls.first?.base64.isEmpty ?? true)
    }

    func testUnreadable422() async {
        let model = await failing(APIError.unknown(statusCode: 422))
        XCTAssertEqual(model.state, .failed(.unreadable))
        XCTAssertFalse(SupplementLabelPhotoModel.Failure.unreadable.canRetrySamePhoto)
    }

    func testRateLimited429() async {
        let model = await failing(APIError.rateLimited(retryAfter: nil))
        XCTAssertEqual(model.state, .failed(.busy))
    }

    func testOffline() async {
        for error in [APIError.networkError("down"), .connectionRefused, .timeout] {
            let model = await failing(error)
            XCTAssertEqual(model.state, .failed(.offline))
        }
    }

    func testProGateAndOtherErrors() async {
        let pro = await failing(APIError.subscriptionRequired)
        XCTAssertEqual(pro.state, .failed(.blocked(.proRequired)))
        let other = await failing(APIError.serverError(statusCode: 500))
        guard case .failed(.other) = other.state else { return XCTFail("expected other") }
    }

    func testRetryResendsTheSamePhoto() async {
        let service = MockLabelService()
        service.readResult = .failure(APIError.networkError("down"))
        let model = SupplementLabelPhotoModel(service: service, upc: nil)
        await model.read(image: image)
        service.readResult = .success(sampleDTO())
        await model.retry()
        guard case .done = model.state else { return XCTFail("expected done") }
        XCTAssertEqual(service.readCalls.count, 2)
        XCTAssertEqual(service.readCalls[0].base64, service.readCalls[1].base64)
        XCTAssertNil(service.readCalls[0].upc)
    }

    private func failing(_ error: Error) async -> SupplementLabelPhotoModel {
        let service = MockLabelService()
        service.readResult = .failure(error)
        let model = SupplementLabelPhotoModel(service: service, upc: nil)
        await model.read(image: image)
        return model
    }
}

// MARK: - Real APIClient wire (status mapping)

@MainActor
final class SupplementLabelWireTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        try await super.tearDown()
    }

    func testReadLabelStatusesMapToFailures() async {
        let service = LiveSupplementLookupService(apiClient: APIClient(session: MockURLProtocol.makeSession()))
        MockURLProtocol.setHandler { _ in .init(statusCode: 422, data: Data(#"{"error":true,"reason":"nope"}"#.utf8)) }
        let unreadable = await SupplementLabelPhotoModel.failure(for: expectError { try await service.readLabel(imageBase64: "QQ==", mediaType: "image/jpeg", upc: nil) })
        XCTAssertEqual(unreadable, .unreadable)
        MockURLProtocol.setHandler { _ in .init(statusCode: 429) }
        let busy = await SupplementLabelPhotoModel.failure(for: expectError { try await service.readLabel(imageBase64: "QQ==", mediaType: "image/jpeg", upc: nil) })
        XCTAssertEqual(busy, .busy)
        let post = MockURLProtocol.recordedRequests.last
        XCTAssertEqual(post?.httpMethod, "POST")
        XCTAssertEqual(post?.url?.path, "/v1/supplements/read-label")
    }

    private func expectError(_ call: () async throws -> some Any) async -> Error {
        do {
            _ = try await call()
            return APIError.unknown(statusCode: 0)
        } catch {
            return error
        }
    }
}
