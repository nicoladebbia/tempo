import SwiftUI

// MARK: - Onboarding View Model
// Per STATE_MACHINES.md Section 10 — 12-step linear flow with persistence.
// Per BUILD_PLAN step 16.1 — State machine with UserDefaults persistence.

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
    var doesTrain: Bool? = nil
    var trainingTypes: Set<String> = []
    var daysPerWeek: Int = 4
    var preferredSplit: String? = nil
    var experienceLevel: String? = nil

    // Academic data
    var university: String = ""
    var yearOfStudy: String? = nil
    var examSchedule: String = ""

    // Goals data
    var primaryGoal: String? = nil
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

    var totalSteps: Int { 12 }

    var stepNumber: Int { currentStep.stepNumber }

    var progress: Double {
        Double(currentStep.stepNumber) / Double(totalSteps)
    }

    var canGoBack: Bool {
        currentStep != .splash && currentStep != .auth
    }

    var canContinue: Bool {
        switch currentStep {
        case .splash, .auth:
            return true
        case .profile:
            return !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !username.trimmingCharacters(in: .whitespaces).isEmpty
        case .trainingSetup:
            return true  // Optional step
        case .academicSetup:
            return true  // Optional step
        case .goals:
            return primaryGoal != nil
        case .whoopConnect, .nutritrackConnect, .healthkit, .notifications:
            return true  // Optional steps
        case .arena:
            return true
        case .complete:
            return true
        }
    }

    // MARK: - Init
    // Per STATE_MACHINES.md — Resume from last completed step on kill.

    init() {
        if let savedStep = UserDefaults.standard.string(forKey: "tempo.onboarding.step"),
           let step = OnboardingStep(rawValue: savedStep) {
            self.currentStep = step
        } else {
            self.currentStep = .splash
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
        guard canGoBack, let prev = currentStep.previous else { return }
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
        guard let data = UserDefaults.standard.dictionary(forKey: "tempo.onboarding.data") else { return }
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

// MARK: - Onboarding Step Enum
// Per STATE_MACHINES.md Section 10

enum OnboardingStep: String, Codable, CaseIterable {
    case splash
    case auth
    case profile
    case trainingSetup
    case academicSetup
    case goals
    case whoopConnect
    case nutritrackConnect
    case healthkit
    case notifications
    case arena
    case complete

    var stepNumber: Int {
        switch self {
        case .splash: return 0
        case .auth: return 1
        case .profile: return 2
        case .trainingSetup: return 3
        case .academicSetup: return 4
        case .goals: return 5
        case .whoopConnect: return 6
        case .nutritrackConnect: return 7
        case .healthkit: return 8
        case .notifications: return 9
        case .arena: return 10
        case .complete: return 11
        }
    }

    var isRequired: Bool {
        switch self {
        case .auth, .profile, .goals: return true
        default: return false
        }
    }

    var isSkippable: Bool {
        switch self {
        case .trainingSetup, .academicSetup, .whoopConnect, .nutritrackConnect, .healthkit, .notifications:
            return true
        default:
            return false
        }
    }

    var next: OnboardingStep? {
        let all = OnboardingStep.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }

    var previous: OnboardingStep? {
        let all = OnboardingStep.allCases
        guard let idx = all.firstIndex(of: self), idx > 0 else { return nil }
        return all[idx - 1]
    }
}
