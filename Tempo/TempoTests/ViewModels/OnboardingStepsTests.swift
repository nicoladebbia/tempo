//
// OnboardingStepsTests.swift
// TempoTests
//
// The six-step onboarding: where each older saved step resumes, what the progress bar counts,
// what lets a person continue, and what is saved for later.
//

@testable import Tempo
import XCTest

@MainActor
final class OnboardingStepsTests: XCTestCase {
    // OnboardingViewModel persists to UserDefaults, which the test host shares with the dev app
    // on this simulator: put it back.
    private let stepKey = "tempo.onboarding.step"
    private let dataKey = "tempo.onboarding.data"
    private var savedStep: Any?
    private var savedData: Any?

    override func setUp() async throws {
        savedStep = UserDefaults.standard.object(forKey: stepKey)
        savedData = UserDefaults.standard.object(forKey: dataKey)
        UserDefaults.standard.removeObject(forKey: stepKey)
        UserDefaults.standard.removeObject(forKey: dataKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedStep, forKey: stepKey)
        UserDefaults.standard.set(savedData, forKey: dataKey)
    }

    // MARK: - The flow

    func testTheFlowHasSixStepsInOrder() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.valueDemo, .goals, .auth, .aboutYou, .permissions, .complete]
        )
    }

    func testTheProgressBarCountsTheFourStepsBetweenTheHookAndTheFinish() {
        XCTAssertNil(OnboardingStep.valueDemo.progressPosition)
        XCTAssertEqual(OnboardingStep.goals.progressPosition, 1)
        XCTAssertEqual(OnboardingStep.auth.progressPosition, 2)
        XCTAssertEqual(OnboardingStep.aboutYou.progressPosition, 3)
        XCTAssertEqual(OnboardingStep.permissions.progressPosition, 4)
        XCTAssertNil(OnboardingStep.complete.progressPosition)
    }

    func testAFreshInstallStartsOnTheHook() {
        XCTAssertEqual(OnboardingViewModel().currentStep, .valueDemo)
    }

    func testAdvanceWalksTheWholeFlowAndCompletes() {
        let completeKey = "tempo.onboarding.complete"
        let before = UserDefaults.standard.object(forKey: completeKey)
        defer { UserDefaults.standard.set(before, forKey: completeKey) }
        let vm = OnboardingViewModel()
        var finished = false
        vm.onComplete = { finished = true }
        for expected in [OnboardingStep.goals, .auth, .aboutYou, .permissions, .complete] {
            vm.advance()
            XCTAssertEqual(vm.currentStep, expected)
        }
        vm.advance()
        XCTAssertTrue(finished)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: completeKey))
    }

    func testNoBackButtonOnTheHookOrTheFinish() {
        let vm = OnboardingViewModel()
        XCTAssertFalse(vm.canGoBack)
        vm.currentStep = .auth
        XCTAssertTrue(vm.canGoBack)
        vm.currentStep = .complete
        XCTAssertFalse(vm.canGoBack)
    }

    // MARK: - Resuming an older run

    func testEveryOlderSavedStepResumesSomewhere() {
        let older = [
            "splash", "valueDemo", "goals", "healthkit", "auth", "profile", "identity", "trainingSetup",
            "academicSetup", "dailyRhythm", "classSchedule", "eatingWindow", "studyPreferences",
            "trainingPreferences", "weekendMode", "whoopConnect", "notifications", "tosAccept", "aiConsent",
            "complete",
        ]
        let expected: [String: OnboardingStep] = [
            "splash": .valueDemo, "valueDemo": .valueDemo, "goals": .goals, "aiConsent": .complete,
            "complete": .complete,
        ]
        for raw in older {
            // Anything between the goal and the finish returns to sign-in, where the terms are asked.
            XCTAssertEqual(OnboardingStep.resumed(fromSaved: raw), expected[raw] ?? .auth, raw)
        }
    }

    func testTheNewStepNamesResumeAsThemselves() {
        for step in OnboardingStep.allCases {
            XCTAssertEqual(OnboardingStep.resumed(fromSaved: step.rawValue), step)
        }
    }

    func testAnUnknownSavedStepStartsOver() {
        XCTAssertEqual(OnboardingStep.resumed(fromSaved: "arena"), .valueDemo)
    }

    func testTheViewModelResumesFromASavedOlderStep() {
        UserDefaults.standard.set("whoopConnect", forKey: stepKey)
        XCTAssertEqual(OnboardingViewModel().currentStep, .auth)
    }

    // MARK: - Continue

    func testTheGoalStepNeedsAGoal() {
        let vm = OnboardingViewModel()
        vm.currentStep = .goals
        XCTAssertFalse(vm.canContinue)
        vm.primaryGoal = .loseFat
        XCTAssertTrue(vm.canContinue)
    }

    func testSigningInNeedsTheTermsTicked() {
        let vm = OnboardingViewModel()
        vm.currentStep = .auth
        XCTAssertFalse(vm.canContinue)
        vm.tosAccepted = true
        XCTAssertTrue(vm.canContinue)
    }

    func testAboutYouNeedsANameAndAValidUsername() {
        let vm = OnboardingViewModel()
        vm.currentStep = .aboutYou
        XCTAssertFalse(vm.canContinue)
        vm.displayName = "Nicola"
        vm.username = "ni"
        XCTAssertFalse(vm.canContinue, "a username needs 3 characters")
        vm.username = "nicola"
        XCTAssertTrue(vm.canContinue)
        vm.username = "nicola!"
        XCTAssertFalse(vm.canContinue, "letters, numbers and underscores only")
    }

    func testThePermissionsAreAllOptional() {
        let vm = OnboardingViewModel()
        vm.currentStep = .permissions
        XCTAssertTrue(vm.canContinue)
    }

    // MARK: - Username

    func testAUsernameIsSuggestedFromTheName() {
        XCTAssertEqual(OnboardingViewModel.suggestedUsername(from: "Nicola De Bbia"), "nicoladebbia")
        XCTAssertEqual(OnboardingViewModel.suggestedUsername(from: "  Zoë-Ann  "), "zoëann")
        XCTAssertEqual(OnboardingViewModel.suggestedUsername(from: ""), "")
        XCTAssertEqual(OnboardingViewModel.suggestedUsername(from: String(repeating: "a", count: 50)).count, 30)
    }

    func testTheHandleFollowsTheNameUntilThePersonTypesTheirOwn() {
        let vm = OnboardingViewModel()
        vm.displayName = "Nic"
        XCTAssertEqual(vm.username, "nic")
        vm.displayName = "Nicola Rossi"
        XCTAssertEqual(vm.username, "nicolarossi")
        vm.username = "nico_r"
        vm.usernameEdited = true
        vm.displayName = "Nicola R"
        XCTAssertEqual(vm.username, "nico_r", "their own handle is kept")
    }

    func testASavedHandleThatIsNotTheSuggestionCountsAsTheirOwn() {
        let first = OnboardingViewModel()
        first.displayName = "Nicola"
        first.username = "nico_r"
        first.currentStep = .aboutYou
        let second = OnboardingViewModel()
        XCTAssertEqual(second.username, "nico_r")
        XCTAssertTrue(second.usernameEdited)
        second.displayName = "Nicola Rossi"
        XCTAssertEqual(second.username, "nico_r")
    }

    func testUsernameRules() {
        XCTAssertTrue(OnboardingViewModel.isValidUsername("nic_ola9"))
        XCTAssertFalse(OnboardingViewModel.isValidUsername("ab"))
        XCTAssertFalse(OnboardingViewModel.isValidUsername("has space"))
        XCTAssertFalse(OnboardingViewModel.isValidUsername(String(repeating: "a", count: 31)))
    }

    // MARK: - What is saved for later

    func testTheAnswersAreSavedForTheProfileAndTheTrainingDefaultsStayTheSame() throws {
        let vm = OnboardingViewModel()
        vm.displayName = "Nicola"
        vm.username = "nicola"
        vm.identityLabel = "Runner"
        vm.primaryGoal = .buildMuscle
        vm.currentStep = .permissions // saving happens on every step change
        let saved = try XCTUnwrap(UserDefaults.standard.dictionary(forKey: dataKey))
        XCTAssertEqual(saved["displayName"] as? String, "Nicola")
        XCTAssertEqual(saved["identityLabel"] as? String, "Runner")
        XCTAssertEqual(saved["primaryGoal"] as? String, "build_muscle")
        // Not asked any more: the same defaults a person who tapped through the training step got.
        XCTAssertEqual(saved["daysPerWeek"] as? Int, 4)
        XCTAssertEqual(saved["experienceLevel"] as? String, "")
        XCTAssertEqual(saved["wakeTimeMinutes"] as? Int, 7 * 60)
        XCTAssertEqual(saved["eatingWindowPreset"] as? String, EatingWindowPreset.twelveTwelve.rawValue)
    }

    func testTheGoalAndTheTermsSurviveARelaunch() {
        let first = OnboardingViewModel()
        first.primaryGoal = .stayHealthy
        first.tosRecorded = true
        first.currentStep = .aboutYou
        let second = OnboardingViewModel()
        XCTAssertEqual(second.currentStep, .aboutYou)
        XCTAssertEqual(second.primaryGoal, .stayHealthy)
        XCTAssertTrue(second.tosRecorded)
        XCTAssertTrue(second.tosAccepted, "the box is already ticked when the terms are recorded")
    }

    // MARK: - Goal

    func testAGoalReadsBothTheNewAndTheOlderSavedNames() {
        XCTAssertEqual(PrimaryGoal(saved: "lose_fat"), .loseFat)
        XCTAssertEqual(PrimaryGoal(saved: "Build Muscle"), .buildMuscle)
        XCTAssertEqual(PrimaryGoal(saved: "Improve Performance"), .performance)
        XCTAssertEqual(PrimaryGoal(saved: "All-Around"), .allAround)
        XCTAssertNil(PrimaryGoal(saved: ""))
        XCTAssertNil(PrimaryGoal(saved: nil))
        XCTAssertNil(PrimaryGoal(saved: "something else"))
    }

    func testEveryGoalHasWordsAndASymbol() {
        for goal in PrimaryGoal.allCases {
            XCTAssertFalse(goal.title.isEmpty)
            XCTAssertFalse(goal.detail.isEmpty)
            XCTAssertFalse(goal.icon.isEmpty)
        }
    }
}
