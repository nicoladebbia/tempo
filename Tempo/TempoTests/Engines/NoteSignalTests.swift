//
// NoteSignalTests.swift
// Tempo
//
// Free-text note → prescription signal classification. Pure (no SwiftData) via
// the extracted `TrainingViewModel.classifyNote`. Locks the deterministic
// keyword rules that feed the weight engine: pain/too-hard/form hold
// conservative, "too easy" nudges up, and the strict guards that keep bare
// "easy"/"light" from false-tripping the risky upward direction.
//

@testable import Tempo
import XCTest

final class NoteSignalTests: XCTestCase {
    private func classify(_ s: String) -> TrainingViewModel.NoteSignalSummary {
        TrainingViewModel.classifyNote(s.lowercased())
    }

    func testPainDetected() {
        XCTAssertTrue(classify("left shoulder hurt on the last rep").pain)
        XCTAssertTrue(classify("sharp pinch in the knee").pain)
        XCTAssertTrue(classify("felt a shoulder tweak").pain)
    }

    func testTooHardDetected() {
        XCTAssertTrue(classify("way too heavy, failed the 3rd rep").tooHard)
        XCTAssertTrue(classify("couldn't lock it out").tooHard)
        XCTAssertTrue(classify("barely got 5").tooHard)
    }

    func testFormIssueDetected() {
        XCTAssertTrue(classify("form broke down on the last two").formIssue)
        XCTAssertTrue(classify("got sloppy at the end").formIssue)
    }

    func testTooEasyDetected() {
        XCTAssertTrue(classify("felt too light, could do more").tooEasy)
        XCTAssertTrue(classify("way too easy").tooEasy)
        XCTAssertTrue(classify("left reps in the tank").tooEasy)
    }

    func testBareEasyOrLightDoesNotTrip() {
        // Deliberately strict: bare "easy"/"light" must not false-trip the risky
        // upward direction.
        XCTAssertFalse(classify("go easy on the knees next time").tooEasy)
        XCTAssertFalse(classify("felt light headed after this one").tooEasy)
    }

    func testEasyNegatorCancels() {
        XCTAssertFalse(classify("not easy at all").tooEasy)
        XCTAssertFalse(classify("that was far from easy").tooEasy)
    }

    func testPainDominatesConservative() {
        let s = classify("hurt my wrist but the weight felt too light")
        XCTAssertTrue(s.pain)
        XCTAssertTrue(s.isConservative, "Pain forces conservative regardless of an easy note")
    }

    func testCleanNoteHasNoSignals() {
        let s = classify("solid session, good tempo throughout")
        XCTAssertFalse(s.pain)
        XCTAssertFalse(s.tooHard)
        XCTAssertFalse(s.tooEasy)
        XCTAssertFalse(s.formIssue)
        XCTAssertFalse(s.isConservative)
    }

    func testMergeCombinesSignals() {
        var a = classify("hurt")
        a.merge(classify("too light"))
        XCTAssertTrue(a.pain, "Merged pain sticks")
        XCTAssertTrue(a.tooEasy, "Merged easy sticks")
        XCTAssertTrue(a.isConservative, "Pain still forces conservative after merge")
    }
}
