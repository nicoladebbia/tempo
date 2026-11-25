//
// TideTests.swift
// TempoTests
//
// The Tide design system's rules that can be checked without a screen.
//

import Testing
@testable import Tempo

struct TideTests {
    @Test
    func moodFollowsTheDayScore() {
        #expect(TideMood(score: 100).level == .onPace)
        #expect(TideMood(score: 67).level == .onPace)
        #expect(TideMood(score: 66).level == .behind)
        #expect(TideMood(score: 34).level == .behind)
        #expect(TideMood(score: 33).level == .offTrack)
        #expect(TideMood(score: 0).level == .offTrack)
        #expect(TideMood(score: nil).level == .unknown)
        #expect(TideMood.neutral.level == .unknown)
    }

    /// A bad day must look different from a good one, and each state has its own word.
    @Test
    func everyMoodIsDistinct() {
        let moods = TideMood.Level.allCases.map(TideMood.init(level:))
        #expect(Set(moods.map(\.word)).count == moods.count)
        #expect(Set(moods.map { "\($0.accent)" }).count == moods.count)
        #expect(TideMood(score: 10).accent != TideMood(score: 90).accent)
    }

    /// Body-size text needs 4.5:1 against the ink background, including the faintest step.
    @Test
    func textStepsMeetContrast() {
        #expect(TideContrast.whiteText(opacity: Tide.tertiaryOpacity, over: Tide.inkRGB) >= 4.5)
        #expect(TideContrast.whiteText(opacity: Tide.secondaryOpacity, over: Tide.inkRGB) >= 7)
        #expect(Tide.tertiaryOpacity < Tide.secondaryOpacity)
    }

    @Test
    func contrastMathsMatchesKnownValues() {
        // White on black is 21:1; identical colours are 1:1.
        #expect(abs(TideContrast.whiteText(opacity: 1, over: (0, 0, 0)) - 21) < 0.01)
        #expect(abs(TideContrast.whiteText(opacity: 0, over: (0.2, 0.2, 0.2)) - 1) < 0.01)
    }

    @Test
    func layoutSitsOnTheFourPointGrid() {
        for value in [Tide.s1, Tide.s2, Tide.s3, Tide.s4, Tide.s5, Tide.s6, Tide.s8, Tide.s10, Tide.edge, Tide.hit] {
            #expect(value.truncatingRemainder(dividingBy: 4) == 0)
        }
        #expect(Tide.hit >= 44)
    }

    /// Four tabs, in this order; Recovery and Lockdown are routes on Today.
    @Test
    func shellHasFourTabs() {
        #expect(AppTab.allCases == [.today, .train, .fuel, .arena])
        #expect(AppTab.allCases.map(\.title) == ["Today", "Train", "Fuel", "Arena"])
        #expect(Set(AppTab.allCases.map(\.icon)).count == 4)
    }

    @Test
    func captureOffersOnlyExistingFlows() {
        #expect(CaptureAction.allCases.map(\.title) == ["Meal", "Scan", "Workout", "Focus"])
        #expect(CaptureSheet.waterStepMl == 250)
    }
}
