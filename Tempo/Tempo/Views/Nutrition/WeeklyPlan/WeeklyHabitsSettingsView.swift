//
// WeeklyHabitsSettingsView.swift
// Tempo
//
// Settings → Weekly habits: the Sunday planning notification (on/off, time),
// the routine every weekly plan reads (edited in Fuel setup), and what the
// app has learned from your logs — real eat-times and real maintenance.
//

import SwiftData
import SwiftUI
import UserNotifications

struct WeeklyHabitsSettingsView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var promptEnabled = true
    @State
    private var promptTime = Date()
    @State
    private var notificationsDenied = false
    @State
    private var observedTimes: [(meal: String, time: String)] = []
    @State
    private var expenditure: AdaptiveExpenditure.Observation?
    @State
    private var routineSummary: [String] = []
    @State
    private var loaded = false

    private static let mealNames = [1: "Breakfast", 2: "Lunch", 3: "Dinner", 4: "Snack", 5: "Second snack"]

    var body: some View {
        Form {
            Section {
                Toggle("Ask me every Sunday", isOn: $promptEnabled)
                    .accessibilityIdentifier("weeklyPromptToggle")
                if promptEnabled {
                    DatePicker("Time", selection: $promptTime, displayedComponents: .hourAndMinute)
                        .accessibilityIdentifier("weeklyPromptTime")
                }
                Button("Plan next week now") {
                    services.appState.weeklyCheckInRequested = true
                }
            } header: {
                Text("Sunday planning")
            } footer: {
                Text(notificationsDenied
                    ? "Notifications are off for Tempo — turn them on in iOS Settings to get the Sunday prompt."
                    : "Tap Yes on the notification and next week is built in the background, around your routine.")
            }

            Section {
                NavigationLink {
                    FuelSetupView(embedded: true)
                } label: {
                    Label("Routine, places & food", systemImage: "calendar")
                }
                ForEach(routineSummary, id: \.self) { line in
                    Text(line)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            } header: {
                Text("Your week")
            } footer: {
                Text("Every Sunday plan reads this. Change it any time — by voice or by hand.")
            }

            Section {
                if observedTimes.isEmpty, expenditure == nil {
                    Text("Log meals for a couple of weeks and your real eating times and calorie burn show up here.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                ForEach(observedTimes, id: \.meal) { item in
                    LabeledContent(item.meal, value: item.time)
                }
                if let expenditure {
                    LabeledContent("Your real maintenance", value: "\(Int(expenditure.kcal.rounded())) kcal")
                    Text(
                        "From \(expenditure.loggedDays) logged days and a \(String(format: "%+.1f", expenditure.trendKgPerWeek)) kg/week weight trend. Plans lean on it \(Int((expenditure.confidence * 100).rounded()))%."
                    )
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            } header: {
                Text("Learned from your logs")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Weekly habits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationsDenied = status == .denied
        }
        .onChange(of: promptEnabled) { _, enabled in
            save()
            if enabled {
                Task {
                    _ = try? await services.pushRegistration.requestAuthorizationAndRegister()
                    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                    notificationsDenied = status == .denied
                }
            }
        }
        .onChange(of: promptTime) { _, _ in
            save()
        }
    }

    private var settings: UserSettings? {
        NutritionTabViewModel.loadUserSettings(modelContext: modelContext)
    }

    private func load() {
        guard !loaded else {
            return
        }
        let settings = settings
        promptEnabled = settings?.weeklyPlanPromptEnabled ?? true
        let minutes = settings?.weeklyPlanPromptMinutes ?? WeeklyPlanReminder.defaultMinutes
        promptTime = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()

        let observed = MealPlanGeneratorService(apiClient: services.apiClient).observedMealTimes(modelContext: modelContext) ?? [:]
        observedTimes = observed.sorted { $0.key < $1.key }.map { (Self.mealNames[$0.key] ?? "Meal \($0.key)", $0.value) }
        expenditure = AdaptiveExpenditure.observe(in: modelContext)
        routineSummary = Self.summary(of: UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine)
        // Set after the state above so the initial values don't trigger a save.
        DispatchQueue.main.async { loaded = true }
    }

    private func save() {
        guard loaded, let settings else {
            return
        }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: promptTime)
        settings.weeklyPlanPromptEnabled = promptEnabled
        settings.weeklyPlanPromptMinutes = (parts.hour ?? 18) * 60 + (parts.minute ?? 0)
        try? modelContext.save()
        Task { await WeeklyPlanReminder.sync(settings: settings) }
    }

    /// One line per weekday that has something in it.
    static func summary(of routine: WeeklyRoutine?) -> [String] {
        guard let routine else {
            return []
        }
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return routine.days.compactMap { day in
            var parts: [String] = []
            if let wake = RoutineTime.string(day.wakeMinutes) {
                parts.append("up \(wake)")
            }
            if let leave = RoutineTime.string(day.leaveHomeMinutes) {
                parts.append("out \(leave)")
            }
            for event in day.events where event.kind == .mealOut {
                parts.append("eat out \(RoutineTime.string(event.startMinutes) ?? "")")
            }
            if let training = day.training {
                parts.append("train \(RoutineTime.string(training.startMinutes) ?? "")")
            }
            guard !parts.isEmpty, (1 ... 7).contains(day.weekday) else {
                return nil
            }
            return "\(names[day.weekday - 1]): \(parts.joined(separator: " · "))"
        }
    }
}
