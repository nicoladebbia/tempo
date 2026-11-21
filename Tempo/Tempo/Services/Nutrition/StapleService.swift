//
// StapleService.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - StapleServiceProtocol

@MainActor
protocol StapleServiceProtocol: AnyObject {
    func fetchAll() throws -> [PantryStaple]

    /// Seeds nothing by itself — returns `true` when the staples list is
    /// empty (so the caller can present the onboarding checklist), `false`
    /// once the user has at least one staple tracked.
    func shouldOfferOnboarding() throws -> Bool

    @discardableResult
    func addStaple(canonicalName: String, displayName: String, status: StapleStatus) throws -> PantryStaple

    /// Adds several at once from the onboarding checklist.
    func addStaples(_ picks: [(canonicalName: String, displayName: String)]) throws

    @discardableResult
    func cycleStatus(_ staple: PantryStaple) throws -> StapleStatus

    func delete(_ staple: PantryStaple) throws

}

// MARK: - LocalStapleService

@MainActor
@Observable
final class LocalStapleService: StapleServiceProtocol {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [PantryStaple] {
        let descriptor = FetchDescriptor<PantryStaple>(
            sortBy: [SortDescriptor(\.displayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func shouldOfferOnboarding() throws -> Bool {
        try fetchAll().isEmpty
    }

    @discardableResult
    func addStaple(canonicalName: String, displayName: String, status: StapleStatus = .have) throws -> PantryStaple {
        let canonical = FoodCanonicalizer.canonicalize(canonicalName)
        if let existing = try fetchAll().first(where: { $0.canonicalName == canonical }) {
            existing.status = status
            existing.updatedAt = Date()
            try modelContext.save()
            return existing
        }
        let staple = PantryStaple(canonicalName: canonical, displayName: displayName, status: status)
        modelContext.insert(staple)
        try modelContext.save()
        return staple
    }

    func addStaples(_ picks: [(canonicalName: String, displayName: String)]) throws {
        for pick in picks {
            try addStaple(canonicalName: pick.canonicalName, displayName: pick.displayName, status: .have)
        }
    }

    @discardableResult
    func cycleStatus(_ staple: PantryStaple) throws -> StapleStatus {
        let next = staple.status.next
        staple.status = next
        staple.updatedAt = Date()
        try modelContext.save()
        return next
    }

    func delete(_ staple: PantryStaple) throws {
        modelContext.delete(staple)
        try modelContext.save()
    }

}

// MARK: - MockStapleService

@MainActor
@Observable
final class MockStapleService: StapleServiceProtocol {
    private(set) var staples: [PantryStaple]

    init(staples: [PantryStaple] = []) {
        self.staples = staples
    }

    func fetchAll() throws -> [PantryStaple] {
        staples.sorted { $0.displayName < $1.displayName }
    }

    func shouldOfferOnboarding() throws -> Bool {
        staples.isEmpty
    }

    @discardableResult
    func addStaple(canonicalName: String, displayName: String, status: StapleStatus = .have) throws -> PantryStaple {
        let canonical = FoodCanonicalizer.canonicalize(canonicalName)
        if let existing = staples.first(where: { $0.canonicalName == canonical }) {
            existing.status = status
            return existing
        }
        let staple = PantryStaple(canonicalName: canonical, displayName: displayName, status: status)
        staples.append(staple)
        return staple
    }

    func addStaples(_ picks: [(canonicalName: String, displayName: String)]) throws {
        for pick in picks {
            try addStaple(canonicalName: pick.canonicalName, displayName: pick.displayName, status: .have)
        }
    }

    @discardableResult
    func cycleStatus(_ staple: PantryStaple) throws -> StapleStatus {
        let next = staple.status.next
        staple.status = next
        return next
    }

    func delete(_ staple: PantryStaple) throws {
        staples.removeAll { $0.id == staple.id }
    }

}
