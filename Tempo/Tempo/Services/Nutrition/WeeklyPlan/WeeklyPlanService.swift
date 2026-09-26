//
// WeeklyPlanService.swift
// Tempo
//
// The week-by-week loop. Sunday's notification (or the in-app Regenerate)
// builds the plan prompt HERE — routine, check-in, pantry, feedback, adaptive
// calories — and hands it to the server job, which works with the app
// closed: Sonnet picks the meals, every home food is checked against USDA,
// the grams are solved so each day hits its macros, and a push says it's
// ready. The phone then saves the plan into the normal WeeklyMealPlan rows
// (next week's plan waits until its Monday) and attaches recipes.
//

import Foundation
import os
import SwiftData

extension Notification.Name {
    /// Posted after a server-built plan was saved as the active plan, so the
    /// Nutrition surfaces reload and run their post-plan passes.
    static let tempoWeeklyPlanApplied = Notification.Name("tempo.nutrition.weeklyPlanApplied")
}

// MARK: - WeeklyPlanService

/// What building a plan needs from the service container.
struct PlanDeps {
    let apiClient: APIClient
    let whoop: any WhoopServiceProtocol
    let trainingEngine: any TrainingEngineProtocol
    let healthKit: any HealthKitServiceProtocol
}

extension PlanDeps {
    @MainActor
    init(_ services: ServiceContainer) {
        self.init(
            apiClient: services.apiClient,
            whoop: services.whoop,
            trainingEngine: services.trainingEngine,
            healthKit: services.healthKit
        )
    }
}

@MainActor
@Observable
final class WeeklyPlanService {
    static let shared = WeeklyPlanService()

    enum Phase: Equatable {
        case idle
        /// The server is building the week starting `weekStart`.
        case building(weekStart: Date)
        /// Ready, for a week that hasn't started yet — saved on its Monday.
        case upcoming(WeeklyPlanPayload, weekStart: Date)
        case failed(String)
    }

