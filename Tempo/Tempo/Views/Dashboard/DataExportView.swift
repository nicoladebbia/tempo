//
// DataExportView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - DataExportView

// App Store compliance — data portability.
// Generates a JSON file with user data and presents UIActivityViewController.

struct DataExportView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allProfiles: [UserProfile]
    @Query
    private var allSettings: [UserSettings]

    @State
    private var exportRange: ExportRange = .last30Days
    @State
    private var isExporting = false
    @State
    private var exportError: String?
    @State
    private var showShareSheet = false
    @State
    private var exportFileURL: URL?

    var body: some View {
        List {
            Section {
                Picker("Date Range", selection: $exportRange) {
                    ForEach(ExportRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .font(.system(size: 14))
            } header: {
                Text("Export Range")
            } footer: {
                Text("Your data will be exported as a JSON file that you can save or share.")
                    .font(.tempoCaption1)
            }
            .listRowBackground(Color.tempoSurfaceCard)

            Section {
                Button {
                    exportData()
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .tint(Color.tempoTextInverse)
                        } else {
                            Label("Export My Data", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Spacer()
                    }
                    .foregroundStyle(Color.tempoTextInverse)
                    .padding(.vertical, TempoSpacing.sm)
                }
                .listRowBackground(Color.tempoSignal)
                .disabled(isExporting)
            }

            if let error = exportError {
                Section {
                    Text(error)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
                .listRowBackground(Color.tempoSurfaceCard)
            }

            Section {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    exportInfoRow(icon: "person.fill", text: "Profile & biometrics")
                    exportInfoRow(icon: "gearshape.fill", text: "Settings & preferences")
                    exportInfoRow(icon: "dumbbell.fill", text: "Workout history")
                    exportInfoRow(icon: "heart.fill", text: "Recovery data")
                    exportInfoRow(icon: "brain.head.profile", text: "Study sessions")
                    exportInfoRow(icon: "flame.fill", text: "Streaks & achievements")
                }
            } header: {
                Text("Included Data")
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Export Logic

    private func exportData() {
        isExporting = true
        exportError = nil

        Task {
            do {
                let data = try buildExportData()
                let jsonData = try JSONSerialization.data(
                    withJSONObject: data,
                    options: [.prettyPrinted, .sortedKeys]
                )

                let fileName = "tempo-export-\(exportDateString()).json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try jsonData.write(to: tempURL)

                await MainActor.run {
                    exportFileURL = tempURL
                    showShareSheet = true
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = "Export failed: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }

    private func buildExportData() throws -> [String: Any] {
        var exportDict: [String: Any] = [:]

        exportDict["export_date"] = ISO8601DateFormatter().string(from: Date())
        exportDict["export_range"] = exportRange.displayName
        exportDict["app_version"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        // Profile
        if let profile = allProfiles.first {
            exportDict["profile"] = [
                "display_name": profile.displayName,
                "username": profile.username,
                "timezone": profile.timezone,
                "weight_kg": profile.weightKg as Any,
                "height_cm": profile.heightCm as Any,
                "age": profile.age as Any,
                "training_split": profile.trainingSplitRaw,
                "weight_unit": profile.weightUnitRaw,
                "total_xp": profile.totalXP,
                "current_level": profile.currentLevel,
                "created_at": ISO8601DateFormatter().string(from: profile.createdAt),
            ]
        }

        // Settings
        if let settings = allSettings.first {
            exportDict["settings"] = [
                "notification_intensity": settings.notificationIntensity,
                "training_split": settings.trainingSplitRaw,
                "weight_unit": settings.weightUnitRaw,
                "wake_time_minutes": settings.wakeTimeMinutes,
                "bedtime_target_minutes": settings.bedtimeTargetMinutes,
                "pomodoro_duration": settings.pomodoroDuration,
                "break_duration": settings.breakDuration,
                "long_break_duration": settings.longBreakDuration,
                "weekend_mode": settings.weekendMode,
                "exam_mode": settings.examMode,
            ]
        }

        // Study Sessions
        let cutoffDate = exportRange.cutoffDate
        let sessionDescriptor = FetchDescriptor<StudySession>(
            predicate: #Predicate<StudySession> { session in
                session.startTime >= cutoffDate
            },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        if let sessions = try? modelContext.fetch(sessionDescriptor) {
            exportDict["study_sessions"] = sessions.map { session in
                var dict: [String: Any] = [
                    "start_time": ISO8601DateFormatter().string(from: session.startTime),
                    "duration_minutes": session.durationMinutes,
                    "session_type": session.sessionTypeRaw,
                    "completed_pomodoros": session.completedPomodoros,
                    "distractions": session.distractions,
                ]
                if let end = session.endTime {
                    dict["end_time"] = ISO8601DateFormatter().string(from: end)
                }
                if let subject = session.subject {
                    dict["subject"] = subject
                }
                return dict
            }
        }

        // Streaks
        let streakDescriptor = FetchDescriptor<Streak>()
        if let streaks = try? modelContext.fetch(streakDescriptor) {
            exportDict["streaks"] = streaks.map { streak in
                var dict: [String: Any] = [
                    "type": streak.typeRaw,
                    "current_count": streak.currentCount,
                    "longest_count": streak.longestCount,
                    "freezes_used": streak.freezesUsed,
                    "freezes_available": streak.freezesAvailable,
                ]
                if let lastDate = streak.lastCompletedDate {
                    dict["last_completed_date"] = ISO8601DateFormatter().string(from: lastDate)
                }
                return dict
            }
        }

        // Non-Negotiables
        let nnDescriptor = FetchDescriptor<NonNegotiable>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let nonNegs = try? modelContext.fetch(nnDescriptor) {
            exportDict["non_negotiables"] = nonNegs.map { nn in
                [
                    "name": nn.name,
                    "type": nn.typeRaw,
                    "icon": nn.icon,
                    "target_value": nn.targetValue,
                    "tracking_method": nn.trackingMethodRaw,
                    "is_active": nn.isActive,
                    "created_at": ISO8601DateFormatter().string(from: nn.createdAt),
                ] as [String: Any]
            }
        }

        // Daily Recovery
        let recoveryDescriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { r in
                r.date >= cutoffDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        if let recoveries = try? modelContext.fetch(recoveryDescriptor) {
            exportDict["daily_recovery"] = recoveries.map { r in
                var dict: [String: Any] = [
                    "date": ISO8601DateFormatter().string(from: r.date),
                    "recovery_score": r.recoveryScore,
                    "recovery_zone": r.recoveryZoneRaw,
                ]
                if let hrv = r.hrvRmssd {
                    dict["hrv_rmssd"] = hrv
                }
                if let rhr = r.restingHR {
                    dict["resting_hr"] = rhr
                }
                if let spo2 = r.spo2 {
                    dict["spo2"] = spo2
                }
                if let sleep = r.sleepHours {
                    dict["sleep_hours"] = sleep
                }
                if let sleepScore = r.sleepScore {
                    dict["sleep_score"] = sleepScore
                }
                return dict
            }
        }

        return exportDict
    }

    private func exportDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func exportInfoRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.tempoTextTertiary)
                .frame(width: 20)
            Text(text)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
        }
    }
}

// MARK: - ExportRange

enum ExportRange: String, CaseIterable, Identifiable {
    case last7Days = "7d"
    case last30Days = "30d"
    case last90Days = "90d"
    case allTime = "all"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .last7Days: "Last 7 Days"
        case .last30Days: "Last 30 Days"
        case .last90Days: "Last 90 Days"
        case .allTime: "All Time"
        }
    }

    var cutoffDate: Date {
        let cal = Calendar.current
        switch self {
        case .last7Days: return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .last30Days: return cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .last90Days: return cal.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        case .allTime: return Date.distantPast
        }
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
