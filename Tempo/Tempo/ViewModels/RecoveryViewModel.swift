import Foundation
import SwiftUI
import SwiftData

// MARK: - Recovery Load State

enum RecoveryLoadState: Sendable {
    case loading
    case loaded
    case error(String)
}

// MARK: - Recovery Tab

enum RecoveryTab: String, CaseIterable, Sendable {
    case today = "Today"
    case sleep = "Sleep"
    case strain = "Strain"
    case trends = "Trends"
}

// MARK: - Recovery ViewModel
// Per MODULE_RECOVERY.md Sections 4-7 and BUILD_PLAN.md Step 8.2.

@Observable
@MainActor
final class RecoveryViewModel {

    // MARK: - State

    var loadState: RecoveryLoadState = .loading
    var selectedTab: RecoveryTab = .today
    var selectedTrendRange: TrendRange = .week

    // MARK: - Today's Data

    var todayRecovery: DailyRecovery?
    var todayPrescription: DailyPrescription?

    // MARK: - Historical Data (for charts)

    var recentRecoveries: [DailyRecovery] = []
    var insights: [RecoveryInsight] = []

    // MARK: - Dependencies

    private let whoop: any WhoopServiceProtocol
    private let recoveryEngine: any RecoveryEngineProtocol
    private let calendar: any CalendarServiceProtocol

    init(
        whoop: any WhoopServiceProtocol,
        recoveryEngine: any RecoveryEngineProtocol,
        calendar: any CalendarServiceProtocol
    ) {
        self.whoop = whoop
        self.recoveryEngine = recoveryEngine
        self.calendar = calendar
    }

    // MARK: - Refresh
    // Per MODULE_RECOVERY.md Section 4 — Pull-to-refresh

