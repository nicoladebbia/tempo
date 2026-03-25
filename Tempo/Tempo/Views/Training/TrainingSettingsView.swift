import SwiftUI
import SwiftData

// MARK: - Training Settings View
// Per MODULE_TRAINING.md Section 14 — Training preferences and configuration.
// Per UX_COPY_BIBLE.md Section 4.9.

struct TrainingSettingsView: View {

    @Environment(\.modelContext) private var modelContext
    @Query private var userSettings: [UserSettings]

    private var settings: UserSettings? { userSettings.first }

    var body: some View {
        List {
            // Training split
            splitSection

            // Weight unit
            unitSection

            // Rest timer
            restTimerSection

            // Deload settings
            // Per MODULE_TRAINING.md Section 14.1 — Deload settings
            deloadSection

            // Football schedule
            footballSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Training Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Split Section

    private var splitSection: some View {
        Section {
            if let settings {
                HStack {
                    Text("Training Split")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Spacer()
                    Text(settings.trainingSplit.displayName)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
        } header: {
            Text("PROGRAM")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Unit Section

    private var unitSection: some View {
        Section {
            HStack {
                Text("Weight Unit")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("kg")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        } header: {
            Text("UNITS")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Rest Timer Section

    private var restTimerSection: some View {
        Section {
            HStack {
                Text("Auto-Start Rest Timer")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoRecoveryGreen)
            }

            HStack {
                Text("Show Plate Calculator")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoRecoveryGreen)
            }
        } header: {
            Text("WORKOUT")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Deload Section
    // Per MODULE_TRAINING.md Section 14.1 — Auto-deload, frequency, type

    private var deloadSection: some View {
        Section {
            HStack {
                Text("Auto-Deload")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoRecoveryGreen)
            }

            HStack {
                Text("Deload Frequency")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text("Every 5 weeks")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Text("Automatically schedule a deload week every 4-6 weeks")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextTertiary)
        } header: {
            Text("DELOAD")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }

    // MARK: - Football Section

    private var footballSection: some View {
        Section {
            if let settings {
                let days = settings.footballDays
                let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

                ForEach(0..<7, id: \.self) { dayIndex in
                    HStack {
                        Text(dayNames[dayIndex])
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        if days.isActive(on: dayIndex + 2 > 7 ? dayIndex + 2 - 7 : dayIndex + 2) {
                            Image(systemName: "sportscourt.fill")
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoRecoveryYellow)
                        }
                    }
                }
            }
        } header: {
            Text("FOOTBALL SCHEDULE")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        } footer: {
            Text("Football days are set during onboarding. Match days lock your training schedule.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
        .listRowBackground(Color.tempoSurfaceCard)
    }
}
