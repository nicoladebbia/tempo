//
// FuelSetupReviewView.swift
// Tempo
//
// Every Fuel setup answer, editable: what the AI understood from the talk,
// the manual path, and the Settings editor. Weights show in the user's unit.
//

import MapKit
import SwiftData
import SwiftUI

// MARK: - FuelSetupReviewView

struct FuelSetupReviewView: View {
    @Binding
    var draft: FuelSetupDraft
    var onTalkAgain: () -> Void
    var onSave: () -> Void

    @Query
    private var settings: [UserSettings]

    @State
    private var isLocating = false

    private var unit: WeightUnit {
        settings.first?.weightUnit ?? .kg
    }

    var body: some View {
        Form {
            Section {
                Button {
                    onTalkAgain()
                } label: {
                    Label("Tell me more (talk or type)", systemImage: "mic.fill")
                        .foregroundStyle(Color.tempoSignal)
                }
                .accessibilityIdentifier("fuelSetupTalkAgain")
            } footer: {
                if !draft.missingFields.isEmpty {
                    Text("Still needed: \(draft.missingFields.map(\.label).joined(separator: ", ")).")
                        .foregroundStyle(Color.tempoWarning)
                }
            }

            bodySection
            goalSection
            foodSection
            eatingSection
            cookingSection
            weekSection
            placesSection

            Section("Anything else") {
                TextField("Notes for your planner", text: $draft.notes, axis: .vertical)
                    .lineLimit(2 ... 8)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // .decimalPad has no Return key.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isLocating = true
                Task {
                    draft.routine = await PlaceLocator.locateMissing(in: draft.routine)
                    isLocating = false
                    onSave()
                }
            } label: {
                Group {
                    if isLocating {
                        ProgressView()
                    } else {
                        Text("Save")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoPrimary)
            .disabled(isLocating)
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.sm)
            .background(Color.tempoBgPrimary)
            .accessibilityIdentifier("fuelSetupSave")
        }
    }

    // MARK: - Sections

    private var bodySection: some View {
        Section("You") {
            numberRow("Weight", value: weightBinding(\.weightKg), unit: unit.abbreviation, id: "fuelWeight")
            numberRow("Height", value: $draft.heightCm, unit: "cm", id: "fuelHeight")
            numberRow("Age", value: intBinding(\.age), unit: "yrs", id: "fuelAge")
            Picker("Sex", selection: $draft.sex) {
                Text("—").tag(BiologicalSex?.none)
                ForEach(BiologicalSex.allCases, id: \.self) { sex in
                    Text(sex.rawValue.capitalized).tag(BiologicalSex?.some(sex))
                }
            }
            numberRow("Body fat (optional)", value: $draft.bodyFatPercent, unit: "%", id: "fuelBodyFat")
        }
    }

    private var goalSection: some View {
        Section("Goal") {
            Picker("Goal", selection: $draft.goal) {
                Text("—").tag(DietaryGoal?.none)
                ForEach(DietaryGoal.allCases, id: \.self) { goal in
                    Text(goal.displayName).tag(DietaryGoal?.some(goal))
                }
            }
            if let goal = draft.goal, goal != .maintain {
                numberRow("Goal weight", value: weightBinding(\.goalWeightKg), unit: unit.abbreviation, id: "fuelGoalWeight")
                numberRow("Per week", value: weightBinding(\.weeklyRateKg), unit: unit.abbreviation, id: "fuelRate")
            }
            Stepper(
                "Training days: \(draft.trainingDaysPerWeek ?? draft.routine.trainingDaysPerWeek)",
                value: Binding(
                    get: { draft.trainingDaysPerWeek ?? draft.routine.trainingDaysPerWeek },
                    set: { draft.trainingDaysPerWeek = $0 }
                ),
                in: 0 ... 7
            )
        }
    }

    private var foodSection: some View {
        Section {
            ForEach(DietRestriction.allCases) { restriction in
                Toggle(restriction.label, isOn: Binding(
                    get: { draft.restrictions.contains(restriction) },
                    set: { on in
                        if on {
                            draft.restrictions.insert(restriction)
                        } else {
                            draft.restrictions.remove(restriction)
                        }
                    }
                ))
                .tint(Color.tempoSignal)
            }
            listRow("Allergies", values: $draft.allergies)
            listRow("Won't eat", values: $draft.dislikedFoods)
            listRow("Love", values: $draft.favoriteFoods)
        } header: {
            Text("Food")
        } footer: {
            Text("Separate items with commas.")
        }
    }

    private var eatingSection: some View {
        Section("Eating") {
            Stepper("Meals a day: \(draft.mealsPerDay ?? 4)", value: Binding(
                get: { draft.mealsPerDay ?? 4 },
                set: { draft.mealsPerDay = $0 }
            ), in: 1 ... 8)
            Toggle("I skip breakfast", isOn: Binding(
                get: { draft.breakfastSkipped ?? false },
                set: { draft.breakfastSkipped = $0 }
            ))
            .tint(Color.tempoSignal)
            OptionalTimeRow(label: "First meal after", minutes: $draft.eatingWindowStartMinutes)
            OptionalTimeRow(label: "Last meal by", minutes: $draft.eatingWindowEndMinutes)
        }
    }

    private var cookingSection: some View {
        Section("Cooking & shopping") {
            Picker("Cooking skill", selection: $draft.cookingSkill) {
                Text("—").tag(CookingSkill?.none)
                ForEach(CookingSkill.allCases, id: \.self) { skill in
                    Text(skill.rawValue.capitalized).tag(CookingSkill?.some(skill))
                }
            }
            Stepper("Days I can cook: \(draft.cookableDaysPerWeek ?? 4)", value: Binding(
                get: { draft.cookableDaysPerWeek ?? 4 },
                set: { draft.cookableDaysPerWeek = $0 }
            ), in: 0 ... 7)
            Stepper("Weekday cooking: \(draft.cookMinutesWeekday ?? 30) min", value: Binding(
                get: { draft.cookMinutesWeekday ?? 30 },
                set: { draft.cookMinutesWeekday = $0 }
            ), in: 0 ... 180, step: 5)
            Stepper("Weekend cooking: \(draft.cookMinutesWeekend ?? 60) min", value: Binding(
                get: { draft.cookMinutesWeekend ?? 60 },
                set: { draft.cookMinutesWeekend = $0 }
            ), in: 0 ... 240, step: 5)
            Picker("Leftovers", selection: $draft.leftoverTolerance) {
                Text("—").tag(LeftoverTolerance?.none)
                ForEach(LeftoverTolerance.allCases, id: \.self) { tolerance in
                    Text(tolerance.displayName).tag(LeftoverTolerance?.some(tolerance))
                }
            }
            numberRow("Weekly food budget", value: intBinding(\.weeklyBudgetUSD), unit: "$", id: "fuelBudget")
            listRow("Stores", values: $draft.stores)
        }
    }

    private var weekSection: some View {
        Section {
            ForEach(draft.routine.days) { day in
                NavigationLink {
                    DayRoutineEditor(day: $draft.routine[day.weekday], places: draft.routine.places)
                } label: {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        Text(day.name)
                            .font(.tempoBodyBold)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(Self.summary(of: day, places: draft.routine.places))
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .lineLimit(2)
                    }
                }
                .accessibilityIdentifier("fuelDay\(day.weekday)")
            }
        } header: {
            Text("Your week")
        } footer: {
            Text(
                "Meals are timed around this: breakfast before you leave, a packed meal while you're out, around training, and meals out where you actually eat."
            )
        }
    }

