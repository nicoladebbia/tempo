//
// NotificationSettingsView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI
import UserNotifications

// MARK: - NotificationSettingsView

// Per BUILD_PLAN step 12.5 — Notification settings UI.
// Per WIREFRAMES.md Screen 58 — NotificationSettingsView layout.
// Per ONBOARDING_AND_NOTIFICATIONS.md — Intensity, categories, quiet hours.

struct NotificationSettingsView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    // MARK: - Authorization State

    @Environment(\.scenePhase)
    private var scenePhase
    @State
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State
    private var hasCheckedAuth = false

    // MARK: - Local State

    @State
    private var intensity: Int = 3
    @State
    private var morningBriefing: Bool = true
    @State
    private var accountability: Bool = true
    @State
    private var recovery: Bool = true
    @State
    private var mealReminders: Bool = true
    @State
    private var bedtimeReminder: Bool = true
    @State
    private var streakWarning: Bool = true
    @State
    private var arenaNotifications: Bool = true
    @State
    private var weeklyReport: Bool = true
    @State
    private var trainingReminder: Bool = true
    @State
    private var trainerSessionReminder: Bool = true
    @State
    private var weeklyUploadReminder: Bool = true
    @State
    private var soundEnabled: Bool = true
    @State
    private var quietHoursEnabled: Bool = false
    @State
    private var quietHoursStart: Date = Self.timeFromMinutes(1380)
    @State
    private var quietHoursEnd: Date = Self.timeFromMinutes(420)

    var body: some View {
        TideSettingsPage {
            // MARK: - Permission Gate

            if hasCheckedAuth {
                switch authorizationStatus {
                case .notDetermined:
                    notificationPermissionCard
                case .denied:
                    notificationDeniedCard
                case .authorized,
                     .provisional,
                     .ephemeral:
                    authorizedContent
                @unknown default:
                    authorizedContent
                }
            } else {
                ProgressView()
                    .tint(Tide.text2)
                    .frame(maxWidth: .infinity, minHeight: Tide.settingsRow * 3)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(Tide.bodyStrong)
            }
        }
        .sensoryFeedback(.selection, trigger: intensity)
        .onAppear {
            loadFromSettings()
            checkAuthorizationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from iOS Settings: pick up the new permission.
            if phase == .active {
                checkAuthorizationStatus()
            }
        }
    }

    // MARK: - Permission Not Determined Card

    private var notificationPermissionCard: some View {
        VStack(spacing: Tide.settingsGroupGap) {
            permissionHeader(
                icon: "bell.badge.fill",
                iconTint: mood.accent,
                title: "Enable Notifications",
                message: "Tempo uses notifications to keep you accountable. Get morning briefings, workout reminders, streak warnings, and drill-sergeant escalations when you fall behind."
            )

            SettingsGroupCard {
                notificationFeatureRow(icon: "sunrise.fill", text: "Morning briefing with your daily plan")
                notificationFeatureRow(icon: "bolt.fill", text: "Accountability escalations")
                notificationFeatureRow(icon: "flame.fill", text: "Streak warnings before you lose progress")
                notificationFeatureRow(icon: "moon.fill", text: "Bedtime reminders for recovery")
            }

            VStack(spacing: Tide.s2) {
                Button {
                    requestNotificationPermission()
                } label: {
                    Text("Enable Notifications")
                }
                .buttonStyle(.tidePrimary)

                Button {
                    // Allow skipping — show settings anyway
                    authorizationStatus = .authorized
                } label: {
                    Text("Skip for now")
                        .font(Tide.bodyStrong)
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Permission Denied Card

    private var notificationDeniedCard: some View {
        VStack(spacing: Tide.settingsGroupGap) {
            permissionHeader(
                icon: "bell.slash.fill",
                iconTint: Tide.text3,
                title: "Notifications Disabled",
                message: "Notifications are turned off in iOS Settings. Tempo needs notifications for accountability reminders, morning briefings, and streak warnings."
            )

            Button {
                openSystemSettings()
            } label: {
                Label("Open Settings", systemImage: "gear")
            }
            .buttonStyle(.tidePrimary)

            // Still show the settings toggles below (for when they return)
            authorizedContent
        }
    }

    /// The icon, title and explanation at the top of a permission state.
    private func permissionHeader(icon: String, iconTint: Color, title: String, message: String) -> some View {
        TideSettingsHero {
            Image(systemName: icon)
                .font(Tide.title)
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)
            Text(title)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Authorized Content (normal toggle list)

    private var authorizedContent: some View {
        VStack(spacing: Tide.settingsGroupGap) {
            summaryCard
            intensitySection
            dailyRemindersSection
            accountabilitySection
            socialSection
            quietHoursSection
        }
    }

    // MARK: - Summary

    /// How many of the reminders are on, so the page reads at a glance.
    private var remindersOn: Int {
        [
            morningBriefing, recovery, mealReminders, bedtimeReminder, weeklyReport,
            accountability, streakWarning, trainingReminder, trainerSessionReminder, weeklyUploadReminder,
            arenaNotifications,
        ].count(where: { $0 })
    }

    private let remindersTotal = 11

    private var summaryCard: some View {
        TideSettingsHero {
            Text("Reminders on").tideLabel()
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(
                    "\(remindersOn)", unit: "of \(remindersTotal)",
                    size: Tide.numeralL, relativeTo: .largeTitle
                )
                Spacer(minLength: Tide.s2)
                Text(IntensityOption(rawValue: intensity)?.title ?? "")
                    .tideLabel(mood.accent)
            }
            TideLevelBar(progress: Double(remindersOn) / Double(remindersTotal), height: Tide.bar)
                .background(Tide.fill, in: .capsule)
                .padding(.top, Tide.s1)
                .accessibilityHidden(true)
        }
        .animation(Tide.snap, value: remindersOn)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Permission Helpers

    private func checkAuthorizationStatus() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                authorizationStatus = settings.authorizationStatus
                hasCheckedAuth = true
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                authorizationStatus = granted ? .authorized : .denied
            }
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func notificationFeatureRow(icon: String, text: String) -> some View {
        HStack(spacing: Tide.s3) {
            SettingsIconTile(systemName: icon, tint: mood.accent)
            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Tide.s2)
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, minHeight: Tide.settingsRow, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Intensity Section

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSettingsSection(title: "Intensity") {
                // Per UX_COPY_BIBLE.md — onb_notif_intensity_label
                ForEach(IntensityOption.allCases) { option in
                    Button {
                        intensity = option.rawValue
                        persistIntensity(option.rawValue)
                    } label: {
                        intensityRow(option)
                    }
                    .buttonStyle(.tideSettingsRow)
                    .accessibilityAddTraits(intensity == option.rawValue ? .isSelected : [])

                    if option != .savage {
                        TideSettingsHairline(inset: Tide.s4)
                    }
                }
            }

            // Preview text for selected intensity
            Text(IntensityOption(rawValue: intensity)?.preview ?? "")
                .font(Tide.caption)
                .foregroundStyle(mood.accent)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tide.s2)
                .contentTransition(.opacity)
                .animation(Tide.snap, value: intensity)
        }
    }

    private func intensityRow(_ option: IntensityOption) -> some View {
        let isSelected = intensity == option.rawValue
        let isLarge = typeSize.isAccessibilitySize
        let indicator = Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(Tide.headline)
            .foregroundStyle(isSelected ? mood.accent : Tide.text3)
            .accessibilityHidden(true)
        let title = Text(option.title)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
        let recommended = Text("REC")
            .font(Tide.label)
            .foregroundStyle(Tide.ink)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.hair)
            .background(mood.accent, in: .capsule)
        let detail = Text(option.description)
            .font(Tide.caption)
            .foregroundStyle(Tide.text2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        return Group {
            if isLarge {
                // At accessibility sizes the circle moves up beside the name, so the
                // description gets the whole card width.
                VStack(alignment: .leading, spacing: Tide.s2) {
                    HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                        indicator
                        title
                    }
                    if option == .drillSergeant {
                        recommended
                    }
                    detail
                }
            } else {
                HStack(spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        HStack(spacing: Tide.s2) {
                            title
                            if option == .drillSergeant {
                                recommended
                            }
                        }
                        detail
                    }
                    Spacer(minLength: Tide.s2)
                    indicator
                }
            }
        }
        .padding(.horizontal, Tide.s4)
        .padding(.vertical, Tide.s3)
        .frame(maxWidth: .infinity, minHeight: Tide.settingsRow, alignment: .leading)
        .contentShape(.rect)
    }

    // MARK: - Daily Reminders Section

    private var dailyRemindersSection: some View {
        SettingsFormCard(title: "Daily reminders") {
            settingsToggle(
                "Morning Briefing",
                isOn: $morningBriefing,
                icon: "sunrise.fill",
                onToggle: { enabled in
                    persistToggle(\.morningBriefingEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("MORNING_BRIEFING")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Recovery Updates",
                isOn: $recovery,
                icon: "heart.fill",
                onToggle: { enabled in
                    persistToggle(\.recoveryEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("RECOVERY_REPORT")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Meal Reminders",
                isOn: $mealReminders,
                icon: "fork.knife",
                onToggle: { enabled in
                    persistToggle(\.mealRemindersEnabled, value: enabled)
                    if enabled {
                        MealReminderPlanner.reschedule(
                            modelContext: modelContext, notifications: services.notifications
                        )
                    } else {
                        services.notifications.cancelCategory("MEAL_REMINDER")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Bedtime Reminder",
                isOn: $bedtimeReminder,
                icon: "moon.fill",
                onToggle: { enabled in
                    persistToggle(\.bedtimeReminderEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("BEDTIME_REMINDER")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Weekly Report",
                isOn: $weeklyReport,
                icon: "chart.bar.fill",
                onToggle: { enabled in
                    persistToggle(\.weeklyReportEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("WEEKLY_SUMMARY")
                    }
                }
            )
        }
    }

    // MARK: - Accountability Section

    private var accountabilitySection: some View {
        SettingsFormCard(title: "Accountability") {
            settingsToggle(
                "Accountability Reminders",
                isOn: $accountability,
                icon: "bolt.fill",
                onToggle: { enabled in
                    persistToggle(\.accountabilityEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("ACCOUNTABILITY_GENTLE")
                        services.notifications.cancelCategory("ACCOUNTABILITY_FIRM")
                        services.notifications.cancelCategory("ACCOUNTABILITY_URGENT")
                        services.notifications.cancelCategory("ACCOUNTABILITY_FINAL")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Streak Warnings",
                isOn: $streakWarning,
                icon: "flame.fill",
                onToggle: { enabled in
                    persistToggle(\.streakWarningEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("STREAK_WARNING")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Training Reminders",
                isOn: $trainingReminder,
                icon: "dumbbell.fill",
                onToggle: { enabled in
                    persistToggle(\.trainingReminderEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("TRAINING_REMINDER")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Trainer Sessions",
                isOn: $trainerSessionReminder,
                icon: "figure.strengthtraining.traditional",
                onToggle: { enabled in
                    persistToggle(\.trainerSessionReminderEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelTrainerSessionReminders()
                    } else {
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "New-Week Upload Reminder",
                isOn: $weeklyUploadReminder,
                icon: "calendar.badge.exclamationmark",
                onToggle: { enabled in
                    persistToggle(\.weeklyUploadReminderEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelWeeklyUploadReminders()
                    } else {
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                }
            )
        }
    }

    // MARK: - Social Section

    private var socialSection: some View {
        SettingsFormCard(title: "Social & sound") {
            settingsToggle(
                "Arena Notifications",
                isOn: $arenaNotifications,
                icon: "trophy.fill",
                onToggle: { enabled in
                    persistToggle(\.arenaNotificationsEnabled, value: enabled)
                    if !enabled {
                        services.notifications.cancelCategory("ARENA_SOCIAL")
                    }
                }
            )
            SettingsRowDivider()
            settingsToggle(
                "Notification Sound",
                isOn: $soundEnabled,
                icon: "speaker.wave.2.fill",
                onToggle: { enabled in
                    persistToggle(\.soundEnabled, value: enabled)
                }
            )
        }
    }

    // MARK: - Quiet Hours Section

    private var quietHoursSection: some View {
        SettingsFormCard(
            title: "Quiet hours",
            footnote: "Time Sensitive notifications (accountability escalations) still break through during quiet hours."
        ) {
            settingsToggle(
                "Quiet Hours",
                isOn: $quietHoursEnabled,
                icon: "moon.zzz.fill",
                onToggle: { enabled in
                    persistToggle(\.quietHoursEnabled, value: enabled)
                }
            )

            if quietHoursEnabled {
                SettingsRowDivider()
                SettingsControlRow(label: "From", icon: "sunset.fill") {
                    DatePicker("From", selection: $quietHoursStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: quietHoursStart) { _, newValue in
                            persistQuietHoursStart(newValue)
                        }
                }

                SettingsRowDivider()
                SettingsControlRow(label: "Until", icon: "sunrise.fill") {
                    DatePicker("Until", selection: $quietHoursEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .onChange(of: quietHoursEnd) { _, newValue in
                            persistQuietHoursEnd(newValue)
                        }
                }
            }
        }
        .animation(Tide.snap, value: quietHoursEnabled)
    }

    // MARK: - Shared Components

    /// One switch row. The master look of every toggle on this page.
    private func settingsToggle(
        _ label: String,
        isOn: Binding<Bool>,
        icon: String,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        SettingsControlRow(label: label, icon: icon) {
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onToggle(newValue)
                }
                .sensoryFeedback(.selection, trigger: isOn.wrappedValue)
        }
    }

    // MARK: - Persistence

    private func loadFromSettings() {
        guard let settings else {
            return
        }
        intensity = settings.notificationIntensity
        morningBriefing = settings.morningBriefingEnabled
        accountability = settings.accountabilityEnabled
        recovery = settings.recoveryEnabled
        mealReminders = settings.mealRemindersEnabled
        bedtimeReminder = settings.bedtimeReminderEnabled
        streakWarning = settings.streakWarningEnabled
        arenaNotifications = settings.arenaNotificationsEnabled
        weeklyReport = settings.weeklyReportEnabled
        trainingReminder = settings.trainingReminderEnabled
        trainerSessionReminder = settings.trainerSessionReminderEnabled
        weeklyUploadReminder = settings.weeklyUploadReminderEnabled
        soundEnabled = settings.soundEnabled
        quietHoursEnabled = settings.quietHoursEnabled
        quietHoursStart = Self.timeFromMinutes(settings.quietHoursStartMinutes)
        quietHoursEnd = Self.timeFromMinutes(settings.quietHoursEndMinutes)
    }

    private func persistIntensity(_ value: Int) {
        settings?.notificationIntensity = value
        settings?.updatedAt = Date()
    }

    private func persistToggle(_ keyPath: ReferenceWritableKeyPath<UserSettings, Bool>, value: Bool) {
        settings?[keyPath: keyPath] = value
        settings?.updatedAt = Date()
    }

    private func persistQuietHoursStart(_ date: Date) {
        let minutes = Self.minutesFromTime(date)
        settings?.quietHoursStartMinutes = minutes
        settings?.updatedAt = Date()
    }

    private func persistQuietHoursEnd(_ date: Date) {
        let minutes = Self.minutesFromTime(date)
        settings?.quietHoursEndMinutes = minutes
        settings?.updatedAt = Date()
    }

    // MARK: - Time Helpers

    private static func timeFromMinutes(_ minutes: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = minutes / 60
        components.minute = minutes % 60
        return Calendar.current.date(from: components) ?? Date()
    }

    private static func minutesFromTime(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

// MARK: - IntensityOption

private enum IntensityOption: Int, CaseIterable, Identifiable {
    case gentle = 1
    case firm = 2
    case drillSergeant = 3
    case savage = 4

    var id: Int {
        rawValue
    }

    /// Per UX_COPY_BIBLE.md — Notification intensity option strings
    var title: String {
        switch self {
        case .gentle: "Gentle Coach"
        case .firm: "Firm Coach"
        case .drillSergeant: "Drill Sergeant"
        case .savage: "Savage Mode"
        }
    }

    var description: String {
        switch self {
        case .gentle: "Supportive and encouraging. Reminders without the edge."
        case .firm: "Direct and clear. No sugarcoating, but no yelling."
        case .drillSergeant: "Tough love. Gets louder as the day goes on."
        case .savage: "Maximum pressure. Not for the faint-hearted."
        }
    }

    var preview: String {
        switch self {
        case .gentle: "\"Hey! You've got 3 tasks left today. You can totally do this!\""
        case .firm: "\"3 tasks remaining. 5 hours left. Time to focus.\""
        case .drillSergeant: "\"3 non-negotiables left. Clock's ticking. Move.\""
        case .savage: "\"3 tasks undone. Another wasted day incoming. Prove me wrong.\""
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        NotificationSettingsView()
            .environment(ServiceContainer.mock())
    }
    .modelContainer(for: UserSettings.self, inMemory: true)
}
