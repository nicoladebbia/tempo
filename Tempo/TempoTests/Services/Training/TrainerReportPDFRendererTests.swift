//
// TrainerReportPDFRendererTests.swift
// Tempo
//
// Fix #8 — pins that the PDF renderer produces real, non-empty PDF data and
// paginates: a small report fits on one page, a large one spills onto more.
// Builds `TrainerReportDocument` fixtures directly (no SwiftData needed —
// the renderer only reads the pure document), and also drops a sample PDF
// and a sample WhatsApp text into the scratchpad for a manual look.
//

import Foundation
@testable import Tempo
import XCTest

final class TrainerReportPDFRendererTests: XCTestCase {
    private func strings(_ language: TrainerReportLanguage = .italian) -> TrainerReportStrings {
        TrainerReportStrings.forLanguage(language)
    }

    private func exerciseLine(_ index: Int) -> TrainerReportExerciseLine {
        TrainerReportExerciseLine(
            name: "Exercise \(index)",
            prescriptionText: "3×8 reps @ 80kg",
            actualText: "80kg×8, 80kg×8, 82.5kg×6 · RPE 8",
            adjustmentText: index.isMultiple(of: 2) ? "Adjusted: Recovery yellow −20%" : nil,
            overrideApplied: false,
            noteText: nil
        )
    }

    private func sessionRow(dayOffset: Int, exerciseCount: Int) -> TrainerReportSessionRow {
        TrainerReportSessionRow(
            id: "session-\(dayOffset)",
            scheduledDate: Date(timeIntervalSince1970: TimeInterval(dayOffset * 86400)),
            dateLabel: "Mon \(dayOffset) Jan",
            title: "Upper Body",
            status: .done,
            statusLabel: "Done",
            completionFraction: 1,
            recoveryScoreText: "62%",
            exercises: (0 ..< exerciseCount).map(exerciseLine),
            conditioning: [TrainerReportConditioningRow(text: "Block 1 · 3:00 · RPE 7")],
            prs: [TrainerReportPRLine(text: "New PR: Bench Press 85kg×5")],
            notes: ["Felt strong today"]
        )
    }

    private func document(sessionCount: Int, exercisesPerSession: Int) -> TrainerReportDocument {
        let sessions = (0 ..< sessionCount).map { sessionRow(dayOffset: $0, exerciseCount: exercisesPerSession) }
        let summary = TrainerReportSummary(
            scheduledCount: sessionCount, doneCount: sessionCount, missedCount: 0, movedCount: 0,
            completionRate: 1, averageRecoveryScore: 62, painNoteCount: 0
        )
        return TrainerReportDocument(
            language: .italian,
            scope: .week,
            strings: strings(),
            programName: "Marco's Plan",
            title: "Report allenamento — Marco's Plan",
            dateRangeLabel: "Periodo: 21 set 2026 – 27 set 2026",
            generatedLabel: "Generato il 27 set 2026",
            summary: summary,
            summaryLines: ["Aderenza: 100% (\(sessionCount)/\(sessionCount))"],
            sessions: sessions
        )
    }

    func testRenderProducesNonEmptyPDFData() {
        let data = TrainerReportPDFRenderer.renderPDF(for: document(sessionCount: 1, exercisesPerSession: 1))
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(TrainerReportPDFRenderer.pageCount(in: data), 1)
    }

    func testLargeReportPaginatesToMultiplePages() {
        // 40 sessions, 6 exercises each — comfortably overflows one A4 page.
        let data = TrainerReportPDFRenderer.renderPDF(for: document(sessionCount: 40, exercisesPerSession: 6))
        let pages = TrainerReportPDFRenderer.pageCount(in: data)
        XCTAssertFalse(data.isEmpty)
        XCTAssertGreaterThan(pages, 1, "a 40-session report should spill onto more than one page")
    }

    func testEmptyDocumentStillRendersOnePage() {
        let empty = TrainerReportDocument(
            language: .english,
            scope: .week,
            strings: strings(.english),
            programName: "Empty",
            title: "Training report — Empty",
            dateRangeLabel: "Period: 21 Sep 2026 – 27 Sep 2026",
            generatedLabel: "Generated on 27 Sep 2026",
            summary: TrainerReportSummary(
                scheduledCount: 0, doneCount: 0, missedCount: 0, movedCount: 0,
                completionRate: 0, averageRecoveryScore: nil, painNoteCount: 0
            ),
            summaryLines: [],
            sessions: []
        )
        let data = TrainerReportPDFRenderer.renderPDF(for: empty)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(TrainerReportPDFRenderer.pageCount(in: data), 1)
    }

    // MARK: - Sample output for manual review

    func testWriteSampleOutputsToScratchpad() throws {
        let sample = document(sessionCount: 3, exercisesPerSession: 3)
        let pdfData = TrainerReportPDFRenderer.renderPDF(for: sample)
        let text = TrainerReportTextFormatter.text(for: sample)

        let dir =
            URL(
                fileURLWithPath: "/private/tmp/claude-501/-Users-nicoladebbia-dev-tempo-Tempo/49b549d2-8f7e-406c-9f71-55a42f498b03/scratchpad/fix8"
            )
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try pdfData.write(to: dir.appendingPathComponent("sample-report.pdf"))
        try text.write(to: dir.appendingPathComponent("sample-report.txt"), atomically: true, encoding: .utf8)

        XCTAssertFalse(pdfData.isEmpty)
        XCTAssertFalse(text.isEmpty)
    }
}
