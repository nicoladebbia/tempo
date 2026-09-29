@testable import App
import Fluent
import Foundation
import Testing
import Vapor
import XCTVapor

// MARK: - ReceiptItemAliasController tests

//
// Real Postgres + Redis harness (same pattern as SupplementControllerTests /
// GroceryShareControllerTests). Each test uses a fresh store_chain so rows
// from other tests in this suite never collide.

@Suite("ReceiptItemAliasController", .serialized)
struct ReceiptItemAliasTests {
    private func withApp(_ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            try await app.autoMigrate()
            try await app.asyncBoot()
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @discardableResult
    private func makeUser(app: Application) async throws -> (user: User, token: String) {
        let suffix = UUID().uuidString.prefix(12)
        let user = User(appleUserID: "apple_\(suffix)", username: "user_\(suffix)", displayName: "Test User")
        user.tosAcceptedAt = Date()
        try await user.save(on: app.db)
        let req = Request(application: app, on: app.eventLoopGroup.next())
        let token = try await JWTService.issueAccessToken(userID: user.requireID(), deviceID: "test-device", on: req)
        return (user, token)
    }

    /// Lowercased — the controller normalizes store_chain to lowercase before
    /// storing it (Self.validateStoreChain), so a raw Fluent query comparing
    /// against a mixed-case chain (UUID().uuidString is uppercase) would
    /// never match what actually got persisted.
    private func freshChain() -> String {
        "test_chain_\(UUID().uuidString.lowercased().prefix(8))"
    }

    // MARK: - Lookup

    @Test func lookupWithNoMatchReturnsNilMatch() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()
            try await app.test(.POST, "v1/nutrition/receipt-aliases/lookup", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(LookupBody(storeChain: chain, rawTexts: ["NEVER SEEN BEFORE"]))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[LookupResultWire]>.self)
                #expect(json.data.count == 1)
                #expect(json.data[0].rawText == "NEVER SEEN BEFORE")
                #expect(json.data[0].match == nil)
            })
        }
    }

    @Test func confirmThenLookupFindsMatchDespiteWhitespaceAndCaseDifferences() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()

            try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(ConfirmBody(
                    storeChain: chain,
                    rawText: "PUB GRK YOG 0%",
                    expandedName: "Publix Greek Yogurt 0% Fat",
                    canonicalFoodName: "greek yogurt",
                    barcode: nil
                ))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
            })

            // Different whitespace + case than what was confirmed above —
            // normalization should still hit the same row.
            try await app.test(.POST, "v1/nutrition/receipt-aliases/lookup", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(LookupBody(storeChain: chain, rawTexts: ["  pub   grk yog 0%  "]))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[LookupResultWire]>.self)
                #expect(json.data.count == 1)
                #expect(json.data[0].match?.expandedName == "Publix Greek Yogurt 0% Fat")
                #expect(json.data[0].match?.canonicalFoodName == "greek yogurt")
                #expect(json.data[0].match?.confirmationCount == 1)
                #expect(json.data[0].match?.isTrusted == false)
            })
        }
    }

    @Test func batchLookupReturnsMixOfMatchedAndUnmatchedInInputOrder() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()

            try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(ConfirmBody(
                    storeChain: chain,
                    rawText: "CHKN BRST 1.32LB",
                    expandedName: "Chicken Breast",
                    canonicalFoodName: "chicken breast",
                    barcode: nil
                ))
            }, afterResponse: { res async throws in #expect(res.status == .ok) })

            try await app.test(.POST, "v1/nutrition/receipt-aliases/lookup", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(LookupBody(
                    storeChain: chain,
                    rawTexts: ["CHKN BRST 1.32LB", "SOME UNKNOWN ITEM", "chkn brst 1.32lb"]
                ))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<[LookupResultWire]>.self)
                #expect(json.data.count == 3)
                #expect(json.data[0].rawText == "CHKN BRST 1.32LB")
                #expect(json.data[0].match?.canonicalFoodName == "chicken breast")
                #expect(json.data[1].rawText == "SOME UNKNOWN ITEM")
                #expect(json.data[1].match == nil)
                #expect(json.data[2].rawText == "chkn brst 1.32lb")
                #expect(json.data[2].match?.canonicalFoodName == "chicken breast")
            })
        }
    }

    // MARK: - Confirm

    @Test func confirmCreatesNewRowWithCountOneAndNotTrusted() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()

            try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(ConfirmBody(
                    storeChain: chain,
                    rawText: "DAWN PWASH LEMON",
                    expandedName: "Dawn Dish Soap Lemon",
                    canonicalFoodName: "dish soap",
                    barcode: "111222333"
                ))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<MatchWire>.self)
                #expect(json.data.confirmationCount == 1)
                #expect(json.data.isTrusted == false)
                #expect(json.data.expandedName == "Dawn Dish Soap Lemon")
                #expect(json.data.barcode == "111222333")
            })

            let count = try await ReceiptItemAlias.query(on: app.db)
                .filter(\.$storeChain == chain)
                .count()
            #expect(count == 1)
        }
    }

    @Test func confirmingSameExpansionThreeTimesFlipsTrusted() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()

            func confirm() async throws -> MatchWire {
                var result: MatchWire!
                try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: token)
                    try req.content.encode(ConfirmBody(
                        storeChain: chain,
                        rawText: "GV WHIPPED CREAM",
                        expandedName: "Whipped Cream",
                        canonicalFoodName: "whipped cream",
                        barcode: nil
                    ))
                }, afterResponse: { res async throws in
                    #expect(res.status == .ok)
                    result = try res.content.decode(RawEnvelope<MatchWire>.self).data
                })
                return result
            }

            let first = try await confirm()
            #expect(first.confirmationCount == 1)
            #expect(first.isTrusted == false)

            let second = try await confirm()
            #expect(second.confirmationCount == 2)
            #expect(second.isTrusted == false)

            let third = try await confirm()
            #expect(third.confirmationCount == 3)
            #expect(third.isTrusted == true)
        }
    }

    @Test func confirmingADifferentExpansionResetsTheCount() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            let chain = freshChain()

            // Confirm "Chicken Breast" twice — count reaches 2, not yet trusted.
            for _ in 0 ..< 2 {
                try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                    req.headers.bearerAuthorization = .init(token: token)
                    try req.content.encode(ConfirmBody(
                        storeChain: chain,
                        rawText: "CHKN BRST 1.32LB",
                        expandedName: "Chicken Breast",
                        canonicalFoodName: "chicken breast",
                        barcode: nil
                    ))
                }, afterResponse: { res async throws in #expect(res.status == .ok) })
            }

            // A disagreeing confirmation for the SAME raw_text/store_chain key
            // resets the row per the documented simplification.
            try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(ConfirmBody(
                    storeChain: chain,
                    rawText: "CHKN BRST 1.32LB",
                    expandedName: "Boneless Chicken Thigh",
                    canonicalFoodName: "chicken thigh",
                    barcode: nil
                ))
            }, afterResponse: { res async throws in
                #expect(res.status == .ok)
                let json = try res.content.decode(RawEnvelope<MatchWire>.self)
                #expect(json.data.expandedName == "Boneless Chicken Thigh")
                #expect(json.data.canonicalFoodName == "chicken thigh")
                #expect(json.data.confirmationCount == 1)
                #expect(json.data.isTrusted == false)
            })

            // Exactly one row for this key — the reset overwrote it, it didn't
            // create a second competing row.
            let count = try await ReceiptItemAlias.query(on: app.db)
                .filter(\.$storeChain == chain)
                .count()
            #expect(count == 1)
        }
    }

    // MARK: - Validation (malformed body must be 400, never 500)

    @Test func malformedConfirmBodyReturnsBadRequestNotServerError() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.POST, "v1/nutrition/receipt-aliases/confirm", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                req.headers.contentType = .json
                // Missing required expanded_name / canonical_food_name.
                req.body = ByteBuffer(string: #"{"store_chain":"publix","raw_text":"X"}"#)
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }

    @Test func emptyRawTextsReturnsBadRequest() async throws {
        try await withApp { app in
            let (_, token) = try await makeUser(app: app)
            try await app.test(.POST, "v1/nutrition/receipt-aliases/lookup", beforeRequest: { req in
                req.headers.bearerAuthorization = .init(token: token)
                try req.content.encode(LookupBody(storeChain: "publix", rawTexts: []))
            }, afterResponse: { res async throws in
                #expect(res.status == .badRequest)
            })
        }
    }
}

// MARK: - Wire types

private struct LookupBody: Content {
    let storeChain: String
    let rawTexts: [String]
}

private struct ConfirmBody: Content {
    let storeChain: String
    let rawText: String
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?
}

private struct MatchWire: Decodable {
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?
    let isTrusted: Bool
    let confirmationCount: Int
}

private struct LookupResultWire: Decodable {
    let rawText: String
    let match: MatchWire?
}

private struct RawEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T
}
