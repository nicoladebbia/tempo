import SwiftUI
import SwiftData

// MARK: - Notification Settings View
// Per BUILD_PLAN step 12.5 — Notification settings UI.
// Per WIREFRAMES.md Screen 58 — NotificationSettingsView layout.
// Per ONBOARDING_AND_NOTIFICATIONS.md — Intensity, categories, quiet hours.

struct NotificationSettingsView: View {

    @Environment(ServiceContainer.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [UserSettings]

    private var settings: UserSettings? { allSettings.first }

    // MARK: - Local State

    @State private var intensity: Int = 3
    @State private var morningBriefing: Bool = true
    @State private var accountability: Bool = true
    @State private var recovery: Bool = true
    @State private var mealReminders: Bool = true
    @State private var bedtimeReminder: Bool = true
    @State private var streakWarning: Bool = true
    @State private var arenaNotifications: Bool = true
    @State private var weeklyReport: Bool = true
    @State private var trainingReminder: Bool = true
    @State private var soundEnabled: Bool = true
    @State private var quietHoursEnabled: Bool = false
    @State private var quietHoursStart: Date = Self.timeFromMinutes(1380)
    @State private var quietHoursEnd: Date = Self.timeFromMinutes(420)

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {

                // MARK: - Intensity Section
                intensitySection

                // MARK: - Daily Reminders
                dailyRemindersSection

                // MARK: - Accountability
                accountabilitySection

                // MARK: - Social
                socialSection

                // MARK: - Sound
                soundSection

                // MARK: - Quiet Hours
                quietHoursSection
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadFromSettings)
    }

    // MARK: - Intensity Section

    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("INTENSITY")

