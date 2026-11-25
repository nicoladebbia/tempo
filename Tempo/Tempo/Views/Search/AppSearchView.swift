//
// AppSearchView.swift
// Tempo
//
// Search from anywhere: one field, instant results over screens, settings,
// exercises, saved meals and pantry items. A tap goes straight to the place.
// The shell hosts it (`appSearchHost`), so any screen can open it by setting
// `AppState.searchRequested`.
//

import SwiftData
import SwiftUI

// MARK: - AppSearchView

struct AppSearchView: View {
    /// Called with the chosen destination; the host closes the sheet and goes there.
    let onPick: (AppSearchDestination) -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var query = ""
    @State
    private var entries = AppSearchCatalog.all
    @FocusState
    private var focused: Bool

    private var results: [AppSearchEntry] {
        AppSearchMatcher.results(for: query, in: entries)
    }

    private var isSearching: Bool {
        !AppSearchMatcher.normalize(query).isEmpty
    }

    /// With nothing typed, the screens are listed so the sheet is also a menu.
    private var shown: [AppSearchEntry] {
        isSearching ? results : entries.filter { $0.section == .screens }
    }

    var body: some View {
        TideScrollPage(spacing: Tide.s5, spacer: Tide.s2) {
            if shown.isEmpty {
                TideEmptyPanel(
                    systemImage: "magnifyingglass",
                    title: "Nothing found",
                    message: "Try another word: a screen, a setting, an exercise, a saved meal or a pantry item."
                )
                .accessibilityIdentifier("search.empty")
            } else {
                ForEach(AppSearchEntry.Section.allCases, id: \.self) { section in
                    let rows = shown.filter { $0.section == section }
                    if !rows.isEmpty {
                        TideSettingsSection(title: isSearching ? section.title : "Go to") {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                                if index > 0 {
                                    TideSettingsHairline(inset: Tide.s4 + Tide.icon + Tide.s3)
                                }
                                Button { onPick(entry.destination) } label: {
                                    SettingsNavRow(icon: entry.icon, title: entry.title, subtitle: entry.subtitle)
                                }
                                .buttonStyle(.tideSettingsRow)
                                .accessibilityIdentifier("search.result.\(entry.id)")
                            }
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            field
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s4)
                .padding(.bottom, Tide.s2)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            entries = AppSearchLoader.entries(in: modelContext)
            focused = true
        }
        .accessibilityIdentifier("search.sheet")
    }

    private var field: some View {
        HStack(spacing: Tide.s2) {
            HStack(spacing: Tide.s2) {
                Image(systemName: "magnifyingglass")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .accessibilityHidden(true)
                TextField("Search Tempo", text: $query)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .focused($focused)
                    .submitLabel(.search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        if let first = results.first {
                            onPick(first.destination)
                        }
                    }
                    .accessibilityIdentifier("search.field")
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Tide.text3)
                            .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                    .accessibilityIdentifier("search.clear")
                }
            }
            .padding(.leading, Tide.s4)
            .frame(minHeight: Tide.hit)
            .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)

            Button("Close") { dismiss() }
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .frame(minHeight: Tide.hit)
                .accessibilityIdentifier("search.close")
        }
    }
}

// MARK: - AppSearchHost

/// Presents search, Settings (optionally on one page) and "Ask Tempo" for the
/// whole app, and carries a chosen result to its place.
private struct AppSearchHost: ViewModifier {
    @Environment(ServiceContainer.self)
    private var services

    /// The result picked while the sheet is still closing; it is opened once the sheet is gone.
    @State
    private var pending: AppSearchDestination?

    func body(content: Content) -> some View {
        @Bindable
        var appState = services.appState
        content
            .sheet(isPresented: $appState.searchRequested, onDismiss: openPending) {
                AppSearchView { destination in
                    pending = destination
                    appState.searchRequested = false
                }
            }
            .sheet(item: $appState.requestedSettings) { request in
                SettingsSheet(page: request.page)
            }
            .sheet(isPresented: $appState.askRequested) {
                CoachChat()
            }
    }

    private func openPending() {
        guard let destination = pending else {
            return
        }
        pending = nil
        AppSearchRouter.perform(AppSearchAction.resolve(destination), appState: services.appState)
    }
}

extension View {
    /// Hosts the search sheet, the Settings sheet and "Ask Tempo" for the whole app.
    func appSearchHost() -> some View {
        modifier(AppSearchHost())
    }
}

// MARK: - AppSearchRouter

/// Carries an `AppSearchAction` out against the app's existing routing.
enum AppSearchRouter {
    @MainActor
    static func perform(_ action: AppSearchAction, appState: AppState) {
        switch action {
        case let .selectTab(tab):
            tab == .today ? appState.open(.today) : (appState.activeTab = tab)
        case let .pushToday(route):
            appState.openOnToday(route)
        case let .presentSettings(page):
            appState.requestedSettings = SettingsRequest(page: page)
        case let .openTrain(page, exercise):
            appState.requestedTrain = TrainRoute(page: page, exercise: exercise)
            appState.activeTab = .train
        case let .openFuel(section, kitchen):
            appState.requestedNutrition = NutritionRoute(section: section, kitchen: kitchen)
            appState.activeTab = .fuel
        case .presentAsk:
            appState.askRequested = true
        }
    }
}
