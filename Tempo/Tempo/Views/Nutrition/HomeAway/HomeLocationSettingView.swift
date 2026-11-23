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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    currentCard
                    Button {
                        Task { await setHomeHere() }
                    } label: {
                        Label(isWorking ? "Locating…" : "I'm home now", systemImage: "location.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tidePrimary)
                    .disabled(isWorking)
                    .accessibilityIdentifier("homeSetHere")

                    if let message {
                        Text(message)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    searchSection
                    Text("Home stays on this phone. It is never uploaded or shared with the AI.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s4)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
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
    }

    private var currentCard: some View {
        HStack(spacing: Tide.s3) {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(home == nil ? "No home set" : (home?.label ?? "Home set"))
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(home == nil
                    ? "Set it so Tempo knows when you eat in."
                    : "Within about 150 m counts as home.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if home != nil {
                Button(role: .destructive) {
                    store.clearHome()
                    home = nil
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
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .accessibilityIdentifier("homeCurrent")
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSectionLabel(title: "Or search an address")
            TextField("Street, city", text: $query)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .fuelField(radius: Tide.tileRadius)
                .onSubmit { Task { await search() } }
                .accessibilityIdentifier("homeSearchField")
            GlassEffectContainer(spacing: Tide.s1) {
                VStack(spacing: Tide.s2) {
                    ForEach(results, id: \.self) { item in
                        Button {
                            choose(item)
                        } label: {
                            VStack(alignment: .leading, spacing: Tide.hair) {
                                Text(item.name ?? "Address")
                                    .font(Tide.bodyStrong)
                                    .foregroundStyle(Tide.text)
                                    .multilineTextAlignment(.leading)
                                if let title = item.placemark.title {
                                    Text(title)
                                        .font(Tide.caption)
                                        .foregroundStyle(Tide.text2)
                                        .multilineTextAlignment(.leading)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
                            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                            .contentShape(.rect(cornerRadius: Tide.tileRadius))
                        }
                        .buttonStyle(FuelPressStyle())
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
        save(item.placemark.coordinate, label: item.placemark.title ?? item.name)
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
