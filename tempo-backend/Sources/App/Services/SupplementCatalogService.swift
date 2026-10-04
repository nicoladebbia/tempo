import Fluent
import Foundation
import Redis
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
        let count = try await req.redis.increment(key).get()
        if count == 1 {
            _ = try await req.redis.expire(key, after: .seconds(24 * 3600)).get()
        }
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
                    apply(s, to: existing)
                    existing.updatedAt = Date()
                    try await existing.save(on: db)
                } else if SupplementText.dedupeKey(brand: existing.brand, name: existing.name)
                    == SupplementText.dedupeKey(brand: s.brand, name: s.name)
                {
                    try await confirm(existing, userID: userID, on: db)
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

    /// Idempotent: one confirmation per user.
    private static func confirm(_ entry: SupplementCatalogEntry, userID: String, on db: Database) async throws {
        let entryID = try entry.requireID()
        let already = try await SupplementCatalogConfirmation.query(on: db)
            .filter(\.$entryID == entryID).filter(\.$userID == userID).count()
        if already == 0 {
            do {
                try await SupplementCatalogConfirmation(entryID: entryID, userID: userID).save(on: db)
            } catch {
                // Same user confirmed in parallel: the unique index made it a no-op.
            }
        }
        let total = try await SupplementCatalogConfirmation.query(on: db).filter(\.$entryID == entryID).count()
        if total != entry.confirmationCount {
            entry.confirmationCount = max(1, total)
            try await entry.save(on: db)
        }
    }

    // MARK: Read

    static func entry(upc: String, on db: Database) async throws -> SupplementCatalogEntry? {
        try await SupplementCatalogEntry.query(on: db).filter(\.$entryKey == "upc:\(upc)").first()
    }

    static func entry(id: UUID, on db: Database) async throws -> SupplementCatalogEntry? {
        try await SupplementCatalogEntry.find(id, on: db)
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
        return try await builder.sort(\.$confirmationCount, .descending).sort(\.$updatedAt, .descending).limit(limit).all()
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
            communityConfirmations: max(1, entry.confirmationCount)
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
