import Fluent
import Foundation
import Redis
import SQLKit
import Vapor

// MARK: - SupplementText (sanitizing + normalizing)

//
// Everything that lands in the shared catalog, or comes back from the label
// reader, goes through here first. Label text and user input are DATA: control
// / invisible characters are stripped, markup brackets dropped, length capped.

enum SupplementText {
    static let maxLength = 120
    static let maxIngredients = 60
    static let maxNumber = 10000.0

    static let knownKinds: Set<String> = [
        "protein", "creatine", "omega3", "multivitamin", "vitamin", "preworkout", "electrolytes", "other",
    ]

    /// Trimmed, single-spaced, no control/format/private-use characters, no `<>`; nil when empty.
    static func clean(_ raw: String?, max: Int = maxLength) -> String? {
        guard let raw else { return nil }
        var out = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control where scalar.properties.isWhitespace:
                out.append(" ")
            case .control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .surrogate, .unassigned:
                continue
            default:
                if scalar == "<" || scalar == ">" { continue }
                out.append(scalar)
            }
        }
        let collapsed = String(out).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        let capped = String(collapsed.prefix(max)).trimmingCharacters(in: .whitespaces)
        return capped.isEmpty ? nil : capped
    }

    /// Lowercase, diacritics folded, letters and digits only, single spaces.
    static func normalized(_ raw: String?) -> String {
        guard let raw else { return "" }
        let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let mapped = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// Dedupe key for search results.
    static func dedupeKey(brand: String?, name: String) -> String {
        "\(normalized(brand))|\(normalized(name))"
    }
}

// MARK: - Submission

struct SupplementCatalogSubmission: Sendable {
    var upc: String?
    var brand: String?
    var name: String
    var kind: String
    var dosePerServing: String?
    var servingsPerContainer: Double?
    var proteinGramsPerServing: Double?
    var caloriesPerServing: Double?
    var carbsGramsPerServing: Double?
    var fatGramsPerServing: Double?
    var ingredients: [String]
    var origin: String

    /// "upc:<canonical>" or "name:<brand>|<name>".
    var entryKey: String {
        if let upc { return "upc:\(upc)" }
        return "name:\(SupplementText.dedupeKey(brand: brand, name: name))"
    }
}

// MARK: - SupplementCatalogService

enum SupplementCatalogService {
    static let dailyCap = 50

    // MARK: Validation

    /// Request body → clean submission, or a 400. Strings are cleaned and capped;
    /// numbers outside 0…10000 and more than 60 ingredients are rejected.
    static func validate(_ input: SupplementCatalogRequest) throws -> SupplementCatalogSubmission {
        guard let name = SupplementText.clean(input.name) else {
            throw Abort(.badRequest, reason: "A supplement needs a name.")
        }
        var upc: String?
        if let rawUPC = input.upc?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUPC.isEmpty {
            do {
                upc = try SupplementUPC.normalize(rawUPC).canonical
            } catch {
                throw Abort(.badRequest, reason: "That barcode doesn't look right.")
            }
        }
        guard input.origin == "label_photo" || input.origin == "manual" else {
            throw Abort(.badRequest, reason: "Unknown origin.")
        }
        let rawIngredients = input.ingredients ?? []
        guard rawIngredients.count <= SupplementText.maxIngredients else {
            throw Abort(.badRequest, reason: "Too many ingredients (max \(SupplementText.maxIngredients)).")
        }
        func number(_ value: Double?) throws -> Double? {
            guard let value else { return nil }
            guard value.isFinite, value >= 0, value <= SupplementText.maxNumber else {
                throw Abort(.badRequest, reason: "Numbers must be between 0 and \(Int(SupplementText.maxNumber)).")
            }
            return value
        }
        let kind = input.kind.lowercased()
        let submission = SupplementCatalogSubmission(
            upc: upc,
            brand: SupplementText.clean(input.brand),
            name: name,
            kind: SupplementText.knownKinds.contains(kind) ? kind : "other",
            dosePerServing: SupplementText.clean(input.dosePerServing),
            servingsPerContainer: try number(input.servingsPerContainer),
            proteinGramsPerServing: try number(input.proteinGramsPerServing),
            caloriesPerServing: try number(input.caloriesPerServing),
            carbsGramsPerServing: try number(input.carbsGramsPerServing),
            fatGramsPerServing: try number(input.fatGramsPerServing),
            ingredients: rawIngredients.compactMap { SupplementText.clean($0) },
            origin: input.origin
        )
        // A name made only of symbols can't be matched on later.
        if submission.upc == nil, SupplementText.normalized(name).isEmpty {
            throw Abort(.badRequest, reason: "A supplement needs a name.")
        }
        return submission
    }

