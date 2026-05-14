//
// OnboardingViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - OnboardingViewModel

// Per STATE_MACHINES.md Section 10 — "show then ask" flow with persistence.
// Per BUILD_PLAN step 16.1 — State machine with UserDefaults persistence.
// Reordered: splash→valueDemo→goals→healthKit→auth→profile→training→academic→whoop→notifications→complete

@Observable
@MainActor
final class OnboardingViewModel {
    // MARK: - State

    // Per STATE_MACHINES.md Section 10

    var currentStep: OnboardingStep {
        didSet { persistStep() }
    }

    var isAnimatingTransition = false

    // Profile data
    var displayName: String = ""
    var username: String = ""

    // Training data
    var doesTrain: Bool?
    var trainingTypes: Set<String> = []
    var daysPerWeek: Int = 4
    var preferredSplit: String?
    var experienceLevel: String?

    // Academic data
    var university: String = ""
    var yearOfStudy: String?
    /// Legacy free-text exam schedule. Kept for backward-compatibility with users
    /// onboarded before the structured `classBlocks` schema landed; new users
    /// fill out classBlocks instead. The daily-plan engine flips
    /// `examScheduleMigratedAt` on the profile when this has been resolved.
    var examSchedule: String = ""

    // MARK: - Daily plan profile (per INTELLIGENCE_REMEDIATION_PLAN.md §8)

    /// Wake time as minutes-from-midnight. Default 07:00. Captured in the
    /// `.dailyRhythm` step.
    var wakeTimeMinutes: Int = 7 * 60

    /// Target nightly sleep duration in hours. Default 8.0.
    var sleepTargetHours: Double = 8.0

    var chronotype: Chronotype = .neutral

    /// Term-bounded weekly class schedule. Empty by default.
    var classBlocks: [OnboardingClassBlock] = []

    /// Optional weekly work shifts.
    var workBlocks: [OnboardingWorkBlock] = []

    var termStartDate: Date?
    var termEndDate: Date?

    var trainingTimePreference: TrainingTimePreference = .anyFree

    var eatingWindowPreset: EatingWindowPreset = .twelveTwelve
    var eatingWindowStartMinutes: Int = 8 * 60
    var eatingWindowEndMinutes: Int = 20 * 60
    var breakfastSkipped: Bool = false
    var postWorkoutMandatory: Bool = true

    /// Pomodoro length in minutes (25 / 50 / 90 standard; 5..120 allowed).
    var studySessionLengthMinutes: Int = 50

    var weekendDifferential: WeekendDifferential = .lateWake

    // Goals data
    var primaryGoal: String?
    var studyTarget: Int = 120
    var mealTarget: Int = 4
    var timeWasters: Set<String> = []
    var eveningStartTime: Date = {
        var components = DateComponents()
        components.hour = 19
        components.minute = 30
        return Calendar.current.date(from: components) ?? Date()
    }()

    // Integration states
    var whoopConnected: Bool = false
    var healthkitGranted: Bool = false
    var notificationsGranted: Bool = false
    /// User chose to enable AI features in the onboarding aiConsent step.
    /// Per AI_INTELLIGENCE_ENGINE.md §11.3.
    var aiConsentGranted: Bool = false
    var aiConsentError: String?

    var onComplete: (() -> Void)?

    // MARK: - Computed

    var totalSteps: Int {
        OnboardingStep.allCases.count
    }

    var stepNumber: Int {
        currentStep.stepNumber
    }

    var progress: Double {
        Double(currentStep.stepNumber) / Double(totalSteps)
    }

    var canGoBack: Bool {
        currentStep != .splash && currentStep != .auth && currentStep != .complete
    }

    var canContinue: Bool {
        switch currentStep {
        case .splash,
             .valueDemo,
             .auth:
            true
        case .profile:
            !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
                !username.trimmingCharacters(in: .whitespaces).isEmpty
        case .trainingSetup,
             .academicSetup,
             .dailyRhythm,
             .classSchedule,
             .eatingWindow,
             .studyPreferences,
             .trainingPreferences,
             .weekendMode:
            true // Optional steps
        case .goals:
            primaryGoal != nil
        case .whoopConnect,
             .healthkit,
             .notifications,
             .aiConsent:
            true // Optional steps
        case .complete:
            true
        }
    }

    // MARK: - Init

    // Per STATE_MACHINES.md — Resume from last completed step on kill.