    func refresh(modelContext: ModelContext) async {
        loadState = .loading

        do {
            let today = Date()

            // Fetch Whoop data
            let recoveryData = try? await whoop.fetchRecovery(for: today)
            let sleepData = try? await whoop.fetchSleep(for: today)
            let cycleData = try? await whoop.fetchCycle(for: today)

            // Build or update DailyRecovery
            let recovery = buildDailyRecovery(
                date: today,
                recoveryData: recoveryData,
                sleepData: sleepData,
                cycleData: cycleData,
                modelContext: modelContext
            )

            // Get calendar events for prescription context
            let endDate = Calendar.current.date(byAdding: .day, value: 2, to: today) ?? today
            let events = (try? await calendar.fetchEvents(
                for: DateInterval(start: today, end: endDate)
            )) ?? []

            // Generate prescription
            let prescription = recoveryEngine.generatePrescription(
                recovery: recovery,
                schedule: events
            )

            // Persist
            modelContext.insert(recovery)
            modelContext.insert(prescription)
            try? modelContext.save()

            // Load historical data
            let historyDays = trendRangeDays(selectedTrendRange)
            let historyStart = Calendar.current.date(
                byAdding: .day, value: -historyDays, to: today
            ) ?? today

            let descriptor = FetchDescriptor<DailyRecovery>(
                predicate: #Predicate { $0.date >= historyStart },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            recentRecoveries = (try? modelContext.fetch(descriptor)) ?? []

            // Detect trends
            insights = recoveryEngine.detectTrends(
                recoveries: recentRecoveries,
                days: historyDays
            )

            todayRecovery = recovery
            todayPrescription = prescription
            loadState = .loaded

        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    // MARK: - Trend Range

    enum TrendRange: String, CaseIterable, Sendable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }

    func trendRangeDays(_ range: TrendRange) -> Int {
        switch range {
        case .week: 7
        case .month: 30
        case .quarter: 90
        }
    }

    // MARK: - Formatted Display Values
    // Per MODULE_RECOVERY.md Section 13 — Data Formatting Rules

    var formattedRecoveryScore: String {
        guard let score = todayRecovery?.recoveryScore else { return "--" }
        return "\(Int(score))"
    }

    var recoveryZone: RecoveryZone {
        guard let score = todayRecovery?.recoveryScore else { return .red }
        return RecoveryZone(score: score)
    }

    var formattedHRV: String {
        guard let hrv = todayRecovery?.hrvRmssd else { return "--" }
        return "\(Int(hrv))"
    }

    var formattedRHR: String {
        guard let rhr = todayRecovery?.restingHR else { return "--" }
        return "\(Int(rhr))"
    }

    var formattedSpO2: String {
        guard let spo2 = todayRecovery?.spo2 else { return "--" }
        return "\(Int(spo2))"
    }

    var formattedSkinTemp: String {
        guard let temp = todayRecovery?.skinTemp else { return "--" }
        return String(format: "%.1f", temp)
    }

    var formattedSleepHours: String {
        guard let hours = todayRecovery?.sleepHours else { return "--" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var formattedSleepScore: String {
        guard let score = todayRecovery?.sleepScore else { return "--" }
        return "\(Int(score))%"
    }

    var formattedStrain: String {
        guard let strain = todayRecovery?.strain else { return "--" }
        return String(format: "%.1f", strain)
    }

    var formattedCalories: String {
        guard let cal = todayRecovery?.caloriesBurned else { return "--" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: cal)) ?? "\(Int(cal))"
    }

    var formattedBedtime: String {
        guard let bedtime = todayPrescription?.bedtimeTarget else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: bedtime)
    }

    var formattedCaffeineCutoff: String {
        todayPrescription?.caffeineCutoffFormatted ?? "--"
    }

    var formattedHydration: String {
        guard let ml = todayPrescription?.hydrationTargetMl else { return "--" }
        let liters = Double(ml) / 1000.0
        return String(format: "%.1fL", liters)
    }

    // MARK: - Chart Data

    var recoveryChartData: [(Date, Double)] {
        recentRecoveries.map { ($0.date, $0.recoveryScore) }
    }

    var hrvChartData: [(Date, Double)] {
        recentRecoveries.compactMap { r in
            guard let hrv = r.hrvRmssd else { return nil }
            return (r.date, hrv)
        }
    }

    var rhrChartData: [(Date, Double)] {
        recentRecoveries.compactMap { r in
            guard let rhr = r.restingHR else { return nil }
            return (r.date, rhr)
        }
    }

    var sleepChartData: [(Date, Double)] {
        recentRecoveries.compactMap { r in
            guard let hours = r.sleepHours else { return nil }
            return (r.date, hours)
        }
    }

    var strainChartData: [(Date, Double)] {
        recentRecoveries.compactMap { r in
            guard let strain = r.strain else { return nil }
            return (r.date, strain)
        }
    }

    // MARK: - Averages

    var avgRecovery7d: Double? {
        let recent = recentRecoveries.suffix(7)
        guard !recent.isEmpty else { return nil }
        return recent.map(\.recoveryScore).reduce(0, +) / Double(recent.count)
    }

    var avgHRV7d: Double? {
        let values = recentRecoveries.suffix(7).compactMap(\.hrvRmssd)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    var avgRHR7d: Double? {
        let values = recentRecoveries.suffix(7).compactMap(\.restingHR)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Recovery Comparison
    // Per MODULE_RECOVERY.md Section 4.2 — Comparison label

    var comparisonText: String {
        guard let score = todayRecovery?.recoveryScore,
              let avg = avg30dRecovery else {
            return "Your first recovery day!"
        }
        let diff = score - avg
        let percent = abs(diff / avg * 100)
        if abs(diff) < 1 {
            return "Right at your average"
        } else if diff > 0 {
            return "↑ \(Int(percent))% above your average"
        } else {
            return "↓ \(Int(percent))% below your average"
        }
    }

    var comparisonIsPositive: Bool {
        guard let score = todayRecovery?.recoveryScore,
              let avg = avg30dRecovery else { return true }
        return score >= avg
    }

    private var avg30dRecovery: Double? {
        let values = recentRecoveries.suffix(30).map(\.recoveryScore)
        guard values.count >= 2 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Sleep Stage Data

    var deepSleepMinutes: Int { todayRecovery?.deepSleepMin ?? 0 }
    var remSleepMinutes: Int { todayRecovery?.remSleepMin ?? 0 }
    var lightSleepMinutes: Int { todayRecovery?.lightSleepMin ?? 0 }
    var awakeMinutes: Int { todayRecovery?.awakeMin ?? 0 }

    var totalSleepStageMinutes: Int {
        deepSleepMinutes + remSleepMinutes + lightSleepMinutes
    }

    // MARK: - Private Helpers

    private func buildDailyRecovery(
        date: Date,
        recoveryData: WhoopRecoveryData?,
        sleepData: WhoopSleepData?,
        cycleData: WhoopCycleData?,
        modelContext: ModelContext
    ) -> DailyRecovery {

        let startOfDay = Calendar.current.startOfDay(for: date)

        // Check if we already have a recovery for today
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            // Update existing record with fresh data
            if let r = recoveryData {
                existing.recoveryScore = r.score
                existing.hrvRmssd = r.hrvRmssd
                existing.restingHR = r.restingHeartRate
                existing.spo2 = r.spo2
                existing.skinTemp = r.skinTemp
                existing.recoveryZoneRaw = RecoveryZone(score: r.score).rawValue
            }
            if let s = sleepData {
                existing.sleepHours = s.totalHours
                existing.sleepScore = s.sleepScore
                existing.sleepEfficiency = s.sleepEfficiency
                existing.sleepConsistency = s.sleepConsistency
                existing.deepSleepMin = s.deepSleepMinutes
                existing.remSleepMin = s.remSleepMinutes
                existing.lightSleepMin = s.lightSleepMinutes
                existing.awakeMin = s.awakeMinutes
                existing.respiratoryRate = s.respiratoryRate
            }
            if let c = cycleData {
                existing.strain = c.strain
                existing.avgHR = c.averageHeartRate
                existing.maxHR = c.maxHeartRate
                existing.caloriesBurned = c.caloriesBurned
            }
            return existing
        }

        // Create new
        return DailyRecovery(
            date: date,
            recoveryScore: recoveryData?.score ?? 0,
            hrvRmssd: recoveryData?.hrvRmssd,
            restingHR: recoveryData?.restingHeartRate,
            spo2: recoveryData?.spo2,
            skinTemp: recoveryData?.skinTemp,
            sleepHours: sleepData?.totalHours,
            sleepScore: sleepData?.sleepScore,
            sleepEfficiency: sleepData?.sleepEfficiency,
            sleepConsistency: sleepData?.sleepConsistency,
            deepSleepMin: sleepData?.deepSleepMinutes,
            remSleepMin: sleepData?.remSleepMinutes,
            lightSleepMin: sleepData?.lightSleepMinutes,
            awakeMin: sleepData?.awakeMinutes,
            respiratoryRate: sleepData?.respiratoryRate,
            strain: cycleData?.strain,
            avgHR: cycleData?.averageHeartRate,
            maxHR: cycleData?.maxHeartRate,
            caloriesBurned: cycleData?.caloriesBurned
        )
    }
}