    // MARK: Per-user cap

    /// 50 submissions per user per 24 h (fixed window from the first one).
    static func enforceCap(userID: String, on req: Request) async throws {
        let key = RedisKey("supplement:catalog:cap:\(userID)")
        // Atomic: the key is created WITH its TTL (SET NX EX) before the INCR, so a
        // crash in between can never leave a counter that lives forever.
        _ = try await req.redis.set(key, to: "0", onCondition: .keyDoesNotExist, expiration: .seconds(24 * 3600)).get()
        let count = try await req.redis.increment(key).get()
        if count > dailyCap {
            throw Abort(.tooManyRequests, reason: "Easy. You've added a lot of supplements today. Try again tomorrow.")
        }
    }

    // MARK: Submit

    /// Creates, updates (owner) or confirms (anyone else). Never lets a second
    /// user overwrite an entry.
    static func submit(_ s: SupplementCatalogSubmission, userID: String, on db: Database) async throws -> SupplementLookupDTO {
        for attempt in 0 ..< 2 {
            if let existing = try await SupplementCatalogEntry.query(on: db).filter(\.$entryKey == s.entryKey).first() {
                if existing.contributorID == userID {
                    // Once other people confirmed it, the entry is frozen: the creator
                    // can't rewrite what others vouched for.
                    if existing.confirmationCount > 1 {
                        return try await dto(existing, on: db)
                    }
                    apply(s, to: existing)
                    existing.updatedAt = Date()
                    try await existing.save(on: db)
                } else if SupplementText.dedupeKey(brand: existing.brand, name: existing.name)
                    == SupplementText.dedupeKey(brand: s.brand, name: s.name)
                {
                    let refreshed = try await confirm(existing, agrees: agrees(existing, s), userID: userID, on: db)
                    return try await dto(refreshed, on: db)
                }
                // else: someone else's entry for this barcode with different data: leave it alone.
                return try await dto(existing, on: db)
            }

            let entry = SupplementCatalogEntry()
            entry.entryKey = s.entryKey
            apply(s, to: entry)
            entry.origin = s.origin
            entry.contributorID = userID
            entry.confirmationCount = 1
            entry.disputeCount = 0
            entry.reportCount = 0
            entry.createdAt = Date()
            entry.updatedAt = entry.createdAt
            do {
                try await entry.save(on: db)
            } catch {
                // Lost a race to create the same key: loop once and treat it as existing.
                if attempt == 0 { continue }
                throw error
            }
            try await SupplementCatalogConfirmation(entryID: entry.requireID(), userID: userID).save(on: db)
            return try await dto(entry, on: db)
        }
        throw Abort(.internalServerError)
    }

    private static func apply(_ s: SupplementCatalogSubmission, to entry: SupplementCatalogEntry) {
        entry.entryKey = s.entryKey
        entry.upc = s.upc
        entry.brand = s.brand
        entry.name = s.name
        entry.kind = s.kind
        entry.dosePerServing = s.dosePerServing
        entry.servingsPerContainer = s.servingsPerContainer
        entry.proteinGramsPerServing = s.proteinGramsPerServing
        entry.caloriesPerServing = s.caloriesPerServing
        entry.carbsGramsPerServing = s.carbsGramsPerServing
        entry.fatGramsPerServing = s.fatGramsPerServing
        entry.ingredients = s.ingredients
    }