    enum BuildError: LocalizedError {
        case noProfile
        case server(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .noProfile: "Set up your fuel profile first."
            case let .server(code): WeeklyPlanService.message(forServerError: code)
            case .timedOut: "The plan is taking longer than usual. It'll show up when it's ready."
            }
        }
    }

    private(set) var phase: Phase = .idle

    /// The job being waited on or saved right now. Launch and foreground both
    /// sync, and saving spans many awaits (recipes), so without this two
    /// syncs — or a sync and Regenerate — could save the same job twice.
    private var inFlightJobID: String?

    private let logger = Logger.nutrition
    private let defaults: UserDefaults
    private enum Key {
        static let pendingJobID = "weeklyPlan.pendingJobID"
        static let appliedJobID = "weeklyPlan.appliedJobID"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Week math

    /// The Monday a plan built now is for: Saturday/Sunday plan NEXT week,
    /// Monday–Friday rebuild the current one.
    nonisolated static func weekStart(for now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sun … 7 = Sat
        let daysSinceMonday = (weekday + 5) % 7
        let thisMonday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let isWeekend = weekday == 1 || weekday == 7
        return isWeekend ? calendar.date(byAdding: .day, value: 7, to: thisMonday) ?? thisMonday : thisMonday
    }

    /// This week's Monday — what the in-app Regenerate rebuilds.
    nonisolated static func currentWeekStart(for now: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let daysSinceMonday = (calendar.component(.weekday, from: today) + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
    }

    nonisolated static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    nonisolated static func date(fromDay string: String, calendar: Calendar = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    nonisolated static func message(forServerError code: String) -> String {
        switch code {
        case "subscription_required": "Weekly plans are a Pro feature."
        case "ai_budget_exhausted": "The AI is at capacity right now. Try again in a bit."
        case "timed out": "The plan build timed out. Try again."
        default: "Couldn't build the plan. Try again."
        }
    }

    // MARK: - Request

    /// Build the prompt on device and hand it to the server. Returns once the
    /// job is queued — fast enough for a background notification action.
    @discardableResult
    func requestWeek(
        checkIn: String? = nil,
        weekStart: Date = WeeklyPlanService.weekStart(),
        intake: MealPlanIntake? = nil,
        modelContext: ModelContext,
        deps: PlanDeps
    ) async throws -> WeeklyPlanJobDTO {
        let prepared = try await prepare(
            checkIn: checkIn,
            weekStart: weekStart,
            intake: intake,
            modelContext: modelContext,
            deps: deps
        )
        let body = WeeklyPlanJobRequest(
            weekStart: Self.dayString(weekStart),
            system: prepared.system,
            prompt: prepared.prompt,
            targets: Dictionary(uniqueKeysWithValues: prepared.targets.map { type, target in
                (type.rawValue, WeeklyPlanJobRequest.Target(
                    kcal: target.calories,
                    proteinG: target.proteinGrams,
                    carbsG: target.carbsGrams,
                    fatG: target.fatGrams
                ))
            }),
            timezone: TimeZone.current.identifier
        )
        let job: WeeklyPlanJobDTO = try await deps.apiClient.request(.createWeeklyPlan(), body: body)
        defaults.set(job.id, forKey: Key.pendingJobID)
        phase = .building(weekStart: weekStart)
        logger.info("[WeeklyPlan] requested job \(job.id, privacy: .public) for \(job.weekStart, privacy: .public)")
        return job
    }

    // MARK: - Sync

    /// Launch / foreground / "plan ready" push: pick up a finished job. A plan
    /// for a week that has started is saved now; a future one waits.
    func sync(modelContext: ModelContext, deps: PlanDeps, now: Date = Date()) async {
        let job: WeeklyPlanJobDTO?
        do {
            job = try await latestJob(apiClient: deps.apiClient)
        } catch {
            logger.info("[WeeklyPlan] sync skipped: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Only the job this phone asked for and hasn't saved yet — never an
        // old one, or one a cancelled Regenerate left running.
        guard let job, job.id == defaults.string(forKey: Key.pendingJobID),
              job.id != defaults.string(forKey: Key.appliedJobID),
              job.id != inFlightJobID
        else {
            if case .building = phase, inFlightJobID == nil {
                phase = .idle
            }
            return
        }
        let weekStart = Self.date(fromDay: job.weekStart) ?? Self.weekStart(for: now)
        switch job.status {
        case .queued,
             .running:
            phase = .building(weekStart: weekStart)
        case .failed:
            phase = .failed(Self.message(forServerError: job.error ?? ""))
            defaults.removeObject(forKey: Key.pendingJobID)
        case .ready:
            guard let plan = job.plan else {
                return
            }
            if weekStart > now {
                phase = .upcoming(plan, weekStart: weekStart)
                return
            }
            inFlightJobID = job.id
            defer { inFlightJobID = nil }
            do {
                _ = try await apply(job, plan: plan, weekStart: weekStart, modelContext: modelContext, deps: deps)
                NotificationCenter.default.post(name: .tempoWeeklyPlanApplied, object: nil)
            } catch {
                logger.error("[WeeklyPlan] apply failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Build now (in-app Regenerate)

    /// Request + wait + save, for the Regenerate button. Throws when the
    /// server path isn't available so the caller can fall back to building
    /// on device.
    func buildNow(
        weekStart: Date,
        intake: MealPlanIntake? = nil,
        modelContext: ModelContext,
        deps: PlanDeps,
        timeout: Duration = .seconds(420),
        onStatus: ((String) -> Void)? = nil
    ) async throws -> WeeklyMealPlan {
        onStatus?("Drafting the week…")
        let job = try await requestWeek(weekStart: weekStart, intake: intake, modelContext: modelContext, deps: deps)
        // Superseded or abandoned → forget the job so a later sync can't
        // apply it over the plan that replaced it.
        inFlightJobID = job.id
        var finished = false
        defer {
            inFlightJobID = nil
            if !finished {
                defaults.removeObject(forKey: Key.pendingJobID)
                phase = .idle
            }
        }
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var polls = 0
        while clock.now < deadline {
            try await Task.sleep(for: .seconds(polls < 6 ? 5 : 8))
            polls += 1
            if polls == 8 {
                onStatus?("Checking every food against USDA…")
            }
            let current: WeeklyPlanJobDTO = try await deps.apiClient.request(.weeklyPlan(id: job.id))
            switch current.status {
            case .queued,
                 .running:
                continue
            case .failed:
                throw BuildError.server(current.error ?? "")
            case .ready:
                guard let plan = current.plan else {
                    throw BuildError.server("ai_unreadable")
                }
                onStatus?("Writing recipes for every meal…")
                let saved = try await apply(
                    current,
                    plan: plan,
                    weekStart: weekStart,
                    intake: intake,
                    modelContext: modelContext,
                    deps: deps
                )
                finished = true
                return saved
            }
        }
        throw BuildError.timedOut
    }

    // MARK: - Internals

    private func latestJob(apiClient: APIClient) async throws -> WeeklyPlanJobDTO? {
        do {
            return try await apiClient.request(.latestWeeklyPlan())
        } catch APIError.notFound {
            return nil
        }
    }

    private func prepare(
        checkIn: String?,
        weekStart: Date,
        intake callerIntake: MealPlanIntake? = nil,
        modelContext: ModelContext,
        deps: PlanDeps,
        forPrompt: Bool = true
    ) async throws -> MealPlanGeneratorService.PreparedWeeklyPlan {
        guard let profile = Self.activeProfile(in: modelContext) else {
            throw BuildError.noProfile
        }
        let (intake, wake) = await NutritionTabViewModel.planInputs(
            intake: callerIntake,
            modelContext: modelContext,
            whoop: deps.whoop,
            trainingEngine: deps.trainingEngine,
            healthKit: deps.healthKit,
            week: weekStart
        )
        let routine = UserDailyPlanProfile.current(in: modelContext)?.weeklyRoutine
        // Saving a finished plan only needs targets + intake, not Maps.
        let nearby = forPrompt ? await NearbyRestaurants.around(routine) : [:]
        return MealPlanGeneratorService(apiClient: deps.apiClient).prepareWeeklyPlan(
            profile: profile,
            whoopTDEE: nil,
            wakeMinutesOverride: wake,
            modelContext: modelContext,
            intake: intake,
            checkIn: checkIn,
            nearbyRestaurants: nearby
        )
    }

    private func apply(
        _ job: WeeklyPlanJobDTO,
        plan: WeeklyPlanPayload,
        weekStart: Date,
        intake: MealPlanIntake? = nil,
        modelContext: ModelContext,
        deps: PlanDeps
    ) async throws -> WeeklyMealPlan {
        guard let profile = Self.activeProfile(in: modelContext) else {
            throw BuildError.noProfile
        }
        guard let json = plan.jsonString else {
            throw BuildError.server("ai_unreadable")
        }
        let generator = MealPlanGeneratorService(apiClient: deps.apiClient)
        let prepared = try await prepare(
            checkIn: nil,
            weekStart: weekStart,
            intake: intake,
            modelContext: modelContext,
            deps: deps,
            forPrompt: false
        )
        let saved = try await generator.finishWeeklyPlan(
            json,
            prepared: prepared,
            profile: profile,
            weekStart: weekStart,
            macrosVerified: true,
            modelContext: modelContext
        )
        saved.inputsFingerprint = MealPlanInputsFingerprint.current(in: modelContext)
        try? modelContext.save()
        defaults.set(job.id, forKey: Key.appliedJobID)
        defaults.removeObject(forKey: Key.pendingJobID)
        phase = .idle
        logger.info("[WeeklyPlan] applied job \(job.id, privacy: .public) for \(job.weekStart, privacy: .public)")
        return saved
    }

    private static func activeProfile(in context: ModelContext) -> DietaryProfile? {
        (try? context.fetch(FetchDescriptor<DietaryProfile>(predicate: #Predicate { $0.isActive == true })))?.first
    }
}
