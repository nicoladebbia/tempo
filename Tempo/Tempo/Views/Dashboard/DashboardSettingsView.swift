//
// DashboardSettingsView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - DashboardSettingsView

// General app settings accessible from the dashboard gear icon.
// Organized into sections with NavigationLinks to detail editors.

struct DashboardSettingsView: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood

    @Environment(\.dynamicTypeSize)
    private var headerTypeSize
    @Query
    private var allSettings: [UserSettings]
    @Query
    private var allProfiles: [UserProfile]
    #if DEBUG
        @Query
        private var allExercisesForImageBackfill: [Exercise]
        @State private var isGeneratingMissingImages = false
        @State private var missingImagesStatus: String?
    #endif

    private var settings: UserSettings? {
        allSettings.first
    }

    private var profile: UserProfile? {
        allProfiles.first
    }

    // MARK: - Account deletion state

    //
    // Apple-required per App Store Review Guideline 5.1.1(v): users must be
    // able to initiate account deletion from within the app. Backend wipes
    // owned data and soft-deletes the user row; iOS then drops local
    // credentials.

    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    /// The server's answer about the plan, shared with the Subscription page.
    @State private var plan = PlanModel()
    /// Confirms "Show tips again".
    @State private var tipsToast: ToastData?

    var body: some View {
        TideSettingsPage {
            profileHeaderCard

            SettingsGroupCard(title: "You & your day") {
                NavigationLink {
                    ScheduleSettingsDetailView()
                } label: {
                    SettingsNavRow(icon: "clock.fill", title: "Schedule", subtitle: scheduleSubtitle)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    TrainingSettingsDetailView()
                } label: {
                    SettingsNavRow(icon: "dumbbell.fill", title: "Training", subtitle: trainingSubtitle)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    FocusTimerSettingsDetailView()
                } label: {
                    SettingsNavRow(icon: "timer", title: "Focus Timer", subtitle: focusSubtitle)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    ModesSettingsDetailView()
                } label: {
                    SettingsNavRow(icon: "bolt.fill", title: "Modes", subtitle: modesSubtitle)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    FuelSetupView(embedded: true)
                } label: {
                    SettingsStatusRow(
                        icon: "fork.knife", title: "Diet Profile",
                        status: dietProfileStatusText, statusColor: dietProfileStatusColor
                    )
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    WeeklyHabitsSettingsView()
                } label: {
                    SettingsNavRow(
                        icon: "calendar.badge.clock",
                        title: "Weekly habits", subtitle: "Sunday planning, routine, what we've learned"
                    )
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("settingsWeeklyHabits")

                NavigationLink {
                    SetupChecklistPage()
                } label: {
                    SettingsStatusRow(
                        icon: "checklist", title: "Get set up",
                        status: setupStatusText, statusColor: setupStatusColor
                    )
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("settingsGetSetUp")
            }

            SettingsGroupCard(title: "Connections & alerts") {
                NavigationLink {
                    ConnectionsView()
                } label: {
                    SettingsStatusRow(
                        icon: "link", title: "Connections",
                        status: connectionsSummary, statusColor: connectionsSummaryColor
                    )
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("settingsConnections")

                NavigationLink {
                    NotificationInboxView(onOpen: { dismiss() })
                } label: {
                    SettingsStatusRow(
                        icon: "tray.fill", title: "Today's notifications",
                        status: inboxStatus, statusColor: inboxStatusColor
                    )
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("settingsNotificationInbox")

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsNavRow(icon: "bell.fill", title: "Notifications", subtitle: notificationsSubtitle)
                }
                .buttonStyle(.tideSettingsRow)
                .accessibilityIdentifier("settingsNotifications")
            }

            AIFeaturesSettingsCard()

            SettingsGroupCard(title: "Account & data") {
                NavigationLink {
                    SubscriptionDetailView(plan: plan)
                } label: {
                    SettingsNavRow(icon: "crown.fill", title: "Subscription", subtitle: subscriptionStatusText)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    AccountDetailView()
                } label: {
                    SettingsNavRow(
                        icon: "person.crop.circle",
                        title: "Account",
                        subtitle: services.authService.authState == .unauthenticated
                            || services.authService.authState == .expired
                            ? "Not signed in — tap to sign in"
                            : "Sign-in, member since, delete"
                    )
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    DataExportView()
                } label: {
                    SettingsNavRow(icon: "square.and.arrow.up", title: "Export My Data")
                }
                .buttonStyle(.tideSettingsRow)

                ShowTipsAgainRow(toast: $tipsToast)

                if let supportURL = URL(string: "https://tempo.app/support") {
                    Link(destination: supportURL) {
                        SettingsActionRow(icon: "questionmark.circle", title: "Support", tint: Tide.text)
                    }
                    .buttonStyle(.tideSettingsRow)
                }

                SettingsActionRow(
                    icon: "number", title: "Version", tint: Tide.text,
                    trailingText: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                )
            }

            #if DEBUG
                SettingsGroupCard(title: "Developer") {
                    NavigationLink {
                        DailyReadinessHarnessView()
                    } label: {
                        SettingsNavRow(
                            icon: "flask.fill", iconTint: Tide.streak,
                            title: "D0 Prompt Harness", subtitle: "Run ~20 synthetic days through Haiku"
                        )
                    }
                    .buttonStyle(.tideSettingsRow)

                    Button {
                        Task { await generateMissingExerciseImages() }
                    } label: {
                        SettingsNavRow(
                            icon: "photo.badge.plus", iconTint: Tide.streak,
                            title: "Generate missing exercise pictures",
                            subtitle: missingImagesStatus ?? "Walk the local library, request any missing ones"
                        )
                    }
                    .buttonStyle(.tideSettingsRow)
                    .disabled(isGeneratingMissingImages)
                }
            #endif
        }
        .tempoToast($tipsToast)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(Tide.bodyStrong)
            }
        }
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await performAccountDeletion() }
            }
        } message: {
            Text("This permanently deletes all your data. This cannot be undone.")
        }
        .alert(
            "Could not delete account",
            isPresented: Binding(
                get: { deleteAccountError != nil },
                set: {
                    if !$0 {
                        deleteAccountError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .task { await plan.refresh(apiClient: services.apiClient) }
        .task { await NotificationInbox.shared.refresh() }
    }

    // MARK: - Profile Header Card

    private var profileHeaderCard: some View {
        NavigationLink {
            ProfileSettingsDetailView()
        } label: {
            // At accessibility sizes the picture sits above the text so the name keeps its width.
            let layout = headerTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s4))
            layout {
                // The ring is the way to the next level.
                TideSettingsAvatar(initial: profileInitial)
                    .padding(Tide.s1)
                    .overlay {
                        TideRing(progress: levelProgress, color: mood.accent, lineWidth: Tide.barSlim, glow: false)
                    }

                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(profile?.displayName ?? "Athlete")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("@\(profile?.username ?? "—") · \(profile?.identityLabel ?? "Athlete")")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(profileStatsLine)
                        .tideLabel(mood.accent)
                        .padding(.top, Tide.s1)
                        .contentTransition(.numericText())
                }

                if !headerTypeSize.isAccessibilitySize {
                    Spacer(minLength: Tide.s2)

                    Image(systemName: "chevron.right")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
            }
            .tideCard(padding: Tide.s4)
            .contentShape(.rect(cornerRadius: Tide.cardRadius))
        }
        .buttonStyle(TideSettingsCardPressStyle())
    }

    // MARK: - Live Summary Subtitles

    private func timeString(fromMinutes minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }

    private var scheduleSubtitle: String {
        guard let s = settings else {
            return "Not set up"
        }
        // leisureTimeMinutes is a TIME-OF-DAY (validated 0..<1440 alongside
        // wake/bedtime as invalidTimeOfDay), NOT a duration — render as a clock.
        return "Wake \(timeString(fromMinutes: s.wakeTimeMinutes)) · Bed \(timeString(fromMinutes: s.bedtimeTargetMinutes)) · Leisure \(timeString(fromMinutes: s.leisureTimeMinutes))"
    }

    private var trainingSubtitle: String {
        guard let s = settings else {
            return "Not set up"
        }
        let days = s.footballDaysRaw.nonzeroBitCount
        let football = days == 0 ? "no football" : "\(days) football day\(days == 1 ? "" : "s")"
        return "\(s.trainingSplit.displayName) · \(football) · \(s.weightUnitRaw)"
    }

    private var focusSubtitle: String {
        guard let s = settings else {
            return "Not set up"
        }
        return "\(s.pomodoroDuration) / \(s.breakDuration) / \(s.longBreakDuration) min"
    }

    private var modesSubtitle: String {
        guard let s = settings else {
            return "None active"
        }
        var active: [String] = []
        if s.weekendMode {
            active.append("Weekend")
        }
        if s.examMode {
            active.append("Exam")
        }
        return active.isEmpty ? "None active" : active.joined(separator: " · ")
    }

    /// The level the reminder switches add up to, and quiet hours when they are on.
    private var notificationsSubtitle: String {
        guard let settings else {
            return "Default"
        }
        let policy = NotificationPolicy(settings: settings)
        let level = policy.level?.title ?? "Custom"
        guard let quiet = policy.quietHours else {
            return level
        }
        return "\(level) · quiet \(Self.clock(quiet.startMinutes))–\(Self.clock(quiet.endMinutes))"
    }

    private static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private var inboxStatus: String {
        let inbox = NotificationInbox.shared
        if inbox.items.isEmpty {
            return "None today"
        }
        return inbox.unreadCount > 0 ? "\(inbox.unreadCount) new" : "All read"
    }

    private var inboxStatusColor: Color {
        NotificationInbox.shared.unreadCount > 0 ? mood.accent : Tide.text2
    }

    /// 0...1 toward the next level, worked out the way the Arena does it.
    private var levelProgress: Double {
        settingsLevelProgress(totalXP: profile?.totalXP ?? 0, engine: services.xpEngine)
    }

    private var profileStatsLine: String {
        let level = profile?.currentLevel ?? 1
        let xp = profile?.totalXP ?? 0
        let xpStr = xp >= 1000 ? String(format: "%.1fk XP", Double(xp) / 1000) : "\(xp) XP"
        return "Lvl \(level) · \(xpStr)"
    }

    // MARK: - Subscription

    private var subscriptionStatusText: String {
        plan.status(device: services.subscriptions.state).title
    }

    #if DEBUG

        // MARK: - Exercise image backfill (DEBUG only) — feat/exercise-images

        /// Walks the local exercise library and requests any missing picture,
        /// skipping ones ExerciseImageService already has cached or already
        /// knows failed this session. Rate-aware: relies on
        /// ExerciseImageService's own session-scoped failure memory (so a 429
        /// from the backend's 40/day cap stops hammering after the first hit)
        /// rather than adding a second rate limiter here.
        @MainActor
        private func generateMissingExerciseImages() async {
            guard !isGeneratingMissingImages else {
                return
            }
            isGeneratingMissingImages = true
            defer { isGeneratingMissingImages = false }

            let missing = allExercisesForImageBackfill.filter {
                !services.exerciseImages.hasCachedOrFailedResult(for: $0)
            }
            guard !missing.isEmpty else {
                missingImagesStatus = "All \(allExercisesForImageBackfill.count) exercises already have a picture."
                return
            }

            for (done, exercise) in missing.enumerated() {
                _ = await services.exerciseImages.imageData(for: exercise)
                missingImagesStatus = "\(done + 1)/\(missing.count) checked"
            }
            missingImagesStatus = "Done — checked \(missing.count) missing pictures."
        }
    #endif

    // MARK: - Account deletion action

    @MainActor
    private func performAccountDeletion() async {
        guard !isDeletingAccount else {
            return
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try await services.authService.deleteAccount()
            // AuthService flips authState to .unauthenticated; the app root
            // observes that and routes back to the sign-in screen, so no
            // explicit navigation is needed here.
            dismiss()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private var profileInitial: String {
        let name = profile?.displayName ?? "A"
        return String(name.prefix(1)).uppercased()
    }

    @AppStorage("healthKitAuthorized")
    private var healthKitAuthorized = false

    private var dietProfileStatusText: String {
        let descriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate { $0.isActive == true }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0 ? "Configured" : "Not Set Up"
    }

    /// The "Get set up" lines, from the same real state the Today card reads.
    private var setupChecklist: SetupChecklist {
        SetupChecklist(SetupChecklistLoader.signals(
            healthAllowed: healthKitAuthorized,
            whoopConnected: services.whoop.providesRealData,
            resolved: true,
            in: modelContext
        ))
    }

    private var setupStatusText: String {
        let checklist = setupChecklist
        return checklist.doneCount == checklist.total ? "All done" : "\(checklist.doneCount) of \(checklist.total)"
    }

    private var setupStatusColor: Color {
        let checklist = setupChecklist
        return checklist.doneCount == checklist.total ? Tide.settingsOK : Tide.text3
    }

    private var dietProfileStatusColor: Color {
        let descriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate { $0.isActive == true }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0 ? Tide.settingsOK : Tide.text3
    }

    /// What the Connections row says: how many are on, or what needs the user.
    private var connectionsSummary: String {
        ConnectionStatus.summary(connectionStatuses)
    }

    private var connectionsSummaryColor: Color {
        switch ConnectionStatus.summaryTone(connectionStatuses) {
        case .ok: Tide.settingsOK
        case .off: Tide.text3
        case .attention: Tide.settingsAttention
        }
    }

    private var connectionStatuses: [ConnectionStatus] {
        ConnectionsSnapshot.statuses(whoop: services.whoop, healthAsked: healthKitAuthorized)
    }
}

// MARK: - ProfileSettingsDetailView

struct ProfileSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Environment(\.displayScale)
    private var displayScale
    @Query
    private var allProfiles: [UserProfile]
    @Query
    private var allSettings: [UserSettings]
    /// The overall accountability streak (typeRaw == "overall"), for real
    /// streak stats on the profile.
    @Query(filter: #Predicate<Streak> { $0.typeRaw == "overall" })
    private var overallStreaks: [Streak]
    /// The active dietary profile — canonical source for biometrics (it owns
    /// the "Refresh from Health" flow). Profile shows these read-only.
    @Query(filter: #Predicate<DietaryProfile> { $0.isActive == true })
    private var activeDietProfiles: [DietaryProfile]
    /// The one target (a weight, a lift or a run time) with its date.
    @Query(filter: #Predicate<Goal> { $0.isActive == true }, sort: \Goal.createdAt, order: .reverse)
    private var activeGoals: [Goal]

    private var profile: UserProfile? {
        allProfiles.first
    }

    private var settings: UserSettings? {
        allSettings.first
    }

    private var overallStreak: Streak? {
        overallStreaks.first
    }

    private var dietProfile: DietaryProfile? {
        activeDietProfiles.first
    }

    @State
    private var displayName = ""
    @State
    private var username = ""
    @State
    private var identityLabel = OnboardingViewModel.identityLabels[0]

    private let identityOptions = OnboardingViewModel.identityLabels

    var body: some View {
        TideSettingsPage {
            heroCard
            statsCard
            trainingSummaryCard
            identityCard
            goalTargetCard
            biometricsCard
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: Tide.s3) {
            // The ring is the way to the next level.
            TideSettingsAvatar(initial: profileInitial, diameter: Tide.settingsAvatarLarge)
                .padding(Tide.s2)
                .overlay {
                    TideRing(
                        progress: settingsLevelProgress(totalXP: profile?.totalXP ?? 0, engine: services.xpEngine),
                        color: mood.accent, lineWidth: Tide.bar
                    )
                }

            VStack(spacing: Tide.hair) {
                Text(displayName.isEmpty ? "Athlete" : displayName)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("@\(username.isEmpty ? "—" : username)")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)

                // Identity as a small tag under the username, so it reads
                // below it and never louder.
                Text(identityLabel)
                    .tideLabel(Tide.text3)
                    .padding(.top, Tide.s1)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .tideCard(padding: Tide.s6)
    }

    private var profileInitial: String {
        let name = displayName.isEmpty ? (profile?.displayName ?? "A") : displayName
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - Stats

    private var statsCard: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            statCell(value: "\(profile?.currentLevel ?? 1)", label: "Level")
            statDivider
            statCell(value: streakDisplay, label: "Streak")
            statDivider
            statCell(value: xpDisplay, label: "Total XP")
            statDivider
            statCell(value: memberSince, label: "Member")
        }
        .tideCard(padding: Tide.s4)
    }

    private var streakDisplay: String {
        let current = overallStreak?.currentCount ?? 0
        return current == 0 ? "—" : "\(current)d"
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: Tide.s1) {
            TideNumber(value, size: Tide.numeralS, relativeTo: .headline)
            Text(label)
                .tideLabel(Tide.text3)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Tide.hair)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statDivider: some View {
        if !typeSize.isAccessibilitySize {
            Rectangle()
                .fill(Tide.hairline)
                .frame(width: 1 / displayScale, height: Tide.s6)
                .accessibilityHidden(true)
        }
    }

    private var xpDisplay: String {
        let xp = profile?.totalXP ?? 0
        return xp >= 1000 ? String(format: "%.1fk", Double(xp) / 1000) : "\(xp)"
    }

    private var memberSince: String {
        guard let created = profile?.createdAt else {
            return "—"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM ''yy"
        return f.string(from: created)
    }

    // MARK: - Training summary (read-only, surfaced from UserSettings)

    private var trainingSummaryCard: some View {
        SettingsFormCard(title: "Training") {
            SettingsInfoRow(
                label: "Split", value: settings?.trainingSplit.displayName ?? "—",
                icon: "dumbbell.fill"
            )
            SettingsRowDivider()
            SettingsInfoRow(
                label: "Football days", value: footballSummary,
                icon: "sportscourt.fill"
            )
            SettingsRowDivider()
            SettingsInfoRow(
                label: "Weight unit", value: (settings?.weightUnitRaw ?? "kg").uppercased(),
                icon: "scalemass.fill"
            )
            if let longest = overallStreak?.longestCount, longest > 0 {
                SettingsRowDivider()
                SettingsInfoRow(
                    label: "Longest streak", value: "\(longest) days",
                    icon: "flame.fill", iconTint: Tide.streak
                )
            }
        }
    }

    private var footballSummary: String {
        let days = settings?.footballDaysRaw.nonzeroBitCount ?? 0
        return days == 0 ? "None" : "\(days)/week"
    }

    // MARK: - Identity (editable)

    private var identityCard: some View {
        SettingsFormCard(title: "Identity") {
            labeledField(label: "Display Name", text: $displayName, placeholder: "Your name") { newValue in
                profile?.displayName = newValue
                touch()
            }
            SettingsRowDivider(underTitle: false)
            labeledField(
                label: "Username", text: $username, placeholder: "username",
                prefix: "@", autocapitalize: false
            ) { newValue in
                profile?.username = newValue
                touch()
            }
            SettingsRowDivider(underTitle: false)
            identityLabelRow
            SettingsRowDivider(underTitle: false)
            goalRow
        }
    }

    /// A measurable target with a date. Today and the progress screens show how it is going.
    private var goalTargetCard: some View {
        SettingsGroupCard {
            NavigationLink {
                GoalEditorView()
            } label: {
                SettingsNavRow(icon: "target", title: "Target and date", subtitle: goalTargetSubtitle)
            }
            .buttonStyle(.tideSettingsRow)
            .accessibilityIdentifier("settingsGoalTarget")
        }
    }

    private var goalTargetSubtitle: String {
        guard let goal = activeGoals.first else {
            return "A weight, a lift or a run time, and when"
        }
        let by = goal.targetDate.formatted(.dateTime.day().month(.abbreviated))
        return "\(GoalFormat.headline(for: goal, unit: settings?.weightUnit ?? .kg)) by \(by)"
    }

    /// The goal picked in onboarding, changeable here.
    private var goalRow: some View {
        SettingsControlRow(label: "Goal") {
            Picker(
                "Goal",
                selection: Binding(
                    get: { settings?.primaryGoal },
                    set: { newValue in
                        settings?.primaryGoal = newValue
                        touch()
                    }
                )
            ) {
                Text("Not set").tag(PrimaryGoal?.none)
                ForEach(PrimaryGoal.allCases, id: \.self) { goal in
                    Text(goal.title).tag(PrimaryGoal?.some(goal))
                }
            }
            .labelsHidden()
            .font(Tide.bodyStrong)
            .tint(Tide.text2)
            .padding(typeSize.isAccessibilitySize ? .leading : .trailing, -Tide.s3)
            .accessibilityIdentifier("settingsGoalPicker")
        }
    }

    private var identityLabelRow: some View {
        SettingsControlRow(label: "Identity") {
            Picker("Identity", selection: $identityLabel) {
                ForEach(identityOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .font(Tide.bodyStrong)
            .tint(Tide.text2)
            // A menu picker pads its own end; pull it back to the row's edge.
            .padding(typeSize.isAccessibilitySize ? .leading : .trailing, -Tide.s3)
            .onChange(of: identityLabel) { _, newValue in
                profile?.identityLabel = newValue
                touch()
            }
        }
    }

    // MARK: - Biometrics (editable)

    /// Biometrics are READ-ONLY here. They're owned by the active
    /// DietaryProfile (which has the "Refresh from Health" flow); editing
    /// them lives there, not on the profile screen.
    private var biometricsCard: some View {
        SettingsFormCard(
            title: "Biometrics",
            footnote: "Biometrics come from your Diet Profile. Update them there with “Refresh from Health.”"
        ) {
            if let d = dietProfile {
                SettingsInfoRow(
                    label: "Weight",
                    value: String(format: "%.1f kg", d.currentWeightKg),
                    icon: "scalemass"
                )
                SettingsRowDivider()
                SettingsInfoRow(
                    label: "Height",
                    value: String(format: "%.0f cm", d.heightCm),
                    icon: "ruler"
                )
                SettingsRowDivider()
                SettingsInfoRow(label: "Age", value: "\(d.age)", icon: "calendar")
                SettingsRowDivider()
                SettingsInfoRow(
                    label: "Est. BMR",
                    value: "\(Int(bmr(from: d))) kcal",
                    icon: "flame"
                )
            } else {
                NavigationLink {
                    FuelSetupView(embedded: true)
                } label: {
                    SettingsNavRow(
                        icon: "heart.text.square",
                        title: "Set up biometrics", subtitle: "In Diet Profile → Refresh from Health"
                    )
                }
                .buttonStyle(.tideSettingsRow)
            }
        }
    }

    /// Mifflin-St Jeor BMR from the dietary profile (same formula as
    /// UserProfile.estimatedBMR, sex-aware via the diet profile).
    private func bmr(from d: DietaryProfile) -> Double {
        let base = (10 * d.currentWeightKg) + (6.25 * d.heightCm) - (5 * Double(d.age))
        return d.biologicalSex == .female ? base - 161 : base + 5
    }

    // MARK: - Reusable row builders

    private func labeledField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        prefix: String? = nil,
        autocapitalize: Bool = true,
        onCommit: @escaping (String) -> Void
    ) -> some View {
        let field = TextField(placeholder, text: text)
            .font(Tide.body)
            .foregroundStyle(Tide.text)
            .multilineTextAlignment(typeSize.isAccessibilitySize || prefix != nil ? .leading : .trailing)
            .textInputAutocapitalization(autocapitalize ? .words : .never)
            .autocorrectionDisabled(!autocapitalize)
            .onChange(of: text.wrappedValue) { _, newValue in onCommit(newValue) }
        return SettingsControlRow(label: label) {
            if let prefix {
                // The "@" hugs the name: a hidden copy of the text sets the width,
                // and the real field sits on top of it.
                HStack(spacing: 0) {
                    Text(prefix)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text3)
                    Text(text.wrappedValue.isEmpty ? placeholder : text.wrappedValue)
                        .font(Tide.body)
                        .lineLimit(1)
                        .hidden()
                        .padding(.trailing, Tide.s1)
                        .overlay { field }
                }
                .frame(minHeight: Tide.hit)
                // Cancel the caret room so the name lines up with the other values.
                .padding(.trailing, -Tide.s1)
            } else {
                field
                    .frame(minHeight: Tide.hit)
            }
        }
    }

    // MARK: - Load / Save

    private func loadProfile() {
        guard let p = profile else {
            return
        }
        displayName = p.displayName
        username = p.username
        identityLabel = identityOptions.contains(p.identityLabel) ? p.identityLabel : identityOptions[0]
    }

    private func touch() {
        profile?.updatedAt = Date()
        try? modelContext.save()
    }
}

// MARK: - Level progress

/// 0...1 toward the next level, worked out the way the Arena does it, so the
/// ring on the profile picture and the bar in the Arena always agree.
private func settingsLevelProgress(totalXP: Int, engine: any XPEngineProtocol) -> Double {
    let level = engine.currentLevel(totalXP: totalXP)
    let floor = engine.xpForLevel(level)
    let ceiling = level + 1 <= LevelSystem.definitions.count ? engine.xpForLevel(level + 1) : floor + 10000
    return min(max(Double(totalXP - floor) / Double(max(1, ceiling - floor)), 0), 1)
}
