//
// OnboardingViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - OnboardingViewModel

// Per STATE_MACHINES.md Section 10 — "show then ask" flow with persistence.
// Six steps: hook, goal, sign in (with the terms), about you, permissions, ready.
// Everything else is asked later, in the place it is needed; the answers that used to be
// collected here start from the defaults below.

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
    var displayName: String = "" {
        didSet {
            // The handle follows the name until the person types in the handle field.
            if !usernameEdited {
                username = Self.suggestedUsername(from: displayName)
            }
        }
    }

    var username: String = ""
    /// The person typed their own handle: stop suggesting one from the name.
    var usernameEdited = false

    // Identity ("What best describes you?")
    var identityLabel: String = OnboardingViewModel.identityLabels[0]

    /// Canonical, ordered identity options. Single source of truth shared by
    /// the onboarding picker and Settings > Profile.
    static let identityLabels: [String] = [
        "Athlete", "Student", "Student-Athlete", "Coach", "Personal Trainer",
        "Bodybuilder", "Runner", "Cyclist", "Swimmer", "Combat Sports",
        "Team Sport Player", "Weekend Warrior", "Military / First Responder",
        "Office Worker", "Remote Worker", "Entrepreneur", "Artist / Creative",
        "Parent", "Retiree", "General Fitness",
    ]

    /// The name shown for a stored identity label. The stored label stays English (it is saved and compared).
    static func identityDisplayName(_ label: String) -> String {
        switch label {
        case "Athlete": String(localized: "Athlete")
        case "Student": String(localized: "Student")
        case "Student-Athlete": String(localized: "Student-Athlete")
        case "Coach": String(localized: "Coach")
        case "Personal Trainer": String(localized: "Personal Trainer")
        case "Bodybuilder": String(localized: "Bodybuilder")
        case "Runner": String(localized: "Runner")
        case "Cyclist": String(localized: "Cyclist")
        case "Swimmer": String(localized: "Swimmer")
        case "Combat Sports": String(localized: "Combat Sports")
        case "Team Sport Player": String(localized: "Team Sport Player")
        case "Weekend Warrior": String(localized: "Weekend Warrior")
        case "Military / First Responder": String(localized: "Military / First Responder")
        case "Office Worker": String(localized: "Office Worker")
        case "Remote Worker": String(localized: "Remote Worker")
        case "Entrepreneur": String(localized: "Entrepreneur")
        case "Artist / Creative": String(localized: "Artist / Creative")
        case "Parent": String(localized: "Parent")
        case "Retiree": String(localized: "Retiree")
        case "General Fitness": String(localized: "General Fitness")
        default: label
        }
    }

    // Training defaults. Onboarding no longer asks: these are what a person who tapped through
    // the old training step got (4 days a week, so Upper/Lower; no experience level, so the
    // strength model treats them as a beginner). Both are set in Settings > Training.
    var daysPerWeek: Int = 4
    var preferredSplit: String?
    var experienceLevel: String?

    // MARK: - Daily plan profile (per INTELLIGENCE_REMEDIATION_PLAN.md §8)

    // Not asked any more: each field keeps the default below and the Ready step saves it, so
    // the daily-plan engine, the meal planner and the reminders read the same row as before.
    // Wake time and bedtime live in Settings > Schedule, the eating window in Settings > Diet
    // Profile, the training time in Settings > Training, the study length in Settings > Focus Timer.

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

    // Goal
    var primaryGoal: PrimaryGoal?

    // Permissions
    var healthkitGranted: Bool = false
    var notificationsGranted: Bool = false

    /// The "I agree to the Terms of Service and Privacy Policy" checkbox on the sign-in step.
    /// Sign in with Apple stays disabled until it is ticked. Per LAUNCH_PUNCH_LIST.md §3.5.
    var tosAccepted: Bool = false
    /// The server has the acceptance (it answers 451 until it does). Saved, so going back to
    /// the sign-in step never asks twice.
    var tosRecorded: Bool = false
    var tosAcceptError: String?

    var onComplete: (() -> Void)?

    // MARK: - Computed

    /// Steps the progress bar counts: everything between the hook and the finish.
    var progressSteps: [OnboardingStep] {
        OnboardingStep.countedSteps
    }

    var canGoBack: Bool {
        currentStep != .valueDemo && currentStep != .complete
    }

    var canContinue: Bool {
        switch currentStep {
        case .valueDemo,
             .permissions,
             .complete:
            true
        case .goals:
            primaryGoal != nil
        case .auth:
            tosAccepted
        case .aboutYou:
            !displayName.trimmingCharacters(in: .whitespaces).isEmpty && Self.isValidUsername(username)
        }
    }

    /// 3 to 30 letters, numbers or underscores.
    static func isValidUsername(_ raw: String) -> Bool {
        let username = raw.trimmingCharacters(in: .whitespaces)
        guard (3 ... 30).contains(username.count) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return username.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// A handle to start from, made from a name: "Nicola De Bbia" becomes "nicoladebbia".
    static func suggestedUsername(from name: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let letters = name.lowercased().unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(letters).prefix(30))
    }

    // MARK: - Init

    // Per STATE_MACHINES.md — Resume from last completed step on kill.

    init() {
        let key = Self.stepKey
        if let saved = UserDefaults.standard.string(forKey: key) {
            // A step saved by the older 20-step flow moves to the nearest step of this one.
            currentStep = OnboardingStep.resumed(fromSaved: saved)
        } else {
            currentStep = .valueDemo
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
        UserDefaults.standard.removeObject(forKey: Self.stepKey)
        // "tempo.onboarding.data" stays until ContentView has built the
        // profile from it (name, split, experience); it clears it then.
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
            // Stamp the migration sentinel — onboarding has captured the
            // structured class schedule (even if empty), so the legacy
            // free-text examSchedule path no longer applies.
            examScheduleMigratedAt: Date()
        )
    }

    /// Save the captured daily-plan profile to SwiftData as the ONE local
    /// row. Re-entering the complete step (app killed on it, state restoration)
    /// or re-running onboarding never leaves a duplicate: stray rows are removed,
    /// so readers that take `UserDailyPlanProfile.current(in:)` see one row.
    ///
    /// `replacingExisting` decides what happens to a row that is already there.
    /// The six-step onboarding no longer asks for the wake time, eating window or
    /// schedule, so the finish screen passes `false` and keeps what the person
    /// already set; the answers here are only defaults. Returns `true` when a new
    /// row was made (the caller pushes it to the backend then).
    @discardableResult
    func persistDailyPlanProfile(in context: ModelContext, replacingExisting: Bool = true) throws -> Bool {
        let existing = (try? context.fetch(FetchDescriptor<UserDailyPlanProfile>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        ))) ?? []
        guard let keep = existing.first else {
            context.insert(buildDailyPlanProfile())
            try context.save()
            return true
        }
        for duplicate in existing.dropFirst() {
            context.delete(duplicate)
        }
        if replacingExisting {
            apply(to: keep, in: context)
        }
        try context.save()
        return false
    }

    /// Overwrite `profile` with the in-memory onboarding state. Class / work
    /// blocks are replaced with fresh rows (fresh ids — `ClassBlock.id` is
    /// unique, so reusing the onboarding ids next to the old rows would collide).
    private func apply(to profile: UserDailyPlanProfile, in context: ModelContext) {
        profile.wakeTimeMinutes = wakeTimeMinutes
        profile.sleepTargetHours = sleepTargetHours
        profile.chronotype = chronotype
        profile.termStartDate = termStartDate
        profile.termEndDate = termEndDate
        profile.trainingTimePreference = trainingTimePreference
        profile.eatingWindowPreset = eatingWindowPreset
        profile.eatingWindowStartMinutes = eatingWindowStartMinutes
        profile.eatingWindowEndMinutes = eatingWindowEndMinutes
        profile.breakfastSkipped = breakfastSkipped
        profile.postWorkoutMandatory = postWorkoutMandatory
        profile.studySessionLengthMinutes = studySessionLengthMinutes
        profile.weekendDifferential = weekendDifferential
        profile.examScheduleMigratedAt = Date()
        profile.updatedAt = Date()

        for block in profile.classBlocks {
            context.delete(block)
        }
        for block in profile.workBlocks {
            context.delete(block)
        }
        profile.classBlocks = classBlocks.map {
            ClassBlock(
                weekday: $0.weekday,
                startMinuteOfDay: $0.startMinuteOfDay,
                endMinuteOfDay: $0.endMinuteOfDay,
                courseCode: $0.courseCode,
                courseName: $0.courseName,
                location: $0.location
            )
        }
        profile.workBlocks = workBlocks.map {
            WorkBlock(
                weekday: $0.weekday,
                startMinuteOfDay: $0.startMinuteOfDay,
                endMinuteOfDay: $0.endMinuteOfDay,
                label: $0.label
            )
        }
    }

    /// Push the captured daily-plan profile to the backend. Failures don't
    /// block onboarding — the local SwiftData copy survives and a later
    /// background sync will retry. Per ADR-014 (offline-first).
    @MainActor
    func syncDailyPlanProfile(apiClient: APIClient) async {
        let dto = OnboardingDailyPlanProfileDTO(
            wakeTimeMinutes: wakeTimeMinutes,
            sleepTargetHours: sleepTargetHours,
            chronotype: chronotype.rawValue,
            trainingTimePreference: trainingTimePreference.rawValue,
            eatingWindowPreset: eatingWindowPreset.rawValue,
            eatingWindowStartMinutes: eatingWindowStartMinutes,
            eatingWindowEndMinutes: eatingWindowEndMinutes,
            breakfastSkipped: breakfastSkipped,
            postWorkoutMandatory: postWorkoutMandatory,
            studySessionLengthMinutes: studySessionLengthMinutes,
            weekendDifferential: weekendDifferential.rawValue,
            termStartDate: termStartDate,
            termEndDate: termEndDate,
            classBlocks: classBlocks.map {
                OnboardingDailyPlanProfileDTO.ClassBlock(
                    weekday: $0.weekday,
                    startMinuteOfDay: $0.startMinuteOfDay,
                    endMinuteOfDay: $0.endMinuteOfDay,
                    courseCode: $0.courseCode,
                    courseName: $0.courseName,
                    location: $0.location
                )
            },
            workBlocks: workBlocks.map {
                OnboardingDailyPlanProfileDTO.WorkBlock(
                    weekday: $0.weekday,
                    startMinuteOfDay: $0.startMinuteOfDay,
                    endMinuteOfDay: $0.endMinuteOfDay,
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

    // MARK: - ToS Acceptance (LAUNCH_PUNCH_LIST.md §3.5)

    /// Record the user's ToS+Privacy acceptance on the backend, right after Sign in with Apple
    /// (the server answers 451 to everything else until it has it). On success, advances the
    /// step. On failure, sets `tosAcceptError` so the View can surface a retry.
    @MainActor
    func submitToSAcceptance(apiClient: APIClient, isSignedIn: Bool = true) async {
        tosAcceptError = nil
        if tosRecorded || Self.skipsBackendForDebugBypass(isSignedIn: isSignedIn) {
            advance()
            return
        }
        do {
            let body = AcceptToSRequestDTO(documentVersion: nil)
            let _: AcceptToSResponseDTO = try await apiClient.request(
                APIEndpoint<AcceptToSResponseDTO>.acceptToS(),
                body: body
            )
            tosRecorded = true
            persistData()
            advance()
        } catch {
            tosAcceptError = Self.readableMessage(for: error)
        }
    }

    /// DEBUG "Skip Sign In" leaves no JWT, so these authenticated calls
    /// can only 401. Record the choice locally and move on instead of
    /// dead-ending the simulator flow. Release builds always hit the backend
    /// (the auth step has no skip there).
    static func skipsBackendForDebugBypass(isSignedIn: Bool) -> Bool {
        #if DEBUG
            return !isSignedIn
        #else
            return false
        #endif
    }

    /// Human copy instead of "The operation couldn't be completed.
    /// (Tempo.APIError error 3.)".
    static func readableMessage(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? error.localizedDescription
    }

    // MARK: - Persistence

    // Per STATE_MACHINES.md — UserDefaults for step + data.

    static let stepKey = "tempo.onboarding.step"
    static let dataKey = "tempo.onboarding.data"

    private func persistStep() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: Self.stepKey)
        persistData()
    }

    private func persistData() {
        // Encode class/work blocks as JSON so UserDefaults can store them.
        let classBlocksData = (try? JSONEncoder().encode(classBlocks)) ?? Data()
        let workBlocksData = (try? JSONEncoder().encode(workBlocks)) ?? Data()

        // NOTE: every value here MUST be a property-list type. A boxed
        // `Optional.none` (e.g. `someOptional as Any` when nil) makes
        // `UserDefaults.set` raise NSInvalidArgumentException and the app
        // hard-crashes. Optional dates are therefore inserted only when set.
        var data: [String: Any] = [
            "displayName": displayName,
            "username": username,
            "identityLabel": identityLabel,
            "daysPerWeek": daysPerWeek,
            "preferredSplit": preferredSplit ?? "",
            "experienceLevel": experienceLevel ?? "",
            "primaryGoal": primaryGoal?.rawValue ?? "",
            "tosRecorded": tosRecorded,
            // Daily plan profile fields.
            "wakeTimeMinutes": wakeTimeMinutes,
            "sleepTargetHours": sleepTargetHours,
            "chronotype": chronotype.rawValue,
            "classBlocks": classBlocksData,
            "workBlocks": workBlocksData,
            "trainingTimePreference": trainingTimePreference.rawValue,
            "eatingWindowPreset": eatingWindowPreset.rawValue,
            "eatingWindowStartMinutes": eatingWindowStartMinutes,
            "eatingWindowEndMinutes": eatingWindowEndMinutes,
            "breakfastSkipped": breakfastSkipped,
            "postWorkoutMandatory": postWorkoutMandatory,
            "studySessionLengthMinutes": studySessionLengthMinutes,
            "weekendDifferential": weekendDifferential.rawValue,
        ]
        if let termStartDate {
            data["termStartDate"] = termStartDate
        }
        if let termEndDate {
            data["termEndDate"] = termEndDate
        }
        UserDefaults.standard.set(data, forKey: Self.dataKey)
    }

    private func loadPersistedData() {
        guard let data = UserDefaults.standard.dictionary(forKey: Self.dataKey) else {
            return
        }
        displayName = data["displayName"] as? String ?? ""
        username = data["username"] as? String ?? ""
        // A saved handle that is not the one the name would give was typed by the person.
        usernameEdited = !username.isEmpty && username != Self.suggestedUsername(from: displayName)
        identityLabel = data["identityLabel"] as? String ?? OnboardingViewModel.identityLabels[0]
        daysPerWeek = data["daysPerWeek"] as? Int ?? 4
        preferredSplit = data["preferredSplit"] as? String
        experienceLevel = data["experienceLevel"] as? String
        primaryGoal = PrimaryGoal(saved: data["primaryGoal"] as? String)
        tosRecorded = data["tosRecorded"] as? Bool ?? false
        tosAccepted = tosRecorded
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


// MARK: - OnboardingClassBlock

/// View-model representation of `ClassBlock`. Stays a value type so onboarding
/// can edit it freely without touching SwiftData mid-flow; the final commit
/// step materialises these into `ClassBlock` model rows.
struct OnboardingClassBlock: Codable, Identifiable, Hashable {
    var id = UUID()
    var weekday: Int // 1 = Sunday … 7 = Saturday
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var courseCode: String
    var courseName: String?
    var location: String?
}

// MARK: - OnboardingWorkBlock

struct OnboardingWorkBlock: Codable, Identifiable, Hashable {
    var id = UUID()
    var weekday: Int
    var startMinuteOfDay: Int
    var endMinuteOfDay: Int
    var label: String
}


// MARK: - OnboardingStep

// "Show then ask" flow — demonstrate value before collecting data.
// valueDemo → goals → auth → aboutYou → permissions → complete

enum OnboardingStep: String, Codable, CaseIterable {
    case valueDemo
    case goals
    /// Sign in with Apple, with the Terms of Service and Privacy Policy checkbox. Required by
    /// Apple Guideline 5.1.1 and GDPR Article 7. The backend gates all non-auth / non-tos routes
    /// behind ToSGateMiddleware (451) until the acceptance is posted, which happens right
    /// after sign-in. Per LAUNCH_PUNCH_LIST.md §3.5.
    case auth
    /// Name, username and "what best describes you".
    case aboutYou
    /// Health, notifications and location, each optional.
    case permissions
    case complete

    /// The steps the progress bar counts: everything between the hook and the finish.
    static let countedSteps: [OnboardingStep] = [.goals, .auth, .aboutYou, .permissions]

    /// 1-based place among the counted steps; nil on the hook and the finish.
    var progressPosition: Int? {
        Self.countedSteps.firstIndex(of: self).map { $0 + 1 }
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

    /// Where to resume from a saved step name. The older flow had 20 steps; whatever was saved
    /// maps to the nearest step of this one. Every step after the goal and before the end goes
    /// back to sign-in, because the terms are now accepted there and an older run may have
    /// reached those steps without them (the sign-in step shows "already signed in" and only
    /// asks for the checkbox).
    static func resumed(fromSaved raw: String) -> OnboardingStep {
        switch raw {
        case "splash",
             "valueDemo":
            .valueDemo
        case "goals":
            .goals
        case "aiConsent",
             "complete":
            .complete
        case "healthkit",
             "auth",
             "profile",
             "identity",
             "trainingSetup",
             "academicSetup",
             "dailyRhythm",
             "classSchedule",
             "eatingWindow",
             "studyPreferences",
             "trainingPreferences",
             "weekendMode",
             "whoopConnect",
             "notifications",
             "tosAccept":
            .auth
        default:
            OnboardingStep(rawValue: raw) ?? .valueDemo
        }
    }
}
