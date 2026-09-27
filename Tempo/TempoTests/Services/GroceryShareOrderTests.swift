//
// GroceryShareOrderTests.swift
// Tempo
//
// feat/grocery-share-order (Lane C). Covers:
//   - GroceryShareTextFormatter's grouped-by-aisle plain-text checklist
//   - snake_case wire encoding of the share snapshot DTO (the iOS decoder
//     has no global key strategy, unlike the backend, so every CodingKeys
//     entry here is load-bearing — GroceryShareOrderTests pins it)
//   - SharedGroceryListService's last-write-wins push/pull contract
//     (mirrors the backend's GroceryShareControllerTests
//     staleOwnerPushDoesNotClobberNewerShopperTick)
//   - GroceryOrderLinks fallback URL building
//

import Foundation
import SwiftData
@testable import Tempo
import XCTest

// MARK: - GroceryShareTextFormatterTests

@MainActor
final class GroceryShareTextFormatterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeList(items: [(name: String, category: String, checked: Bool)]) -> GroceryList {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        for entry in items {
            let item = GroceryListItem(
                list: list,
                canonicalFoodName: entry.name.lowercased(),
                displayName: entry.name,
                quantity: 2,
                unit: .cans,
                category: entry.category,
                isChecked: entry.checked
            )
            context.insert(item)
        }
        return list
    }

    func testGroupsByAisleInStoreWalkOrderWithCheckboxes() throws {
        let list = makeList(items: [
            ("Black Beans", "pantry", false),
            ("Spinach", "produce", true),
            ("Milk", "dairy", false),
        ])

        let text = GroceryShareTextFormatter.text(for: list)
        let lines = text.components(separatedBy: "\n")

        // Store-walk order: produce, dairy, ..., pantry.
        let produceIndex = try? XCTUnwrap(lines.firstIndex(of: "PRODUCE"))
        let dairyIndex = try? XCTUnwrap(lines.firstIndex(of: "DAIRY"))
        let pantryIndex = try? XCTUnwrap(lines.firstIndex(of: "PANTRY"))
        XCTAssertNotNil(produceIndex)
        XCTAssertNotNil(dairyIndex)
        XCTAssertNotNil(pantryIndex)
        XCTAssertLessThan(try XCTUnwrap(produceIndex), try XCTUnwrap(dairyIndex))
        XCTAssertLessThan(try XCTUnwrap(dairyIndex), try XCTUnwrap(pantryIndex))

        XCTAssertTrue(text.contains("☑ 2 cans Spinach"), "Checked item uses the filled box")
        XCTAssertTrue(text.contains("☐ 2 cans Black Beans"))
        XCTAssertTrue(text.contains("☐ 2 cans Milk"))
    }

    func testEmptyListReturnsJustTheTitle() {
        let list = makeList(items: [])
        XCTAssertEqual(GroceryShareTextFormatter.text(for: list, title: "Grocery List"), "Grocery List")
    }
}

// MARK: - GroceryShareItemUpsertDTOEncodingTests

final class GroceryShareItemUpsertDTOEncodingTests: XCTestCase {
    /// The iOS APIClient decoder has NO global snake_case strategy (unlike
    /// the backend), so `updatedAt` only survives the wire round-trip
    /// because of the explicit `CodingKeys` entry. If someone "cleans up"
    /// that enum, the backend silently stops receiving `updated_at` and the
    /// LWW merge breaks — this test exists to catch exactly that.
    func testEncodesUpdatedAtAsSnakeCase() throws {
        let item = GroceryShareItemUpsertDTO(
            id: "abc-123",
            name: "Black Beans",
            quantity: 2,
            unit: "cans",
            category: "pantry",
            checked: false,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["updated_at"], "must ship snake_case for the backend's from-scratch decoder")
        XCTAssertNil(json["updatedAt"], "camelCase key would be silently dropped by the backend")
        XCTAssertEqual(json["id"] as? String, "abc-123")
        XCTAssertEqual(json["quantity"] as? Double, 2)
    }

