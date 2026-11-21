//
// FuelSetupReviewView.swift
// Tempo
//
// Shared editors for the Fuel setup flows: an optional time row, the per-day
// routine editor, the event row and the place locator.
//

import MapKit
import SwiftData
import SwiftUI

// MARK: - FuelSetupText

enum FuelSetupText {
    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

// MARK: - OptionalTimeRow

/// A time that may be unset: a toggle to set it, then a time picker.
struct OptionalTimeRow: View {
    let label: String
    @Binding
    var minutes: Int?
    var defaultMinutes = 12 * 60

    var body: some View {
        HStack {
            Toggle(label, isOn: Binding(
                get: { minutes != nil },
                set: { minutes = $0 ? (minutes ?? defaultMinutes) : nil }
            ))
            .tint(Color.tempoSignal)
            if minutes != nil {
                DatePicker("", selection: Binding(
                    get: { Self.date(minutes ?? defaultMinutes) },
                    set: { minutes = Self.minutes($0) }
                ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
        }
    }

    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(_ date: Date) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// MARK: - DayRoutineEditor

struct DayRoutineEditor: View {
    @Binding
    var day: DayRoutine
    let places: [RoutinePlace]

    var body: some View {
        Form {
            Section("Day") {
                OptionalTimeRow(label: "Wake up", minutes: $day.wakeMinutes, defaultMinutes: 7 * 60)
                OptionalTimeRow(label: "Leave home", minutes: $day.leaveHomeMinutes, defaultMinutes: 8 * 60)
                OptionalTimeRow(label: "Back home", minutes: $day.backHomeMinutes, defaultMinutes: 17 * 60)
                OptionalTimeRow(label: "Bed", minutes: $day.bedMinutes, defaultMinutes: 23 * 60)
            }
            Section("Training") {
                Toggle("Training this day", isOn: Binding(
                    get: { day.training != nil },
                    set: { day.training = $0 ? (day.training ?? TrainingSlot(startMinutes: 17 * 60)) : nil }
                ))
                .tint(Color.tempoSignal)
                if day.training != nil {
                    DatePicker("Starts", selection: Binding(
                        get: { OptionalTimeRow.date(day.training?.startMinutes ?? 17 * 60) },
                        set: { day.training?.startMinutes = OptionalTimeRow.minutes($0) }
                    ), displayedComponents: .hourAndMinute)
                    Stepper("\(day.training?.durationMinutes ?? 60) min", value: Binding(
                        get: { day.training?.durationMinutes ?? 60 },
                        set: { day.training?.durationMinutes = $0 }
                    ), in: 15 ... 240, step: 15)
                    TextField("What (e.g. gym — legs, football)", text: Binding(
                        get: { day.training?.kind ?? "" },
                        set: { day.training?.kind = $0 }
                    ))
                }
            }
            Section {
                ForEach($day.events) { $event in
                    RoutineEventRow(event: $event, places: places)
                }
                .onDelete { day.events.remove(atOffsets: $0) }
                Button {
                    day.events.append(RoutineEvent(kind: .classOrWork, title: "Class", startMinutes: 11 * 60, endMinutes: 12 * 60))
                } label: {
                    Label("Add class / work", systemImage: "plus")
                }
                Button {
                    day.events.append(RoutineEvent(kind: .mealOut, title: "Lunch out", startMinutes: 13 * 60, placeID: places.first?.id))
                } label: {
                    Label("Add a meal out", systemImage: "fork.knife")
                }
            } header: {
                Text("Fixed events")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - RoutineEventRow

struct RoutineEventRow: View {
    @Binding
    var event: RoutineEvent
    let places: [RoutinePlace]

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            HStack {
                TextField("Title", text: $event.title)
                    .font(.tempoBodyBold)
                Picker("", selection: $event.kind) {
                    ForEach(RoutineEvent.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
            }
            HStack {
                DatePicker("", selection: Binding(
                    get: { OptionalTimeRow.date(event.startMinutes) },
                    set: { event.startMinutes = OptionalTimeRow.minutes($0) }
                ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                if event.kind != .mealOut {
                    Text("–")
                    DatePicker("", selection: Binding(
                        get: { OptionalTimeRow.date(event.endMinutes ?? event.startMinutes + 60) },
                        set: { event.endMinutes = OptionalTimeRow.minutes($0) }
                    ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            if !places.isEmpty {
                Picker("Where", selection: $event.placeID) {
                    Text("—").tag(UUID?.none)
                    ForEach(places) { place in
                        Text(place.name.isEmpty ? "Unnamed place" : place.name).tag(UUID?.some(place.id))
                    }
                }
            }
            if event.kind == .mealOut {
                TextField("With (e.g. friends)", text: Binding(
                    get: { event.with ?? "" },
                    set: { event.with = $0.isEmpty ? nil : $0 }
                ))
                TextField("Restaurants (usual first)", text: Binding(
                    get: { event.restaurants.joined(separator: ", ") },
                    set: { event.restaurants = FuelSetupText.split($0) }
                ))
            }
        }
        .font(.tempoBody)
    }
}

// MARK: - PlaceLocator

/// Finds coordinates for places the user named ("FIU Modesto Maidique
/// Campus") so the planner can look up restaurants nearby. Best effort.
enum PlaceLocator {
    @MainActor
    static func locateMissing(in routine: WeeklyRoutine) async -> WeeklyRoutine {
        var out = routine
        out.places.removeAll { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        for index in out.places.indices where !out.places[index].hasCoordinate {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = out.places[index].name
            guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
                continue
            }
            let coordinate = item.placemark.coordinate
            out.places[index].latitude = coordinate.latitude
            out.places[index].longitude = coordinate.longitude
            out.places[index].address = out.places[index].address ?? item.placemark.title
        }
        return out
    }
}
