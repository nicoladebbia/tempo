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

    var body: some View {
        List {
            // MARK: - Profile Header

            Section {
                NavigationLink {
                    ProfileSettingsDetailView()
                } label: {
                    HStack(spacing: TempoSpacing.md) {
                        Circle()
                            .fill(Color.tempoSurfaceCard)
                            .frame(width: 48, height: 48)
                            .overlay {
                                Text(profileInitial)
                                    .font(.tempoTitle3)
                                    .foregroundStyle(Color.tempoTextPrimary)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile?.displayName ?? "Athlete")
                                .font(.tempoCallout)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.tempoTextPrimary)

                            Text("@\(profile?.username ?? "—")")
                                .font(.tempoFootnote)
                                .foregroundStyle(Color.tempoTextTertiary)

                            Text(profile?.identityLabel ?? "Athlete")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }

            // MARK: - Settings Sections

            Section("Schedule") {
                NavigationLink {
                    ScheduleSettingsDetailView()
                } label: {
                    Label("Wake Time, Bedtime, Leisure", systemImage: "clock.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Training") {
                NavigationLink {
                    TrainingSettingsDetailView()
                } label: {
                    Label("Split, Football, Weight Unit", systemImage: "dumbbell.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Focus Timer") {
                NavigationLink {
                    FocusTimerSettingsDetailView()
                } label: {
                    Label("Pomodoro, Break, Sessions", systemImage: "timer")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Notifications") {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notification Preferences", systemImage: "bell.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Integrations") {
                NavigationLink {
                    WhoopConnectionView()
                } label: {
                    integrationRow(
                        icon: "waveform.path.ecg",
                        label: "Whoop",
                        status: whoopStatusText,
                        statusColor: whoopStatusColor
                    )
                }

                NavigationLink {
                    DietaryProfileSetupView()
                } label: {
                    integrationRow(
                        icon: "fork.knife",
                        label: "Diet Profile",
                        status: dietProfileStatusText,
                        statusColor: dietProfileStatusColor
                    )
                }

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    integrationRow(
                        icon: "heart.text.square",
                        label: "HealthKit",
                        status: healthKitStatusText,
                        statusColor: healthKitStatusColor
                    )
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Modes") {
                NavigationLink {
                    ModesSettingsDetailView()
                } label: {
                    Label("Weekend, Exam Mode", systemImage: "bolt.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Coach") {
                NavigationLink {
                    CoachMemoryView()
                } label: {
                    Label("Coach's Memory", systemImage: "brain")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Appearance") {
                NavigationLink {
                    AppearanceSettingsDetailView()
                } label: {
                    Label("Accent Color", systemImage: "paintbrush.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Data") {
                NavigationLink {
                    DataExportView()
                } label: {
                    Label("Export My Data", systemImage: "square.and.arrow.up")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            // MARK: - Account
            //
            // Apple Guideline 5.1.1(v): account deletion must be initiated
            // in-app. The warning copy is the canonical
            // `settings_delete_warning` string in UX_COPY_BIBLE.md §28.

            Section("Subscription") {
                HStack {
                    Label("Plan", systemImage: "crown.fill")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text(subscriptionStatusText)
                        .font(.tempoDataSmall)
                        .foregroundStyle(
                            services.subscriptions.isPro
                                ? Color.tempoSuccess : Color.tempoTextTertiary
                        )
                }

                if !services.subscriptions.isPro {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Subscribe to Pro", systemImage: "sparkles")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoSignal)
                    }
                }

                Button {
                    Task { await restorePurchases() }
                } label: {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                .disabled(isRestoring)

                if let restoreError {
                    Text(restoreError)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Account") {
                Button {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Account", systemImage: "trash")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoSignal)
                }
                .disabled(isDeletingAccount)

                Text("This permanently deletes all your data, including XP, achievements, streaks, and workout history. You'll be removed from all leaderboards and active challenges. This cannot be undone.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .listRowBackground(Color.tempoSurfaceCard)

            // MARK: - About

            Section("About") {
                HStack {
                    Text("Version")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .font(.tempoDataSmall)
                        .foregroundStyle(Color.tempoTextTertiary)
                }

                if let supportURL = URL(string: "https://tempo.app/support") {
                    Link(destination: supportURL) {
                        HStack {
                            Label("Support", systemImage: "questionmark.circle")
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
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

    private func integrationRow(icon: String, label: String, status: String, statusColor: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Spacer()
            Text(status)
                .font(.tempoFootnote)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
    }

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
}

// MARK: - ProfileSettingsDetailView

struct ProfileSettingsDetailView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Query
    private var allProfiles: [UserProfile]
    @Query(filter: #Predicate<DietaryProfile> { $0.isActive })
    private var activeDietaryProfiles: [DietaryProfile]
    @Query
    private var allSettings: [UserSettings]

    /// Set true to push the weekly-schedule editor sheet. Bound to the row.
    @State private var showWeeklyScheduleEditor = false

    // Identity — editable (user-chosen, not from HealthKit)
    @State private var displayName: String = ""
    @State private var username: String = ""

    // Biometrics — read-only, sourced from HealthKit via BiometricsSync.
    // Mirrored into local @State so the view shows the refreshed values
    // immediately after .task fires; the SwiftData write-through is the
    // source of truth for everything else (TDEE, meal plan).
    @State private var biometrics: BiometricsSnapshot?

    private var userProfile: UserProfile? { allProfiles.first }
    private var dietaryProfile: DietaryProfile? { activeDietaryProfiles.first }
    private var userSettings: UserSettings? { allSettings.first }

    var body: some View {
        List {
            identitySection
            biometricsSection
            goalSection
            integrationsSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadIdentity()
            biometrics = await BiometricsSync.refresh(
                healthKit: services.healthKit,
                modelContext: modelContext
            )
        }
        .sheet(isPresented: $showWeeklyScheduleEditor) {
            WeeklyScheduleEditorSheet(
                userSettings: userSettings,
                modelContext: modelContext
            )
        }
    }

    // MARK: - Identity

    private var identitySection: some View {
        Section("Identity") {
            TextField("Display Name", text: $displayName)
                .font(.tempoSubheadline)
                .onChange(of: displayName) { _, newValue in
                    userProfile?.displayName = newValue
                    userProfile?.updatedAt = Date()
                    try? modelContext.save()
                }

            TextField("Username", text: $username)
                .font(.tempoSubheadline)
                .autocapitalization(.none)
                .onChange(of: username) { _, newValue in
                    userProfile?.username = newValue
                    userProfile?.updatedAt = Date()
                    try? modelContext.save()
                }
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Biometrics (read-only, HealthKit-synced)

    private var biometricsSection: some View {
        Section {
            // Header row — explains where the data comes from.
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                Image(systemName: "heart.text.square.fill")
                    .font(.tempoCallout)
                    .foregroundStyle(Color.tempoSignal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synced from Apple Health")
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("Update these in the Health app — Tempo reads them, never writes.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Button {
                    if let url = URL(string: "x-apple-health://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Open")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSignal)
                }
            }

            readOnlyRow(
                label: "Weight",
                value: biometrics?.weightKg.map { String(format: "%.1f kg", $0) } ?? "—"
            )
            readOnlyRow(
                label: "Height",
                value: biometrics?.heightCm.map { String(format: "%.0f cm", $0) } ?? "—"
            )
            readOnlyRow(
                label: "Age",
                value: biometrics?.age.map { "\($0) years" } ?? "—"
            )
            readOnlyRow(
                label: "Biological Sex",
                value: biometrics?.biologicalSex?.displayName ?? "—"
            )
            readOnlyRow(
                label: "Body Fat",
                value: biometrics?.bodyFatPercent.map { String(format: "%.1f%%", $0) } ?? "—"
            )
        } header: {
            Text("Biometrics")
        } footer: {
            if let date = biometrics?.measurementDate {
                Text("Last measurement: \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else if biometrics?.isCompleteForTDEE == false {
                Text("Some biometrics are missing — open the Health app to add them.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoSignal)
            }
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Goal & Training (read-only, from DietaryProfile)

    private var goalSection: some View {
        Section {
            readOnlyRow(
                label: "Goal",
                value: dietaryProfile?.primaryGoal.displayName ?? "—"
            )
            readOnlyRow(
                label: "Training",
                value: dietaryProfile.map { "\($0.trainingFrequency)× / week" } ?? "—"
            )
            // Weekly schedule — tappable, opens the picker sheet. Locks day
            // types per weekday so meal-plan generation doesn't have to guess.
            Button {
                showWeeklyScheduleEditor = true
            } label: {
                HStack {
                    Text("Weekly Schedule")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                    Text(weeklyScheduleSummary)
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Image(systemName: "chevron.right")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .buttonStyle(.plain)
        } header: {
            Text("Goal & Training")
        } footer: {
            Text("Goal and frequency are set in the dietary profile. Weekly schedule drives meal-plan calorie targets.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    /// Short summary of the user's weekly DayType layout. Counts each type
    /// and renders the highest-count non-rest tag plus rest count, e.g.
    /// "4× Strength · 2× Soccer · 1 Rest".
    private var weeklyScheduleSummary: String {
        let plan = userSettings?.weeklyTrainingPlan ?? WeeklyTrainingPlan.defaultPlan
        guard !plan.isEmpty else { return "Not set" }
        var counts: [DayType: Int] = [:]
        for day in plan.values {
            counts[day, default: 0] += 1
        }
        let parts = counts
            .sorted { ($0.value, $0.key.displayName) > ($1.value, $1.key.displayName) }
            .prefix(2)
            .map { "\($0.value)× \($0.key.displayName)" }
        return parts.joined(separator: " · ")
    }

    // MARK: - Integrations

    private var integrationsSection: some View {
        Section("Integrations") {
            // HealthKit row — green when at least the TDEE-required fields are
            // present; otherwise amber to flag missing pieces. Last sync
            // timestamp lives in the biometrics footer; here we just gate on
            // completeness so the user gets an at-a-glance status.
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Color.tempoSignal)
                Text("Apple Health")
                    .font(.tempoSubheadline)
                Spacer()
                Text(healthKitStatusLabel)
                    .font(.tempoFootnote)
                    .foregroundStyle(healthKitStatusColor)
            }

            // Whoop row — mirrors the connectionState the DashboardSettings
            // header bar uses. Keeps a single source of truth on integration
            // health.
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color.tempoSignal)
                Text("Whoop")
                    .font(.tempoSubheadline)
                Spacer()
                Text(whoopStatusLabel)
                    .font(.tempoFootnote)
                    .foregroundStyle(whoopStatusColor)
            }
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func readOnlyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)
            Spacer()
            Text(value)
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    private var healthKitStatusLabel: String {
        guard let bio = biometrics else { return "Checking…" }
        return bio.isCompleteForTDEE ? "Connected" : "Missing data"
    }

    private var healthKitStatusColor: Color {
        guard let bio = biometrics else { return Color.tempoTextSecondary }
        return bio.isCompleteForTDEE ? Color.tempoSignal : Color.tempoAmber
    }

    private var whoopStatusLabel: String {
        switch services.whoop.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .disconnected: return "Not connected"
        case .error: return "Error"
        }
    }

    private var whoopStatusColor: Color {
        switch services.whoop.connectionState {
        case .connected: return Color.tempoSignal
        case .connecting: return Color.tempoTextSecondary
        case .disconnected: return Color.tempoTextSecondary
        case .error: return Color.tempoAmber
        }
    }

    private func loadIdentity() {
        guard let p = userProfile else { return }
        displayName = p.displayName
        username = p.username
    }
}


// MARK: - WeeklyScheduleEditorSheet

/// Sheet that wraps `WeeklyTrainingPlanPickerView` for the Settings flow.
/// Local @State holds the working copy; "Save" writes back to UserSettings.
private struct WeeklyScheduleEditorSheet: View {
    let userSettings: UserSettings?
    let modelContext: ModelContext

    @Environment(\.dismiss)
    private var dismiss

    @State private var workingPlan: [Int: DayType] = WeeklyTrainingPlan.defaultPlan

    var body: some View {
        NavigationStack {
            ScrollView {
                WeeklyTrainingPlanPickerView(plan: $workingPlan)
                    .padding(TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Weekly Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        userSettings?.weeklyTrainingPlan = workingPlan
                        userSettings?.updatedAt = Date()
                        try? modelContext.save()
                        dismiss()
                    }
                    .font(.tempoCallout.weight(.semibold))
                    .foregroundStyle(Color.tempoSignal)
                }
            }
            .onAppear {
                if let existing = userSettings?.weeklyTrainingPlan, !existing.isEmpty {
                    workingPlan = existing
                }
            }
        }
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
    private var leisureMinutes = 60

    var body: some View {
        List {
            Section {
                DatePicker(selection: $wakeTime, displayedComponents: .hourAndMinute) {
                    Label("Wake Time", systemImage: "sunrise.fill")
                        .font(.tempoSubheadline)
                }
                .onChange(of: wakeTime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.wakeTimeMinutes = (comps.hour ?? 6) * 60 + (comps.minute ?? 0)
                    save()
                }

                DatePicker(selection: $bedtime, displayedComponents: .hourAndMinute) {
                    Label("Bedtime Target", systemImage: "moon.fill")
                        .font(.tempoSubheadline)
                }
                .onChange(of: bedtime) { _, newValue in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                    settings?.bedtimeTargetMinutes = (comps.hour ?? 22) * 60 + (comps.minute ?? 30)
                    save()
                }

                Stepper(value: $leisureMinutes, in: 15 ... 180, step: 15) {
                    HStack {
                        Label("Leisure Time", systemImage: "hourglass")
                            .font(.tempoSubheadline)
                        Spacer()
                        Text("\(leisureMinutes) min")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .onChange(of: leisureMinutes) { _, newValue in
                    settings?.leisureTimeMinutes = newValue
                    save()
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        guard let s = settings else {
            return
        }
        wakeTime = dateFromMinutes(s.wakeTimeMinutes)
        bedtime = dateFromMinutes(s.bedtimeTargetMinutes)
        leisureMinutes = s.leisureTimeMinutes
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

    var body: some View {
        List {
            Section {
                Picker(selection: $trainingSplit) {
                    ForEach(TrainingSplit.allCases, id: \.self) { split in
                        Text(split.displayName).tag(split)
                    }
                } label: {
                    Label("Split", systemImage: "dumbbell.fill")
                        .font(.tempoSubheadline)
                }
                .onChange(of: trainingSplit) { _, newValue in
                    settings?.trainingSplit = newValue
                    save()
                }

                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    HStack {
                        Label("Football Days", systemImage: "sportscourt.fill")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        Text("\(settings?.footballDays.rawValue.nonzeroBitCount ?? 0)/week")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }

                    // Editable day chips (was a read-only label — no input
                    // existed, so it was stuck at 0/week). Mon=1<<0 … Sun=1<<6.
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
                                    .frame(height: 36)
                                    .background(isOn ? Color.tempoSignal : Color.tempoBgSecondary)
                                    .foregroundStyle(isOn ? .white : Color.tempoTextSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Picker(selection: Binding(
                    get: { settings?.weightUnit ?? .kg },
                    set: { newValue in
                        settings?.weightUnit = newValue
                        save()
                    }
                )) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.rawValue.uppercased()).tag(unit)
                    }
                } label: {
                    Label("Weight Unit", systemImage: "scalemass.fill")
                        .font(.tempoSubheadline)
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Deload") {
                Toggle(isOn: $autoDeload) {
                    Label("Auto Deload", systemImage: "arrow.down.right.circle")
                        .font(.tempoSubheadline)
                }
                .tint(Color.tempoSignal)
                .onChange(of: autoDeload) { _, newValue in
                    settings?.autoDeload = newValue
                    save()
                }

                if autoDeload {
                    Stepper(value: $deloadWeeks, in: 3 ... 8) {
                        HStack {
                            Text("Every")
                                .font(.tempoSubheadline)
                            Spacer()
                            Text("\(deloadWeeks) weeks")
                                .font(.tempoSubheadline)
                                .foregroundStyle(Color.tempoTextSecondary)
                        }
                    }
                    .onChange(of: deloadWeeks) { _, newValue in
                        settings?.deloadFrequencyWeeks = newValue
                        save()
                    }
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
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
        List {
            Section {
                Stepper(value: $pomodoroDuration, in: 10 ... 60, step: 5) {
                    HStack {
                        Label("Pomodoro", systemImage: "timer")
                            .font(.tempoSubheadline)
                        Spacer()
                        Text("\(pomodoroDuration) min")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .onChange(of: pomodoroDuration) { _, newValue in
                    settings?.pomodoroDuration = newValue
                    save()
                }

                Stepper(value: $breakDuration, in: 3 ... 15) {
                    HStack {
                        Label("Break", systemImage: "cup.and.saucer.fill")
                            .font(.tempoSubheadline)
                        Spacer()
                        Text("\(breakDuration) min")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .onChange(of: breakDuration) { _, newValue in
                    settings?.breakDuration = newValue
                    save()
                }

                Stepper(value: $longBreakDuration, in: 10 ... 30, step: 5) {
                    HStack {
                        Label("Long Break", systemImage: "cup.and.saucer")
                            .font(.tempoSubheadline)
                        Spacer()
                        Text("\(longBreakDuration) min")
                            .font(.tempoSubheadline)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .onChange(of: longBreakDuration) { _, newValue in
                    settings?.longBreakDuration = newValue
                    save()
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
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

    var body: some View {
        List {
            Section {
                Toggle(isOn: $weekendMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Weekend Mode", systemImage: "party.popper.fill")
                            .font(.tempoSubheadline)
                        Text("Relaxed schedule on weekends")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .tint(Color.tempoSignal)
                .onChange(of: weekendMode) { _, newValue in
                    settings?.weekendMode = newValue
                    save()
                }

                Toggle(isOn: $examMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Exam Mode", systemImage: "pencil.and.list.clipboard")
                            .font(.tempoSubheadline)
                        Text("Prioritize study, reduce training load")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .tint(Color.tempoSignal)
                .onChange(of: examMode) { _, newValue in
                    settings?.examMode = newValue
                    save()
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Modes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            weekendMode = settings?.weekendMode ?? false
            examMode = settings?.examMode ?? false
        }
    }

    private func save() {
        try? modelContext.save()
    }
}
