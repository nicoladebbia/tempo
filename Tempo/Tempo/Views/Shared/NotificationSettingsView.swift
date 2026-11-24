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
//
// The page leads with the two things most people need: how much Tempo may send
// (Essential / Balanced / Everything) and when it must stay quiet. The individual
// switches are all still here, under "Fine tune". A level is a preset over those
// switches and is read back from them, so it says "Custom" once they match no preset.

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
    /// The reminders that are switched on.
    @State
    private var enabled: Set<NotificationTopic> = Set(NotificationTopic.allCases)
    @State
    private var fineTuneOpen = false
    @State
    private var soundEnabled: Bool = true
    @State
    private var quietHoursEnabled: Bool = false
    @State
    private var quietHoursStart: Date = Self.timeFromMinutes(1380)
    @State
    private var quietHoursEnd: Date = Self.timeFromMinutes(420)

    /// The level the switches add up to, nil for Custom.
    private var level: NotificationLevel? {
        NotificationLevel.matching(enabled)
    }

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
                // The permission check takes a moment: the page's own shape,
                // breathing, instead of a lone spinner.
                LoadingStateView(style: .list)
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
        .sensoryFeedback(.selection, trigger: enabled)
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

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        VStack(spacing: Tide.settingsGroupGap) {
            summaryCard
            levelSection
            quietHoursSection
            intensitySection
            fineTuneSection
        }
    }

    // MARK: - Summary

    private var remindersOn: Int {
        enabled.count
    }

    private var remindersTotal: Int {
        NotificationTopic.allCases.count
    }

    private var summaryCard: some View {
        TideSettingsHero {
            TideLabel("Reminders on")
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber(
                    "\(remindersOn)", unit: "of \(remindersTotal)",
                    size: Tide.numeralL, relativeTo: .largeTitle
                )
                Spacer(minLength: Tide.s2)
                Text(level?.title ?? "Custom")
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

    // MARK: - Level Section

    /// How much Tempo may send: three presets over the switches under "Fine tune".
    private var levelSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSettingsSection(title: "What to send") {
                ForEach(NotificationLevel.allCases) { option in
                    Button {
                        applyLevel(option)
                    } label: {
                        choiceRow(
                            title: option.title, detail: option.summary,
                            isSelected: level == option, isRecommended: false
                        )
                    }
                    .buttonStyle(.tideSettingsRow)
                    .accessibilityAddTraits(level == option ? .isSelected : [])
                    .accessibilityIdentifier("notificationLevel-\(option.rawValue)")

                    if option != NotificationLevel.allCases.last {
                        TideSettingsHairline(inset: Tide.s4)
                    }
                }
            }

            Text(
                level == nil
                    ? "Custom: you turned individual reminders on or off under Fine tune. Pick a level to start over."
                    : "Each level only changes which reminders are on. You can still change any of them under Fine tune."
            )
            .font(Tide.caption)
            .foregroundStyle(level == nil ? Tide.settingsAttention : Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Tide.s2)
            .accessibilityIdentifier("notificationLevelNote")
        }
    }

    // MARK: - Intensity Section

    /// How hard the accountability reminders push. Tone, not volume: it sits beside the level, not in it.
    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            TideSettingsSection(title: "How hard it pushes") {
                // Per UX_COPY_BIBLE.md — onb_notif_intensity_label
                ForEach(IntensityOption.allCases) { option in
                    Button {
                        intensity = option.rawValue
                        persistIntensity(option.rawValue)
                    } label: {
                        choiceRow(
                            title: option.title, detail: option.description,
                            isSelected: intensity == option.rawValue, isRecommended: option == .drillSergeant
                        )
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

    /// One choice in a list of choices: a title, what it means, and a tick.
    private func choiceRow(title: String, detail: String, isSelected: Bool, isRecommended: Bool) -> some View {
        let isLarge = typeSize.isAccessibilitySize
        let indicator = Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(Tide.headline)
            .foregroundStyle(isSelected ? mood.accent : Tide.text3)
            .accessibilityHidden(true)
        let titleText = Text(title)
            .font(Tide.bodyStrong)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
        let recommended = Text("REC")
            .font(Tide.label)
            .foregroundStyle(Tide.ink)
            .padding(.horizontal, Tide.s2)
            .padding(.vertical, Tide.hair)
            .background(mood.accent, in: .capsule)
        let detailText = Text(detail)
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
                        titleText
                    }
                    if isRecommended {
                        recommended
                    }
                    detailText
                }
            } else {
                HStack(spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        HStack(spacing: Tide.s2) {
                            titleText
                            if isRecommended {
                                recommended
                            }
                        }
                        detailText
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

    // MARK: - Fine Tune

    /// Every individual switch, folded away until wanted.
    private var fineTuneSection: some View {
        VStack(spacing: Tide.settingsGroupGap) {
            TideSettingsSection {
                Button {
                    withAnimation(Tide.snap) {
                        fineTuneOpen.toggle()
                    }
                } label: {
                    TideSettingsRowLine {
                        HStack(spacing: Tide.s3) {
                            SettingsIconTile(systemName: "slider.horizontal.3", tint: mood.accent)
                            Text("Fine tune")
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } trailing: {
                        HStack(spacing: Tide.s2) {
                            Text(level == nil ? "Custom" : "\(remindersOn) of \(remindersTotal) on")
                                .font(Tide.caption)
                                .foregroundStyle(level == nil ? Tide.settingsAttention : Tide.text2)
                            Image(systemName: "chevron.down")
                                .font(Tide.label)
                                .foregroundStyle(Tide.text3)
                                .rotationEffect(.degrees(fineTuneOpen ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.horizontal, Tide.s4)
                    .padding(.vertical, Tide.s3)
                    .frame(maxWidth: .infinity, minHeight: Tide.settingsRow, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityValue(fineTuneOpen ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("notificationFineTune")
            }

            if fineTuneOpen {
                dailyRemindersSection
                accountabilitySection
                socialSection
            }
        }
    }

    // MARK: - Daily Reminders Section

    private var dailyRemindersSection: some View {
        SettingsFormCard(title: "Daily reminders") {
            topicToggle("Morning Briefing", topic: .morningBriefing, icon: "sunrise.fill")
            SettingsRowDivider()
            topicToggle("Recovery Updates", topic: .recovery, icon: "heart.fill")
            SettingsRowDivider()
            topicToggle("Meal Reminders", topic: .meals, icon: "fork.knife")
            SettingsRowDivider()
            topicToggle("Bedtime Reminder", topic: .bedtime, icon: "moon.fill")
            SettingsRowDivider()
            topicToggle("Weekly Report", topic: .weeklyReport, icon: "chart.bar.fill")
        }
    }

    // MARK: - Accountability Section

    private var accountabilitySection: some View {
        SettingsFormCard(title: "Accountability") {
            topicToggle("Accountability Reminders", topic: .accountability, icon: "bolt.fill")
            SettingsRowDivider()
            topicToggle("Streak Warnings", topic: .streak, icon: "flame.fill")
            SettingsRowDivider()
            topicToggle("Training Reminders", topic: .training, icon: "dumbbell.fill")
            SettingsRowDivider()
            topicToggle("Trainer Sessions", topic: .trainerSession, icon: "figure.strengthtraining.traditional")
            SettingsRowDivider()
            topicToggle("New-Week Upload Reminder", topic: .weeklyUpload, icon: "calendar.badge.exclamationmark")
        }
    }

    // MARK: - Social Section

    private var socialSection: some View {
        SettingsFormCard(title: "Social & sound") {
            topicToggle("Arena Notifications", topic: .arena, icon: "trophy.fill")
            SettingsRowDivider()
            SettingsControlRow(label: "Notification Sound", icon: "speaker.wave.2.fill") {
                Toggle("Notification Sound", isOn: $soundEnabled)
                    .labelsHidden()
                    .onChange(of: soundEnabled) { _, newValue in
                        settings?.soundEnabled = newValue
                        settings?.updatedAt = Date()
                    }
            }
        }
    }

    // MARK: - Quiet Hours Section

    private var quietHoursSection: some View {
        SettingsFormCard(
            title: "Quiet hours",
            footnote: "Inside this window only escalating accountability warnings and defrost reminders come through. The rest are skipped, not delayed."
        ) {
            SettingsControlRow(label: "Quiet Hours", icon: "moon.zzz.fill") {
                Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                    .labelsHidden()
                    .onChange(of: quietHoursEnabled) { _, newValue in
                        // Loading the page sets this too: only a real change is saved.
                        guard settings?.quietHoursEnabled != newValue else {
                            return
                        }
                        settings?.quietHoursEnabled = newValue
                        settings?.updatedAt = Date()
                        commitPolicy()
                    }
                    .sensoryFeedback(.selection, trigger: quietHoursEnabled)
                    .accessibilityIdentifier("notificationQuietHoursToggle")
            }

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
    private func topicToggle(_ label: String, topic: NotificationTopic, icon: String) -> some View {
        SettingsControlRow(label: label, icon: icon) {
            Toggle(
                label,
                isOn: Binding(
                    get: { enabled.contains(topic) },
                    set: { setTopic(topic, on: $0) }
                )
            )
            .labelsHidden()
        }
    }

    // MARK: - Changing a switch

    /// Switches one reminder on or off. Off also clears what was already queued; the
    /// policy then keeps the schedulers from adding it back.
    private func setTopic(_ topic: NotificationTopic, on: Bool, commit: Bool = true) {
        guard enabled.contains(topic) != on else {
            return
        }
        if on {
            enabled.insert(topic)
        } else {
            enabled.remove(topic)
        }
        settings?.set(topic, on: on)
        if !on {
            for category in topic.categoryIDs {
                services.notifications.cancelCategory(category)
            }
            switch topic {
            case .trainerSession: services.notifications.cancelTrainerSessionReminders()
            case .weeklyUpload: services.notifications.cancelWeeklyUploadReminders()
            default: break
            }
        }
        if commit {
            commitPolicy()
        }
    }

    /// Picks a level by setting every switch to match it.
    private func applyLevel(_ target: NotificationLevel) {
        for topic in NotificationTopic.allCases {
            setTopic(topic, on: target.topics.contains(topic), commit: false)
        }
        commitPolicy()
    }

    /// Saves the policy the schedulers read, drops queued reminders it no longer allows, and
    /// rebuilds the ones it newly allows (quiet hours turned off, a reminder switched on).
    private func commitPolicy() {
        NotificationPolicyStore.sync(from: settings)
        let notifications = services.notifications
        MealReminderPlanner.reschedule(modelContext: modelContext, notifications: notifications)
        Task {
            await notifications.removePendingNotAllowedByPolicy()
            // ContentView rebuilds trainer, weekly-upload and supplement reminders on this.
            NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        }
    }

    // MARK: - Persistence

    private func loadFromSettings() {
        guard let settings else {
            return
        }
        intensity = settings.notificationIntensity
        enabled = Set(NotificationTopic.allCases.filter { settings.isOn($0) })
        soundEnabled = settings.soundEnabled
        quietHoursEnabled = settings.quietHoursEnabled
        quietHoursStart = Self.timeFromMinutes(settings.quietHoursStartMinutes)
        quietHoursEnd = Self.timeFromMinutes(settings.quietHoursEndMinutes)
        // Whatever the page shows is what the schedulers use.
        NotificationPolicyStore.sync(from: settings)
    }

    private func persistIntensity(_ value: Int) {
        settings?.notificationIntensity = value
        settings?.updatedAt = Date()
    }

    private func persistQuietHoursStart(_ date: Date) {
        let minutes = Self.minutesFromTime(date)
        guard settings?.quietHoursStartMinutes != minutes else {
            return
        }
        settings?.quietHoursStartMinutes = minutes
        settings?.updatedAt = Date()
        commitPolicy()
    }

    private func persistQuietHoursEnd(_ date: Date) {
        let minutes = Self.minutesFromTime(date)
        guard settings?.quietHoursEndMinutes != minutes else {
            return
        }
        settings?.quietHoursEndMinutes = minutes
        settings?.updatedAt = Date()
        commitPolicy()
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