    /// Key figures within tolerance (+-10% or +-1 g/kcal): protein, calories, carbs, fat per
    /// serving, and servings per container, each compared only when both sides gave a number.
    /// A second user whose figures differ doesn't confirm the entry, they dispute it.
    static func agrees(_ entry: SupplementCatalogEntry, _ s: SupplementCatalogSubmission) -> Bool {
        func close(_ a: Double?, _ b: Double?) -> Bool {
            guard let a, let b else { return true }
            return abs(a - b) <= max(1, 0.1 * max(abs(a), abs(b)))
        }
        return close(entry.proteinGramsPerServing, s.proteinGramsPerServing)
            && close(entry.caloriesPerServing, s.caloriesPerServing)
            && close(entry.carbsGramsPerServing, s.carbsGramsPerServing)
            && close(entry.fatGramsPerServing, s.fatGramsPerServing)
            && close(entry.servingsPerContainer, s.servingsPerContainer)
    }

    /// Idempotent: one row per user (agreeing = a confirmation, otherwise a dispute; a later
    /// submit by the same user replaces their earlier vote). Counts are recomputed from the
    /// tables in ONE UPDATE statement, so parallel confirms can't leave a stale number behind.
    private static func confirm(
        _ entry: SupplementCatalogEntry, agrees: Bool, userID: String, on db: Database
    ) async throws -> SupplementCatalogEntry {
        let entryID = try entry.requireID()
        if let row = try await SupplementCatalogConfirmation.query(on: db)
            .filter(\.$entryID == entryID).filter(\.$userID == userID).first()
        {
            if row.agrees != agrees {
                row.agrees = agrees
                try await row.save(on: db)
            }
        } else {
            let row = SupplementCatalogConfirmation(entryID: entryID, userID: userID)
            row.agrees = agrees
            // A parallel insert by the same user hits the unique index: a harmless no-op.
            try? await row.save(on: db)
        }
        try await recount(entryIDs: [entryID], on: db)
        return try await SupplementCatalogEntry.find(entryID, on: db) ?? entry
    }

    /// Recomputes confirmation / dispute / report counts for entries from their rows.
    static func recount(entryIDs: [UUID], on db: Database) async throws {
        guard let sql = db as? SQLDatabase else { return }
        for entryID in entryIDs {
            try await sql.raw("""
            UPDATE supplement_catalog_entries SET \
            confirmation_count = GREATEST(1, (SELECT COUNT(*) FROM supplement_catalog_confirmations \
            WHERE entry_id = \(bind: entryID) AND agrees)), \
            dispute_count = (SELECT COUNT(*) FROM supplement_catalog_confirmations \
            WHERE entry_id = \(bind: entryID) AND NOT agrees), \
            report_count = (SELECT COUNT(*) FROM supplement_catalog_reports WHERE entry_id = \(bind: entryID)) \
            WHERE id = \(bind: entryID)
            """).run()
        }
    }

    // MARK: Reports (App Store 1.2: users can flag wrong info)

    /// Hidden from lookup and search once at least 2 people reported it AND reports >= confirmations.
    static func isHidden(_ entry: SupplementCatalogEntry) -> Bool {
        entry.reportCount >= 2 && entry.reportCount >= entry.confirmationCount
    }

    /// One report per user per entry; repeating it changes nothing.
    static func report(entryID: UUID, userID: String, on db: Database) async throws {
        guard try await SupplementCatalogEntry.find(entryID, on: db) != nil else {
            throw Abort(.notFound, reason: "Product not found.")
        }
        let already = try await SupplementCatalogReport.query(on: db)
            .filter(\.$entryID == entryID).filter(\.$userID == userID).count()
        if already == 0 {
            try? await SupplementCatalogReport(entryID: entryID, userID: userID).save(on: db)
        }
        try await recount(entryIDs: [entryID], on: db)
    }

    // MARK: Account deletion

