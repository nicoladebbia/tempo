//
// GroceryShareMenu.swift
// Tempo
//
// Created by Tempo on 26/09/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - GroceryShareMenu

//
// Menu of every "get this list out of the app" action for a GroceryList
// (feat/grocery-share-order, Lane C): share as plain text, a live shopper
// link, or order online. Self-contained — creates its own
// SharedGroceryListService from `services.apiClient` rather than going
// through ServiceContainer (this is the only call site).
//
// Wired into GroceryListView's toolbar via a single, clearly-marked line —
// see GroceryListView.swift's `ToolbarItem(placement: .topBarTrailing)`.

struct GroceryShareMenu: View {
    let list: GroceryList

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.openURL)
    private var openURL

    @State private var service: SharedGroceryListService?
    @State private var share: GroceryShare?
    @State private var isWorking = false
    @State private var errorMessage: String?

    @State private var textToShare: String?
    @State private var showLiveLinkSheet = false
    @State private var showOrderLinksSheet = false

    var body: some View {
        Menu {
            Button {
                textToShare = GroceryShareTextFormatter.text(for: list)
            } label: {
                Label("Share as Text", systemImage: "doc.plaintext")
            }

            if let share, share.isLive {
                Button {
                    showLiveLinkSheet = true
                } label: {
                    Label("Share Live Link", systemImage: "link")
                }
            } else {
                Button {
                    Task { await startSharing() }
                } label: {
                    Label("Share Live Link", systemImage: "link.badge.plus")
                }
            }

            Button {
                Task { await orderOnInstacart() }
            } label: {
                Label("Order on Instacart", systemImage: "cart.badge.plus")
            }

            Button {
                showOrderLinksSheet = true
            } label: {
                Label("Find Online", systemImage: "magnifyingglass")
            }
        } label: {
            if isWorking {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
        .disabled(isWorking)
        .task {
            let svc = SharedGroceryListService(apiClient: services.apiClient)
            service = svc
            share = svc.fetchShare(for: list, in: modelContext)
        }
        .sheet(item: Binding(
            get: { textToShare.map { ShareTextPayload(text: $0) } },
            set: {
                if $0 == nil {
                    textToShare = nil
                }
            }
        )) { payload in
            ShareSheet(items: [payload.text])
        }
        .sheet(isPresented: $showLiveLinkSheet) {
            if let share {
                ShareLiveLinkSheet(share: share) {
                    Task { await stopSharing() }
                }
            }
        }
        .sheet(isPresented: $showOrderLinksSheet) {
            GroceryOrderLinksSheet(itemNames: list.activeItems.map(\.displayName))
        }
        .alert("Grocery Sharing", isPresented: Binding(
            get: { errorMessage != nil },
            set: {
                if !$0 {
                    errorMessage = nil
                }
            }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Actions

    private func startSharing() async {
        guard let service else {
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            share = try await service.startSharing(list: list, in: modelContext)
            showLiveLinkSheet = true
            HapticManager.lightImpact()
        } catch {
            errorMessage = (error as? APIError)?.userMessage ?? "Couldn't create the share link. Try again."
        }
    }

    private func stopSharing() async {
        guard let service else {
            return
        }
        isWorking = true
        defer { isWorking = false }
        await service.stopSharing(list: list, in: modelContext)
        share = service.fetchShare(for: list, in: modelContext)
    }

    private func orderOnInstacart() async {
        guard let service else {
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await service.createInstacartCartURL(items: list.activeItems)
            openURL(url)
        } catch {
            // Not configured server-side, or the Instacart request failed —
            // fall back to per-item search links rather than an error.
            showOrderLinksSheet = true
        }
    }
}

// MARK: - ShareTextPayload

/// `ShareLink`'s text-item form needs no wrapper, but presenting the
/// existing `ShareSheet` (UIActivityViewController) via `.sheet(item:)`
/// does — `String` isn't `Identifiable`.
private struct ShareTextPayload: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - ShareLiveLinkSheet

/// Shown right after a live link is created (or reopened from the menu).
/// Surfaces the URL, a system share sheet, and "Stop Sharing" in one place
/// so the owner doesn't have to dig back into the toolbar menu to revoke it.
struct ShareLiveLinkSheet: View {
    let share: GroceryShare
    var onStopSharing: () -> Void

    @Environment(\.dismiss)
    private var dismiss
    @State private var showSystemShareSheet = false
    @State private var showStopConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.lg) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.tempoSignal)
                Text("Anyone with this link can check off items while you shop — no Tempo account needed.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                Text(share.url)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                Spacer()
                Button {
                    showSystemShareSheet = true
                } label: {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                Button(role: .destructive) {
                    showStopConfirmation = true
                } label: {
                    Text("Stop Sharing")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
            }
            .padding(TempoSpacing.screenEdge)
            .navigationTitle("Live Shared List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSystemShareSheet) {
                if let url = URL(string: share.url) {
                    ShareSheet(items: [url])
                }
            }
            .confirmationDialog(
                "Stop sharing this list?",
                isPresented: $showStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Sharing", role: .destructive) {
                    onStopSharing()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The link will stop working immediately.")
            }
        }
    }
}

// MARK: - GroceryOrderLinksSheet

/// Fallback "find it online" list — one row per item, each opening a
/// pre-filled search on Instacart (Publix/Aldi) or Amazon (Whole Foods).
/// Shown when Instacart's "Order online" isn't configured server-side, or
/// the request otherwise fails.
struct GroceryOrderLinksSheet: View {
    let itemNames: [String]

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.openURL)
    private var openURL

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Instacart ordering isn't set up yet, or the request failed. Search for each item instead:")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                ForEach(GroceryOrderLinks.fallbackLinks(for: itemNames)) { link in
                    Button {
                        openURL(link.url)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(link.itemName)
                                    .font(.tempoBody)
                                    .foregroundStyle(Color.tempoTextPrimary)
                                Text(link.storeName)
                                    .font(.tempoCaption2)
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
            .navigationTitle("Find Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
