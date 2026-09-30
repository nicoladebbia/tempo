import Fluent
import Vapor

// MARK: - ReceiptItemAliasController

// Crowd-sourced item alias table. Routes:
//   POST /v1/nutrition/receipt-aliases/lookup  — batch lookup by store_chain + raw_texts
//   POST /v1/nutrition/receipt-aliases/confirm — record a confirmation, growing trust
//
// Free for every signed-in user (mirrors ReceiptController's requireUserID
// pattern) — this is a shared crowd table, not scoped by user. The client is
// expected to treat both endpoints as silently skippable if unreachable
// (iOS-side concern, nothing enforced here).

struct ReceiptItemAliasController: RouteCollection {
    /// A confirmed mapping needs this many agreeing confirmations before
    /// it's surfaced as `is_trusted`.
    static let trustThreshold = 3

    func boot(routes: RoutesBuilder) throws {
        routes.post("lookup", use: lookup)
        routes.post("confirm", use: confirm)
    }

    // MARK: - POST /lookup

    @Sendable
    func lookup(req: Request) async throws -> Envelope<[ReceiptAliasLookupResultDTO]> {
        _ = try req.auth.requireUserID()
        let input = try Self.decode(ReceiptAliasLookupRequest.self, from: req)
        let storeChain = try Self.validateStoreChain(input.storeChain)
        guard !input.rawTexts.isEmpty else {
            throw Abort(.badRequest, reason: "raw_texts must contain at least 1 entry.")
        }
        guard input.rawTexts.count <= 200 else {
            throw Abort(.badRequest, reason: "raw_texts must contain at most 200 entries.")
        }

        let normalizedPairs = input.rawTexts.map { ($0, ReceiptItemAliasNormalizer.normalize($0)) }
        let normalizedKeys = Array(Set(normalizedPairs.map(\.1)))

        let rows = try await ReceiptItemAlias.query(on: req.db)
            .filter(\.$storeChain == storeChain)
            .filter(\.$normalizedRawText ~~ normalizedKeys)
            .all()
        var byKey: [String: ReceiptItemAlias] = [:]
        for row in rows {
            byKey[row.normalizedRawText] = row
        }

        let results = normalizedPairs.map { rawText, key in
            ReceiptAliasLookupResultDTO(
                rawText: rawText,
                match: byKey[key].map(ReceiptAliasMatchDTO.init(model:))
            )
        }
        return Envelope(data: results, requestID: req.requestID)
    }

    // MARK: - POST /confirm

    @Sendable
    func confirm(req: Request) async throws -> Envelope<ReceiptAliasMatchDTO> {
        _ = try req.auth.requireUserID()
        let input = try Self.decode(ReceiptAliasConfirmRequest.self, from: req)
        let storeChain = try Self.validateStoreChain(input.storeChain)

        let rawText = input.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            throw Abort(.badRequest, reason: "raw_text must not be empty.")
        }
        let expandedName = input.expandedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalFoodName = input.canonicalFoodName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expandedName.isEmpty else {
            throw Abort(.badRequest, reason: "expanded_name must not be empty.")
        }
        guard !canonicalFoodName.isEmpty else {
            throw Abort(.badRequest, reason: "canonical_food_name must not be empty.")
        }
        if let barcode = input.barcode, barcode.count > 64 {
            throw Abort(.badRequest, reason: "barcode is too long.")
        }

        let normalized = ReceiptItemAliasNormalizer.normalize(rawText)

        if let existing = try await ReceiptItemAlias.query(on: req.db)
            .filter(\.$storeChain == storeChain)
            .filter(\.$normalizedRawText == normalized)
            .first()
        {
            let sameExpansion = existing.expandedName.caseInsensitiveCompare(expandedName) == .orderedSame
                && existing.canonicalFoodName.caseInsensitiveCompare(canonicalFoodName) == .orderedSame

            if sameExpansion {
                existing.confirmationCount += 1
                if existing.confirmationCount >= Self.trustThreshold {
                    existing.isTrusted = true
                }
                if existing.barcode == nil, let barcode = input.barcode, !barcode.isEmpty {
                    existing.barcode = barcode
                }
            } else {
                // DELIBERATE SIMPLIFICATION (documented per spec): a row is
                // keyed on (store_chain, normalized_raw_text), so there's
                // only one `is_trusted` bool per key — there's no per-row
                // support for tracking multiple competing expansions and
                // letting the most-confirmed one win independently. When a
                // confirmation disagrees with what's stored, the new
                // expansion simply OVERWRITES the row and RESETS
                // confirmation_count to 1 (un-trusting it if it was
                // trusted). This means one canonical mapping wins per key —
                // whichever expansion has the most *consecutive* agreeing
                // confirmations — and two expansions being confirmed in
                // alternation never lets either reach `is_trusted`. Good
                // enough for a crowd table; a real per-candidate vote count
                // is future work.
                existing.expandedName = expandedName
                existing.canonicalFoodName = canonicalFoodName
                existing.barcode = input.barcode
                existing.confirmationCount = 1
                existing.isTrusted = false
            }
            existing.updatedAt = Date()
            try await existing.save(on: req.db)
            return Envelope(data: ReceiptAliasMatchDTO(model: existing), requestID: req.requestID)
        }

        let alias = ReceiptItemAlias(
            storeChain: storeChain,
            normalizedRawText: normalized,
            expandedName: expandedName,
            canonicalFoodName: canonicalFoodName,
            barcode: input.barcode,
            confirmationCount: 1,
            isTrusted: false
        )
        try await alias.save(on: req.db)
        return Envelope(data: ReceiptAliasMatchDTO(model: alias), requestID: req.requestID)
    }

    // MARK: - Helpers

    private static func validateStoreChain(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 64 else {
            throw Abort(.badRequest, reason: "store_chain must be 1...64 characters.")
        }
        return trimmed
    }

    /// `req.content.decode` throws a plain `DecodingError` on a malformed
    /// body, which is NOT an `AbortError` — TempoErrorMiddleware would turn
    /// that into an opaque 500. Wrap it so a missing/malformed field is
    /// always a clear 400 instead.
    private static func decode<T: Content>(_: T.Type, from req: Request) throws -> T {
        do {
            return try req.content.decode(T.self)
        } catch {
            req.logger.warning("receipt-aliases: malformed request body: \(error)")
            throw Abort(.badRequest, reason: "Malformed or missing request fields.")
        }
    }
}

// MARK: - Wire DTOs

struct ReceiptAliasLookupRequest: Content {
    let storeChain: String
    let rawTexts: [String]
}

struct ReceiptAliasConfirmRequest: Content {
    let storeChain: String
    let rawText: String
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?
}

struct ReceiptAliasMatchDTO: Content {
    let expandedName: String
    let canonicalFoodName: String
    let barcode: String?
    let isTrusted: Bool
    let confirmationCount: Int

    init(model: ReceiptItemAlias) {
        expandedName = model.expandedName
        canonicalFoodName = model.canonicalFoodName
        barcode = model.barcode
        isTrusted = model.isTrusted
        confirmationCount = model.confirmationCount
    }
}

struct ReceiptAliasLookupResultDTO: Content {
    let rawText: String
    let match: ReceiptAliasMatchDTO?
}