    func testUpsertRequestRoundTripsItemsArray() throws {
        let request = GroceryShareUpsertRequestDTO(
            token: "tok1",
            title: "Grocery List",
            store: "Publix",
            items: [
                GroceryShareItemUpsertDTO(
                    id: "1", name: "Milk", quantity: 1, unit: "l", category: "dairy",
                    checked: false, updatedAt: Date(timeIntervalSince1970: 0)
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GroceryShareUpsertRequestDTO.self, from: data)

        XCTAssertEqual(decoded.token, "tok1")
        XCTAssertEqual(decoded.items.count, 1)
        XCTAssertEqual(decoded.items.first?.name, "Milk")
    }
}

// MARK: - SharedGroceryListServiceTests

@MainActor
final class SharedGroceryListServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        try await super.setUp()
        MockURLProtocol.reset()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Schema(TempoSchemaV1.models), configurations: [config])
        context = container.mainContext
    }

    override func tearDown() async throws {
        MockURLProtocol.reset()
        container = nil
        context = nil
        try await super.tearDown()
    }

    private func makeService() -> SharedGroceryListService {
        let session = MockURLProtocol.makeSession()
        let apiClient = APIClient(session: session)
        return SharedGroceryListService(apiClient: apiClient)
    }

    /// Wraps `dto` in the `{ok, data}` envelope shape `APIClient` unwraps
    /// for `expectsEnvelope`-true endpoints (upsert/get grocery share both are).
    /// `nonisolated` (and free of `self`) so it can be called from inside
    /// `MockURLProtocol`'s `@Sendable` handler closure without a
    /// cross-actor capture.
    private nonisolated static func envelope(_ dto: GroceryShareDTO) -> MockURLProtocol.Stub {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dtoData = try! encoder.encode(dto) // swiftlint:disable:this force_try — test fixture
        let dtoJSON = try! JSONSerialization.jsonObject(with: dtoData) // swiftlint:disable:this force_try
        let finalData = try! JSONSerialization.data(withJSONObject: ["ok": true, "data": dtoJSON]) // swiftlint:disable:this force_try
        return .init(statusCode: 200, data: finalData, headers: ["Content-Type": "application/json"])
    }

    // MARK: - Pull: apply remote ticks by item id

    func testPullAndApplyChecksLocalItemWhenRemoteTickIsNewer() async throws {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        let item = GroceryListItem(
            list: list, canonicalFoodName: "milk", displayName: "Milk",
            quantity: 1, unit: .liters, category: "dairy", isChecked: false
        )
        context.insert(item)

        let share = GroceryShare(
            listID: list.id, token: "tok1", url: "https://example.com/g/tok1",
            expiresAt: Date().addingTimeInterval(3600),
            itemStateJSON: GroceryShare.encodeItemState([
                GroceryShareItemState(id: item.id.uuidString, checked: false, updatedAt: Date(timeIntervalSince1970: 0)),
            ])
        )
        context.insert(share)

        let remoteDTO = GroceryShareDTO(
            token: "tok1", url: "https://example.com/g/tok1", title: "Grocery List", store: nil,
            expiresAt: Date().addingTimeInterval(3600), revoked: false,
            items: [
                GroceryShareItemDTO(
                    id: item.id.uuidString, name: "Milk", quantity: 1, unit: "l", category: "dairy",
                    checked: true, updatedAt: Date() // newer than the baseline's epoch-0 timestamp
                ),
            ]
        )
        MockURLProtocol.setHandler { _ in Self.envelope(remoteDTO) }

        let service = makeService()
        try await service.pullAndApply(list: list, in: context)

        XCTAssertTrue(item.isChecked, "A shopper tick newer than our baseline must be applied")
    }

    func testPullAndApplyIgnoresRemoteTickOlderThanBaseline() async throws {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        let item = GroceryListItem(
            list: list, canonicalFoodName: "milk", displayName: "Milk",
            quantity: 1, unit: .liters, category: "dairy", isChecked: true
        )
        context.insert(item)

        let recentBaseline = Date()
        let share = GroceryShare(
            listID: list.id, token: "tok1", url: "https://example.com/g/tok1",
            expiresAt: Date().addingTimeInterval(3600),
            itemStateJSON: GroceryShare.encodeItemState([
                GroceryShareItemState(id: item.id.uuidString, checked: true, updatedAt: recentBaseline),
            ])
        )
        context.insert(share)

        // A stale response (e.g. an out-of-order network reply) reporting
        // unchecked at a timestamp OLDER than what we already know locally.
        let staleDTO = GroceryShareDTO(
            token: "tok1", url: "https://example.com/g/tok1", title: "Grocery List", store: nil,
            expiresAt: Date().addingTimeInterval(3600), revoked: false,
            items: [
                GroceryShareItemDTO(
                    id: item.id.uuidString, name: "Milk", quantity: 1, unit: "l", category: "dairy",
                    checked: false, updatedAt: Date(timeIntervalSince1970: 0)
                ),
            ]
        )
        MockURLProtocol.setHandler { _ in Self.envelope(staleDTO) }

        let service = makeService()
        try await service.pullAndApply(list: list, in: context)

        XCTAssertTrue(item.isChecked, "A stale remote value must not clobber a newer local state")
    }

    // MARK: - Push: LWW baseline diffing

    func testUnchangedItemKeepsBaselineTimestampAcrossReposhes() async throws {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        let item = GroceryListItem(
            list: list, canonicalFoodName: "beans", displayName: "Black Beans",
            quantity: 2, unit: .cans, category: "pantry", isChecked: false
        )
        context.insert(item)

        MockURLProtocol.setHandler { request in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try? decoder.decode(GroceryShareUpsertRequestDTO.self, from: request.capturedBody())
            let echoedItems = (decoded?.items ?? []).map {
                GroceryShareItemDTO(
                    id: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit,
                    category: $0.category, checked: $0.checked, updatedAt: $0.updatedAt
                )
            }
            let dto = GroceryShareDTO(
                token: "tok1", url: "https://example.com/g/tok1", title: "Grocery List", store: nil,
                expiresAt: Date().addingTimeInterval(3600), revoked: false, items: echoedItems
            )
            return Self.envelope(dto)
        }

        let service = makeService()
        _ = try await service.startSharing(list: list, in: context)

        // Distinct wall-clock second so a "bump to now" would actually be
        // observable in the ISO8601-encoded (second precision) timestamp.
        try await Task.sleep(for: .seconds(1.1))
        try await service.refreshSnapshot(for: list, in: context)

        // MockURLProtocol.recordedRequests is lock-protected (safe to read
        // from the test's actor after the awaits above complete), unlike a
        // plain local var captured into the @Sendable handler closure.
        let capturedBodies = MockURLProtocol.recordedRequests.map { $0.capturedBody() }
        XCTAssertEqual(capturedBodies.count, 2)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let firstPush = try decoder.decode(GroceryShareUpsertRequestDTO.self, from: capturedBodies[0])
        let secondPush = try decoder.decode(GroceryShareUpsertRequestDTO.self, from: capturedBodies[1])

        XCTAssertEqual(
            firstPush.items.first?.updatedAt, secondPush.items.first?.updatedAt,
            "Item never changed locally — the second push must resend the SAME timestamp, not a fresh 'now'"
        )
    }

    func testTogglingLocallyBumpsTheItemsTimestampOnNextPush() async throws {
        let list = GroceryList(weekStartDate: Date())
        context.insert(list)
        let item = GroceryListItem(
            list: list, canonicalFoodName: "beans", displayName: "Black Beans",
            quantity: 2, unit: .cans, category: "pantry", isChecked: false
        )
        context.insert(item)

        MockURLProtocol.setHandler { request in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try? decoder.decode(GroceryShareUpsertRequestDTO.self, from: request.capturedBody())
            let echoedItems = (decoded?.items ?? []).map {
                GroceryShareItemDTO(
                    id: $0.id, name: $0.name, quantity: $0.quantity, unit: $0.unit,
                    category: $0.category, checked: $0.checked, updatedAt: $0.updatedAt
                )
            }
            let dto = GroceryShareDTO(
                token: "tok1", url: "https://example.com/g/tok1", title: "Grocery List", store: nil,
                expiresAt: Date().addingTimeInterval(3600), revoked: false, items: echoedItems
            )
            return Self.envelope(dto)
        }

        let service = makeService()
        _ = try await service.startSharing(list: list, in: context)
        try await Task.sleep(for: .seconds(1.1))
        item.isChecked = true
        try await service.refreshSnapshot(for: list, in: context)

        let capturedBodies = MockURLProtocol.recordedRequests.map { $0.capturedBody() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let firstPush = try decoder.decode(GroceryShareUpsertRequestDTO.self, from: capturedBodies[0])
        let secondPush = try decoder.decode(GroceryShareUpsertRequestDTO.self, from: capturedBodies[1])

        XCTAssertNotEqual(
            firstPush.items.first?.updatedAt, secondPush.items.first?.updatedAt,
            "Checked value actually changed locally — the new push must carry a fresh timestamp"
        )
        XCTAssertTrue(secondPush.items.first?.checked ?? false)
    }
}

