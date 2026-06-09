//
// DashboardViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import CoreLocation
import Foundation
import SwiftData
import SwiftUI
#if canImport(WeatherKit)
    import WeatherKit
#endif

// MARK: - DashboardViewModel

@Observable
@MainActor
final class DashboardViewModel {
    // MARK: - State

    private(set) var loadState: DashboardLoadState = .loading
    private(set) var snapshot: DailySnapshot?
    private(set) var lastRefresh: Date?

    // MARK: - Quadrant Data

    private(set) var body: BodyQuadrantData = .empty
    private(set) var fuel: FuelQuadrantData = .empty
    private(set) var mind: MindQuadrantData = .empty
    private(set) var move: MoveQuadrantData = .empty

    // MARK: - Quick Actions

    // Context-aware action buttons shown below the quadrant grid.
    // Maximum 2 visible at a time. Priority-ordered by what's most actionable now.

    struct QuickAction: Identifiable {
        let id = UUID()
        let title: String
        let icon: String
        let targetTab: Tab
        let color: Color
    }

    var quickActions: [QuickAction] {
        var actions: [QuickAction] = []

        // Workout planned but not done
        if move.workoutStatus == .planned, let name = move.workoutName {
            actions.append(QuickAction(
                title: "Start \(name) Workout",
                icon: "dumbbell.fill",
                targetTab: .training,
                color: .tempoAmber
            ))
        }

        // Study target not met
        if mind.studyMinutesToday < mind.studyTargetMinutes, mind.studyTargetMinutes > 0 {
            let remaining = mind.studyTargetMinutes - mind.studyMinutesToday
            actions.append(QuickAction(
                title: "Start Study Timer (\(remaining)m left)",
                icon: "timer",
                targetTab: .lockdown,
                color: .tempoElectric
            ))
        }

        // No meals logged
        if let logged = fuel.mealsLogged, logged == 0, fuel.isConnected {
            actions.append(QuickAction(
                title: "Log a Meal",
                icon: "fork.knife",
                targetTab: .dashboard,
                color: .tempoViolet
            ))
        } else if !fuel.isConnected {
            actions.append(QuickAction(
                title: "Log a Meal",
                icon: "fork.knife",
                targetTab: .dashboard,
                color: .tempoViolet
            ))
        }

        // Non-negotiables incomplete
        if nonNegotiablesDone < nonNegotiablesTotal, nonNegotiablesTotal > 0 {
            let remaining = nonNegotiablesTotal - nonNegotiablesDone
            actions.append(QuickAction(
                title: "\(remaining) Non-Negotiable\(remaining > 1 ? "s" : "") Left",
                icon: "lock.fill",
                targetTab: .lockdown,
                color: .tempoSignal
            ))
        }

        // Recovery check when low
        if let recovery = body.recoveryScore, recovery < 40 {
            actions.append(QuickAction(
                title: "View Recovery Plan",
                icon: "heart.fill",
                targetTab: .recovery,
                color: .tempoRecoveryRed
            ))
        }

        return Array(actions.prefix(2))
    }

    // MARK: - Weather Data

    // Lightweight weather info for hydration/workout recommendations.

    struct WeatherInfo {
        let temperatureCelsius: Double
        let conditionSymbol: String // SF Symbol name
        let isRaining: Bool
        let recommendation: String?

        var formattedTemperature: String {
            "\(Int(temperatureCelsius))\u{00B0}"
        }

        var hydrationTarget: Double? {
            if temperatureCelsius > 30 {
                return 3.5
            }
            if temperatureCelsius > 25 {
                return 3.0
            }
            return nil
        }
    }

    private(set) var weather: WeatherInfo?

    /// Fetch current weather using WeatherKit.
    func fetchWeather() async {
        #if canImport(WeatherKit)
            do {
                let weatherService = WeatherService.shared
                // Use a default location (or CLLocationManager if authorized)
                // For now, attempt to get weather at a reasonable default
                // This will be enhanced when CoreLocation is authorized
                guard let location = await getCurrentLocation() else {
                    return
                }

                let currentWeather = try await weatherService.weather(for: location)
                let current = currentWeather.currentWeather
                let tempC = current.temperature.converted(to: .celsius).value
                let isRaining = current.condition == .rain ||
                    current.condition == .heavyRain ||
                    current.condition == .drizzle ||
                    current.condition == .thunderstorms

                let conditionSymbol = switch current.condition {
                case .clear,
                     .mostlyClear:
                    "sun.max.fill"
                case .partlyCloudy:
                    "cloud.sun.fill"
                case .cloudy,
                     .mostlyCloudy:
                    "cloud.fill"
                case .rain,
                     .heavyRain,
                     .drizzle:
                    "cloud.rain.fill"
                case .thunderstorms:
                    "cloud.bolt.rain.fill"
                case .snow,
                     .heavySnow:
                    "cloud.snow.fill"
                case .windy:
                    "wind"
                default:
                    "cloud.fill"
                }

                var recommendation: String?
                if tempC > 30 {
                    recommendation = "Stay hydrated -- target 3.5L today"
                } else if isRaining {
                    recommendation = "Indoor workout recommended"
                } else if tempC < 5 {
                    recommendation = "Layer up for outdoor activity"
                }

                weather = WeatherInfo(
                    temperatureCelsius: tempC,
                    conditionSymbol: conditionSymbol,
                    isRaining: isRaining,
                    recommendation: recommendation
                )
            } catch {
                #if DEBUG
                    print("[Dashboard] Weather fetch failed: \(error)")
                #endif
            }
        #endif
    }

    private func getCurrentLocation() async -> CLLocation? {
        // Fetch one fresh location fix ONLY if the user has already granted
        // location access. We deliberately do NOT trigger the permission prompt
        // here — weather is a passive header ornament, so an unsolicited
        // launch-time popup is the wrong UX. Authorization is requested later
        // via an explicit user action (settings toggle). Until then, weather
        // simply stays hidden for users who haven't opted in.
        await OneShotLocationProvider().requestLocationIfAuthorized()
    }

    // MARK: - Non-Negotiables

    private(set) var nonNegotiables: [NonNegotiableItem] = []

    // MARK: - Daily Score

    var dailyScore: Int? {
        computeDailyScore()
    }

    var formattedDailyScore: String {
        guard let dailyScore else {
            return "--"
        }
        return "\(dailyScore)"
    }

    // MARK: - Greeting

    var greeting: String {
        greetingForCurrentTime(firstName: userName)
    }

    var formattedDate: String {
        TempoDateFormatters.dashboardHeader.string(from: Date())
    }

    /// Current wall-clock time formatted "h:mm a" (e.g. "2:30 PM"). Re-reads
    /// `Date()` on every access; views wrap the consuming text in a
    /// `TimelineView(.everyMinute)` so it ticks without a manual refresh.
    var formattedTimeNow: String {
        TempoDateFormatters.timeOnly.string(from: Date())
    }

    // MARK: - Dependencies

    private let healthKit: any HealthKitServiceProtocol
    private let whoop: any WhoopServiceProtocol
    private let calendar: any CalendarServiceProtocol
    private var userName: String?

    /// SwiftData model context for reading today's MealLog records.
    /// Set externally by the View layer (DashboardView injects via modelContext).
    /// `internal` (not `private`) so the `DashboardViewModel+NutritionFetch`
    /// extension in another file can read it.
    var fuelContext: ModelContext?

    // MARK: - Init

    init(services: ServiceContainer) {
        healthKit = services.healthKit
        whoop = services.whoop
        calendar = services.calendar
        userName = nil
    }

    /// Inject the SwiftData context used to read native nutrition logs.
    func setFuelContext(_ context: ModelContext) {
        fuelContext = context
    }

    /// Set the user's display name (called from view layer after querying SwiftData).
    func setUserName(_ name: String?) {
        userName = name
    }

    // MARK: - Refresh

    // Per DATA_FLOW_ARCHITECTURE.md Section 2.1 — fetch from all sources concurrently.
    // HealthKit data is real; Whoop via service protocol; nutrition from native MealLog SwiftData.
    // Body quadrant: Whoop primary, HealthKit fallback for sleep/HRV/RHR.
    // Move quadrant: real steps, energy, workouts, HR from HealthKit.

