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

/// A time that may be unset: a switch to set it, then the time beside it.
struct OptionalTimeRow: View {
    let label: String
    @Binding
    var minutes: Int?
    var defaultMinutes = 12 * 60

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s2))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        layout {
            Toggle(isOn: Binding(
                get: { minutes != nil },
                set: { minutes = $0 ? (minutes ?? defaultMinutes) : nil }
            )) {
                Text(label)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(minutes == nil ? Tide.text2 : Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tint(mood.accent)
            if minutes != nil {
                DatePicker("", selection: Binding(
                    get: { Self.date(minutes ?? defaultMinutes) },
                    set: { minutes = Self.minutes($0) }
                ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
            }
        }
        .frame(minHeight: Tide.hit)
        .animation(Tide.snap, value: minutes == nil)
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

/// One day of the week: when it starts and ends, training, and the fixed
/// events (classes, work, meals out). Three grouped cards instead of a form.
struct DayRoutineEditor: View {
    @Binding
    var day: DayRoutine
    let places: [RoutinePlace]

    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                FuelRowGroup(title: "Day") {
                    OptionalTimeRow(label: "Wake up", minutes: $day.wakeMinutes, defaultMinutes: 7 * 60)
                    OptionalTimeRow(label: "Leave home", minutes: $day.leaveHomeMinutes, defaultMinutes: 8 * 60)
                    OptionalTimeRow(label: "Back home", minutes: $day.backHomeMinutes, defaultMinutes: 17 * 60)
                    OptionalTimeRow(label: "Bed", minutes: $day.bedMinutes, defaultMinutes: 23 * 60)
                }
                training
                events
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollDismissesKeyboard(.interactively)
        .tint(mood.accent)
        .tidePage()
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var training: some View {
        FuelRowGroup(title: "Training") {
            Toggle(isOn: Binding(
                get: { day.training != nil },
                set: { day.training = $0 ? (day.training ?? TrainingSlot(startMinutes: 17 * 60)) : nil }
            )) {
                Text("Training this day")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
            }
            .frame(minHeight: Tide.hit)
            if day.training != nil {
                DatePicker("Starts", selection: Binding(
                    get: { OptionalTimeRow.date(day.training?.startMinutes ?? 17 * 60) },
                    set: { day.training?.startMinutes = OptionalTimeRow.minutes($0) }
                ), displayedComponents: .hourAndMinute)
                    .font(Tide.bodyStrong)
                    .frame(minHeight: Tide.hit)
                Stepper(value: Binding(
                    get: { day.training?.durationMinutes ?? 60 },
                    set: { day.training?.durationMinutes = $0 }
                ), in: 15 ... 240, step: 15) {
                    Text("\(day.training?.durationMinutes ?? 60) min")
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                }
                .frame(minHeight: Tide.hit)
                TextField("What (e.g. gym — legs, football)", text: Binding(
                    get: { day.training?.kind ?? "" },
                    set: { day.training?.kind = $0 }
                ))
                .font(Tide.body)
                .fuelField()
            }
        }
    }

    private var events: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Fixed events")
                .padding(.horizontal, Tide.s1)
            ForEach($day.events) { $event in
                RoutineEventRow(event: $event, places: places) {
                    withAnimation(Tide.snap) { day.events.removeAll { $0.id == event.id } }
                }
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s2))
                : AnyLayout(HStackLayout(spacing: Tide.s2))
            GlassEffectContainer(spacing: Tide.s2) {
                layout {
                    Button {
                        withAnimation(Tide.snap) {
                            day.events.append(RoutineEvent(kind: .classOrWork, title: "Class", startMinutes: 11 * 60, endMinutes: 12 * 60))
                        }
                    } label: {
                        Label("Add class / work", systemImage: "plus")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                    Button {
                        withAnimation(Tide.snap) {
                            day.events.append(RoutineEvent(
                                kind: .mealOut,
                                title: "Lunch out",
                                startMinutes: 13 * 60,
                                placeID: places.first?.id
                            ))
                        }
                    } label: {
                        Label("Add a meal out", systemImage: "fork.knife")
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.tideGlass)
                }
            }
        }
    }
}

// MARK: - RoutineEventRow

/// One fixed event as its own card: name and kind on top, the time, the
/// place, and (for a meal out) who with and which restaurants.
struct RoutineEventRow: View {
    @Binding
    var event: RoutineEvent
    let places: [RoutinePlace]
    var onDelete: (() -> Void)?

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(spacing: Tide.s2) {
                Image(systemName: event.kind == .mealOut ? "fork.knife" : "book.fill")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(mood.accent)
                    .accessibilityHidden(true)
                TextField("Title", text: $event.title)
                    .font(Tide.headline)
                Picker("", selection: $event.kind) {
                    ForEach(RoutineEvent.Kind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .labelsHidden()
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.danger)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete event")
                }
            }
            HStack(spacing: Tide.s2) {
                DatePicker("", selection: Binding(
                    get: { OptionalTimeRow.date(event.startMinutes) },
                    set: { event.startMinutes = OptionalTimeRow.minutes($0) }
                ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                if event.kind != .mealOut {
                    Text("–")
                        .foregroundStyle(Tide.text2)
                    DatePicker("", selection: Binding(
                        get: { OptionalTimeRow.date(event.endMinutes ?? event.startMinutes + 60) },
                        set: { event.endMinutes = OptionalTimeRow.minutes($0) }
                    ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                Spacer(minLength: 0)
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
                .fuelField()
                TextField("Restaurants (usual first)", text: Binding(
                    get: { event.restaurants.joined(separator: ", ") },
                    set: { event.restaurants = FuelSetupText.split($0) }
                ))
                .fuelField()
            }
        }
        .font(Tide.body)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
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