    init() {
        if let savedStep = UserDefaults.standard.string(forKey: "tempo.onboarding.step"),
           let step = OnboardingStep(rawValue: savedStep)
        {
            currentStep = step
        } else if UserDefaults.standard.string(forKey: "tempo.onboarding.step") != nil {
            // Migration: saved step doesn't match any valid case (e.g. removed "arena").
            // Reset to splash so user re-starts onboarding cleanly.
            currentStep = .splash
            UserDefaults.standard.removeObject(forKey: "tempo.onboarding.step")
        } else {
            currentStep = .splash
        }
        loadPersistedData()
    }

    // MARK: - Navigation

    func advance() {
        guard let next = currentStep.next else {
            complete()
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = next
        }
    }

    func goBack() {
        guard canGoBack, let prev = currentStep.previous else {
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = prev
        }
    }

    func skip() {
        advance()
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: "tempo.onboarding.complete")
        UserDefaults.standard.removeObject(forKey: "tempo.onboarding.step")
        UserDefaults.standard.removeObject(forKey: "tempo.onboarding.data")
        onComplete?()
    }

    // MARK: - Daily plan profile

    /// Build a `UserDailyPlanProfile` SwiftData row from the in-memory
    /// onboarding state. Caller is responsible for inserting it into the
    /// model context. Per INTELLIGENCE_REMEDIATION_PLAN.md §8.
    func buildDailyPlanProfile() -> UserDailyPlanProfile {
        let classes = classBlocks.map {
            ClassBlock(
                id: $0.id,
                weekday: $0.weekday,
                startMinuteOfDay: $0.startMinuteOfDay,
                endMinuteOfDay: $0.endMinuteOfDay,
                courseCode: $0.courseCode,
                courseName: $0.courseName,
                location: $0.location
            )
        }
        let works = workBlocks.map {
            WorkBlock(
                id: $0.id,
                weekday: $0.weekday,
                startMinuteOfDay: $0.startMinuteOfDay,
                endMinuteOfDay: $0.endMinuteOfDay,
                label: $0.label
            )
        }
        return UserDailyPlanProfile(
            wakeTimeMinutes: wakeTimeMinutes,
            sleepTargetHours: sleepTargetHours,
            chronotype: chronotype,
            classBlocks: classes,
            workBlocks: works,
            termStartDate: termStartDate,
            termEndDate: termEndDate,
            trainingTimePreference: trainingTimePreference,
            eatingWindowPreset: eatingWindowPreset,
            eatingWindowStartMinutes: eatingWindowStartMinutes,
            eatingWindowEndMinutes: eatingWindowEndMinutes,
            breakfastSkipped: breakfastSkipped,
            postWorkoutMandatory: postWorkoutMandatory,
            studySessionLengthMinutes: studySessionLengthMinutes,
            weekendDifferential: weekendDifferential,
            // Stamp the migration sentinel — a user who finished the structured
            // schedule step has by definition resolved the legacy examSchedule
            // free-text (even if they left classBlocks empty).
            examScheduleMigratedAt: classBlocks.isEmpty && examSchedule.isEmpty ? nil : Date()
        )
    }

    /// Push the captured daily-plan profile to the backend. Failures don't
    /// block onboarding — the local SwiftData copy survives and a later
    /// background sync will retry. Per ADR-014 (offline-first).
    @MainActor
    func syncDailyPlanProfile(apiClient: APIClient) async {
        let dto = OnboardingDailyPlanProfileDTO(
            wake_time_minutes: wakeTimeMinutes,
            sleep_target_hours: sleepTargetHours,
            chronotype: chronotype.rawValue,
            training_time_preference: trainingTimePreference.rawValue,
            eating_window_preset: eatingWindowPreset.rawValue,
            eating_window_start_minutes: eatingWindowStartMinutes,
            eating_window_end_minutes: eatingWindowEndMinutes,
            breakfast_skipped: breakfastSkipped,
            post_workout_mandatory: postWorkoutMandatory,
            study_session_length_minutes: studySessionLengthMinutes,
            weekend_differential: weekendDifferential.rawValue,
            term_start_date: termStartDate,
            term_end_date: termEndDate,
            class_blocks: classBlocks.map {
                OnboardingDailyPlanProfileDTO.ClassBlock(
                    weekday: $0.weekday,
                    start_minute_of_day: $0.startMinuteOfDay,
                    end_minute_of_day: $0.endMinuteOfDay,
                    course_code: $0.courseCode,
                    course_name: $0.courseName,
                    location: $0.location
                )
            },
            work_blocks: workBlocks.map {
                OnboardingDailyPlanProfileDTO.WorkBlock(
                    weekday: $0.weekday,
                    start_minute_of_day: $0.startMinuteOfDay,
                    end_minute_of_day: $0.endMinuteOfDay,
                    label: $0.label
                )
            }
        )
        do {
            let _: EmptyResponse = try await apiClient.request(
                APIEndpoint<EmptyResponse>.setDailyPlanProfile(),
                body: dto
            )
        } catch {
            // Non-fatal — surface in logs for diagnosis but keep onboarding flowing.
            print("[onboarding] syncDailyPlanProfile failed: \(error.localizedDescription)")
        }
    }

    // MARK: - AI Consent (AI_INTELLIGENCE_ENGINE.md §11.3)

    /// Record the user's AI-data-sharing decision on the backend. Called from
    /// the `.aiConsent` onboarding step. On success, advances the step.
    /// On failure, sets `aiConsentError` so the View can surface a retry.
    @MainActor
    func setAIConsent(_ granted: Bool, apiClient: APIClient) async {
        aiConsentError = nil
        do {
            let body = AIConsentRequestDTO(consented: granted)
            let _: AIConsentResponseDTO = try await apiClient.request(
                APIEndpoint<AIConsentResponseDTO>.setAIConsent(),
                body: body
            )
            aiConsentGranted = granted
            advance()
        } catch {
            aiConsentError = error.localizedDescription
        }
    }

    // MARK: - Persistence

    // Per STATE_MACHINES.md — UserDefaults for step + data.

    private func persistStep() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: "tempo.onboarding.step")
        persistData()
    }

    private func persistData() {
        // Encode class/work blocks as JSON so UserDefaults can store them.
        let classBlocksData = (try? JSONEncoder().encode(classBlocks)) ?? Data()
        let workBlocksData = (try? JSONEncoder().encode(workBlocks)) ?? Data()

        let data: [String: Any] = [
            "displayName": displayName,
            "username": username,
            "doesTrain": doesTrain ?? false,
            "trainingTypes": Array(trainingTypes),
            "daysPerWeek": daysPerWeek,
            "preferredSplit": preferredSplit ?? "",
            "experienceLevel": experienceLevel ?? "",
            "university": university,
            "primaryGoal": primaryGoal ?? "",
            "studyTarget": studyTarget,
            "mealTarget": mealTarget,
            "timeWasters": Array(timeWasters),
            // Daily plan profile fields.
            "wakeTimeMinutes": wakeTimeMinutes,
            "sleepTargetHours": sleepTargetHours,
            "chronotype": chronotype.rawValue,
            "classBlocks": classBlocksData,
            "workBlocks": workBlocksData,
            "termStartDate": termStartDate as Any,
            "termEndDate": termEndDate as Any,
            "trainingTimePreference": trainingTimePreference.rawValue,
            "eatingWindowPreset": eatingWindowPreset.rawValue,
            "eatingWindowStartMinutes": eatingWindowStartMinutes,
            "eatingWindowEndMinutes": eatingWindowEndMinutes,
            "breakfastSkipped": breakfastSkipped,
            "postWorkoutMandatory": postWorkoutMandatory,
            "studySessionLengthMinutes": studySessionLengthMinutes,
            "weekendDifferential": weekendDifferential.rawValue,
        ]
        UserDefaults.standard.set(data, forKey: "tempo.onboarding.data")
    }

    private func loadPersistedData() {
        guard let data = UserDefaults.standard.dictionary(forKey: "tempo.onboarding.data") else {
            return
        }
        displayName = data["displayName"] as? String ?? ""
        username = data["username"] as? String ?? ""
        doesTrain = data["doesTrain"] as? Bool
        trainingTypes = Set(data["trainingTypes"] as? [String] ?? [])
        daysPerWeek = data["daysPerWeek"] as? Int ?? 4
        preferredSplit = data["preferredSplit"] as? String
        experienceLevel = data["experienceLevel"] as? String
        university = data["university"] as? String ?? ""
        primaryGoal = data["primaryGoal"] as? String
        studyTarget = data["studyTarget"] as? Int ?? 120
        mealTarget = data["mealTarget"] as? Int ?? 4
        timeWasters = Set(data["timeWasters"] as? [String] ?? [])
        // Daily plan profile.
        wakeTimeMinutes = data["wakeTimeMinutes"] as? Int ?? wakeTimeMinutes
        sleepTargetHours = data["sleepTargetHours"] as? Double ?? sleepTargetHours
        if let raw = data["chronotype"] as? String, let v = Chronotype(rawValue: raw) {
            chronotype = v
        }
        if let blob = data["classBlocks"] as? Data,
           let decoded = try? JSONDecoder().decode([OnboardingClassBlock].self, from: blob)
        {
            classBlocks = decoded
        }
        if let blob = data["workBlocks"] as? Data,
           let decoded = try? JSONDecoder().decode([OnboardingWorkBlock].self, from: blob)
        {
            workBlocks = decoded
        }
        termStartDate = data["termStartDate"] as? Date
        termEndDate = data["termEndDate"] as? Date
        if let raw = data["trainingTimePreference"] as? String, let v = TrainingTimePreference(rawValue: raw) {
            trainingTimePreference = v
        }
        if let raw = data["eatingWindowPreset"] as? String, let v = EatingWindowPreset(rawValue: raw) {
            eatingWindowPreset = v
        }
        eatingWindowStartMinutes = data["eatingWindowStartMinutes"] as? Int ?? eatingWindowStartMinutes
        eatingWindowEndMinutes = data["eatingWindowEndMinutes"] as? Int ?? eatingWindowEndMinutes
        breakfastSkipped = data["breakfastSkipped"] as? Bool ?? false
        postWorkoutMandatory = data["postWorkoutMandatory"] as? Bool ?? true
        studySessionLengthMinutes = data["studySessionLengthMinutes"] as? Int ?? studySessionLengthMinutes
        if let raw = data["weekendDifferential"] as? String, let v = WeekendDifferential(rawValue: raw) {
            weekendDifferential = v
        }
    }
}