    private var isRefreshing = false
    /// Timestamp of the last successful refresh. Used to debounce rapid
    /// re-invocations from SwiftUI lifecycle churn (`.task` re-launching
    /// on view re-evaluation, `.onChange(of: connectionState)` racing with
    /// the cold-launch refresh, tab switches re-mounting the view). The
    /// stale fetches would just get cancelled by URLSession and clutter
    /// the log; skipping them is cheaper than firing-then-cancelling.
    private var lastRefreshAt: Date?
    private static let refreshDebounceInterval: TimeInterval = 2.0

    func refresh() async {
        guard !isRefreshing else {
            return
        }
        if let lastRefreshAt,
           Date().timeIntervalSince(lastRefreshAt) < Self.refreshDebounceInterval
        {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let started = Date()
        await DebugTrace.$refreshID.withValue(DebugTrace.newID()) {
            await refreshBody()
        }
        lastRefreshAt = Date()
        #if DEBUG
            let elapsedMs = Date().timeIntervalSince(started) * 1000
            print("\(DebugTrace.prefix)[Dashboard] refresh() complete in \(String(format: "%.0f", elapsedMs))ms")
        #endif
    }

    /// Returns true for `CancellationError` or `NSURLErrorCancelled` (-999)
    /// — the two flavors of "parent task torn down" that surface when the
    /// Dashboard view detaches mid-fetch. Treated as "no new data" rather
    /// than a real failure.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
            && nsError.code == NSURLErrorCancelled
    }

