@testable import App
import Testing

// MARK: - ProgramImportPageSplitter tests

//
// Pure, no DB/network — splits the sentinel-delimited transcript Claude
// returns from a multi-image TRANSCRIBE batch back into one string per page.

@Suite("ProgramImportPageSplitter")
struct ProgramImportPageSplitterTests {
    @Test func splitsThreeSentinelSeparatedPages() {
        let raw = """
        === PAGE 1 ===
        Squat 3x8 @70%

        === PAGE 2 ===
        Bench 3x8 @65%

        === PAGE 3 ===
        Deadlift 1x5 @80%
        """
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == ["Squat 3x8 @70%", "Bench 3x8 @65%", "Deadlift 1x5 @80%"])
    }

    @Test func discardsPreambleBeforeFirstSentinel() {
        let raw = """
        Sure, here is the transcription:

        === PAGE 1 ===
        Leg Press 3x10
        """
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == ["Leg Press 3x10"])
    }

    @Test func isCaseInsensitiveAndToleratesFlexibleEqualsRuns() {
        let raw = """
        ==page 1==
        Row 3x12
        ========== PAGE 2 ==========
        Pulldown 3x12
        """
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == ["Row 3x12", "Pulldown 3x12"])
    }

    @Test func noSentinelAtAllFallsBackToWholeTrimmedText() {
        let raw = "  Just one page of content, no markers.  \n"
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == ["Just one page of content, no markers."])
    }

    @Test func emptyInputReturnsEmptyArray() {
        #expect(ProgramImportPageSplitter.split("   \n\n  ") == [])
        #expect(ProgramImportPageSplitter.split("") == [])
    }

    @Test func handlesAnEmptyPageBetweenTwoSentinels() {
        let raw = """
        === PAGE 1 ===
        === PAGE 2 ===
        Only page 2 has content
        """
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == ["", "Only page 2 has content"])
    }

    @Test func preservesOrderForManyPages() {
        let raw = (1 ... 5).map { "=== PAGE \($0) ===\nPage \($0) body" }.joined(separator: "\n")
        let pages = ProgramImportPageSplitter.split(raw)
        #expect(pages == (1 ... 5).map { "Page \($0) body" })
    }
}
