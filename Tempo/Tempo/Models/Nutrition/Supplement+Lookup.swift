//
// Supplement+Lookup.swift
// Tempo
//
// Bridges the barcode-lookup wire contract (`SupplementLookupDTO`, see
// APIEndpoints+Supplements.swift) onto the shelf model, plus the small pure
// helpers the scan flow needs: detecting "you already own this" and turning
// a rescan into a restock instead of a duplicate row. Kept separate from
// Supplement.swift (shared groundwork another lane also reads) to avoid
// churn on that file.
//

import Foundation

extension Supplement {
    /// Builds a new shelf item from a successful barcode lookup. Servings
    /// start at a full container — this path is for a NEW product, never a
    /// restock (see `duplicate(forUPC:name:in:)` + `restock(fromContainerSize:)`
    /// for the "already own this" path).
    convenience init(lookup dto: SupplementLookupDTO) {
        self.init(
            name: dto.name,
            kind: SupplementKind(rawValue: dto.kind) ?? .other,
            dosePerServing: dto.dosePerServing ?? "",
            proteinGramsPerServing: dto.proteinGramsPerServing ?? 0,
            servingsRemaining: dto.servingsPerContainer ?? 0
        )
        brand = dto.brand
        upc = dto.upc
        servingsPerContainer = dto.servingsPerContainer
    }

    /// Finds the shelf item a new scan should be treated as a restock of:
    /// same UPC first (the exact product), else the same name
    /// case-insensitively (label/reprint changed the barcode but not the
    /// product). Archived items don't count — an archived supplement being
    /// rescanned should come back as a new/active row, not silently restock
    /// a shelf item the user already retired.
    static func duplicate(forUPC upc: String, name: String, in shelf: [Supplement]) -> Supplement? {
        let active = shelf.filter { !$0.isArchived }
        if let byUPC = active.first(where: { $0.upc == upc }) {
            return byUPC
        }
        return active.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Restocks from a freshly scanned/bought container: tops up
    /// `servingsRemaining` by a full container and stamps `lastRestockedAt`.
    func restock(fromContainerSize containerSize: Double) {
        servingsRemaining += max(0, containerSize)
        lastRestockedAt = Date()
        updatedAt = Date()
    }
}
