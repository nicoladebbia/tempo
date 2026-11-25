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
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
    private var supplementRemindersEnabled = true
    @State
    private var loaded = false

    private static let mealNames = [1: "Breakfast", 2: "Lunch", 3: "Dinner", 4: "Snack", 5: "Second snack"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tide.s5) {
                hero
                FuelRowGroup(
                    title: "Sunday planning",
                    footnote: notificationsDenied
                        ? "Notifications are off for Tempo — turn them on in iOS Settings to get the Sunday prompt."
                        : "Tap Yes on the notification and next week is built in the background, around your routine."
                ) {
                    Toggle("Ask me every Sunday", isOn: $promptEnabled)
                        .font(Tide.bodyStrong)
                        .frame(minHeight: Tide.hit)
                        .accessibilityIdentifier("weeklyPromptToggle")
                    if promptEnabled {
                        DatePicker("Time", selection: $promptTime, displayedComponents: .hourAndMinute)
                            .font(Tide.bodyStrong)
                            .frame(minHeight: Tide.hit)
                            .accessibilityIdentifier("weeklyPromptTime")
                    }
                    Button {
                        HapticManager.lightImpact()
                        services.appState.weeklyCheckInRequested = true
                    } label: {
                        actionLabel("Plan next week now", icon: "calendar.badge.plus")
                    }
                    .buttonStyle(.plain)
                    if notificationsDenied {
                        Button { CameraPermission.openSettings() } label: {
                            actionLabel("Open Settings", icon: "gearshape")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("weeklyOpenSettings")
                    }
                }

                FuelRowGroup(
                    title: "Your week",
                    footnote: "Every Sunday plan reads this. Change it any time — by voice or by hand."
                ) {
                    NavigationLink {
                        FuelSetupView(embedded: true)
                    } label: {
                        HStack(spacing: Tide.s3) {
                            Label("Routine, places & food", systemImage: "calendar")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                            Spacer(minLength: Tide.s2)
                            Image(systemName: "chevron.right")
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    ForEach(routineSummary, id: \.self) { line in
                        routineRow(line)
                    }
                }

                FuelRowGroup(title: "Learned from your logs") {
                    if observedTimes.isEmpty, expenditure == nil {
                        Text("Log meals for a couple of weeks and your real eating times and calorie burn show up here.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(observedTimes, id: \.meal) { item in
                        LabeledContent(item.meal, value: item.time)
                            .font(Tide.body)
                    }
                    if let expenditure {
                        VStack(alignment: .leading, spacing: Tide.s1) {
                            LabeledContent("Your real maintenance", value: "\(Int(expenditure.kcal.rounded())) kcal")
                                .font(Tide.bodyStrong)
                            Text(
                                "From \(expenditure.loggedDays) logged days and a \(String(format: "%+.1f", expenditure.trendKgPerWeek)) kg/week weight trend. Plans lean on it \(Int((expenditure.confidence * 100).rounded()))%."
                            )
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .explains(.fuelRealMaintenance)
                    }
                }

                FuelRowGroup(
                    footnote: "Per-supplement reminders can still be turned off individually from the shelf."
                ) {
                    Toggle("Remind me to take my supplements", isOn: $supplementRemindersEnabled)
                        .font(Tide.bodyStrong)
                        .frame(minHeight: Tide.hit)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s8)
        }
        .tint(mood.accent)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .animation(Tide.snap, value: promptEnabled)
        .animation(Tide.snap, value: notificationsDenied)
        .tidePage()
        .navigationTitle("Weekly habits")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
            let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            notificationsDenied = status == .denied
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: re-read the notification permission.
            guard phase == .active else {
                return
            }
            Task {
                let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
                notificationsDenied = status == .denied
            }
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
        .onChange(of: supplementRemindersEnabled) { _, enabled in
            guard loaded, let settings else {
                return
            }
            settings.supplementRemindersEnabled = enabled
            try? modelContext.save()
            NotificationCenter.default.post(name: .tempoSupplementsChanged, object: nil)
        }
    }

    /// The state of the Sunday habit in one sentence, so the page opens with an answer.
    private var hero: some View {
        // At large text the tile sits above the words instead of squeezing them.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Tide.s4))
        return layout {
            TideIconTile(
                systemName: promptEnabled ? "calendar.badge.clock" : "calendar.badge.minus",
                tint: promptEnabled ? mood.accent : Tide.text3,
                size: Tide.tileLarge
            )
            VStack(alignment: .leading, spacing: Tide.s1) {
                Text(promptEnabled ? "Next week gets planned every Sunday" : "Sunday planning is off")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(promptEnabled ? "Asked at \(promptTime.formatted(date: .omitted, time: .shortened))." :
                    "You can still plan a week by hand.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func actionLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(Tide.bodyStrong)
            .foregroundStyle(mood.accent)
            .frame(maxWidth: .infinity, minHeight: Tide.hit, alignment: .leading)
            .contentShape(.rect)
    }

    private var settings: UserSettings? {
        NutritionTabViewModel.loadUserSettings(modelContext: modelContext)
    }

    /// "Mon: up 07:00 · train 17:30" shown as a day name and its detail,
    /// so a week reads as a column instead of seven small sentences.
    @ViewBuilder
    private func routineRow(_ line: String) -> some View {
        if let split = line.range(of: ": ") {
            LabeledContent {
                Text(line[split.upperBound...])
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(line[..<split.lowerBound])
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(line)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
    }

    private func load() {
        guard !loaded else {
            return
        }
        let settings = settings
        promptEnabled = settings?.weeklyPlanPromptEnabled ?? true
        let minutes = settings?.weeklyPlanPromptMinutes ?? WeeklyPlanReminder.defaultMinutes
        promptTime = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        supplementRemindersEnabled = settings?.supplementRemindersEnabled ?? true

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
