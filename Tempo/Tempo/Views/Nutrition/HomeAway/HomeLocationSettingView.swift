//
// HomeLocationSettingView.swift
// Tempo
//
// Where the user says where home is. "I'm home now" is the ONLY place in the
// app that asks for location permission; logging a meal never prompts. The
// spot is stored on this device only (HomeLocationStore) and never leaves it.
//

import CoreLocation
import MapKit
import SwiftUI

struct HomeLocationSettingView: View {
    var onChange: () -> Void = {}

    @Environment(\.locationFixProvider)
    private var locationProvider
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var home: HomeLocation? = HomeLocationStore().home
    @State
    private var query = ""
    @State
    private var results: [MKMapItem] = []
    @State
    private var isWorking = false
    @State
    private var message: String?

    private let store = HomeLocationStore()

    /// How far from the pin still counts as home, in metres (the line under the map says "about 150 m").
    private static let homeRadius: Double = 150

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    currentCard
                    if let message {
                        FuelBanner(icon: "location.slash.fill", tint: Tide.warn, title: message)
                    }
                    searchSection
                    Label("Home stays on this phone. It is never uploaded or shared with the AI.", systemImage: "lock.fill")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollDismissesKeyboard(.interactively)
            .fuelBottomBar {
                Button {
                    Task { await setHomeHere() }
                } label: {
                    Label(isWorking ? "Locating…" : "I'm home now", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tidePrimary)
                .disabled(isWorking)
                .accessibilityIdentifier("homeSetHere")
            }
            .animation(Tide.snap, value: message)
            .tidePage()
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("homeDone")
                }
            }
        }
        // A sheet is its own page, even when it comes up from inside one.
        .environment(\.tideInsidePage, false)
    }

    /// The map is the hero: the pin and the 150 m that count as home. Without
    /// a home it says what setting one does.
    @ViewBuilder
    private var currentCard: some View {
        if let home {
            let center = CLLocationCoordinate2D(latitude: home.latitude, longitude: home.longitude)
            VStack(spacing: 0) {
                Map(
                    position: .constant(.region(MKCoordinateRegion(
                        center: center, latitudinalMeters: Self.homeRadius * 6, longitudinalMeters: Self.homeRadius * 6
                    ))),
                    interactionModes: []
                ) {
                    MapCircle(center: center, radius: Self.homeRadius)
                        .foregroundStyle(mood.accent.opacity(0.22))
                        .stroke(mood.accent, lineWidth: 2)
                    Marker("Home", systemImage: "house.fill", coordinate: center)
                        .tint(mood.accent)
                }
                .frame(height: Tide.fuelPhoto * 0.75)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                HStack(spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(home.label ?? "Home set")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Within about 150 m counts as home.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive) {
                        store.clearHome()
                        self.home = nil
                        results = []
                        onChange()
                    } label: {
                        Text("Clear")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.danger)
                            .padding(.horizontal, Tide.s2)
                            .frame(minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("homeClear")
                }
                .padding(Tide.s4)
            }
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.tileRadius))
            .clipShape(.rect(cornerRadius: Tide.tileRadius))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("homeCurrent")
        } else {
            FuelEmptyState(icon: "house", title: "No home set", message: "Set it so Tempo knows when you eat in.")
                .accessibilityIdentifier("homeCurrent")
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: "Or search an address")
                .padding(.horizontal, Tide.s1)
            HStack(spacing: Tide.s2) {
                Image(systemName: "magnifyingglass")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
                TextField("Street, city", text: $query)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .accessibilityIdentifier("homeSearchField")
            }
            .fuelField(radius: Tide.tileRadius)
            if !results.isEmpty {
                FuelRowGroup {
                    ForEach(results, id: \.self) { item in
                        Button {
                            choose(item)
                        } label: {
                            HStack(spacing: Tide.s3) {
                                VStack(alignment: .leading, spacing: Tide.hair) {
                                    Text(item.name ?? "Address")
                                        .font(Tide.bodyStrong)
                                        .foregroundStyle(Tide.text)
                                        .multilineTextAlignment(.leading)
                                    if let title = item.address?.fullAddress {
                                        Text(title)
                                            .font(Tide.caption)
                                            .foregroundStyle(Tide.text2)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "mappin.circle")
                                    .font(Tide.headline)
                                    .foregroundStyle(mood.accent)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func setHomeHere() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        guard await locationProvider.requestPermission() else {
            message = "Location is off for Tempo. Turn it on in Settings, or search an address below."
            return
        }
        guard let fix = await locationProvider.fixIfAuthorized(timeout: 8) else {
            message = "Couldn't get a fix. Try again, or search an address."
            return
        }
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= HomeAwayDecider.maxUsableAccuracy else {
            message = "That fix is too rough. Step outside or search an address."
            return
        }
        save(fix.coordinate, label: "Where I am now")
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        results = await Array(((try? MKLocalSearch(request: request).start().mapItems) ?? []).prefix(5))
        message = results.isEmpty ? "No match. Try a fuller address." : nil
    }

    private func choose(_ item: MKMapItem) {
        save(item.location.coordinate, label: item.address?.fullAddress ?? item.name)
        results = []
    }

    private func save(_ coordinate: CLLocationCoordinate2D, label: String?) {
        store.setHome(latitude: coordinate.latitude, longitude: coordinate.longitude, label: label)
        home = store.home
        message = nil
        HapticManager.success()
        onChange()
    }
}