    // Body of refresh() lifted into its own method so we can wrap the entire
    // call chain in a TaskLocal correlation ID. Every downstream log line that
    // calls DebugTrace.prefix will be tagged with the same [T:abc123] marker.
    private func refreshBody() async {
        loadState = .loading

        let today = Date()

        // Fetch Whoop data only when connected.
        // Per INTEGRATION_SPECS.md: Whoop primary, HealthKit fallback.
        let recovery: WhoopRecoveryData?
        let whoopSleepData: WhoopSleepData?
        let cycle: WhoopCycleData?
        #if DEBUG
            print("\(DebugTrace.prefix)[Dashboard] Whoop state: \(whoop.connectionState), isDemoMode: \(whoop.isDemoMode)")
        #endif
        // Track cancellation so we can preserve the previously-good `body`
        // quadrant instead of clobbering it with HealthKit fallbacks. A
        // tab-switch / view-detach triggers NSURLErrorCancelled on every
        // in-flight Whoop request simultaneously.
        //
        // IMPORTANT: only the BODY quadrant depends on Whoop. The Fuel /
        // Mind / Move quadrants (nutrition totals, study, steps) must
        // still rebuild on a cancelled-Whoop refresh — otherwise logging
        // a meal then returning to the Dashboard leaves the Fuel kcal
        // frozen, because the all-cancelled path used to early-return
        // before fetchNutritionTotalsForToday ran.
        var whoopRecoveryCancelled = false
        var whoopSleepCancelled = false
        var whoopCycleCancelled = false
        if whoop.connectionState == .connected {
            // Fire the three Whoop reads CONCURRENTLY. Previously they ran
            // sequentially (recovery → sleep → cycle), which made the cold-
            // launch dashboard refresh ~3× one round-trip (~1.8s measured).
            // They're independent endpoints, so async let runs them in
            // parallel — same pattern the HealthKit block below already
            // uses. Each is awaited in its own do/catch so one failure /
            // cancellation doesn't abort the others and the per-call
            // cancellation flags stay accurate.
            async let recoveryFetch = whoop.fetchRecovery(for: today)
            async let sleepFetch = whoop.fetchSleep(for: today)
            async let cycleFetch = whoop.fetchCycle(for: today)

            do { recovery = try await recoveryFetch }
            catch {
                recovery = nil
                whoopRecoveryCancelled = Self.isCancellation(error)
                #if DEBUG
                    print("\(DebugTrace.prefix)[Dashboard] Whoop recovery fetch failed: \(error)")
                #endif
            }
            do { whoopSleepData = try await sleepFetch }
            catch {
                whoopSleepData = nil
                whoopSleepCancelled = Self.isCancellation(error)
                #if DEBUG
                    print("\(DebugTrace.prefix)[Dashboard] Whoop sleep fetch failed: \(error)")
                #endif
            }
            do { cycle = try await cycleFetch }
            catch {
                cycle = nil
                whoopCycleCancelled = Self.isCancellation(error)
                #if DEBUG
                    print("\(DebugTrace.prefix)[Dashboard] Whoop cycle fetch failed: \(error)")
                #endif
            }
        } else {
            recovery = nil
            whoopSleepData = nil
            cycle = nil
            #if DEBUG
                print("\(DebugTrace.prefix)[Dashboard] Whoop not connected — skipping Whoop data fetch")
            #endif
        }
        // Fetch HealthKit data (always — used as fallback or standalone).
        // Each call is wrapped individually so a single HealthKit failure
        // (e.g. no authorization) doesn't prevent Whoop data from displaying.
        var steps: Int
        var energy: Double
        var heartRates: [HeartRateSample]
        var hrv: Double?
        var rhr: Double?
        var hkSleepData: SleepData
        var workouts: [WorkoutSample]
        // Fetch all HealthKit metrics concurrently, but await each in its own
        // do/catch so one metric's failure can't wipe the others. A bare
        // `async let … ; try await` group aborts on the FIRST throw — and
        // `fetchHeartRate` (descriptor-based) throws HealthKit error code 11
        // ("No data available") on empty results, which on an iPhone without
        // an Apple Watch is *every* refresh. That previously discarded a
        // successfully-fetched step count (the zero-steps bug). HealthKit's
        // empty-result throw is a normal "no data" case, not a fetch failure;
        // each helper already returns a sane empty default on its own, so we
        // just fall back to that default per-metric here.
        async let hkSteps = healthKit.fetchSteps(for: today)
        async let hkActiveEnergy = healthKit.fetchActiveEnergy(for: today)
        async let hkHeartRate = healthKit.fetchHeartRate(for: today)
        async let hkHRV = healthKit.fetchHRV(for: today)
        async let hkRHR = healthKit.fetchRestingHeartRate(for: today)
        async let hkSleep = healthKit.fetchSleepAnalysis(for: today)
        async let hkWorkouts = healthKit.fetchWorkouts(for: today)

        steps = (try? await hkSteps) ?? 0
        energy = (try? await hkActiveEnergy) ?? 0
        heartRates = (try? await hkHeartRate) ?? []
        hrv = try? await hkHRV
        rhr = try? await hkRHR
        hkSleepData = (try? await hkSleep) ?? SleepData(
            totalHours: 0, deepSleepMinutes: 0, remSleepMinutes: 0,
            lightSleepMinutes: 0, awakeMinutes: 0, sleepEfficiency: 0,
            bedtime: nil, wakeTime: nil
        )
        workouts = (try? await hkWorkouts) ?? []

        #if DEBUG
            // Single-line summary of every HK metric outcome — easier to scan
            // than the per-helper logs scattered through HealthKitService.
            // `nil` means the helper threw (HK error 11 / no auth / etc.);
            // numeric values are real fetched data.
            let hrvStr = hrv.map { String(format: "%.1f", $0) } ?? "nil"
            let rhrStr = rhr.map { String(format: "%.1f", $0) } ?? "nil"
            print(
                "\(DebugTrace.prefix)[Dashboard] HK summary steps=\(steps) hr=\(heartRates.count) hrv=\(hrvStr) rhr=\(rhrStr) sleep=\(String(format: "%.1f", hkSleepData.totalHours))h workouts=\(workouts.count)"
            )
        #endif

        // Aggregate today's MealLog records from SwiftData (native nutrition).
        // Refresh the shared 7-day Whoop TDEE average so the no-plan Fuel
        // calorie/macro estimate matches Nutrition Today exactly — both read
        // `whoop.weeklyTDEEAverage`. ensureWeeklyTDEEAverage never throws.
        if whoop.connectionState == .connected {
            await whoop.ensureWeeklyTDEEAverage()
        }
        let nutritionTotals = fetchNutritionTotalsForToday(whoopAvgTDEE: whoop.weeklyTDEEAverage)

        let now = Date()
        let healthKitConnected = steps > 0 || !heartRates.isEmpty || hrv != nil

        // Build Body quadrant
        // Per INTEGRATION_SPECS.md: Whoop primary for recovery/HRV/RHR, HealthKit fallback.
        let hasWhoopData = recovery != nil
        let sleepHours: Double
        let sleepPerf: Double
        let bodyHRV: Double?
        let bodyRHR: Double?

        if let whoopSleepData, whoopSleepData.totalHours > 0 {
            sleepHours = whoopSleepData.totalHours
            sleepPerf = whoopSleepData.sleepScore
        } else {
            sleepHours = hkSleepData.totalHours
            sleepPerf = Double(hkSleepData.sleepScore)
        }

        if let recovery {
            bodyHRV = recovery.hrvRmssd
            bodyRHR = recovery.restingHeartRate
        } else {
            bodyHRV = hrv
            bodyRHR = rhr
        }

        let dataSource: BiometricDataSource = hasWhoopData ? .whoop :
            (healthKitConnected ? .healthKit : .none)

        // Preserve the prior Body snapshot only when ALL Whoop calls were
        // cancelled (tab-switch storm). In that case recovery/sleep/cycle
        // are all nil and rebuilding would flash a blank/HK-fallback card.
        // Everything below this (Fuel/Mind/Move) still rebuilds.
        let allWhoopCancelled = whoopRecoveryCancelled
            && whoopSleepCancelled
            && whoopCycleCancelled
        if !allWhoopCancelled {
            body = BodyQuadrantData(
                recoveryScore: recovery?.score,
                hrv: bodyHRV,
                rhr: bodyRHR,
                sleepHours: sleepHours > 0 ? sleepHours : nil,
                sleepPerformance: sleepPerf > 0 ? sleepPerf : nil,
                strain: cycle?.dayStrain,
                spo2: recovery?.spo2,
                isConnected: hasWhoopData || healthKitConnected,
                lastSync: now,
                dataSource: dataSource
            )
            #if DEBUG
                print(
                    "\(DebugTrace.prefix)[Dashboard] Body built: recovery=\(recovery?.score ?? -1), hrv=\(bodyHRV ?? -1), rhr=\(bodyRHR ?? -1), sleep=\(sleepHours)h, strain=\(cycle?.dayStrain ?? -1), source=\(dataSource.rawValue), connected=\(hasWhoopData || healthKitConnected)"
                )
            #endif
        } else {
            #if DEBUG
                print("\(DebugTrace.prefix)[Dashboard] All Whoop fetches cancelled — preserving prior body, rebuilding Fuel/Mind/Move")
            #endif
        }

        // Persist today's DailyRecovery from the live Whoop fetch. The
        // Dashboard runs on most launches, so it becomes the canonical
        // writer of the day's recovery row. Without this, opening the
        // Dashboard before the Recovery tab left no DailyRecovery for
        // today → the workout ensurer's Week Plan generated with a
        // default (green) zone → "Pull" on a 47%-recovery day that
        // should be "Mobility". One persisted score → every recovery-
        // dependent surface (Week Plan, Recovery tab, Move) agrees.
        if let recovery, let context = fuelContext {
            upsertDailyRecovery(recovery, sleepHours: sleepHours, context: context)
        }

        // Snapshot body composition once/day (Withings → HealthKit) so a 30-day
        // trend exists for the monthly summary (INTELLIGENT_TRAINING_SYSTEM §4.3/§17).
        if let context = fuelContext {
            await snapshotBodyCompositionIfNeeded(context: context)
        }

        // Build Fuel quadrant with recovery-adjusted targets.
        // Targets come from NutritionTarget if present; defaults are used otherwise.
        let baseCalTarget = nutritionTotals.calorieTarget
        let baseProtTarget = nutritionTotals.proteinTarget
        let baseCarbTarget = nutritionTotals.carbsTarget
        let baseFatTarget = nutritionTotals.fatTarget
        let recoveryZone = recovery.map { RecoveryZone(score: $0.score) }
        let isRestDay = false // Will be enriched by refreshTrainingStatus

        let adjusted = NutritionEngine.adjustedTargets(
            baseCalories: baseCalTarget > 0 ? baseCalTarget : 2400,
            baseProtein: baseProtTarget > 0 ? baseProtTarget : 180,
            baseCarbs: baseCarbTarget > 0 ? baseCarbTarget : 280,
            baseFat: baseFatTarget > 0 ? baseFatTarget : 80,
            recoveryZone: recoveryZone,
            currentStrain: cycle?.dayStrain,
            isTrainingDay: true, // Enriched by refreshTrainingStatus
            isRestDay: isRestDay
        )

        let consumedCal = nutritionTotals.calories
        let consumedProt = nutritionTotals.protein
        let consumedCarbs = nutritionTotals.carbs
        let consumedFat = nutritionTotals.fat
        let mealsLoggedCount = nutritionTotals.mealsLogged

        // Generate AI coaching message
        let coaching = NutritionEngine.coachingMessage(
            proteinCurrent: consumedProt, proteinTarget: adjusted.proteinTarget,
            carbsCurrent: consumedCarbs, carbsTarget: adjusted.carbsTarget,
            fatCurrent: consumedFat, fatTarget: adjusted.fatTarget,
            caloriesCurrent: consumedCal, calorieTarget: adjusted.calorieTarget,
            isTrainingDay: true,
            recoveryZone: recoveryZone,
            mealsLogged: mealsLoggedCount
        )

        // `isConnected` drives the Fuel tile's render path: when false, the
        // card shows the "Add Meal" connect prompt. We're connected if the
        // user has either logged a meal OR has a planned meal for today —
        // both mean nutrition is actively in use.
        let nutritionConnected = mealsLoggedCount > 0 || nutritionTotals.nextMeal != nil
        var fuelData = FuelQuadrantData(
            caloriesConsumed: consumedCal,
            calorieTarget: adjusted.calorieTarget,
            proteinGrams: consumedProt,
            proteinTarget: adjusted.proteinTarget,
            carbsGrams: consumedCarbs,
            carbsTarget: adjusted.carbsTarget,
            fatGrams: consumedFat,
            fatTarget: adjusted.fatTarget,
            mealsLogged: mealsLoggedCount > 0 ? mealsLoggedCount : nil,
            mealsPlanned: nutritionTotals.mealsPlanned,
            isConnected: nutritionConnected,
            lastSync: now
        )
        fuelData.adjustedTargets = adjusted
        fuelData.coachingMessage = coaching
        fuelData.activeCaloriesBurned = Int(energy)
        fuelData.estimatedBMR = 1800 // Will use real BMR when UserProfile is available
        fuelData.nextMeal = nutritionTotals.nextMeal
        fuelData.lastEatenAt = nutritionTotals.lastEatenAt
        fuel = fuelData

        // Build Mind quadrant — exams from calendar, study data local
        // Per BUILD_PLAN step 13.2 — exam countdown from real calendar data.
        let threeWeeks = DateInterval(
            start: Calendar.current.startOfDay(for: Date()),
            end: Calendar.current.date(byAdding: .weekOfYear, value: 3, to: Date()) ?? Date()
        )
        let calendarExams = calendar.detectExamDates(in: threeWeeks)
        let examItems = calendarExams.map { exam in
            ExamData(name: exam.subject, date: exam.date)
        }

        // Per BUILD_PLAN 13.2 — feed soonest-exam distance to AccountabilityEngine
        // so its adjustedTarget(+50% study within 7 days) actually fires.
        let resolvedExams = examItems.isEmpty ? mind.exams : examItems
        AccountabilityEngine.daysToNextExam = resolvedExams
            .map(\.daysUntil)
            .filter { $0 >= 0 }
            .min()

        mind = MindQuadrantData(
            studyMinutesToday: mind.studyMinutesToday,
            studyTargetMinutes: mind.studyTargetMinutes,
            currentStreakDays: mind.currentStreakDays,
            exams: resolvedExams
        )

        // Build Move quadrant from real HealthKit data
        let latestHR = heartRates.last.map { Int($0.bpm) }
        let todaysWorkout = workouts.first
        let workoutStatus: DashboardWorkoutStatus
        let workoutName: String?
        let workoutDuration: Int?

        if let workout = todaysWorkout {
            workoutStatus = .completed
            workoutName = workout.workoutType.capitalized
            workoutDuration = Int(workout.durationMinutes)
        } else {
            workoutStatus = .none
            workoutName = nil
            workoutDuration = nil
        }

        // Steps: HealthKit only (Whoop does not expose steps natively).
        // Calories + strain: Whoop only (via backend proxy `fetchCycle`).
        //
        // When all three Whoop fetches were CANCELLED (tab-switch storm),
        // `cycle` is nil — but that's not "no data", it's "we didn't get
        // to fetch it". Preserve the prior strain + active calories so a
        // cancelled refresh doesn't blank them out (same preserve-prior
        // rule the Body quadrant uses). Only fall to nil when Whoop is
        // genuinely unavailable (disconnected), where nil correctly
        // renders "--" instead of a misleading zero.
        let whoopCalories: Int?
        let whoopStrain: Double?
        if let cycle {
            whoopCalories = Int(cycle.caloriesBurned)
            whoopStrain = cycle.dayStrain
        } else if allWhoopCancelled {
            whoopCalories = move.activeCalories
            whoopStrain = move.strain
        } else {
            whoopCalories = nil
            whoopStrain = nil
        }

        move = MoveQuadrantData(
            workoutStatus: workoutStatus,
            workoutName: workoutName,
            workoutDurationMinutes: workoutDuration,
            steps: steps,
            stepsTarget: 10000,
            activeCalories: whoopCalories,
            strain: whoopStrain,
            heartRateCurrent: latestHR,
            isConnected: healthKitConnected || !workouts.isEmpty,
            lastSync: now
        )

        // Non-negotiables are populated by refreshAccountability() from real data.
        // Don't overwrite with fake data here — leave as-is (empty or previously loaded).

        lastRefresh = now
        loadState = .loaded
        updateScoreTrend()
        refreshInsights()
    }