// MARK: - In-memory value types for class/work blocks

/// View-model representation of `ClassBlock`. Stays a value type so onboarding
/// can edit it freely without touching SwiftData mid-flow; the final commit
/// step materialises these into `ClassBlock` model rows.
struct OnboardingClassBlock: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var weekday: Int          // 1 = Sunday … 7 = Saturday
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var courseCode: String
    var courseName: String?
    var location: String?
}

struct OnboardingWorkBlock: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var weekday: Int
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var label: String
}

// MARK: - OnboardingStep

// "Show then ask" flow — demonstrate value before collecting data.
// splash→valueDemo→goals→healthKit→auth→profile→training→academic→whoop→notifications→complete

enum OnboardingStep: String, Codable, CaseIterable {
    case splash
    case valueDemo
    case goals
    case healthkit
    case auth
    case profile
    case trainingSetup
    case academicSetup
    // ── Daily plan profile (INTELLIGENCE_REMEDIATION_PLAN.md §8) ──
    /// Wake time + sleep target + chronotype.
    case dailyRhythm
    /// Term-bounded weekly class schedule + optional work shifts.
    case classSchedule
    /// Intermittent-fasting / eating-window preferences.
    case eatingWindow
    /// Pomodoro length + study session preferences.
    case studyPreferences
    /// Preferred training time of day.
    case trainingPreferences
    /// Weekend differential.
    case weekendMode
    // ──────────────────────────────────────────────
    case whoopConnect
    case notifications
    /// AI data-sharing consent. Required by AI_INTELLIGENCE_ENGINE.md §11.3 and
    /// gated by SubscriptionMiddleware on the backend — without consent every
    /// AI route returns 402 ai_consent_required.
    /// Per INTELLIGENCE_REMEDIATION_PLAN.md §4.6.
    case aiConsent
    case complete

    var stepNumber: Int {
        // Derived from declaration order so adding/reordering steps doesn't
        // require touching this switch.
        Self.allCases.firstIndex(of: self) ?? 0
    }

    var isRequired: Bool {
        switch self {
        case .auth,
             .profile,
             .goals: true
        default: false
        }
    }

    var isSkippable: Bool {
        switch self {
        case .healthkit,
             .trainingSetup,
             .academicSetup,
             .dailyRhythm,
             .classSchedule,
             .eatingWindow,
             .studyPreferences,
             .trainingPreferences,
             .weekendMode,
             .whoopConnect,
             .notifications,
             .aiConsent:
            true
        default:
            false
        }
    }

    var next: OnboardingStep? {
        let all = OnboardingStep.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else {
            return nil
        }
        return all[idx + 1]
    }

    var previous: OnboardingStep? {
        let all = OnboardingStep.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else {
            return nil
        }
        return all[idx - 1]
    }
}
