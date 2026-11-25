//
// PlanModel.swift
// Tempo
//
// Holds the server's answer about the plan for the Settings row and the
// Subscription page, so both show the same thing. A failed refresh keeps the
// last answer instead of flipping a Pro account back to Free.
//

import Foundation

@Observable
@MainActor
final class PlanModel {
    enum Load: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private(set) var server: ServerPlan?
    private(set) var load: Load = .idle

    func refresh(fetch: @Sendable () async throws -> ServerPlan) async {
        load = .loading
        do {
            server = try await fetch()
            load = .loaded
        } catch {
            load = .failed
        }
    }

    func refresh(apiClient: APIClient) async {
        await refresh { try await ServerPlan.fetch(apiClient: apiClient) }
    }

    func status(device: SubscriptionState) -> PlanStatus {
        PlanStatus.resolve(server: server, device: device)
    }
}