    private var placesSection: some View {
        Section {
            ForEach($draft.routine.places) { $place in
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    HStack {
                        TextField("Place", text: $place.name)
                            .font(.tempoBodyBold)
                        if place.hasCoordinate {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Color.tempoSuccess)
                                .accessibilityLabel("Found on the map")
                        }
                    }
                    TextField("Restaurants you eat at here", text: Binding(
                        get: { place.usualRestaurants.joined(separator: ", ") },
                        set: { place.usualRestaurants = Self.split($0) }
                    ))
                    .font(.tempoCaption1)
                }
            }
            .onDelete { draft.routine.places.remove(atOffsets: $0) }
            Button {
                draft.routine.places.append(RoutinePlace(name: ""))
            } label: {
                Label("Add a place", systemImage: "plus")
            }
        } header: {
            Text("Places")
        } footer: {
            Text("Campus, work, gym. We also look up other restaurants near each place when planning your week.")
        }
    }

    // MARK: - Rows

    private func numberRow(_ label: String, value: Binding<Double?>, unit: String, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", value: value, format: .number.precision(.fractionLength(0 ... 1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .accessibilityIdentifier(id)
            Text(unit)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 32, alignment: .leading)
        }
    }

    private func listRow(_ label: String, values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField("None", text: Binding(
                get: { values.wrappedValue.joined(separator: ", ") },
                set: { values.wrappedValue = Self.split($0) }
            ), axis: .vertical)
        }
    }

    private func weightBinding(_ keyPath: WritableKeyPath<FuelSetupDraft, Double?>) -> Binding<Double?> {
        Binding(
            get: { draft[keyPath: keyPath].map { WeightUnit.kg.convert($0, to: unit) } },
            set: { draft[keyPath: keyPath] = $0.map { unit.convert($0, to: .kg) } }
        )
    }

    private func intBinding(_ keyPath: WritableKeyPath<FuelSetupDraft, Int?>) -> Binding<Double?> {
        Binding(
            get: { draft[keyPath: keyPath].map(Double.init) },
            set: { draft[keyPath: keyPath] = $0.map { Int($0.rounded()) } }
        )
    }

    static func split(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func summary(of day: DayRoutine, places: [RoutinePlace]) -> String {
        var parts: [String] = []
        if let wake = RoutineTime.string(day.wakeMinutes) {
            parts.append("Up \(wake)")
        }
        if let leave = RoutineTime.string(day.leaveHomeMinutes) {
            parts.append("out \(leave)")
        }
        if let back = RoutineTime.string(day.backHomeMinutes) {
            parts.append("home \(back)")
        }
        if let training = day.training, let time = RoutineTime.string(training.startMinutes) {
            parts.append("train \(time)")
        }
        for event in day.events where event.kind == .mealOut {
            let place = event.restaurants.first ?? places.first { $0.id == event.placeID }?.name ?? "out"
            parts.append("eat \(place) \(RoutineTime.string(event.startMinutes) ?? "")")
        }
        let classes = day.events.filter { $0.kind == .classOrWork }.count
        if classes > 0 {
            parts.append("\(classes) class/work")
        }
        return parts.isEmpty ? "Not set — tap to add" : parts.joined(separator: " · ")
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
                    set: { event.restaurants = FuelSetupReviewView.split($0) }
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
