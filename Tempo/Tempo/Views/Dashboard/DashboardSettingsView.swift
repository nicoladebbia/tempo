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
    @Query
    private var allProfiles: [UserProfile]

    private var profile: UserProfile? {
        allProfiles.first
    }

    @State
    private var displayName = ""
    @State
    private var username = ""
    @State
    private var weightKg = ""
    @State
    private var heightCm = ""
    @State
    private var age = ""

    var body: some View {
        List {
            Section("Identity") {
                TextField("Display Name", text: $displayName)
                    .font(.tempoSubheadline)
                    .onChange(of: displayName) { _, newValue in
                        profile?.displayName = newValue
                        profile?.updatedAt = Date()
                        save()
                    }

                TextField("Username", text: $username)
                    .font(.tempoSubheadline)
                    .autocapitalization(.none)
                    .onChange(of: username) { _, newValue in
                        profile?.username = newValue
                        profile?.updatedAt = Date()
                        save()
                    }
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section("Biometrics") {
                HStack {
                    Text("Weight (kg)")
                        .font(.tempoSubheadline)
                    Spacer()
                    TextField("--", text: $weightKg)
                        .font(.tempoSubheadline)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .onChange(of: weightKg) { _, newValue in
                            profile?.weightKg = Double(newValue)
                            profile?.updatedAt = Date()
                            save()
                        }
                }

                HStack {
                    Text("Height (cm)")
                        .font(.tempoSubheadline)
                    Spacer()
                    TextField("--", text: $heightCm)
                        .font(.tempoSubheadline)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 80)
                        .onChange(of: heightCm) { _, newValue in
                            profile?.heightCm = Double(newValue)
                            profile?.updatedAt = Date()
                            save()
                        }
                }

                HStack {
                    Text("Age")
                        .font(.tempoSubheadline)
                    Spacer()
                    TextField("--", text: $age)
                        .font(.tempoSubheadline)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                        .onChange(of: age) { _, newValue in
                            profile?.age = Int(newValue)
                            profile?.updatedAt = Date()
                            save()
                        }
                }
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadProfile() }
    }

    private func loadProfile() {
        guard let p = profile else {
            return
        }
        displayName = p.displayName
        username = p.username
        weightKg = p.weightKg.map { String(format: "%.1f", $0) } ?? ""
        heightCm = p.heightCm.map { String(format: "%.0f", $0) } ?? ""
        age = p.age.map { "\($0)" } ?? ""
    }

    private func save() {
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

                HStack {
                    Label("Football Days", systemImage: "sportscourt.fill")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text("\(settings?.footballDays.rawValue.nonzeroBitCount ?? 0)/week")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
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