    /// The user's footprint in the shared catalog: entries they created stay for everyone else
    /// but lose the link to them; their confirmations, disputes and reports go, and the
    /// affected entries' counts are recomputed.
    static func forget(userID: String, on db: Database) async throws {
        var affected = Set<UUID>()
        for row in try await SupplementCatalogConfirmation.query(on: db).filter(\.$userID == userID).all() {
            affected.insert(row.entryID)
        }
        for row in try await SupplementCatalogReport.query(on: db).filter(\.$userID == userID).all() {
            affected.insert(row.entryID)
        }
        for entry in try await SupplementCatalogEntry.query(on: db).filter(\.$contributorID == userID).all() {
            if let id = entry.id { affected.insert(id) }
        }
        try await SupplementCatalogEntry.query(on: db).filter(\.$contributorID == userID)
            .set(\.$contributorID, to: nil).update()
        try await SupplementCatalogConfirmation.query(on: db).filter(\.$userID == userID).delete()
        try await SupplementCatalogReport.query(on: db).filter(\.$userID == userID).delete()
        try await recount(entryIDs: Array(affected), on: db)
    }

    // MARK: Read

    static func entry(upc: String, on db: Database) async throws -> SupplementCatalogEntry? {
        let found = try await SupplementCatalogEntry.query(on: db).filter(\.$entryKey == "upc:\(upc)").first()
        return found.flatMap { isHidden($0) ? nil : $0 }
    }

    static func entry(id: UUID, on db: Database) async throws -> SupplementCatalogEntry? {
        let found = try await SupplementCatalogEntry.find(id, on: db)
        return found.flatMap { isHidden($0) ? nil : $0 }
    }

    /// Entries where every query word appears in brand or name (case-insensitive), best-confirmed first.
    static func search(query: String, limit: Int = 10, on db: Database) async throws -> [SupplementCatalogEntry] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).prefix(6).map(String.init)
        guard !words.isEmpty else { return [] }
        let builder = SupplementCatalogEntry.query(on: db)
        for word in words {
            let pattern = "%" + word.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
            builder.group(.or) { group in
                group.filter(\.$name, .custom("ILIKE"), pattern)
                group.filter(\.$brand, .custom("ILIKE"), pattern)
            }
        }
        return try await builder.sort(\.$confirmationCount, .descending).sort(\.$updatedAt, .descending).limit(limit * 3).all()
            .filter { !isHidden($0) }.prefix(limit).map { $0 }
    }

    static func dto(_ entry: SupplementCatalogEntry, on _: Database) async throws -> SupplementLookupDTO {
        SupplementLookupDTO(
            upc: entry.upc ?? "",
            brand: entry.brand,
            name: entry.name,
            kind: entry.kind,
            dosePerServing: entry.dosePerServing,
            servingsPerContainer: entry.servingsPerContainer,
            proteinGramsPerServing: entry.proteinGramsPerServing,
            caloriesPerServing: entry.caloriesPerServing,
            carbsGramsPerServing: entry.carbsGramsPerServing,
            fatGramsPerServing: entry.fatGramsPerServing,
            certifications: [],
            source: "tempo",
            ingredients: entry.ingredients.isEmpty ? nil : entry.ingredients,
            communityConfirmations: max(1, entry.confirmationCount),
            disputed: entry.disputeCount > 0 ? true : nil,
            catalogID: entry.id?.uuidString.lowercased()
        )
    }

    static func searchHit(_ entry: SupplementCatalogEntry) -> SupplementSearchHit {
        SupplementSearchHit(
            id: "tempo:\(entry.id?.uuidString.lowercased() ?? "")", brand: entry.brand, name: entry.name, kind: entry.kind,
            netContents: nil, onMarket: true, source: "tempo"
        )
    }
}

// MARK: - Request body

/// camelCase on purpose: the app's global decoder converts the snake_case wire keys.
struct SupplementCatalogRequest: Content {
    let upc: String?
    let brand: String?
    let name: String
    let kind: String
    let dosePerServing: String?
    let servingsPerContainer: Double?
    let proteinGramsPerServing: Double?
    let caloriesPerServing: Double?
    let carbsGramsPerServing: Double?
    let fatGramsPerServing: Double?
    let ingredients: [String]?
    let origin: String
}
