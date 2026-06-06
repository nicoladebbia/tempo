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
    @Query
    private var allSettings: [UserSettings]
    @Query
    private var allProfiles: [UserProfile]

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
    // Refreshed on appear — location auth can change in iOS Settings while away.
    @State private var locationStatus: CLAuthorizationStatus = CLLocationManager().authorizationStatus

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                profileHeaderCard

                SettingsGroupCard(title: "You & your day") {
                    NavigationLink {
                        ScheduleSettingsDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "clock.fill", iconTint: .tempoAmber,
                            title: "Schedule", subtitle: scheduleSubtitle
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        TrainingSettingsDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "dumbbell.fill", iconTint: .tempoSignal,
                            title: "Training", subtitle: trainingSubtitle
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FocusTimerSettingsDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "timer", iconTint: .tempoElectric,
                            title: "Focus Timer", subtitle: focusSubtitle
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        ModesSettingsDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "bolt.fill", iconTint: .tempoViolet,
                            title: "Modes", subtitle: modesSubtitle
                        )
                    }
                    .buttonStyle(.plain)
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
                    .buttonStyle(.plain)

                    NavigationLink {
                        DietaryProfileSetupView()
                    } label: {
                        SettingsStatusRow(
                            icon: "fork.knife", title: "Diet Profile",
                            status: dietProfileStatusText, statusColor: dietProfileStatusColor
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        openSystemSettings()
                    } label: {
                        SettingsStatusRow(
                            icon: "heart.text.square", title: "HealthKit",
                            status: healthKitStatusText, statusColor: healthKitStatusColor,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        openSystemSettings()
                    } label: {
                        SettingsStatusRow(
                            icon: "cloud.sun.fill", title: "Weather (Location)",
                            status: locationStatusText, statusColor: locationStatusColor,
                            showsChevron: false
                        )
                    }
                    .buttonStyle(.plain)
                }
                .onAppear { locationStatus = CLLocationManager().authorizationStatus }

                SettingsGroupCard(title: "Notifications") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        SettingsNavRow(
                            icon: "bell.fill", iconTint: .tempoSignal,
                            title: "Notifications", subtitle: notificationsSubtitle
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroupCard(title: "Appearance") {
                    NavigationLink {
                        AppearanceSettingsDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "paintbrush.fill", iconTint: .tempoAmber,
                            title: "Accent Color", subtitle: accentSubtitle
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroupCard(title: "Your data") {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        SettingsNavRow(
                            icon: "square.and.arrow.up", iconTint: .tempoElectric,
                            title: "Export My Data"
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroupCard(title: "Subscription") {
                    NavigationLink {
                        SubscriptionDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "crown.fill", iconTint: .tempoAmber,
                            title: "Subscription", subtitle: subscriptionStatusText
                        )
                    }
                    .buttonStyle(.plain)
                }

                SettingsGroupCard(title: "Account & about") {
                    NavigationLink {
                        AccountDetailView()
                    } label: {
                        SettingsNavRow(
                            icon: "person.crop.circle", iconTint: .tempoElectric,
                            title: "Account", subtitle: "Sign-in, member since, delete"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsActionRow(
                        icon: "number", title: "Version", tint: .tempoTextPrimary,
                        trailingText: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                    )

                    if let supportURL = URL(string: "https://tempo.app/support") {
                        Link(destination: supportURL) {
                            SettingsActionRow(
                                icon: "questionmark.circle", title: "Support",
                                tint: .tempoTextPrimary
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.tempoSubheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoSignal)
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
                set: { if !$0 { deleteAccountError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deleteAccountError = nil }
        } message: {
            Text(deleteAccountError ?? "")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    // MARK: - Profile Header Card

    @ViewBuilder
    private var profileHeaderCard: some View {
        NavigationLink {
            ProfileSettingsDetailView()
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Circle()
                    .fill(Color.tempoSurfaceElevated)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(profileInitial)
                            .font(.tempoTitle2)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }

                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(profile?.displayName ?? "Athlete")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)

                    Text("@\(profile?.username ?? "—") · \(profile?.identityLabel ?? "Athlete")")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)

                    Text(profileStatsLine)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                Spacer(minLength: TempoSpacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscription Card

    @ViewBuilder
    private var subscriptionCard: some View {
        SettingsGroupCard(title: "Subscription") {
            HStack(spacing: TempoSpacing.md) {
                SettingsIconTile(systemName: "crown.fill", tint: .tempoAmber)
                Text("Plan")
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer(minLength: TempoSpacing.sm)
                Text(subscriptionStatusText)
                    .font(.tempoDataSmall)
                    .foregroundStyle(
                        services.subscriptions.isPro ? Color.tempoSuccess : Color.tempoTextTertiary
                    )
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.vertical, TempoSpacing.md)
            .frame(minHeight: 44)

            if !services.subscriptions.isPro {
                Button {
                    showPaywall = true
                } label: {
                    SettingsActionRow(icon: "sparkles", title: "Subscribe to Pro", tint: .tempoSignal)
                }
                .buttonStyle(.plain)
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                SettingsActionRow(icon: "arrow.clockwise", title: "Restore Purchases", tint: .tempoTextPrimary)
            }
            .buttonStyle(.plain)
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
        guard let s = settings else { return "Not set up" }
        // leisureTimeMinutes is a TIME-OF-DAY (validated 0..<1440 alongside
        // wake/bedtime as invalidTimeOfDay), NOT a duration — render as a clock.
        return "Wake \(timeString(fromMinutes: s.wakeTimeMinutes)) · Bed \(timeString(fromMinutes: s.bedtimeTargetMinutes)) · Leisure \(timeString(fromMinutes: s.leisureTimeMinutes))"
    }

    private var trainingSubtitle: String {
        guard let s = settings else { return "Not set up" }
        let days = s.footballDaysRaw.nonzeroBitCount
        let football = days == 0 ? "no football" : "\(days) football day\(days == 1 ? "" : "s")"
        return "\(s.trainingSplit.displayName) · \(football) · \(s.weightUnitRaw)"
    }

    private var focusSubtitle: String {
        guard let s = settings else { return "Not set up" }
        return "\(s.pomodoroDuration) / \(s.breakDuration) / \(s.longBreakDuration) min"
    }

    private var modesSubtitle: String {
        guard let s = settings else { return "None active" }
        var active: [String] = []
        if s.weekendMode { active.append("Weekend") }
        if s.examMode { active.append("Exam") }
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

    private var accentSubtitle: String {
        AccentColorOption(rawValue: accentColorChoice)?.displayName ?? "Signal Red"
    }

    private var profileStatsLine: String {
        let level = profile?.currentLevel ?? 1
        let xp = profile?.totalXP ?? 0
        let xpStr = xp >= 1000 ? String(format: "%.1fk XP", Double(xp) / 1000) : "\(xp) XP"
        return "Lvl \(level) · \(xpStr)"
    }

    @AppStorage("accentColorChoice")
    private var accentColorChoice: String = AccentColorOption.signalRed.rawValue

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
        guard !isRestoring else { return }
        isRestoring = true
        restoreError = nil
        defer { isRestoring = false }

        do {
            try await services.subscriptions.restorePurchases()
        } catch {
            restoreError = error.localizedDescription
        }
    }

    // MARK: - Account deletion action

    @MainActor
    private func performAccountDeletion() async {
        guard !isDeletingAccount else { return }
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
            return .tempoSuccess
        }
        if case .error = services.whoop.connectionState {
            return .tempoError
        }
        return .tempoTextTertiary
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
        return count > 0 ? .tempoSuccess : .tempoTextTertiary
    }

    private var healthKitStatusText: String {
        healthKitAuthorized ? "Authorized" : "Not Authorized"
    }

    private var healthKitStatusColor: Color {
        healthKitAuthorized ? .tempoSuccess : .tempoTextTertiary
    }

    private var locationStatusText: String {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: "Authorized"
        case .denied, .restricted: "Denied"
        case .notDetermined: "Not Set Up"
        @unknown default: "Not Set Up"
        }
    }

    private var locationStatusColor: Color {
        switch locationStatus {
        case .authorizedWhenInUse, .authorizedAlways: .tempoSuccess
        case .denied, .restricted: .tempoError
        default: .tempoTextTertiary
        }
    }
}

// MARK: - ProfileSettingsDetailView

struct ProfileSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
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
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                heroCard
                statsCard
                trainingSummaryCard
                identityCard
                biometricsCard
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroCard: some View {
        VStack(spacing: TempoSpacing.md) {
            Circle()
                .fill(Color.tempoSurfaceElevated)
                .frame(width: 88, height: 88)
                .overlay {
                    Text(profileInitial)
                        .font(.tempoLargeTitle)
                        .foregroundStyle(Color.tempoTextPrimary)
                }

            VStack(spacing: TempoSpacing.xxs) {
                Text(displayName.isEmpty ? "Athlete" : displayName)
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("@\(username.isEmpty ? "—" : username)")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextSecondary)

                // Identity as a subtle secondary tag — toned down so it reads
                // below the username, not louder than it.
                Text(identityLabel.uppercased())
                    .font(.tempoCaption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .padding(.top, TempoSpacing.xxs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xl)
        .padding(.horizontal, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var profileInitial: String {
        let name = displayName.isEmpty ? (profile?.displayName ?? "A") : displayName
        return String(name.prefix(1)).uppercased()
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsCard: some View {
        HStack(spacing: 0) {
            statCell(value: "\(profile?.currentLevel ?? 1)", label: "Level")
            statDivider
            statCell(value: streakDisplay, label: "Streak")
            statDivider
            statCell(value: xpDisplay, label: "Total XP")
            statDivider
            statCell(value: memberSince, label: "Member")
        }
        .padding(.vertical, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var streakDisplay: String {
        let current = overallStreak?.currentCount ?? 0
        return current == 0 ? "—" : "\(current)d"
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(value)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TempoSpacing.xxs)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Color.tempoDivider)
            .frame(width: 1, height: 28)
    }

    private var xpDisplay: String {
        let xp = profile?.totalXP ?? 0
        return xp >= 1000 ? String(format: "%.1fk", Double(xp) / 1000) : "\(xp)"
    }

    private var memberSince: String {
        guard let created = profile?.createdAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM ''yy"
        return f.string(from: created)
    }

    // MARK: - Training summary (read-only, surfaced from UserSettings)

    @ViewBuilder
    private var trainingSummaryCard: some View {
        SettingsFormCard(title: "Training") {
            SettingsInfoRow(
                label: "Split", value: settings?.trainingSplit.displayName ?? "—",
                icon: "dumbbell.fill", iconTint: .tempoSignal
            )
            SettingsRowDivider()
            SettingsInfoRow(
                label: "Football days", value: footballSummary,
                icon: "sportscourt.fill", iconTint: .tempoAmber
            )
            SettingsRowDivider()
            SettingsInfoRow(
                label: "Weight unit", value: (settings?.weightUnitRaw ?? "kg").uppercased(),
                icon: "scalemass.fill", iconTint: .tempoElectric
            )
            if let longest = overallStreak?.longestCount, longest > 0 {
                SettingsRowDivider()
                SettingsInfoRow(
                    label: "Longest streak", value: "\(longest) days",
                    icon: "flame.fill", iconTint: .tempoSignal
                )
            }
        }
    }

    private var footballSummary: String {
        let days = settings?.footballDaysRaw.nonzeroBitCount ?? 0
        return days == 0 ? "None" : "\(days)/week"
    }

    // MARK: - Identity (editable)

    @ViewBuilder
    private var identityCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("IDENTITY")
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.leading, TempoSpacing.sm)

            VStack(spacing: 0) {
                labeledField(label: "Display Name", text: $displayName, placeholder: "Your name") { newValue in
                    profile?.displayName = newValue
                    touch()
                }
                rowDivider
                labeledField(
                    label: "Username", text: $username, placeholder: "username",
                    prefix: "@", autocapitalize: false
                ) { newValue in
                    profile?.username = newValue
                    touch()
                }
                rowDivider
                identityLabelRow
            }
            .padding(.vertical, TempoSpacing.xs)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        }
    }

    private var identityLabelRow: some View {
        HStack {
            Text("Identity")
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Picker("Identity", selection: $identityLabel) {
                ForEach(identityOptions, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
            .labelsHidden()
            .tint(Color.tempoTextSecondary)
            .onChange(of: identityLabel) { _, newValue in
                profile?.identityLabel = newValue
                touch()
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
    }

    // MARK: - Biometrics (editable)

    // Biometrics are READ-ONLY here. They're owned by the active
    // DietaryProfile (which has the "Refresh from Health" flow); editing
    // them lives there, not on the profile screen.
    @ViewBuilder
    private var biometricsCard: some View {
        SettingsFormCard(
            title: "Biometrics",
            footnote: "Biometrics come from your Diet Profile. Update them there with “Refresh from Health.”"
        ) {
            if let d = dietProfile {
                SettingsInfoRow(label: "Weight", value: String(format: "%.1f kg", d.currentWeightKg),
                                icon: "scalemass", iconTint: .tempoElectric)
                SettingsRowDivider()
                SettingsInfoRow(label: "Height", value: String(format: "%.0f cm", d.heightCm),
                                icon: "ruler", iconTint: .tempoAmber)
                SettingsRowDivider()
                SettingsInfoRow(label: "Age", value: "\(d.age)", icon: "calendar", iconTint: .tempoViolet)
                SettingsRowDivider()
                SettingsInfoRow(label: "Est. BMR", value: "\(Int(bmr(from: d))) kcal",
                                icon: "flame", iconTint: .tempoSignal)
            } else {
                NavigationLink {
                    DietaryProfileSetupView()
                } label: {
                    SettingsNavRow(
                        icon: "heart.text.square", iconTint: .tempoSignal,
                        title: "Set up biometrics", subtitle: "In Diet Profile → Refresh from Health"
                    )
                }
                .buttonStyle(.plain)
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

    private var rowDivider: some View {
        Divider()
            .overlay(Color.tempoDivider)
            .padding(.leading, TempoSpacing.lg)
    }

    private func labeledField(
        label: String,
        text: Binding<String>,
        placeholder: String,
        prefix: String? = nil,
        autocapitalize: Bool = true,
        onCommit: @escaping (String) -> Void
    ) -> some View {
        HStack {
            Text(label)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            HStack(spacing: 0) {
                if let prefix {
                    Text(prefix)
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                TextField(placeholder, text: text)
                    .font(.tempoSubheadline)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(autocapitalize ? .words : .never)
                    .autocorrectionDisabled(!autocapitalize)
                    .onChange(of: text.wrappedValue) { _, newValue in onCommit(newValue) }
            }
        }
        .padding(.horizontal, TempoSpacing.lg)
        .padding(.vertical, TempoSpacing.md)
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
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                // Sleep-window summary (computed from bedtime → wake).
                sleepWindowCard

                SettingsFormCard(
                    title: "Daily rhythm",
                    footnote: "Leisure is when your evening wind-down starts. Tempo uses these to time meals, study, and recovery prompts."
                ) {
                    SettingsControlRow(label: "Wake Time", icon: "sunrise.fill", iconTint: .tempoAmber) {
                        DatePicker("", selection: $wakeTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .onChange(of: wakeTime) { _, newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        settings?.wakeTimeMinutes = (comps.hour ?? 6) * 60 + (comps.minute ?? 0)
                        save()
                    }

                    SettingsRowDivider()

                    SettingsControlRow(label: "Bedtime Target", icon: "moon.fill", iconTint: .tempoViolet) {
                        DatePicker("", selection: $bedtime, displayedComponents: .hourAndMinute)
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
                    SettingsControlRow(label: "Leisure Time", icon: "hourglass", iconTint: .tempoElectric) {
                        DatePicker("", selection: $leisureTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                    .onChange(of: leisureTime) { _, newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        settings?.leisureTimeMinutes = (comps.hour ?? 19) * 60 + (comps.minute ?? 30)
                        save()
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSettings() }
    }

    /// Big computed sleep-window length (bedtime → wake), surfaced as data
    /// the screen didn't show before.
    @ViewBuilder
    private var sleepWindowCard: some View {
        VStack(spacing: TempoSpacing.xs) {
            Text(sleepWindowText)
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("planned sleep window")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xl)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private var sleepWindowText: String {
        guard let s = settings else { return "—" }
        // Minutes from bedtime to wake, wrapping past midnight.
        var span = s.wakeTimeMinutes - s.bedtimeTargetMinutes
        if span <= 0 { span += 24 * 60 }
        let h = span / 60
        let m = span % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
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

// MARK: - TrainingSettingsDetailView

// Note on the local save() in this view: after every successful save we post
// `Notification.Name.tempoTrainingSettingsChanged` so NutritionTabViewModel
// can regenerate its WeeklyMealPlan against the new trainingSplit /
// footballDays. Without this, the Nutrition Plan tab kept showing the
// previous schedule (e.g. Wednesday strength) until the user manually
// re-generated.
struct TrainingSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]

    private var settings: UserSettings? {
        allSettings.first
    }

    /// Mon-first to match the ActiveDays bitmask (index 0 = Monday = 1<<0).
    private let footballDayLabels = ["M", "T", "W", "T", "F", "S", "S"]

    @State
    private var trainingSplit: TrainingSplit = .pushPullLegs
    @State
    private var autoDeload = true
    @State
    private var deloadWeeks = 5

    private var footballCount: Int {
        settings?.footballDaysRaw.nonzeroBitCount ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                // Summary hero — what this config means at a glance.
                VStack(spacing: TempoSpacing.xs) {
                    Text(trainingSplit.displayName)
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(footballCount == 0
                        ? "No football days"
                        : "\(footballCount) football day\(footballCount == 1 ? "" : "s") / week")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.xl)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                SettingsFormCard(title: "Programme") {
                    // Whole-row Menu — fixes the round-1 bug where the bare
                    // .labelsHidden() menu Picker had a tiny dead tap target.
                    // (Segmented is unusable here: 5 long split names won't fit.)
                    Menu {
                        Picker("Split", selection: $trainingSplit) {
                            ForEach(TrainingSplit.allCases, id: \.self) { split in
                                Text(split.displayName).tag(split)
                            }
                        }
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            SettingsIconTile(systemName: "dumbbell.fill", tint: .tempoSignal)
                            Text("Split")
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer(minLength: TempoSpacing.sm)
                            Text(trainingSplit.displayName)
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoTextSecondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        .padding(.horizontal, TempoSpacing.lg)
                        .padding(.vertical, TempoSpacing.md)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .onChange(of: trainingSplit) { _, newValue in
                        settings?.trainingSplit = newValue
                        save()
                    }

                    SettingsRowDivider()

                    SettingsControlRow(label: "Weight Unit", icon: "scalemass.fill", iconTint: .tempoElectric) {
                        Picker("", selection: Binding(
                            get: { settings?.weightUnit ?? .kg },
                            set: { newValue in
                                settings?.weightUnit = newValue
                                save()
                            }
                        )) {
                            ForEach(WeightUnit.allCases, id: \.self) { unit in
                                Text(unit.rawValue.uppercased()).tag(unit)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 110)
                    }
                }

                // Football days — editable chips (Mon=1<<0 … Sun=1<<6).
                SettingsFormCard(
                    title: "Football days",
                    footnote: "Tempo plans recovery and meal timing around your match/training days."
                ) {
                    HStack(spacing: TempoSpacing.xs) {
                        ForEach(Array(footballDayLabels.enumerated()), id: \.offset) { index, dayLabel in
                            let bit = 1 << index
                            let isOn = ((settings?.footballDaysRaw ?? 0) & bit) != 0
                            Button {
                                guard let s = settings else { return }
                                s.footballDaysRaw ^= bit
                                save()
                                HapticManager.selection()
                            } label: {
                                Text(dayLabel)
                                    .font(.tempoCaption1)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(isOn ? Color.tempoSignal : Color.tempoBgSecondary)
                                    .foregroundStyle(isOn ? .white : Color.tempoTextSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(TempoSpacing.lg)
                }

                SettingsFormCard(
                    title: "Deload",
                    footnote: autoDeload
                        ? "Auto-deload lightens your programme every \(deloadWeeks) weeks to manage fatigue."
                        : "Auto-deload is off — you'll manage recovery weeks manually."
                ) {
                    SettingsControlRow(label: "Auto Deload", icon: "arrow.down.right.circle", iconTint: .tempoAmber) {
                        Toggle("", isOn: $autoDeload)
                            .labelsHidden()
                            .tint(Color.tempoAccent)
                    }
                    .onChange(of: autoDeload) { _, newValue in
                        settings?.autoDeload = newValue
                        save()
                    }

                    if autoDeload {
                        SettingsRowDivider()
                        SettingsControlRow(label: "Every", icon: "calendar", iconTint: .tempoViolet) {
                            Stepper("\(deloadWeeks) weeks", value: $deloadWeeks, in: 3 ... 8)
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .fixedSize()
                        }
                        .onChange(of: deloadWeeks) { _, newValue in
                            settings?.deloadFrequencyWeeks = newValue
                            save()
                        }
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Training")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            trainingSplit = settings?.trainingSplit ?? .pushPullLegs
            autoDeload = settings?.autoDeload ?? true
            deloadWeeks = settings?.deloadFrequencyWeeks ?? 5
        }
    }

    private func save() {
        try? modelContext.save()
        // Tell the Nutrition tab to regenerate its plan with the new
        // trainingSplit/footballDays. We intentionally post on EVERY save
        // (every chip toggle); the observer side debounces so a burst of
        // chip taps produces a single regen at the end.
        NotificationCenter.default.post(
            name: .tempoTrainingSettingsChanged,
            object: nil
        )
    }
}

// MARK: - FocusTimerSettingsDetailView

struct FocusTimerSettingsDetailView: View {
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
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                cyclePreviewCard

                SettingsFormCard(
                    title: "Durations",
                    footnote: "A focus block runs, then a short break; after a few blocks you earn a long break."
                ) {
                    SettingsControlRow(label: "Focus block", icon: "timer", iconTint: .tempoSignal) {
                        Stepper("\(pomodoroDuration) min", value: $pomodoroDuration, in: 10 ... 60, step: 5)
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize()
                    }
                    .onChange(of: pomodoroDuration) { _, newValue in
                        settings?.pomodoroDuration = newValue
                        save()
                    }

                    SettingsRowDivider()

                    SettingsControlRow(label: "Short break", icon: "cup.and.saucer.fill", iconTint: .tempoElectric) {
                        Stepper("\(breakDuration) min", value: $breakDuration, in: 3 ... 15)
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize()
                    }
                    .onChange(of: breakDuration) { _, newValue in
                        settings?.breakDuration = newValue
                        save()
                    }

                    SettingsRowDivider()

                    SettingsControlRow(label: "Long break", icon: "cup.and.saucer", iconTint: .tempoAmber) {
                        Stepper("\(longBreakDuration) min", value: $longBreakDuration, in: 10 ... 30, step: 5)
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .fixedSize()
                    }
                    .onChange(of: longBreakDuration) { _, newValue in
                        settings?.longBreakDuration = newValue
                        save()
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Focus Timer")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pomodoroDuration = settings?.pomodoroDuration ?? 25
            breakDuration = settings?.breakDuration ?? 5
            longBreakDuration = settings?.longBreakDuration ?? 15
        }
    }

    /// Visual cycle preview — surfaces what the durations actually produce.
    @ViewBuilder
    private var cyclePreviewCard: some View {
        VStack(spacing: TempoSpacing.md) {
            Text("\(pomodoroDuration) / \(breakDuration) / \(longBreakDuration)")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
            Text("focus / break / long break (min)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)

            HStack(spacing: TempoSpacing.xs) {
                ForEach(0 ..< 4) { i in
                    RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous)
                        .fill(Color.tempoSignal)
                        .frame(height: 8)
                    if i < 3 {
                        RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous)
                            .fill(Color.tempoElectric.opacity(TempoOpacity.o50))
                            .frame(width: 10, height: 8)
                    }
                }
                RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous)
                    .fill(Color.tempoAmber)
                    .frame(width: 24, height: 8)
            }
            .padding(.top, TempoSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, TempoSpacing.xl)
        .padding(.horizontal, TempoSpacing.lg)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    private func save() {
        try? modelContext.save()
    }
}

// MARK: - ModesSettingsDetailView

struct ModesSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
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

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                SettingsFormCard(
                    title: "Weekend",
                    footnote: "Relaxes your schedule and eases accountability on Saturdays and Sundays."
                ) {
                    SettingsControlRow(label: "Weekend Mode", icon: "party.popper.fill", iconTint: .tempoAmber) {
                        Toggle("", isOn: $weekendMode)
                            .labelsHidden()
                            .tint(Color.tempoAccent)
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
                    SettingsControlRow(label: "Exam Mode", icon: "pencil.and.list.clipboard", iconTint: .tempoViolet) {
                        Toggle("", isOn: $examMode)
                            .labelsHidden()
                            .tint(Color.tempoAccent)
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
                        SettingsControlRow(label: "Ends", icon: "calendar.badge.clock", iconTint: .tempoElectric) {
                            DatePicker("", selection: $examEndDate, in: Date()..., displayedComponents: .date)
                                .labelsHidden()
                        }
                        .onChange(of: examEndDate) { _, newValue in
                            settings?.examModeEndDate = newValue
                            save()
                        }
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
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
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                VStack(spacing: TempoSpacing.xs) {
                    Image(systemName: state.isPro ? "crown.fill" : "crown")
                        .font(.system(size: 32))
                        .foregroundStyle(state.isPro ? Color.tempoAmber : Color.tempoTextTertiary)
                    Text(planTitle)
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(planSubtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TempoSpacing.xl)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))

                SettingsFormCard(title: "Details") {
                    SettingsInfoRow(label: "Status", value: planTitle, icon: "checkmark.seal.fill",
                                    iconTint: state.isPro ? .tempoSuccess : .tempoTextTertiary,
                                    valueColor: state.isPro ? .tempoSuccess : .tempoTextTertiary)
                    if let renewal = renewalLine {
                        SettingsRowDivider()
                        SettingsInfoRow(label: renewal.label, value: renewal.value,
                                        icon: "calendar", iconTint: .tempoElectric)
                    }
                    if let plan = productLine {
                        SettingsRowDivider()
                        SettingsInfoRow(label: "Plan", value: plan, icon: "tag.fill", iconTint: .tempoViolet)
                    }
                }

                SettingsFormCard {
                    if !state.isPro {
                        Button { showPaywall = true } label: {
                            SettingsActionRow(icon: "sparkles", title: "Subscribe to Pro", tint: .tempoSignal)
                        }
                        .buttonStyle(.plain)
                        SettingsRowDivider()
                    }
                    Button { Task { await restore() } } label: {
                        SettingsActionRow(icon: "arrow.clockwise", title: "Restore Purchases", tint: .tempoTextPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)
                }

                if let restoreError {
                    Text(restoreError)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .padding(.horizontal, TempoSpacing.sm)
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    private var planTitle: String {
        switch state {
        case .free: "Free"
        case .trial: "Pro · Trial"
        case .active: "Pro"
        case .gracePeriod: "Pro · Billing issue"
        case .expired, .churned: "Expired"
        }
    }

    private var planSubtitle: String {
        state.isPro ? "You have full access to Tempo Pro." : "Upgrade to unlock everything Tempo offers."
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
        guard !isRestoring else { return }
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

    private var profile: UserProfile? { allProfiles.first }

    var body: some View {
        ScrollView {
            VStack(spacing: TempoSpacing.lg) {
                SettingsFormCard(title: "Identity") {
                    SettingsInfoRow(label: "Sign-in", value: "Apple", icon: "applelogo", iconTint: .tempoTextPrimary)
                    SettingsRowDivider()
                    SettingsInfoRow(label: "Member since", value: memberSince, icon: "calendar", iconTint: .tempoElectric)
                    if let id = userIDShort {
                        SettingsRowDivider()
                        SettingsInfoRow(label: "User ID", value: id, icon: "number", iconTint: .tempoViolet)
                    }
                }

                SettingsFormCard(
                    title: "Danger zone",
                    footnote: "Deleting your account permanently removes all data — XP, achievements, streaks, and workout history. You'll be removed from all leaderboards and active challenges. This cannot be undone."
                ) {
                    Button { showDeleteConfirm = true } label: {
                        SettingsActionRow(icon: "trash", title: "Delete Account", tint: .tempoError)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDeleting)
                }
            }
            .padding(.horizontal, TempoSpacing.xl)
            .padding(.vertical, TempoSpacing.lg)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) { Task { await performDeletion() } }
        } message: {
            Text("This permanently deletes all your data. This cannot be undone.")
        }
        .alert("Could not delete account", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    private var memberSince: String {
        guard let created = profile?.createdAt else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: created)
    }

    private var userIDShort: String? {
        if case let .authenticated(userID) = services.authService.authState {
            return String(userID.prefix(8)) + "…"
        }
        return nil
    }

    @MainActor
    private func performDeletion() async {
        guard !isDeleting else { return }
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
