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
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    currentCard
                    Button {
                        Task { await setHomeHere() }
                    } label: {
                        HStack {
                            Image(systemName: "location.fill")
                            Text(isWorking ? "Locating…" : "I'm home now")
                                .fontWeight(.semibold)
                        }
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TempoSpacing.md)
                        .background(Color.tempoSignal)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityIdentifier("homeSetHere")

                    if let message {
                        Text(message)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    searchSection
                    Text("Home stays on this phone. It is never uploaded or shared with the AI.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(home == nil ? "No home set" : (home?.label ?? "Home set"))
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(home == nil
                    ? "Set it so Tempo knows when you eat in."
                    : "Within about 150 m counts as home.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
            Spacer()
            if home != nil {
                Button("Clear", role: .destructive) {
                    store.clearHome()
                    home = nil
                    results = []
                    onChange()
                }
                .font(.tempoCaption1)
                .accessibilityIdentifier("homeClear")
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoBgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        .accessibilityIdentifier("homeCurrent")
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("OR SEARCH AN ADDRESS")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField("Street, city", text: $query)
                .font(.tempoBody)
                .textInputAutocapitalization(.words)
                .submitLabel(.search)
                .padding(TempoSpacing.sm)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                .onSubmit { Task { await search() } }
                .accessibilityIdentifier("homeSearchField")
            ForEach(results, id: \.self) { item in
                Button {
                    choose(item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name ?? "Address")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if let title = item.placemark.title {
                            Text(title)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(TempoSpacing.sm)
                    .background(Color.tempoBgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
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
        save(fix.coordinate, label: "Where I am now")
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            return
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        results = Array(((try? await MKLocalSearch(request: request).start().mapItems) ?? []).prefix(5))
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