    /// Upserts today's DailyRecovery row from the live Whoop fetch so the
    /// Dashboard is the canonical writer of the day's recovery score.
    /// Idempotent: updates the existing today row in place, else inserts.
    private func upsertDailyRecovery(
        _ recovery: WhoopRecoveryData,
        sleepHours: Double,
        context: ModelContext
    ) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return }
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { row in
                row.date >= today && row.date < tomorrow
            }
        )
        let existing = (try? context.fetch(descriptor))?.first
        if let existing {
            existing.recoveryScore = recovery.score
            existing.recoveryZoneRaw = RecoveryZone(score: recovery.score).rawValue
            existing.hrvRmssd = recovery.hrvRmssd
            existing.restingHR = recovery.restingHeartRate
            if sleepHours > 0 { existing.sleepHours = sleepHours }
        } else {
            let row = DailyRecovery(
                date: today,
                recoveryScore: recovery.score,
                hrvRmssd: recovery.hrvRmssd,
                restingHR: recovery.restingHeartRate,
                sleepHours: sleepHours > 0 ? sleepHours : nil
            )
            context.insert(row)
        }
        try? context.save()
    }

    // MARK: - Body Composition Snapshot (INTELLIGENT_TRAINING_SYSTEM §4.3)

    /// Once-daily snapshot of HealthKit body composition into a BodyComposition
    /// row (date-unique → idempotent upsert). Guarded so we don't re-fetch
    /// HealthKit on every Dashboard refresh — only the first refresh of the day.
    private func snapshotBodyCompositionIfNeeded(context: ModelContext) async {
        let today = Calendar.current.startOfDay(for: Date())
        let guardKey = "lastBodyCompSnapshotDay"
        if let last = UserDefaults.standard.object(forKey: guardKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return // already snapshotted today
        }

        let data: BodyCompositionData
        do {
            data = try await healthKit.fetchBodyComposition()
        } catch {
            #if DEBUG
                print("\(DebugTrace.prefix)[Dashboard] body-comp snapshot skipped — fetch failed: \(error)")
            #endif
            return
        }

        // Nothing to store if HealthKit has no body data at all.
        guard data.weightKg != nil || data.bodyFatPercent != nil || data.leanMassKg != nil else {
            #if DEBUG
                print("\(DebugTrace.prefix)[Dashboard] body-comp snapshot skipped — no HealthKit body data")
            #endif
            return
        }

        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else { return }
        let descriptor = FetchDescriptor<BodyComposition>(
            predicate: #Predicate<BodyComposition> { $0.date >= today && $0.date < tomorrow }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.weightKg = data.weightKg
            existing.bodyFatPercent = data.bodyFatPercent
            existing.leanMassKg = data.leanMassKg
            existing.measurementDate = data.measurementDate
            existing.capturedAt = Date()
        } else {
            context.insert(BodyComposition(
                date: today,
                weightKg: data.weightKg,
                bodyFatPercent: data.bodyFatPercent,
                leanMassKg: data.leanMassKg,
                measurementDate: data.measurementDate
            ))
        }
        try? context.save()
        UserDefaults.standard.set(today, forKey: guardKey)
        #if DEBUG
            print("\(DebugTrace.prefix)[Dashboard] body-comp snapshot: weight=\(data.weightKg ?? -1)kg bf=\(data.bodyFatPercent ?? -1)% lean=\(data.leanMassKg ?? -1)kg")
        #endif
    }

    // MARK: - Training Status Connection

    // Per BUILD_PLAN step 9.8 — Connect training data to Dashboard Move quadrant.
    // Shows workout type and completion from SwiftData WorkoutPlan.

    func refreshTrainingStatus(modelContext: ModelContext) {
        #if DEBUG
            let started = Date()
            defer {
                let elapsedMs = Date().timeIntervalSince(started) * 1000
                print("\(DebugTrace.prefix)[Dashboard] refreshTrainingStatus in \(String(format: "%.0f", elapsedMs))ms")
            }
        #endif
        // Run the SAME ensure path the Training tab uses BEFORE reading.
        // The Dashboard used to only read the persisted row, so it showed
        // a stale plan ("Pull") when the Training tab had regenerated a
        // recovery-adjusted plan ("Mobility" on a low-recovery day) and
        // the daily reset had already run (so the ensurer wasn't going to
        // fire on its own). Calling the ensurer here de-dups today's rows
        // AND reconciles the persisted plan against the current Week Plan
        // (which reflects today's live recovery), so Dashboard and
        // Training resolve to the identical canonical plan.
        DailyResetCoordinator.workoutPlanEnsurer?(modelContext)

        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { plan in
                plan.date >= today && plan.date < tomorrow
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        // Pick the SAME survivor the ensurer keeps: an in-progress session
        // wins, else the most recent. After the ensurer call above there
        // should be exactly one row, but the matching selection keeps this
        // robust if a write lands between the ensure and the fetch.
        let todayPlans = (try? modelContext.fetch(descriptor)) ?? []
        guard let todayPlan = todayPlans.first(where: { $0.status == .inProgress })
            ?? todayPlans.first
        else {
            // No plan found — keep existing HealthKit-based move data
            return
        }

        // Enrich move quadrant with training plan status
        let status: DashboardWorkoutStatus
        let name: String?

        switch todayPlan.status {
        case .completed:
            status = .completed
            name = todayPlan.type.displayName
        case .inProgress:
            status = .planned
            name = todayPlan.type.displayName
        case .planned:
            if todayPlan.type == .rest {
                status = .restDay
                name = nil
            } else {
                status = .planned
                name = todayPlan.type.displayName
            }
        case .skipped:
            status = .none
            name = nil
        }

        // Update move quadrant, preserving HealthKit steps/calories/HR data
        move = MoveQuadrantData(
            workoutStatus: status,
            workoutName: name ?? move.workoutName,
            workoutDurationMinutes: todayPlan.actualDurationMinutes ?? move.workoutDurationMinutes,
            steps: move.steps,
            stepsTarget: move.stepsTarget,
            activeCalories: move.activeCalories,
            strain: move.strain,
            heartRateCurrent: move.heartRateCurrent,
            isConnected: move.isConnected,
            lastSync: move.lastSync
        )

        // Generate meal timing suggestions based on training status (Task 3)
        // Fetch wake time from UserSettings if available
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        let wakeMinutes = (try? modelContext.fetch(settingsDescriptor).first?.wakeTimeMinutes) ?? 420
        fuel.mealTimingSuggestions = NutritionEngine.mealTimingSuggestions(
            workoutName: name ?? move.workoutName,
            workoutStatus: status,
            wakeTimeMinutes: wakeMinutes
        )

        // Re-compute adjusted targets with correct training/rest day status
        let isTrainingDay = status == .planned || status == .completed
        let isRestDayNow = status == .restDay
        if let baseCalTarget = fuel.calorieTarget, baseCalTarget > 0 {
            // Today's logged non-gym activity (football etc.) feeds the real
            // sweat-based hydration bonus. Sum across all of today's sessions so
            // a two-session day isn't undercounted. Nil when nothing logged.
            let todayStart = Calendar.current.startOfDay(for: Date())
            let activityDesc = FetchDescriptor<ActivitySession>(
                predicate: #Predicate<ActivitySession> { $0.date == todayStart }
            )
            let todaySessions = (try? modelContext.fetch(activityDesc)) ?? []
            let activityCal = todaySessions.compactMap(\.caloriesBurned).reduce(0, +)
            let activityMin = todaySessions.compactMap(\.durationMinutes).reduce(0, +)

            let baseTargets = fuel.adjustedTargets
            let recomputed = NutritionEngine.adjustedTargets(
                baseCalories: baseTargets?.baseCalorieTarget ?? baseCalTarget,
                baseProtein: baseTargets?.baseProteinTarget ?? (fuel.proteinTarget ?? 180),
                baseCarbs: baseTargets?.baseCarbsTarget ?? (fuel.carbsTarget ?? 280),
                baseFat: baseTargets?.baseFatTarget ?? (fuel.fatTarget ?? 80),
                recoveryZone: body.recoveryZone,
                currentStrain: body.strain,
                isTrainingDay: isTrainingDay,
                isRestDay: isRestDayNow,
                activityCaloriesBurned: activityCal > 0 ? activityCal : nil,
                activityDurationMin: activityMin > 0 ? activityMin : nil
            )
            fuel.adjustedTargets = recomputed
            fuel.calorieTarget = recomputed.calorieTarget
            fuel.proteinTarget = recomputed.proteinTarget
            fuel.carbsTarget = recomputed.carbsTarget
            fuel.fatTarget = recomputed.fatTarget

            // Recompute coaching message with updated targets
            fuel.coachingMessage = NutritionEngine.coachingMessage(
                proteinCurrent: fuel.proteinGrams ?? 0, proteinTarget: recomputed.proteinTarget,
                carbsCurrent: fuel.carbsGrams ?? 0, carbsTarget: recomputed.carbsTarget,
                fatCurrent: fuel.fatGrams ?? 0, fatTarget: recomputed.fatTarget,
                caloriesCurrent: fuel.caloriesConsumed ?? 0, calorieTarget: recomputed.calorieTarget,
                isTrainingDay: isTrainingDay,
                recoveryZone: body.recoveryZone,
                mealsLogged: fuel.mealsLogged ?? 0
            )
        }
    }

    // MARK: - Accountability Connection

    // Per BUILD_PLAN step 10.8 — Connect accountability data to Dashboard.

    func refreshAccountability(modelContext: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        // Fetch today's accountability
        let accDescriptor = FetchDescriptor<DailyAccountability>(
            predicate: #Predicate { da in
                da.date >= today && da.date < tomorrow
            }
        )
        let accountability = try? modelContext.fetch(accDescriptor).first

        // If no DailyAccountability exists yet, still load non-negotiables from SwiftData
        if accountability == nil {
            let nnDescriptor = FetchDescriptor<NonNegotiable>(
                predicate: #Predicate { $0.isActive }
            )
            if let activeNNs = try? modelContext.fetch(nnDescriptor), !activeNNs.isEmpty {
                nonNegotiables = activeNNs.map { nn in
                    NonNegotiableItem(
                        id: nn.id,
                        title: nn.name,
                        isCompleted: false,
                        category: {
                            switch nn.type {
                            case .train: .move
                            case .meals: .fuel
                            case .study: .mind
                            case .sleep: .body
                            case .steps: .move
                            case .hydration: .fuel
                            case .custom: .mind
                            }
                        }()
                    )
                }
            }
            return
        }

        let accountabilityRecord = accountability!

        // Update Mind quadrant with real study data
        let studyMinutes = accountabilityRecord.totalStudyMinutes
        let studyProgress = accountabilityRecord.nonNegotiableProgress?.first(where: {
            $0.nonNegotiable?.type == .study
        })
        let studyTarget = Int(studyProgress?.targetValue ?? 120)

        // Fetch streak
        let streakDescriptor = FetchDescriptor<Streak>(
            predicate: #Predicate { s in s.typeRaw == "overall" }
        )
        let streak = try? modelContext.fetch(streakDescriptor).first

        mind = MindQuadrantData(
            studyMinutesToday: studyMinutes,
            studyTargetMinutes: studyTarget,
            currentStreakDays: streak?.currentCount ?? 0,
            exams: mind.exams // Preserve existing exam data
        )

        // Per BUILD_PLAN step 11.3 — Auto-track meal non-negotiable from native MealLog data.
        // When MealLog records are present today, update the meals non-negotiable progress.
        if let mealsLogged = fuel.mealsLogged, mealsLogged > 0 {
            if let mealProgress = accountabilityRecord.nonNegotiableProgress?.first(where: {
                $0.nonNegotiable?.type == .meals
            }) {
                let target = mealProgress.targetValue
                if Double(mealsLogged) > mealProgress.currentValue {
                    mealProgress.currentValue = Double(mealsLogged)
                    if Double(mealsLogged) >= target, !mealProgress.isCompleted {
                        mealProgress.isCompleted = true
                        mealProgress.completedAt = Date()
                    }
                    try? modelContext.save()
                }
            }
        }

        // Update non-negotiables from real data
        let progress = accountabilityRecord.nonNegotiableProgress ?? []
        nonNegotiables = progress.compactMap { p in
            guard let nn = p.nonNegotiable else {
                return nil
            }
            let category: NonNegotiableCategory = switch nn.type {
            case .train: .move
            case .meals: .fuel
            case .study: .mind
            case .sleep: .body
            case .steps: .move
            case .hydration: .fuel
            case .custom: .mind
            }
            return NonNegotiableItem(
                id: nn.id,
                title: nn.name,
                isCompleted: p.isCompleted,
                category: category
            )
        }
    }

    // MARK: - Non-Negotiable Progress

    var nonNegotiablesDone: Int {
        nonNegotiables.filter(\.isCompleted).count
    }

    var nonNegotiablesTotal: Int {
        nonNegotiables.count
    }

    var nonNegotiableProgress: Double {
        guard nonNegotiablesTotal > 0 else {
            return 0
        }
        return Double(nonNegotiablesDone) / Double(nonNegotiablesTotal)
    }

    // MARK: - Hydration

    func addHydration(_ ml: Int = 250) {
        fuel.addHydration(ml)
    }

    // MARK: - Meal Timing Refresh

    func refreshMealTiming(wakeTimeMinutes: Int) {
        fuel.mealTimingSuggestions = NutritionEngine.mealTimingSuggestions(
            workoutName: move.workoutName,
            workoutStatus: move.workoutStatus,
            wakeTimeMinutes: wakeTimeMinutes
        )
    }

    // MARK: - Last Sync Display

    var formattedLastSync: String {
        guard let lastRefresh else {
            return ""
        }
        let interval = Date().timeIntervalSince(lastRefresh)
        if interval < 60 {
            return "Last sync: Just now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "Last sync: \(minutes)m ago"
        }
        let hours = minutes / 60
        return "Last sync: \(hours)h ago"
    }

    // MARK: - Insight Engine

    struct DashboardInsight {
        let text: String
        let icon: String
        let detailTitle: String
        let detailFinding: String
        let detailRecommendation: String
    }

    /// All generated insights for rotation display.
    private(set) var insights: [DashboardInsight] = []

    /// Index for rotating through insights.
    private var insightIndex: Int = 0

    var currentInsight: DashboardInsight {
        if insights.isEmpty {
            insights = generateAllInsights()
        }
        guard !insights.isEmpty else {
            return DashboardInsight(
                text: "All systems normal. Execute the plan.",
                icon: "checkmark.shield.fill",
                detailTitle: "Status: Operational",
                detailFinding: "Recovery, sleep, nutrition, and training are all within normal ranges.",
                detailRecommendation: "Stay the course. Hit every target and stack another win."
            )
        }
        return insights[insightIndex % insights.count]
    }

    /// Advance to next insight in the rotation.
    func nextInsight() {
        if insights.isEmpty {
            insights = generateAllInsights()
        }
        guard !insights.isEmpty else {
            return
        }
        insightIndex = (insightIndex + 1) % insights.count
    }

    // MARK: - Cross-Module Insight Engine

    // Generates all applicable insights based on current data.
    // Insights are ordered by priority — urgent warnings first, patterns second, celebrations last.

    private func generateAllInsights() -> [DashboardInsight] {
        var result: [DashboardInsight] = []

        // 1. Low recovery warning
        if let recovery = body.recoveryScore, recovery < 40 {
            result.append(DashboardInsight(
                text: "Your recovery is \(Int(recovery))%. Consider a lighter workout today.",
                icon: "exclamationmark.triangle.fill",
                detailTitle: "Low Recovery Alert",
                detailFinding: "Your recovery score is \(Int(recovery))%, which is in the red zone. Training hard today increases injury risk and delays adaptation.",
                detailRecommendation: "Swap today's session for mobility work or a light walk. Sleep 8+ hours tonight to bounce back."
            ))
        }

        // 2. Sleep vs nutrition cross-pattern
        if let sleep = body.sleepHours, sleep < 7 {
            let mealsLogged = fuel.mealsLogged ?? 0
            let mealsPlanned = fuel.mealsPlanned ?? 3
            if mealsLogged < mealsPlanned {
                result.append(DashboardInsight(
                    text: "Poor sleep + missed meals. When you sleep < 7h, you log fewer meals.",
                    icon: "moon.zzz.fill",
                    detailTitle: "Sleep-Nutrition Link",
                    detailFinding: "You got \(String(format: "%.1f", sleep))h of sleep and have only logged \(mealsLogged)/\(mealsPlanned) meals. Sleep deprivation disrupts hunger hormones and decision-making, leading to skipped meals or poor choices.",
                    detailRecommendation: "Set reminders for your remaining meals today. Prioritize protein-rich options — they require less willpower when you're tired. Hit 8+ hours tonight."
                ))
            } else {
                result.append(DashboardInsight(
                    text: "You slept \(String(format: "%.1f", sleep))h. Prioritize an early bedtime tonight.",
                    icon: "moon.zzz.fill",
                    detailTitle: "Sleep Deficit",
                    detailFinding: "You got \(String(format: "%.1f", sleep)) hours of sleep. Cognitive performance and muscle recovery both drop significantly below 7 hours.",
                    detailRecommendation: "Set an alarm for 10 PM tonight. No screens after 9 PM. Your body does its best repair work between 10 PM and 2 AM."
                ))
            }
        }

        // 3. Recovery vs training cross-pattern
        if let recovery = body.recoveryScore, recovery < 60, move.workoutStatus == .planned {
            let workoutName = move.workoutName ?? "Workout"
            result.append(DashboardInsight(
                text: "Recovery at \(Int(recovery))% with \(workoutName) planned. Reduce volume or intensity.",
                icon: "waveform.path.ecg",
                detailTitle: "Recovery vs Training Tension",
                detailFinding: "Your recovery (\(Int(recovery))%) is below optimal for a full training session. Pushing through yellow/red recovery repeatedly leads to overtraining and plateaus.",
                detailRecommendation: "Do the session but cut volume by 20-30%. Focus on technique over load. If recovery stays low for 3+ days, take an extra rest day."
            ))
        }

        // 4. Study vs sleep cross-pattern
        if let sleep = body.sleepHours, sleep >= 8 {
            if mind.studyMinutesToday == 0, mind.studyTargetMinutes > 0 {
                result.append(DashboardInsight(
                    text: "Great sleep (\(String(format: "%.1f", sleep))h). Your brain is primed for deep focus today.",
                    icon: "brain.head.profile",
                    detailTitle: "Sleep-Study Advantage",
                    detailFinding: "You slept \(String(format: "%.1f", sleep)) hours. Research shows you study 40min more effectively on days with 8+ hours of sleep. Memory consolidation and focus are at peak levels.",
                    detailRecommendation: "Start your study session now while cognitive function is highest. Tackle the hardest material first — your brain can handle it today."
                ))
            }
        }

        // 5. Streak celebration
        if mind.currentStreakDays > 7 {
            result.append(DashboardInsight(
                text: "\(mind.currentStreakDays)-day streak. Habits are becoming automatic.",
                icon: "flame.fill",
                detailTitle: "Streak Momentum",
                detailFinding: "You've maintained consistency for \(mind.currentStreakDays) days straight. Habits formed over 21+ days have an 80% chance of sticking permanently.",
                detailRecommendation: "Don't break the chain. Even a 15-minute session on a bad day keeps the streak alive and the habit strong."
            ))
        }

        // 6. Training day reminder
        if move.workoutStatus == .planned, let workoutName = move.workoutName {
            result.append(DashboardInsight(
                text: "Today is \(workoutName) day. Don't skip it.",
                icon: "dumbbell.fill",
                detailTitle: "Training Day",
                detailFinding: "You have \(workoutName) planned for today and haven't started yet. Consistency beats intensity — showing up matters more than having a perfect session.",
                detailRecommendation: "Get it done. Even a shortened session is better than a skipped one. Start within the next 2 hours for optimal hormone levels."
            ))
        }

        // 7. Nutrition deficit warning
        if let consumed = fuel.caloriesConsumed, let target = fuel.calorieTarget, target > 0 {
            let ratio = Double(consumed) / Double(target)
            let hour = Calendar.current.component(.hour, from: Date())
            if ratio < 0.4, hour >= 16 {
                result.append(DashboardInsight(
                    text: "Only \(consumed) of \(target) kcal logged by \(hour > 12 ? hour - 12 : hour)PM. Fuel up.",
                    icon: "fork.knife",
                    detailTitle: "Calorie Deficit Alert",
                    detailFinding: "You've consumed only \(Int(ratio * 100))% of your calorie target with the day winding down. Under-eating sabotages recovery, muscle growth, and cognitive function.",
                    detailRecommendation: "Eat a high-calorie meal now. Focus on protein + carbs: chicken and rice, pasta with meat, or a large smoothie with protein powder. Don't skip dinner."
                ))
            }
        }

        // 8. Protein behind target
        if let protein = fuel.proteinGrams, let target = fuel.proteinTarget, target > 0 {
            let remaining = target - protein
            if remaining > 40 {
                let hour = Calendar.current.component(.hour, from: Date())
                if hour >= 14 {
                    result.append(DashboardInsight(
                        text: "\(remaining)g protein still needed. Every gram counts for recovery.",
                        icon: "leaf.fill",
                        detailTitle: "Protein Gap",
                        detailFinding: "You need \(remaining)g more protein to hit your \(target)g target. Protein synthesis peaks in the 24h post-training window — missing this window means slower gains.",
                        detailRecommendation: "Quick wins: Greek yogurt (15g), chicken breast (30g), whey shake (25g), or eggs (6g each). Spread across remaining meals."
                    ))
                }
            }
        }

        // 9. Steps encouragement
        if let steps = move.steps {
            let target = move.stepsTarget
            let remaining = target - steps
            let hour = Calendar.current.component(.hour, from: Date())
            if remaining > 0, remaining <= 3000, hour >= 15 {
                result.append(DashboardInsight(
                    text: "\(NumberFormatter.localizedString(from: NSNumber(value: remaining), number: .decimal)) steps to go. A 20-min walk closes the gap.",
                    icon: "figure.walk",
                    detailTitle: "Steps Almost There",
                    detailFinding: "You're \(NumberFormatter.localizedString(from: NSNumber(value: remaining), number: .decimal)) steps away from your \(NumberFormatter.localizedString(from: NSNumber(value: target), number: .decimal)) target. A brisk 20-minute walk covers about 2,000-2,500 steps.",
                    detailRecommendation: "Take a walk after your next meal. Walking post-meal improves blood sugar regulation by 30% and gets you closer to your step goal."
                ))
            }
        }

        // 10. High strain + low nutrition
        if let strain = body.strain, strain > 14 {
            let consumed = fuel.caloriesConsumed ?? 0
            let target = fuel.calorieTarget ?? 2400
            if consumed < target / 2 {
                result.append(DashboardInsight(
                    text: "High strain (\(String(format: "%.1f", strain))) but low fuel. You're burning more than you're replacing.",
                    icon: "flame.circle.fill",
                    detailTitle: "Strain-Fuel Imbalance",
                    detailFinding: "Your day strain is \(String(format: "%.1f", strain)) (high intensity) but you've only consumed \(consumed) of \(target) calories. This creates a recovery debt your body will collect on tomorrow.",
                    detailRecommendation: "Eat a substantial meal with carbs to replenish glycogen. Add 200-300 calories above your normal target on high-strain days."
                ))
            }
        }

        // 11. Perfect day recognition
        if let recovery = body.recoveryScore, recovery >= 70,
           move.workoutStatus == .completed,
           mind.studyMinutesToday >= mind.studyTargetMinutes,
           nonNegotiablesDone >= nonNegotiablesTotal, nonNegotiablesTotal > 0
        {
            result.append(DashboardInsight(
                text: "All targets hit. This is what discipline looks like.",
                icon: "star.fill",
                detailTitle: "Perfect Execution Day",
                detailFinding: "Recovery green, workout done, study target hit, all non-negotiables completed. Days like this are rare — most people never string two together.",
                detailRecommendation: "Protect your sleep tonight to make tomorrow just as good. Perfect days compound — three in a row is where real transformation happens."
            ))
        }

        // Default fallback
        if result.isEmpty {
            result.append(DashboardInsight(
                text: "All systems normal. Execute the plan.",
                icon: "checkmark.shield.fill",
                detailTitle: "Status: Operational",
                detailFinding: "Recovery, sleep, nutrition, and training are all within normal ranges. No corrective actions needed today.",
                detailRecommendation: "Stay the course. Days like this are where discipline compounds. Hit every target and stack another win."
            ))
        }

        return result
    }

    /// Regenerate insights after data changes.
    func refreshInsights() {
        insights = generateAllInsights()
        insightIndex = 0
    }

    // MARK: - Score Breakdown

    struct ScoreBreakdown {
        let recoveryPoints: Double
        let nutritionPoints: Double
        let studyPoints: Double
        let movementPoints: Double
        let recoveryAvailable: Bool
        let nutritionAvailable: Bool
        let studyAvailable: Bool
        let movementAvailable: Bool
    }

    var scoreBreakdown: ScoreBreakdown {
        computeScoreBreakdown()
    }

    private func computeScoreBreakdown() -> ScoreBreakdown {
        let recoveryAvailable = body.isConnected && body.recoveryScore != nil
        let recoveryRaw = body.recoveryScore ?? 0

        let nutritionAvailable = fuel.isConnected && fuel.caloriesConsumed != nil
        let nutritionRaw: Double = {
            guard let consumed = fuel.caloriesConsumed,
                  let target = fuel.calorieTarget, target > 0
            else {
                return 0
            }
            return min(100, (Double(consumed) / Double(target)) * 100)
        }()

        let studyAvailable = true
        let studyRaw: Double = {
            guard mind.studyTargetMinutes > 0 else {
                return 100
            }
            return min(100, (Double(mind.studyMinutesToday) / Double(mind.studyTargetMinutes)) * 100)
        }()

        let movementAvailable = move.isConnected
        let movementRaw: Double = {
            let stepsComponent: Double = {
                guard let steps = move.steps, move.stepsTarget > 0 else {
                    return 0
                }
                return min(50, (Double(steps) / Double(move.stepsTarget)) * 50)
            }()
            let workoutComponent: Double = move.workoutStatus == .completed ? 50 : 0
            return min(100, stepsComponent + workoutComponent)
        }()

        return ScoreBreakdown(
            recoveryPoints: recoveryAvailable ? recoveryRaw * 0.25 : 0,
            nutritionPoints: nutritionAvailable ? nutritionRaw * 0.25 : 0,
            studyPoints: studyAvailable ? studyRaw * 0.25 : 0,
            movementPoints: movementAvailable ? movementRaw * 0.25 : 0,
            recoveryAvailable: recoveryAvailable,
            nutritionAvailable: nutritionAvailable,
            studyAvailable: studyAvailable,
            movementAvailable: movementAvailable
        )
    }

    // MARK: - 7-Day Score Trend

    struct DailyScorePoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: Int
    }

    /// Stores the last 7 days of daily scores for sparkline display.
    /// Loaded from persistent DailyScoreEntry model on launch, updated live.
    private(set) var scoreTrend: [DailyScorePoint] = []

    /// Trend direction for the sparkline arrow display.
    var scoreTrendDirection: TrendDirection {
        guard scoreTrend.count >= 2,
              let last = scoreTrend.last,
              let prev = scoreTrend.dropLast().last
        else {
            return .flat
        }
        let delta = last.score - prev.score
        if delta > 2 {
            return .up
        }
        if delta < -2 {
            return .down
        }
        return .flat
    }

    enum TrendDirection {
        case up
        case down
        case flat

        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .flat: "arrow.right"
            }
        }

        var color: Color {
            switch self {
            case .up: .tempoSuccess
            case .down: .tempoError
            case .flat: .tempoTextSecondary
            }
        }
    }

    /// Load persisted score history from SwiftData.
    func loadScoreHistory(modelContext: ModelContext) {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: Date()))!

        let descriptor = FetchDescriptor<DailyScoreEntry>(
            predicate: #Predicate { entry in
                entry.date >= sevenDaysAgo
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        guard let entries = try? modelContext.fetch(descriptor) else {
            return
        }

        var points = entries.map { DailyScorePoint(date: $0.date, score: $0.score) }

        // Add/update today's live score
        let today = calendar.startOfDay(for: Date())
        points.removeAll { calendar.startOfDay(for: $0.date) == today }
        if let todayScore = computeDailyScore() {
            points.append(DailyScorePoint(date: today, score: todayScore))
        }

        scoreTrend = points.suffix(7).map(\.self)
    }

    /// Persist today's score to SwiftData. Called after refresh when score changes.
    func persistDailyScore(modelContext: ModelContext) {
        guard let score = computeDailyScore() else {
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let descriptor = FetchDescriptor<DailyScoreEntry>(
            predicate: #Predicate { entry in
                entry.date >= today && entry.date < tomorrow
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            // Only update if score changed significantly (>5 points)
            if abs(existing.score - score) > 5 {
                existing.score = score
                existing.updatedAt = Date()
            }
        } else {
            let entry = DailyScoreEntry(date: today, score: score)
            modelContext.insert(entry)
        }

        // Prune entries older than 30 days
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today)!
        let pruneDescriptor = FetchDescriptor<DailyScoreEntry>(
            predicate: #Predicate { entry in
                entry.date < thirtyDaysAgo
            }
        )
        if let oldEntries = try? modelContext.fetch(pruneDescriptor) {
            for entry in oldEntries {
                modelContext.delete(entry)
            }
        }

        try? modelContext.save()
    }

    private func updateScoreTrend() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Keep existing historical points, update/add today
        var updated = scoreTrend.filter { point in
            let pointDay = calendar.startOfDay(for: point.date)
            return pointDay != today && pointDay > calendar.date(byAdding: .day, value: -7, to: today)!
        }

        if let todayScore = computeDailyScore() {
            updated.append(DailyScorePoint(date: today, score: todayScore))
        }

        scoreTrend = updated.sorted { $0.date < $1.date }.suffix(7).map(\.self)
    }

    // MARK: - Daily Score Calculation

    // Per MODULE_DASHBOARD.md Section 2.3

    private func computeDailyScore() -> Int? {
        struct Source {
            let isAvailable: Bool
            let rawScore: Double
        }

        // Recovery component
        let recoveryAvailable = body.isConnected && body.recoveryScore != nil
        let recoveryRaw = body.recoveryScore ?? 0

        // Nutrition component
        let nutritionAvailable = fuel.isConnected && fuel.caloriesConsumed != nil
        let nutritionRaw: Double = {
            guard let consumed = fuel.caloriesConsumed,
                  let target = fuel.calorieTarget, target > 0
            else {
                return 0
            }
            let base = min(100, (Double(consumed) / Double(target)) * 100)
            return max(0, base)
        }()

        // Study component
        let studyAvailable = true // Local data always available
        let studyRaw: Double = {
            guard mind.studyTargetMinutes > 0 else {
                return 100
            }
            return min(100, (Double(mind.studyMinutesToday) / Double(mind.studyTargetMinutes)) * 100)
        }()

        // Movement component
        let movementAvailable = move.isConnected
        let movementRaw: Double = {
            let stepsComponent: Double = {
                guard let steps = move.steps, move.stepsTarget > 0 else {
                    return 0
                }
                return min(50, (Double(steps) / Double(move.stepsTarget)) * 50)
            }()
            let workoutComponent: Double = move.workoutStatus == .completed ? 50 : 0
            return min(100, stepsComponent + workoutComponent)
        }()

        let sources = [
            Source(isAvailable: recoveryAvailable, rawScore: recoveryRaw),
            Source(isAvailable: nutritionAvailable, rawScore: nutritionRaw),
            Source(isAvailable: studyAvailable, rawScore: studyRaw),
            Source(isAvailable: movementAvailable, rawScore: movementRaw),
        ]

        let connected = sources.filter(\.isAvailable)
        guard connected.count >= 2 else {
            return nil
        }

        let baseWeight = 0.25
        let missingCount = 4 - connected.count
        let extraPerSource = (baseWeight * Double(missingCount)) / Double(connected.count)

        var score = 0.0
        for source in connected {
            score += source.rawScore * (baseWeight + extraPerSource)
        }

        let clamped = max(0, min(100, score))
        guard !clamped.isNaN, !clamped.isInfinite else {
            return nil
        }
        return Int(round(clamped))
    }

    // MARK: - Greeting

    // Per UX_COPY_BIBLE.md Section 3.2 — Context-aware greeting.
    // Priority: recovery warning > streak milestone > training schedule > deload > time-of-day fallback.

    private func greetingForCurrentTime(firstName: String?) -> String {
        let name = firstName.map { ", \($0)" } ?? ""

        // Priority 1: Low recovery warning
        if let recovery = body.recoveryScore, recovery < 40 {
            return "Recovery is low. Take it easy today\(name)."
        }

        // Priority 2: Streak milestone (7+)
        if mind.currentStreakDays >= 14 {
            return "\(mind.currentStreakDays)-day streak. Keep the pressure on\(name)."
        }

        // Priority 3: Deload week detection (auto-deload enabled + week aligns)
        if isDeloadWeek {
            return "Deload week. Earn your recovery\(name)."
        }

        // Priority 4: Training schedule context
        if let workoutName = move.workoutName {
            switch move.workoutStatus {
            case .planned:
                return "\(workoutName) day. Finish what you started\(name)."
            case .completed:
                return "\(workoutName) crushed. Recover hard\(name)."
            case .restDay:
                return "Rest day. Recovery is training\(name)."
            case .none:
                break
            }
        } else if move.workoutStatus == .restDay {
            return "Rest day. Recovery is training\(name)."
        }

        // Priority 5: Poor sleep nudge
        if let sleep = body.sleepHours, sleep < 6.5 {
            return "Rough night. Push through anyway\(name)."
        }

        // Priority 6: High recovery = green light
        if let recovery = body.recoveryScore, recovery >= 80 {
            return "Recovery is green. Go all out\(name)."
        }

        // Priority 7: Streak building (2-13 days)
        if mind.currentStreakDays >= 7 {
            return "\(mind.currentStreakDays)-day streak. Don't break the chain\(name)."
        }

        // Fallback: Time-based greeting
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0 ..< 4: return "You should be asleep\(name)."
        case 4 ..< 8: return "Early bird gets the gains\(name)."
        case 8 ..< 12: return "Rise and grind\(name)."
        case 12 ..< 14: return "No half reps this afternoon\(name)."
        case 14 ..< 17: return "Keep the pressure on\(name)."
        case 17 ..< 21: return "Finish what you started\(name)."
        case 21 ..< 24: return "Earn your sleep\(name)."
        default: return "Rise and grind\(name)."
        }
    }

    /// Deload week detection. Uses deload frequency from settings (defaults to every 5 weeks).
    /// Approximation based on week-of-year modulo.
    private(set) var deloadFrequencyWeeks: Int = 5

    private var isDeloadWeek: Bool {
        guard deloadFrequencyWeeks > 0 else {
            return false
        }
        let weekOfYear = Calendar.current.component(.weekOfYear, from: Date())
        return weekOfYear % deloadFrequencyWeeks == 0
    }

    func setDeloadFrequency(_ weeks: Int) {
        deloadFrequencyWeeks = weeks
    }

    // MARK: - Preview Helper

    static func preview() -> DashboardViewModel {
        let vm = DashboardViewModel(services: .mock())
        vm.loadState = .loaded
        vm.lastRefresh = Date()
        vm.body = BodyQuadrantData(
            recoveryScore: 72, hrv: 48, rhr: 62, sleepHours: 7.2,
            sleepPerformance: 78, strain: 12.4, spo2: 97.5,
            isConnected: true, lastSync: Date()
        )
        var previewFuel = FuelQuadrantData(
            caloriesConsumed: 2100, calorieTarget: 2400,
            proteinGrams: 165, proteinTarget: 180,
            carbsGrams: 240, carbsTarget: 280,
            fatGrams: 72, fatTarget: 80,
            mealsLogged: 3, mealsPlanned: 4,
            isConnected: true, lastSync: Date()
        )
        previewFuel.hydrationMl = 1500
        previewFuel.activeCaloriesBurned = 342
        previewFuel.estimatedBMR = 1800
        previewFuel.adjustedTargets = NutritionEngine.adjustedTargets(
            baseCalories: 2400, baseProtein: 180, baseCarbs: 280, baseFat: 80,
            recoveryZone: .green, currentStrain: 12.4,
            isTrainingDay: true, isRestDay: false
        )
        previewFuel.coachingMessage = NutritionEngine.coachingMessage(
            proteinCurrent: 165, proteinTarget: 180,
            carbsCurrent: 240, carbsTarget: 280,
            fatCurrent: 72, fatTarget: 80,
            caloriesCurrent: 2100, calorieTarget: 2400,
            isTrainingDay: true, recoveryZone: .green, mealsLogged: 3
        )
        previewFuel.mealTimingSuggestions = NutritionEngine.mealTimingSuggestions(
            workoutName: "Upper Body Push", workoutStatus: .completed, wakeTimeMinutes: 420
        )
        vm.fuel = previewFuel
        vm.mind = MindQuadrantData(
            studyMinutesToday: 95, studyTargetMinutes: 120,
            currentStreakDays: 12,
            exams: [
                ExamData(name: "Calculus II", date: Date().addingTimeInterval(86400 * 6)),
                ExamData(name: "Physics Lab", date: Date().addingTimeInterval(86400 * 14)),
            ]
        )
        vm.move = MoveQuadrantData(
            workoutStatus: .completed, workoutName: "Upper Body Push",
            workoutDurationMinutes: 55, steps: 8432, stepsTarget: 10000,
            activeCalories: 342, heartRateCurrent: 72,
            isConnected: true, lastSync: Date()
        )
        vm.nonNegotiables = [
            NonNegotiableItem(id: UUID(), title: "Morning workout", isCompleted: true, category: .body),
            NonNegotiableItem(id: UUID(), title: "Hit protein target", isCompleted: false, category: .fuel),
            NonNegotiableItem(id: UUID(), title: "2h study session", isCompleted: false, category: .mind),
            NonNegotiableItem(id: UUID(), title: "10k steps", isCompleted: true, category: .move),
            NonNegotiableItem(id: UUID(), title: "8h sleep", isCompleted: true, category: .body),
        ]
        return vm
    }

    // Native nutrition fetch lives in DashboardViewModel+NutritionFetch.swift.
}

// MARK: - OneShotLocationProvider

/// Bridges `CLLocationManager`'s delegate callbacks into a single `async`
/// call that returns one location fix WHEN access is already authorized. It
/// never triggers the permission prompt (see `requestLocationIfAuthorized`).
/// The manager is retained for the lifetime of the request (held by the
/// provider, which is held by the in-flight continuation closure), avoiding
/// the "fresh manager's `.location` is always nil" bug.
private final class OneShotLocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    /// Returns a single location fix only if access is ALREADY granted; returns
    /// nil otherwise WITHOUT triggering the system permission prompt. Use this
    /// for passive/background features that must not interrupt the user with an
    /// unsolicited authorization dialog. Safe to call from `@MainActor`;
    /// resumes exactly once.
    func requestLocationIfAuthorized() async -> CLLocation? {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
                manager.delegate = self
                manager.desiredAccuracy = kCLLocationAccuracyKilometer
                manager.requestLocation()
            }
        default:
            // Not yet determined, denied, or restricted — do not prompt.
            return nil
        }
    }

    private func finish(with location: CLLocation?) {
        manager.delegate = nil
        continuation?.resume(returning: location)
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last)
    }

    func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        finish(with: nil)
    }
}
