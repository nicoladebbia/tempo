//
// SupplementLookupService.swift
// Tempo
//
// Barcode → product for the supplement shelf, via the backend contract in
// APIEndpoints+Supplements.swift (lane building `GET /v1/supplements/lookup/:upc`
// in parallel). Split behind a protocol + a pure outcome mapper so the scan
// flow's error handling (404 / offline / other failure → manual form) is
// unit-testable without hitting the network or SwiftUI.
//

import Foundation

// MARK: - SupplementLookupServicing

@MainActor
protocol SupplementLookupServicing: Sendable {
    func lookUp(upc: String) async throws -> SupplementLookupDTO
}

// MARK: - LiveSupplementLookupService

struct LiveSupplementLookupService: SupplementLookupServicing {
    let apiClient: APIClient

    func lookUp(upc: String) async throws -> SupplementLookupDTO {
        try await apiClient.request(.supplementLookup(upc: upc))
    }
}

// MARK: - SupplementLookupOutcome

/// What the scan screen should show, collapsed from the raw `APIError` into
/// the three states the UI actually branches on.
enum SupplementLookupOutcome: Equatable {
    case found(SupplementLookupDTO)
    /// Backend doesn't know this barcode (404).
    case notFound
    /// No network — checked before the request is attempted.
    case offline
    /// Anything else (server error, timeout, decoding failure, …).
    case failed(String)
}

// MARK: - SupplementLookupRunner

/// Pure orchestration around `SupplementLookupServicing` — takes an offline
/// flag instead of reaching for `NetworkStatus` itself so it can be driven
/// deterministically from a test.
enum SupplementLookupRunner {
    static func run(
        upc: String,
        isOffline: Bool,
        using service: any SupplementLookupServicing
    ) async -> SupplementLookupOutcome {
        if isOffline {
            return .offline
        }
        do {
            let dto = try await service.lookUp(upc: upc)
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
