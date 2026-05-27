//
// CoachVoiceControllerTests.swift
// Tempo
//
// Coach v2.1 Phase 7c — covers the stub voice controller's contract
// (used by SwiftUI previews + chat-view tests when wired). The real
// CoachVoiceController is a thin wrapper over VoiceTranscriber which
// needs AVAudioEngine + speech permissions, so it's covered by
// in-Simulator manual QA, not unit tests.
//

@testable import Tempo
import XCTest

@MainActor
final class CoachVoiceControllerTests: XCTestCase {
    func testStub_startSetsIsListening() async {
        let stub = StubCoachVoiceController()
        XCTAssertFalse(stub.isListening)
        await stub.start()
        XCTAssertTrue(stub.isListening)
    }

    func testStub_stopClearsIsListening() async {
        let stub = StubCoachVoiceController()
        await stub.start()
        stub.stop()
        XCTAssertFalse(stub.isListening)
    }

    func testStub_simulatedPartialPopulatesTranscript() async {
        let stub = StubCoachVoiceController()
        stub.simulatePartial = "soccer at seven pm"
        await stub.start()
        XCTAssertEqual(stub.transcribedText, "soccer at seven pm")
    }

    func testStub_emptyByDefault() async {
        let stub = StubCoachVoiceController()
        await stub.start()
        XCTAssertEqual(stub.transcribedText, "")
    }

    func testInlinePillSource_tabLabels() {
        XCTAssertEqual(CoachInlinePillSource.training.tabLabel, "Training")
        XCTAssertEqual(CoachInlinePillSource.nutritionToday.tabLabel, "Nutrition Today")
        XCTAssertEqual(CoachInlinePillSource.recovery.tabLabel, "Recovery")
    }
}
