//
// OnboardingBackendStepTests.swift
// Tempo
//
// ToS / AI-consent steps: DEBUG "Skip Sign In" must not dead-end on a 401,
// and failures surface human copy rather than "Tempo.APIError error 3".
//

@testable import Tempo
import XCTest

@MainActor
final class OnboardingBackendStepTests: XCTestCase {
    // OnboardingViewModel persists its step to UserDefaults; the test host
    // shares defaults with the dev app on this simulator, so put it back.
    private let stepKey = "tempo.onboarding.step"
    private var savedStep: Any?

    override func setUp() async throws {
        savedStep = UserDefaults.standard.object(forKey: stepKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedStep, forKey: stepKey)
    }

    func testDebugBypassSkipsBackendOnlyWhenSignedOut() {
        XCTAssertTrue(OnboardingViewModel.skipsBackendForDebugBypass(isSignedIn: false))
        XCTAssertFalse(OnboardingViewModel.skipsBackendForDebugBypass(isSignedIn: true))
    }

    func testSignedOutToSAcceptanceAdvancesWithoutError() async {
        let vm = OnboardingViewModel()
        vm.currentStep = .tosAccept
        await vm.submitToSAcceptance(apiClient: APIClient(), isSignedIn: false)
        XCTAssertNil(vm.tosAcceptError)
        XCTAssertNotEqual(vm.currentStep, .tosAccept)
    }

    func testSignedOutAIConsentRecordsChoiceAndAdvances() async {
        let vm = OnboardingViewModel()
        vm.currentStep = .aiConsent
        await vm.setAIConsent(true, apiClient: APIClient(), isSignedIn: false)
        XCTAssertNil(vm.aiConsentError)
        XCTAssertTrue(vm.aiConsentGranted)
        XCTAssertNotEqual(vm.currentStep, .aiConsent)
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
