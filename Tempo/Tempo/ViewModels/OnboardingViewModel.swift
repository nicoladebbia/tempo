//
// OnboardingViewModel.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - OnboardingViewModel

// Per STATE_MACHINES.md Section 10 — 11-step "show then ask" flow with persistence.
// Per BUILD_PLAN step 16.1 — State machine with UserDefaults persistence.
// Reordered: splash→valueDemo→goals→healthKit→auth→profile→training→academic→whoop→nutritrack→notifications→complete

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
    var examSchedule: String = ""

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
    var nutritrackConnected: Bool = false
    var healthkitGranted: Bool = false
    var notificationsGranted: Bool = false

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
        case .trainingSetup:
            true // Optional step
        case .academicSetup:
            true // Optional step
        case .goals:
            primaryGoal != nil
        case .whoopConnect,
             .nutritrackConnect,
             .healthkit,
             .notifications:
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

    // MARK: - Persistence

    // Per STATE_MACHINES.md — UserDefaults for step + data.

    private func persistStep() {
        UserDefaults.standard.set(currentStep.rawValue, forKey: "tempo.onboarding.step")
        persistData()
    }

    private func persistData() {
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
    }
}

// MARK: - OnboardingStep

// "Show then ask" flow — demonstrate value before collecting data.
// splash→valueDemo→goals→healthKit→auth→profile→training→academic→whoop→nutritrack→notifications→complete

enum OnboardingStep: String, Codable, CaseIterable {
    case splash
    case valueDemo
    case goals
    case healthkit
    case auth
    case profile
    case trainingSetup
    case academicSetup
    case whoopConnect
    case nutritrackConnect
    case notifications
    case complete

    var stepNumber: Int {
        switch self {
        case .splash: 0
        case .valueDemo: 1
        case .goals: 2
        case .healthkit: 3
        case .auth: 4
        case .profile: 5
        case .trainingSetup: 6
        case .academicSetup: 7
        case .whoopConnect: 8
        case .nutritrackConnect: 9
        case .notifications: 10
        case .complete: 11
        }
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
             .whoopConnect,
             .nutritrackConnect,
             .notifications:
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