            VStack(spacing: 0) {
                // Per UX_COPY_BIBLE.md — onb_notif_intensity_label
                ForEach(IntensityOption.allCases) { option in
                    Button {
                        intensity = option.rawValue
                        persistIntensity(option.rawValue)
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                                HStack(spacing: TempoSpacing.sm) {
                                    Text(option.title)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.tempoTextPrimary)
                                    if option == .drillSergeant {
                                        Text("REC")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(Color.tempoBone)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.tempoSignal)
                                            .clipShape(Capsule())
                                    }
                                }
                                Text(option.description)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.tempoTextSecondary)
                            }
                            Spacer()
                            Image(systemName: intensity == option.rawValue ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(intensity == option.rawValue ? Color.tempoSignal : Color.tempoTextTertiary)
                        }
                        .padding(.vertical, TempoSpacing.md)
                        .padding(.horizontal, TempoSpacing.lg)
                    }
                    .buttonStyle(.plain)

                    if option != .savage {
                        Divider()
                            .padding(.leading, TempoSpacing.lg)
                    }
                }
            }
            .tempoCard()

            // Preview text for selected intensity
            Text(IntensityOption(rawValue: intensity)?.preview ?? "")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.tempoTextSecondary)
                .padding(.horizontal, TempoSpacing.xs)
        }
    }

    // MARK: - Daily Reminders Section

    private var dailyRemindersSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("DAILY REMINDERS")

            VStack(spacing: 0) {
                settingsToggle(
                    "Morning Briefing",
                    isOn: $morningBriefing,
                    icon: "sunrise.fill",
                    onToggle: { enabled in
                        persistToggle(\.morningBriefingEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("MORNING_BRIEFING") }
                    }
                )
                settingsDivider()
                settingsToggle(
                    "Recovery Updates",
                    isOn: $recovery,
                    icon: "heart.fill",
                    onToggle: { enabled in
                        persistToggle(\.recoveryEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("RECOVERY_REPORT") }
                    }
                )
                settingsDivider()
                settingsToggle(
                    "Meal Reminders",
                    isOn: $mealReminders,
                    icon: "fork.knife",
                    onToggle: { enabled in
                        persistToggle(\.mealRemindersEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("MEAL_REMINDER") }
                    }
                )
                settingsDivider()
                settingsToggle(
                    "Bedtime Reminder",
                    isOn: $bedtimeReminder,
                    icon: "moon.fill",
                    onToggle: { enabled in
                        persistToggle(\.bedtimeReminderEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("BEDTIME_REMINDER") }
                    }
                )
                settingsDivider()
                settingsToggle(
                    "Weekly Report",
                    isOn: $weeklyReport,
                    icon: "chart.bar.fill",
                    onToggle: { enabled in
                        persistToggle(\.weeklyReportEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("WEEKLY_SUMMARY") }
                    }
                )
            }
            .tempoCard()
        }
    }

    // MARK: - Accountability Section

    private var accountabilitySection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("ACCOUNTABILITY")

            VStack(spacing: 0) {
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
                settingsDivider()
                settingsToggle(
                    "Streak Warnings",
                    isOn: $streakWarning,
                    icon: "flame.fill",
                    onToggle: { enabled in
                        persistToggle(\.streakWarningEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("STREAK_WARNING") }
                    }
                )
                settingsDivider()
                settingsToggle(
                    "Training Reminders",
                    isOn: $trainingReminder,
                    icon: "dumbbell.fill",
                    onToggle: { enabled in
                        persistToggle(\.trainingReminderEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("TRAINING_REMINDER") }
                    }
                )
            }
            .tempoCard()
        }
    }

    // MARK: - Social Section

    private var socialSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("SOCIAL")

            VStack(spacing: 0) {
                settingsToggle(
                    "Arena Notifications",
                    isOn: $arenaNotifications,
                    icon: "trophy.fill",
                    onToggle: { enabled in
                        persistToggle(\.arenaNotificationsEnabled, value: enabled)
                        if !enabled { services.notifications.cancelCategory("ARENA_SOCIAL") }
                    }
                )
            }
            .tempoCard()
        }
    }

    // MARK: - Sound Section

    private var soundSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("SOUND")

            VStack(spacing: 0) {
                settingsToggle(
                    "Notification Sound",
                    isOn: $soundEnabled,
                    icon: "speaker.wave.2.fill",
                    onToggle: { enabled in
                        persistToggle(\.soundEnabled, value: enabled)
                    }
                )
            }
            .tempoCard()
        }
    }

    // MARK: - Quiet Hours Section

    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionHeader("QUIET HOURS")

            VStack(spacing: 0) {
                settingsToggle(
                    "Quiet Hours",
                    isOn: $quietHoursEnabled,
                    icon: "moon.zzz.fill",
                    onToggle: { enabled in
                        persistToggle(\.quietHoursEnabled, value: enabled)
                    }
                )

                if quietHoursEnabled {
                    settingsDivider()
                    HStack {
                        Text("From")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        DatePicker("", selection: $quietHoursStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: quietHoursStart) { _, newValue in
                                persistQuietHoursStart(newValue)
                            }
                    }
                    .padding(.vertical, TempoSpacing.md)
                    .padding(.horizontal, TempoSpacing.lg)

                    settingsDivider()
                    HStack {
                        Text("Until")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        DatePicker("", selection: $quietHoursEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .onChange(of: quietHoursEnd) { _, newValue in
                                persistQuietHoursEnd(newValue)
                            }
                    }
                    .padding(.vertical, TempoSpacing.md)
                    .padding(.horizontal, TempoSpacing.lg)
                }
            }
            .tempoCard()
            .animation(.easeInOut(duration: 0.2), value: quietHoursEnabled)

            Text("Time Sensitive notifications (accountability escalations) still break through during quiet hours.")
                .font(.system(size: 12))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.horizontal, TempoSpacing.xs)
        }
    }

    // MARK: - Shared Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.tempoTextTertiary)
            .tracking(0.8)
    }

    private func settingsToggle(
        _ label: String,
        isOn: Binding<Bool>,
        icon: String,
        onToggle: @escaping (Bool) -> Void
    ) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoSignal)
                .frame(width: 24)
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.tempo)
                .labelsHidden()
                .onChange(of: isOn.wrappedValue) { _, newValue in
                    onToggle(newValue)
                }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, TempoSpacing.lg)
    }

    private func settingsDivider() -> some View {
        Divider()
            .padding(.leading, TempoSpacing.lg + 24 + TempoSpacing.md)
    }

    // MARK: - Persistence

    private func loadFromSettings() {
        guard let settings else { return }
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

// MARK: - Intensity Options

private enum IntensityOption: Int, CaseIterable, Identifiable {
    case gentle = 1
    case firm = 2
    case drillSergeant = 3
    case savage = 4

    var id: Int { rawValue }

    // Per UX_COPY_BIBLE.md — Notification intensity option strings
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