// MARK: - GroceryOrderLinksTests

final class GroceryOrderLinksTests: XCTestCase {
    func testInstacartSearchURLEncodesItemName() throws {
        let url = try XCTUnwrap(GroceryOrderLinks.instacartSearchURL(for: "Black Beans"))
        XCTAssertEqual(url.host, "www.instacart.com")
        XCTAssertTrue(url.path.contains("/store/s"))
        XCTAssertEqual(url.queryItemValue("k"), "Black Beans")
    }

    func testAmazonWholeFoodsSearchURLFiltersToWholeFoods() throws {
        let url = try XCTUnwrap(GroceryOrderLinks.amazonWholeFoodsSearchURL(for: "Milk"))
        XCTAssertEqual(url.host, "www.amazon.com")
        XCTAssertEqual(url.queryItemValue("i"), "wholefoods")
        XCTAssertEqual(url.queryItemValue("k"), "Milk")
    }

    func testFallbackLinksReturnsTwoLinksPerItemInOrder() {
        let links = GroceryOrderLinks.fallbackLinks(for: ["Milk", "Eggs"])
        XCTAssertEqual(links.count, 4)
        XCTAssertEqual(links.map(\.itemName), ["Milk", "Milk", "Eggs", "Eggs"])
        XCTAssertTrue(links[0].url.host?.contains("instacart") ?? false)
        XCTAssertTrue(links[1].url.host?.contains("amazon") ?? false)
    }
}

// MARK: - Test helpers

private extension URL {
    func queryItemValue(_ name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == name }?.value
    }
}

private extension URLRequest {
    /// `URLSession` sometimes hands a custom `URLProtocol` the request body
    /// as `httpBodyStream` rather than `httpBody`, even though APIClient set
    /// `httpBody` directly — read whichever is present.
    func capturedBody() -> Data {
        if let httpBody {
            return httpBody
        }
        guard let stream = httpBodyStream else {
            return Data()
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(buffer, count: read)
        }
        return data
    }
}
