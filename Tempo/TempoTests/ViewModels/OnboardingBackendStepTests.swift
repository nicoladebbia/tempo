//
// OnboardingBackendStepTests.swift
// Tempo
//
// ToS acceptance (on the sign-in step): DEBUG "Skip Sign In" must not dead-end on a 401,
// and failures surface human copy rather than "Tempo.APIError error 3".
//

@testable import Tempo
import XCTest

@MainActor
final class OnboardingBackendStepTests: XCTestCase {
    // OnboardingViewModel persists its step to UserDefaults; the test host
    // shares defaults with the dev app on this simulator, so put it back.
    private let stepKey = "tempo.onboarding.step"
    private let dataKey = "tempo.onboarding.data"
    private var savedStep: Any?
    private var savedData: Any?

    override func setUp() async throws {
        savedStep = UserDefaults.standard.object(forKey: stepKey)
        savedData = UserDefaults.standard.object(forKey: dataKey)
        UserDefaults.standard.removeObject(forKey: dataKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedStep, forKey: stepKey)
        UserDefaults.standard.set(savedData, forKey: dataKey)
    }

    func testDebugBypassSkipsBackendOnlyWhenSignedOut() {
        XCTAssertTrue(OnboardingViewModel.skipsBackendForDebugBypass(isSignedIn: false))
        XCTAssertFalse(OnboardingViewModel.skipsBackendForDebugBypass(isSignedIn: true))
    }

    func testSignedOutToSAcceptanceAdvancesWithoutError() async {
        let vm = OnboardingViewModel()
        vm.currentStep = .auth
        await vm.submitToSAcceptance(apiClient: APIClient(), isSignedIn: false)
        XCTAssertNil(vm.tosAcceptError)
        XCTAssertEqual(vm.currentStep, .aboutYou)
    }

    func testAlreadyRecordedToSAcceptanceDoesNotAskTheServerAgain() async {
        let vm = OnboardingViewModel()
        vm.currentStep = .auth
        vm.tosRecorded = true
        // A signed-in call would hit the network; a recorded acceptance goes straight on.
        await vm.submitToSAcceptance(apiClient: APIClient(), isSignedIn: true)
        XCTAssertNil(vm.tosAcceptError)
        XCTAssertEqual(vm.currentStep, .aboutYou)
    }

    func testReadableMessageUsesAPIErrorCopy() {
        XCTAssertEqual(
            OnboardingViewModel.readableMessage(for: APIError.unauthorized),
            APIError.unauthorized.userMessage
        )
        XCTAssertFalse(
            OnboardingViewModel.readableMessage(for: APIError.networkError("x")).contains("APIError")
        )
    }
}
