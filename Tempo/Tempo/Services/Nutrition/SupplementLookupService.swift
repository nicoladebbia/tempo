//
// SupplementLookupService.swift
// Tempo
//
// Barcode → product for the supplement shelf. Sources, in order:
//   1. the user's own shelf (works offline, makes a rescan a restock)
//   2. the on-device cache of every earlier hit
//   3. the backend (`GET /v1/supplements/lookup/:upc`), which asks NIH DSLD by
//      UPC, then Open Food / Products / Beauty Facts, and caches hits in Redis
// plus a DSLD name search for the "type the name" path. Split behind a
// protocol + a pure outcome mapper so the scan flow's handling is
// unit-testable without the network or SwiftUI.
//

import Foundation

// MARK: - SupplementLookupServicing

@MainActor
protocol SupplementLookupServicing: Sendable {
    func lookUp(upc: String) async throws -> SupplementLookupDTO
    func search(query: String) async throws -> [SupplementSearchHit]
    func label(id: String) async throws -> SupplementLookupDTO
    /// Photo of the label (base64 JPEG) → AI-read product. Not saved anywhere.
    func readLabel(imageBase64: String, mediaType: String, upc: String?) async throws -> SupplementLookupDTO
    /// Shares a product with the Tempo catalog. Best effort for callers.
    func submitToCatalog(_ submission: SupplementCatalogSubmission) async throws -> SupplementLookupDTO
}

extension SupplementLookupServicing {
    func search(query _: String) async throws -> [SupplementSearchHit] {
        []
    }

    func label(id _: String) async throws -> SupplementLookupDTO {
        throw APIError.notFound
    }

    func readLabel(imageBase64 _: String, mediaType _: String, upc _: String?) async throws -> SupplementLookupDTO {
        throw APIError.notFound
    }

    func submitToCatalog(_: SupplementCatalogSubmission) async throws -> SupplementLookupDTO {
        throw APIError.notFound
    }
}

// MARK: - LiveSupplementLookupService

struct LiveSupplementLookupService: SupplementLookupServicing {
    let apiClient: APIClient

    func lookUp(upc: String) async throws -> SupplementLookupDTO {
        try await apiClient.request(.supplementLookup(upc: upc))
    }

    func search(query: String) async throws -> [SupplementSearchHit] {
        try await apiClient.request(.supplementSearch(), queryItems: [URLQueryItem(name: "q", value: query)])
    }

    func label(id: String) async throws -> SupplementLookupDTO {
        try await apiClient.request(.supplementLabel(id: id))
    }

    func readLabel(imageBase64: String, mediaType: String, upc: String?) async throws -> SupplementLookupDTO {
        let body = SupplementReadLabelRequest(imageBase64: imageBase64, mediaType: mediaType, upc: upc)
        return try await apiClient.request(.supplementReadLabel(), body: body)
    }

    func submitToCatalog(_ submission: SupplementCatalogSubmission) async throws -> SupplementLookupDTO {
        try await apiClient.request(.supplementCatalogSubmit(), body: submission)
    }
}

// MARK: - SupplementLookupOutcome

/// What the scan screen should show, collapsed from the raw `APIError` into
/// the states the UI actually branches on.
enum SupplementLookupOutcome: Equatable {
    case found(SupplementLookupDTO)
    /// No database knows this barcode (404).
    case notFound
    /// No network — and neither the shelf nor the cache knew it.
    case offline
    /// The barcode itself is wrong (length / check digit). Carries the message.
    case invalid(String)
    /// Anything else (server error, timeout, decoding failure, …).
    case failed(String)
}

// MARK: - SupplementLookupRunner

/// Pure orchestration around `SupplementLookupServicing` — takes an offline
/// flag instead of reaching for `NetworkStatus` itself so it can be driven
/// deterministically from a test.
@MainActor
enum SupplementLookupRunner {
    static func run(
        upc: String,
        isOffline: Bool,
        using service: any SupplementLookupServicing,
        shelf: [Supplement] = [],
        cache: SupplementLookupCache? = nil
    ) async -> SupplementLookupOutcome {
        let barcode: SupplementBarcode
        switch SupplementBarcode.normalize(upc) {
        case let .success(value): barcode = value
        case let .failure(failure): return .invalid(failure.message)
        }

        // 1. The shelf: you already own this exact barcode.
        if let owned = shelf.first(where: { !$0.isArchived && $0.upc.map { barcode.variants.contains($0) } == true }) {
            return .found(SupplementLookupDTO(shelfItem: owned, upc: barcode.canonical))
        }
        // 2. Everything a past lookup resolved.
        if let cached = cache?.dto(for: barcode) {
            return .found(cached)
        }
        if isOffline {
            return .offline
        }
        // 3. The backend (DSLD → Open Facts).
        do {
            let dto = try await service.lookUp(upc: barcode.canonical)
            cache?.store(dto, for: barcode)
            return .found(dto)
        } catch APIError.notFound {
            return .notFound
        } catch let error as APIError {
            return .failed(error.userMessage)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

// MARK: - Shelf item → DTO

extension SupplementLookupDTO {
    /// A product the user already owns, in the shape a lookup returns, so the
    /// scan flow's "already on your shelf → restock" path is one code path.
    init(shelfItem s: Supplement, upc: String) {
        self.init(
            upc: upc,
            brand: s.brand,
            name: s.name,
            kind: s.kindRaw,
            dosePerServing: s.dosePerServing.isEmpty ? nil : s.dosePerServing,
            servingsPerContainer: s.servingsPerContainer,
            proteinGramsPerServing: s.proteinGramsPerServing > 0 ? s.proteinGramsPerServing : nil,
            caloriesPerServing: s.caloriesPerServing,
            carbsGramsPerServing: s.carbsGramsPerServing,
            fatGramsPerServing: s.fatGramsPerServing,
            certifications: [],
            source: "shelf"
        )
    }
}
