//
// DashboardSettingsView.swift
// Tempo
//
// Created by Tempo on 06/05/2026.
//
//

import CoreLocation
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
    @State private var showPaywall = false
    @State private var isRestoring = false
    @State private var restoreError: String?
    /// Refreshed on appear — location auth can change in iOS Settings while away.
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

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
            }

            SettingsGroupCard(title: "Connections") {
                NavigationLink {
                    WhoopConnectionView()
                } label: {
                    SettingsStatusRow(
                        icon: "waveform.path.ecg", title: "Whoop",
                        status: whoopStatusText, statusColor: whoopStatusColor
                    )
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

                Button {
                    openSystemSettings()
                } label: {
                    SettingsStatusRow(
                        icon: "heart.text.square", title: "HealthKit",
                        status: healthKitStatusText, statusColor: healthKitStatusColor,
                        showsChevron: false
                    )
                }
                .buttonStyle(.tideSettingsRow)

                Button {
                    openSystemSettings()
                } label: {
                    SettingsStatusRow(
                        icon: "cloud.sun.fill", title: "Weather (Location)",
                        status: locationStatusText, statusColor: locationStatusColor,
                        showsChevron: false
                    )
                }
                .buttonStyle(.tideSettingsRow)
            }
            .onAppear { locationStatus = CLLocationManager().authorizationStatus }

            SettingsGroupCard(title: "Notifications & plan") {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsNavRow(icon: "bell.fill", title: "Notifications", subtitle: notificationsSubtitle)
                }
                .buttonStyle(.tideSettingsRow)

                NavigationLink {
                    SubscriptionDetailView()
                } label: {
                    SettingsNavRow(icon: "crown.fill", title: "Subscription", subtitle: subscriptionStatusText)
                }
                .buttonStyle(.tideSettingsRow)
            }

            AIFeaturesSettingsCard()

            SettingsGroupCard(title: "Account & data") {
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
        .tideCovered(showPaywall)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
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

    // MARK: - Subscription Card

    private var subscriptionCard: some View {
        SettingsGroupCard(title: "Subscription") {
            SettingsInfoRow(
                label: "Plan",
                value: subscriptionStatusText,
                icon: "crown.fill",
                iconTint: services.subscriptions.isPro ? mood.accent : Tide.text2,
                valueColor: services.subscriptions.isPro ? mood.accent : Tide.text2
            )

            if !services.subscriptions.isPro {
                Button {
                    showPaywall = true
                } label: {
                    SettingsActionRow(icon: "sparkles", title: "Subscribe to Pro", tint: mood.accent)
                }
                .buttonStyle(.tideSettingsRow)
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                SettingsActionRow(icon: "arrow.clockwise", title: "Restore Purchases", tint: Tide.text)
            }
            .buttonStyle(.tideSettingsRow)
            .disabled(isRestoring)
        }
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

    private var notificationsSubtitle: String {
        // Mirrors IntensityOption titles in NotificationSettingsView (1…4).
        switch settings?.notificationIntensity {
        case 1: "Gentle Coach"
        case 2: "Firm Coach"
        case 3: "Drill Sergeant"
        case 4: "Savage Mode"
        default: "Default"
        }
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

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Subscription

    private var subscriptionStatusText: String {
        switch services.subscriptions.state {
        case .free:
            "Free"
        case .trial:
            "Pro · Trial"
        case .active:
            "Pro"
        case .gracePeriod:
            "Pro · Billing issue"
        case .expired,
             .churned:
            "Expired"
        }
    }

    @MainActor
    private func restorePurchases() async {
        guard !isRestoring else {
            return
        }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }

        do {
            try await services.subscriptions.restorePurchases()
        } catch {
            restoreError = error.localizedDescription
        }
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

    private var whoopStatusText: String {
        switch services.whoop.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .error: "Error"
        case .disconnected: "Not Connected"
        }
    }

    private var whoopStatusColor: Color {
        if case .connected = services.whoop.connectionState {
            return Tide.settingsOK
        }
        if case .error = services.whoop.connectionState {
            return Tide.danger
        }
        return Tide.text3
    }

    private var dietProfileStatusText: String {
        let descriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate { $0.isActive == true }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0 ? "Configured" : "Not Set Up"
    }

    private var dietProfileStatusColor: Color {
        let descriptor = FetchDescriptor<DietaryProfile>(
            predicate: #Predicate { $0.isActive == true }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        return count > 0 ? Tide.settingsOK : Tide.text3
    }

    private var healthKitStatusText: String {
        healthKitAuthorized ? "Authorized" : "Not Authorized"
    }

    private var healthKitStatusColor: Color {
        healthKitAuthorized ? Tide.settingsOK : Tide.text3
    }

    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedWhenInUse,
             .authorizedAlways: "Authorized"
        case .denied,
             .restricted: "Denied"
        case .notDetermined: "Not Set Up"
        @unknown default: "Not Set Up"
        }
    }

    private var locationStatusColor: Color {
        switch locationStatus {
        case .authorizedWhenInUse,
             .authorizedAlways: Tide.settingsOK
        case .denied,
             .restricted: Tide.danger
        default: Tide.text3
        }
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

// MARK: - ScheduleSettingsDetailView

struct ScheduleSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var wakeTime = Date()
    @State
    private var bedtime = Date()
    @State
    private var leisureTime = Date()

    var body: some View {
        TideSettingsPage {
            // Sleep-window summary (computed from bedtime → wake).
            sleepWindowCard

            SettingsFormCard(
                title: "Daily rhythm",
                footnote: "Leisure is when your evening wind-down starts. Tempo uses these to time meals, study, and recovery prompts."
            ) {
                SettingsControlRow(label: "Wake Time", icon: "sunrise.fill") {
                    DatePicker("Wake Time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: wakeTime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.wakeTimeMinutes = (comps.hour ?? 6) * 60 + (comps.minute ?? 0)
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: "Bedtime Target", icon: "moon.fill") {
                    DatePicker("Bedtime Target", selection: $bedtime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: bedtime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.bedtimeTargetMinutes = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                    save()
                }

                SettingsRowDivider()

                // Leisure is a TIME-OF-DAY (when wind-down starts), validated
                // 0..<1440 alongside wake/bedtime — not a duration.
                SettingsControlRow(label: "Leisure Time", icon: "hourglass") {
                    DatePicker("Leisure Time", selection: $leisureTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .onChange(of: leisureTime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.leisureTimeMinutes = (comps.hour ?? 19) * 60 + (comps.minute ?? 30)
                    save()
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSettings() }
    }

    /// Big computed sleep-window length (bedtime → wake), surfaced as data
    /// the screen didn't show before.
    private var sleepWindowCard: some View {
        TideSettingsHero {
            Text("Planned sleep window").tideLabel()
            if let span = sleepWindow {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    TideNumber("\(span.hours)", unit: "h", size: Tide.numeralL, relativeTo: .largeTitle)
                    if span.minutes > 0 {
                        TideNumber("\(span.minutes)", unit: "m", size: Tide.numeralL, relativeTo: .largeTitle)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(sleepWindowText) planned sleep window")
            } else {
                TideNumber("—", size: Tide.numeralL, relativeTo: .largeTitle)
            }
            if let settings {
                TideDayBar(start: settings.bedtimeTargetMinutes, end: settings.wakeTimeMinutes)
                    .padding(.top, Tide.s2)
            }
        }
    }

    /// Minutes from bedtime to wake, wrapping past midnight.
    private var sleepWindow: (hours: Int, minutes: Int)? {
        guard let s = settings else {
            return nil
        }
        var span = s.wakeTimeMinutes - s.bedtimeTargetMinutes
        if span <= 0 {
            span += 24 * 60
        }
        return (span / 60, span % 60)
    }

    private var sleepWindowText: String {
        guard let span = sleepWindow else {
            return "—"
        }
        return span.minutes == 0 ? "\(span.hours)h" : "\(span.hours)h \(span.minutes)m"
    }

    private func loadSettings() {
        guard let s = settings else {
            return
        }
        wakeTime = dateFromMinutes(s.wakeTimeMinutes)
        bedtime = dateFromMinutes(s.bedtimeTargetMinutes)
        leisureTime = dateFromMinutes(s.leisureTimeMinutes)
    }

    private func save() {
        try? modelContext.save()
    }

    private func dateFromMinutes(_ totalMinutes: Int) -> Date {
        var comps = DateComponents()
        comps.hour = totalMinutes / 60
        comps.minute = totalMinutes % 60
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - FocusTimerSettingsDetailView

struct FocusTimerSettingsDetailView: View {
    @Environment(\.tideMood)
    private var mood

    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var pomodoroDuration = 25
    @State
    private var breakDuration = 5
    @State
    private var longBreakDuration = 15

    var body: some View {
        TideSettingsPage {
            cyclePreviewCard

            SettingsFormCard(
                title: "Durations",
                footnote: "A focus block runs, then a short break; after a few blocks you earn a long break."
            ) {
                SettingsControlRow(label: "Focus block", icon: "timer") {
                    Stepper("\(pomodoroDuration) min", value: $pomodoroDuration, in: 10 ... 60, step: 5)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: pomodoroDuration) { _, newValue in
                    settings?.pomodoroDuration = newValue
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: "Short break", icon: "cup.and.saucer.fill") {
                    Stepper("\(breakDuration) min", value: $breakDuration, in: 3 ... 15)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: breakDuration) { _, newValue in
                    settings?.breakDuration = newValue
                    save()
                }

                SettingsRowDivider()

                SettingsControlRow(label: "Long break", icon: "cup.and.saucer") {
                    Stepper("\(longBreakDuration) min", value: $longBreakDuration, in: 10 ... 30, step: 5)
                        .font(Tide.bodyStrong)
                        .monospacedDigit()
                        .foregroundStyle(Tide.text2)
                        .fixedSize()
                }
                .onChange(of: longBreakDuration) { _, newValue in
                    settings?.longBreakDuration = newValue
                    save()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: pomodoroDuration)
        .sensoryFeedback(.selection, trigger: breakDuration)
        .sensoryFeedback(.selection, trigger: longBreakDuration)
        .navigationTitle("Focus Timer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pomodoroDuration = settings?.pomodoroDuration ?? 25
            breakDuration = settings?.breakDuration ?? 5
            longBreakDuration = settings?.longBreakDuration ?? 15
        }
    }

    /// Visual cycle preview — surfaces what the durations actually produce.
    private var cyclePreviewCard: some View {
        TideSettingsHero {
            Text("Focus / break / long break").tideLabel()

            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                TideNumber("\(pomodoroDuration)", size: Tide.numeralL, relativeTo: .largeTitle)
                Text("/").font(Tide.title2).foregroundStyle(Tide.text3)
                TideNumber("\(breakDuration)", size: Tide.numeralL, relativeTo: .largeTitle, color: Tide.water)
                Text("/").font(Tide.title2).foregroundStyle(Tide.text3)
                TideNumber(
                    "\(longBreakDuration)", unit: "min", size: Tide.numeralL, relativeTo: .largeTitle,
                    color: Tide.streak
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Focus \(pomodoroDuration), break \(breakDuration), long break \(longBreakDuration) minutes")

            HStack(spacing: Tide.s1) {
                ForEach(0 ..< 4) { i in
                    Capsule()
                        .fill(mood.accent)
                        .frame(height: Tide.s2)
                    if i < 3 {
                        Capsule()
                            .fill(Tide.water.opacity(0.5))
                            .frame(width: Tide.s3, height: Tide.s2)
                    }
                }
                Capsule()
                    .fill(Tide.streak)
                    .frame(width: Tide.s6, height: Tide.s2)
            }
            .padding(.top, Tide.s2)
            .accessibilityHidden(true)
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - ModesSettingsDetailView

struct ModesSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.tideMood)
    private var mood
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    @State
    private var weekendMode = false
    @State
    private var examMode = false
    @State
    private var examEndDate = Date()

    /// Which modes are bending the plan right now, as the toggles show them.
    private var modesHero: some View {
        let active = [weekendMode ? "Weekend" : nil, examMode ? "Exam" : nil].compactMap(\.self)
        return TideSettingsHero {
            Text("Active now").tideLabel()
            Text(active.isEmpty ? "Standard day" : active.joined(separator: " \u{00B7} "))
                .font(Tide.title2)
                .foregroundStyle(active.isEmpty ? Tide.text : mood.accent)
            Text(active.isEmpty ? "No mode is changing your plan." : "Your plan is adjusted while this is on.")
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
        }
        .animation(Tide.snap, value: active)
        .accessibilityElement(children: .combine)
    }

    var body: some View {
        TideSettingsPage {
            modesHero

            SettingsFormCard(
                title: "Weekend",
                footnote: "Relaxes your schedule and eases accountability on Saturdays and Sundays."
            ) {
                SettingsControlRow(label: "Weekend Mode", icon: "party.popper.fill") {
                    Toggle("Weekend Mode", isOn: $weekendMode)
                        .labelsHidden()
                }
                .onChange(of: weekendMode) { _, newValue in
                    settings?.weekendMode = newValue
                    save()
                }
            }

            SettingsFormCard(
                title: "Exam",
                footnote: examMode
                    ? "Study is prioritised and training load reduced until your exam end date."
                    : "Prioritise study and reduce training load during exam periods."
            ) {
                SettingsControlRow(label: "Exam Mode", icon: "pencil.and.list.clipboard") {
                    Toggle("Exam Mode", isOn: $examMode)
                        .labelsHidden()
                }
                .onChange(of: examMode) { _, newValue in
                    settings?.examMode = newValue
                    if newValue, settings?.examModeEndDate == nil {
                        settings?.examModeEndDate = examEndDate
                    }
                    save()
                }

                if examMode {
                    SettingsRowDivider()
                    SettingsControlRow(label: "Ends", icon: "calendar.badge.clock") {
                        DatePicker("Ends", selection: $examEndDate, in: Date()..., displayedComponents: .date)
                            .labelsHidden()
                    }
                    .onChange(of: examEndDate) { _, newValue in
                        settings?.examModeEndDate = newValue
                        save()
                    }
                }
            }
        }
        .animation(Tide.snap, value: examMode)
        .sensoryFeedback(.selection, trigger: weekendMode)
        .sensoryFeedback(.selection, trigger: examMode)
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            weekendMode = settings?.weekendMode ?? false
            examMode = settings?.examMode ?? false
            examEndDate = settings?.examModeEndDate ?? Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()
        }
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - SubscriptionDetailView

/// Surfaces the real subscription state (plan, renewal/expiry, trial
/// countdown) that the root only showed as a single word.
struct SubscriptionDetailView: View {
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var isRestoring = false
    @State
    private var restoreError: String?

    private var state: SubscriptionState {
        services.subscriptions.state
    }

    var body: some View {
        TideSettingsPage {
            planCard

            if !state.isPro {
                Button { showPaywall = true } label: {
                    Label("Subscribe to Pro", systemImage: "sparkles")
                }
                .buttonStyle(.tidePrimary)
            }

            SettingsFormCard(title: "Details") {
                SettingsInfoRow(
                    label: "Status",
                    value: planTitle,
                    icon: "checkmark.seal.fill",
                    iconTint: state.isPro ? mood.accent : Tide.text3,
                    valueColor: state.isPro ? mood.accent : Tide.text3
                )
                if let renewal = renewalLine {
                    SettingsRowDivider()
                    SettingsInfoRow(
                        label: renewal.label,
                        value: renewal.value,
                        icon: "calendar"
                    )
                }
                if let plan = productLine {
                    SettingsRowDivider()
                    SettingsInfoRow(label: "Plan", value: plan, icon: "tag.fill")
                }
            }

            SettingsFormCard(footnote: restoreError, footnoteColor: Tide.danger) {
                Button { Task { await restore() } } label: {
                    SettingsActionRow(icon: "arrow.clockwise", title: "Restore Purchases", tint: Tide.text)
                }
                .buttonStyle(.tideSettingsRow)
                .disabled(isRestoring)
            }
        }
        .tideCovered(showPaywall)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var planCard: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(spacing: Tide.s4))
        return TideSettingsHero {
            layout {
                Image(systemName: state.isPro ? "crown.fill" : "crown")
                    .font(Tide.title)
                    .foregroundStyle(state.isPro ? Tide.streak : Tide.text3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(planTitle)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(planSubtitle)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            if let clock = countdown {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    TideNumber(
                        "\(clock.days)", unit: clock.unit,
                        size: Tide.numeralL, relativeTo: .largeTitle, color: clock.tint
                    )
                    if let progress = clock.progress {
                        TideLevelBar(progress: progress, color: clock.tint, height: Tide.bar)
                            .background(Tide.fill, in: .capsule)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, Tide.s2)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Whole days until the date that matters for this state, with what the
    /// number counts. The trial bar fills from the trial's start to its end.
    private var countdown: (days: Int, unit: String, tint: Color, progress: Double?)? {
        func days(until date: Date) -> Int {
            max(0, Int((date.timeIntervalSinceNow / 86400).rounded(.up)))
        }
        switch state {
        case let .trial(startDate, endDate):
            let left = days(until: endDate)
            let span = max(endDate.timeIntervalSince(startDate), 1)
            let elapsed = min(max(Date().timeIntervalSince(startDate), 0), span)
            return (left, left == 1 ? "day of trial left" : "days of trial left", mood.accent, elapsed / span)
        case let .active(_, expirationDate, isAutoRenewing):
            let left = days(until: expirationDate)
            let unit = isAutoRenewing
                ? (left == 1 ? "day to renewal" : "days to renewal")
                : (left == 1 ? "day until it ends" : "days until it ends")
            return (left, unit, mood.accent, nil)
        case let .gracePeriod(_, graceEndDate):
            let left = days(until: graceEndDate)
            return (left, left == 1 ? "day of grace left" : "days of grace left", Tide.danger, nil)
        case .free,
             .expired,
             .churned:
            return nil
        }
    }

    private var planTitle: String {
        switch state {
        case .free: "Free"
        case .trial: "Pro · Trial"
        case .active: "Pro"
        case .gracePeriod: "Pro · Billing issue"
        case .expired,
             .churned: "Expired"
        }
    }

    private var planSubtitle: String {
        if case .gracePeriod = state {
            return "There is a billing problem. Pro stays on until the grace period ends."
        }
        return state.isPro ? "You have full access to Tempo Pro." : "Upgrade to unlock everything Tempo offers."
    }

    private var renewalLine: (label: String, value: String)? {
        switch state {
        case let .trial(_, endDate): ("Trial ends", Self.dateString(endDate))
        case let .active(_, expirationDate, isAutoRenewing):
            (isAutoRenewing ? "Renews" : "Expires", Self.dateString(expirationDate))
        case let .gracePeriod(_, graceEndDate): ("Grace ends", Self.dateString(graceEndDate))
        case let .expired(_, expiredAt): ("Expired", Self.dateString(expiredAt))
        case let .churned(_, expiredAt): ("Expired", Self.dateString(expiredAt))
        case .free: nil
        }
    }

    private var productLine: String? {
        switch state {
        case let .active(productId, _, _): SubscriptionProduct(rawValue: productId)?.displayName
        case let .gracePeriod(productId, _): SubscriptionProduct(rawValue: productId)?.displayName
        default: nil
        }
    }

    private static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    @MainActor
    private func restore() async {
        guard !isRestoring else {
            return
        }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }
        do { try await services.subscriptions.restorePurchases() }
        catch { restoreError = error.localizedDescription }
    }
}

// MARK: - AccountDetailView

/// Surfaces account identity (sign-in method, user ID, member-since) and
/// houses the Apple-required in-app account deletion.
struct AccountDetailView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dismiss)
    private var dismiss
    @Query
    private var allProfiles: [UserProfile]

    @State
    private var showDeleteConfirm = false
    @State
    private var isDeleting = false
    @State
    private var deleteError: String?

    private var profile: UserProfile? {
        allProfiles.first
    }

    var body: some View {
        TideSettingsPage {
            identityHero

            if !isSignedIn {
                SettingsSignInCard()
            }

            SettingsFormCard(title: "Identity") {
                SettingsInfoRow(
                    label: "Sign-in",
                    value: isSignedIn ? "Apple" : "Not signed in",
                    icon: "applelogo",
                    iconTint: Tide.text
                )
                SettingsRowDivider()
                SettingsInfoRow(label: "Member since", value: memberSince, icon: "calendar")
                if let id = userIDShort {
                    SettingsRowDivider()
                    SettingsInfoRow(label: "User ID", value: id, icon: "number")
                }
            }

            // The destructive group sits alone at the bottom, apart from the rest.
            TideSettingsSection(
                title: "Danger zone",
                footnote: "Deleting your account permanently removes all data — XP, achievements, streaks, and workout history. You'll be removed from all leaderboards and active challenges. This cannot be undone.",
                isDanger: true
            ) {
                Button { showDeleteConfirm = true } label: {
                    SettingsActionRow(icon: "trash", title: "Delete Account", tint: Tide.danger)
                }
                .buttonStyle(.tideSettingsRow)
                .disabled(isDeleting)
            }
            .padding(.top, Tide.s4)
        }
        .sensoryFeedback(.warning, trigger: showDeleteConfirm) { _, isShown in isShown }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) { Task { await performDeletion() } }
        } message: {
            Text("This permanently deletes all your data. This cannot be undone.")
        }
        .alert("Could not delete account", isPresented: Binding(
            get: { deleteError != nil }, set: {
                if !$0 {
                    deleteError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Who this is and whether the data is backed up, before the details.
    private var identityHero: some View {
        let name = profile?.displayName.isEmpty == false ? (profile?.displayName ?? "Athlete") : "Athlete"
        return TideSettingsHero {
            HStack(spacing: Tide.s4) {
                TideSettingsAvatar(initial: String(name.prefix(1)).uppercased())
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(name)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Tide.s2) {
                        Circle()
                            .fill(isSignedIn ? mood.accent : Tide.text3)
                            .frame(width: Tide.s2, height: Tide.s2)
                            .shadow(color: isSignedIn ? mood.accent : .clear, radius: Tide.s1)
                        Text(isSignedIn ? "Backed up to your account" : "Only on this phone")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var memberSince: String {
        guard let created = profile?.createdAt else {
            return "—"
        }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: created)
    }

    private var isSignedIn: Bool {
        if case .authenticated = services.authService.authState {
            return true
        }
        return false
    }

    private var userIDShort: String? {
        if case let .authenticated(userID) = services.authService.authState {
            return String(userID.prefix(8)) + "…"
        }
        return nil
    }

    @MainActor
    private func performDeletion() async {
        guard !isDeleting else {
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await services.authService.deleteAccount()
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
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
