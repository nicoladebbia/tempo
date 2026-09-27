//
// SharedGroceryListService.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import Foundation
import SwiftData

// MARK: - SharedGroceryListService

//
// Owns the "live shared grocery list" link (feat/grocery-share-order, Lane
// C) — pushing a GroceryList's current state to the backend as a public
// `/g/<token>` page a shopper can open without a Tempo account, and pulling
// their checked-item ticks back in.
//
// Deliberately self-contained: NOT added to ServiceContainer. Callers
// (GroceryShareMenu) create one locally via
// `SharedGroceryListService(apiClient: services.apiClient)` — this mirrors
// how ExerciseImageService/RecoveryAIInsightService are constructed, but
// those ARE container-owned because multiple, unrelated views read them;
// grocery sharing only has one call site.
//
// LWW merge contract (see GroceryShare.swift and the backend's
// GroceryShareControllerTests.staleOwnerPushDoesNotClobberNewerShopperTick):
// every push only bumps an item's timestamp to "now" when its `checked`
// value actually changed since the last synced baseline; otherwise it
// resends the OLD baseline timestamp, so the server's last-write-wins
// comparison can't let a stale full-snapshot push overwrite a more recent
// shopper tick.

@MainActor
@Observable
final class SharedGroceryListService {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Local lookup

    func fetchShare(for list: GroceryList, in modelContext: ModelContext) -> GroceryShare? {
        let listID = list.id
        let descriptor = FetchDescriptor<GroceryShare>(
            predicate: #Predicate { $0.listID == listID }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Start / refresh

    /// Creates a new share (first call) or replaces an existing one's
    /// snapshot (already shared for this list). Returns the local record —
    /// `share.url` is what to hand to `ShareLink`.
    @discardableResult
    func startSharing(
        list: GroceryList,
        title: String = "Grocery List",
        store: String? = nil,
        in modelContext: ModelContext
    ) async throws -> GroceryShare {
        let existing = fetchShare(for: list, in: modelContext)
        return try await push(list: list, title: title, store: store, existing: existing, in: modelContext)
    }

    /// Re-pushes the current in-app state to an already-live share. No-op
    /// (and no network call) when there's no active share — callers should
    /// call this on every local edit to a shared list (debounced) rather
    /// than gate on share state themselves.
    func refreshSnapshot(
        for list: GroceryList,
        title: String = "Grocery List",
        store: String? = nil,
        in modelContext: ModelContext
    ) async throws {
        guard let existing = fetchShare(for: list, in: modelContext), existing.isLive else {
            return
        }
        _ = try await push(list: list, title: title, store: store, existing: existing, in: modelContext)
    }

    private func push(
        list: GroceryList,
        title: String,
        store: String?,
        existing: GroceryShare?,
        in modelContext: ModelContext
    ) async throws -> GroceryShare {
        let baseline = Dictionary(
            uniqueKeysWithValues: (existing?.decodedItemState() ?? []).map { ($0.id, $0) }
        )
        let now = Date()
        var newBaseline: [GroceryShareItemState] = []

        let items: [GroceryShareItemUpsertDTO] = list.activeItems.map { item in
            let idString = item.id.uuidString
            let updatedAt: Date = if let prior = baseline[idString], prior.checked == item.isChecked {
                // Unchanged locally since the last sync — keep the OLD
                // timestamp. A fresh "now" here would let a routine,
                // content-only re-push (e.g. adding an item) silently win a
                // last-write-wins race against a shopper's more recent tick.
                prior.updatedAt
            } else {
                now
            }
            newBaseline.append(GroceryShareItemState(id: idString, checked: item.isChecked, updatedAt: updatedAt))
            return GroceryShareItemUpsertDTO(
                id: idString,
                name: item.displayName,
                quantity: item.quantity,
                unit: item.unit.displayName,
                category: item.category,
                checked: item.isChecked,
                updatedAt: updatedAt
            )
        }

        let requestBody = GroceryShareUpsertRequestDTO(
            token: existing?.token,
            title: title,
            store: store,
            items: items
        )
        let dto = try await apiClient.request(.upsertGroceryShare(), body: requestBody)

        let share: GroceryShare
        if let existing {
            share = existing
        } else {
            share = GroceryShare(listID: list.id, token: dto.token, url: dto.url, expiresAt: dto.expiresAt)
            modelContext.insert(share)
        }
        share.token = dto.token
        share.url = dto.url
        share.expiresAt = dto.expiresAt
        share.revoked = dto.revoked
        share.itemStateJSON = GroceryShare.encodeItemState(newBaseline)
        try? modelContext.save()
        return share
    }

    // MARK: - Pull

    /// Applies any shopper ticks from the backend onto the local
    /// GroceryListItem rows, by matching stable item id. Call on screen
    /// appear / foreground while a share is active. No-op if there's no
    /// live share.
    func pullAndApply(list: GroceryList, in modelContext: ModelContext) async throws {
        guard let share = fetchShare(for: list, in: modelContext), share.isLive else {
            return
        }
        let dto = try await apiClient.request(.getGroceryShare(token: share.token))

        share.expiresAt = dto.expiresAt
        share.revoked = dto.revoked
        guard !dto.revoked else {
            try? modelContext.save()
            return
        }

        var itemsByID: [String: GroceryListItem] = [:]
        for item in list.orderedItems {
            itemsByID[item.id.uuidString] = item
        }

        var baseline = Dictionary(uniqueKeysWithValues: share.decodedItemState().map { ($0.id, $0) })
        for remote in dto.items {
            guard let local = itemsByID[remote.id] else {
                continue
            }
            let priorBaseline = baseline[remote.id]
            // Only pull the remote value forward when it's newer than what
            // we last synced — otherwise a slow/out-of-order pull could
            // stomp an owner's in-app toggle made after the last push.
            if priorBaseline == nil || remote.updatedAt > priorBaseline!.updatedAt {
                local.isChecked = remote.checked
                baseline[remote.id] = GroceryShareItemState(id: remote.id, checked: remote.checked, updatedAt: remote.updatedAt)
            }
        }
        share.itemStateJSON = GroceryShare.encodeItemState(Array(baseline.values))
        try? modelContext.save()
    }

    // MARK: - Stop

    func stopSharing(list: GroceryList, in modelContext: ModelContext) async {
        guard let share = fetchShare(for: list, in: modelContext) else {
            return
        }
        // Best-effort revoke — still mark revoked locally even if the
        // network call fails (offline, already expired server-side, etc.)
        // so this app stops pushing/pulling for it regardless.
        _ = try? await apiClient.request(.revokeGroceryShare(token: share.token))
        share.revoked = true
        try? modelContext.save()
    }

    // MARK: - Instacart

    /// Asks the backend to build an Instacart "shopping list" link for
    /// `items`. Throws when `INSTACART_API_KEY` isn't configured server-side
    /// or the Instacart request otherwise fails — callers should fall back
    /// to `GroceryOrderLinks.fallbackLinks(for:)` on ANY error here.
    func createInstacartCartURL(
        items: [GroceryListItem],
        title: String = "Tempo Grocery List"
    ) async throws -> URL {
        let wireItems = items.map {
            InstacartCartItemWireDTO(name: $0.displayName, quantity: $0.quantity, unit: $0.unit.displayName)
        }
        let dto = try await apiClient.request(
            .createInstacartCart(),
            body: InstacartCartRequestDTO(title: title, items: wireItems)
        )
        guard let url = URL(string: dto.url) else {
            throw APIError.decodingFailed("Instacart returned an invalid URL")
        }
        return url
    }
}
