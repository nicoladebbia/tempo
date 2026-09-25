//
// TrainerReportPDFRenderer.swift
// Tempo
//
// Fix #8 — renders a `TrainerReportDocument` as an A4 PDF via
// `UIGraphicsPDFRenderer`, one table per session. Reads ONLY fields the
// document already carries, pre-localized and pre-formatted by
// `TrainerReportBuilder` — same no-extra-logic guarantee as
// `TrainerReportTextFormatter`, so the PDF and the WhatsApp text can never
// show different numbers for the same session.
//

import UIKit

enum TrainerReportPDFRenderer {
    // A4 at 72 dpi.
    private static let pageWidth: CGFloat = 595.2
    private static let pageHeight: CGFloat = 841.8
    private static let margin: CGFloat = 36
    private static var contentWidth: CGFloat {
        pageWidth - margin * 2
    }

    private static let titleFont = UIFont.boldSystemFont(ofSize: 18)
    private static let sectionFont = UIFont.boldSystemFont(ofSize: 13)
    private static let bodyFont = UIFont.systemFont(ofSize: 10)
    private static let smallFont = UIFont.systemFont(ofSize: 8.5)
    private static let tableHeaderFont = UIFont.boldSystemFont(ofSize: 8.5)

    private static let doneColor = UIColor(red: 0.15, green: 0.55, blue: 0.25, alpha: 1)
    private static let missedColor = UIColor(red: 0.7, green: 0.15, blue: 0.15, alpha: 1)
    private static let movedColor = UIColor(red: 0.7, green: 0.5, blue: 0.05, alpha: 1)
    private static let prColor = UIColor(red: 0.6, green: 0.45, blue: 0, alpha: 1)

    static func renderPDF(for document: TrainerReportDocument) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        return renderer.pdfData { rendererContext in
            let cursor = Cursor(context: rendererContext)
            cursor.newPage()

            cursor.draw(document.title, font: titleFont, spacingAfter: 2)
            cursor.draw(document.dateRangeLabel, font: bodyFont, color: .darkGray)
            cursor.draw(document.generatedLabel, font: smallFont, color: .gray, spacingAfter: 10)

            cursor.draw(document.strings.summaryTitle, font: sectionFont, spacingAfter: 4)
            for line in document.summaryLines {
                cursor.draw("• \(line)", font: bodyFont, spacingAfter: 2)
            }
            cursor.y += 6
            cursor.drawRule()

            if document.sessions.isEmpty {
                cursor.draw(document.strings.noSessionsText, font: bodyFont)
            }

            for session in document.sessions {
                drawSession(session, strings: document.strings, cursor: cursor)
            }

            cursor.drawRule()
            cursor.draw(document.strings.footer, font: smallFont, color: .gray)
        }
    }

    /// Number of pages in a rendered PDF — used by callers/tests to confirm
    /// pagination actually happened, by parsing the real output rather than
    /// trusting an internal counter.
    static func pageCount(in data: Data) -> Int {
        guard let provider = CGDataProvider(data: data as CFData),
              let pdf = CGPDFDocument(provider)
        else {
            return 0
        }
        return pdf.numberOfPages
    }

    // MARK: - Session drawing

    private static func drawSession(_ session: TrainerReportSessionRow, strings: TrainerReportStrings, cursor: Cursor) {
        cursor.ensureSpace(28)
        cursor.draw("\(session.dateLabel) — \(session.title)", font: sectionFont, spacingAfter: 1)
        cursor.draw(session.statusLabel, font: bodyFont, color: statusColor(session.status), spacingAfter: 3)
        if let recovery = session.recoveryScoreText {
            cursor.draw("\(strings.recoveryLabel): \(recovery)", font: smallFont, color: .darkGray, spacingAfter: 3)
        }

        if !session.exercises.isEmpty {
            drawExerciseTableHeader(strings: strings, cursor: cursor)
            for exercise in session.exercises {
                drawExerciseRow(exercise, strings: strings, cursor: cursor)
            }
        }
        for conditioning in session.conditioning {
            cursor.draw("\(strings.conditioningHeader): \(conditioning.text)", font: smallFont, spacingAfter: 2)
        }
        for pr in session.prs {
            cursor.draw("★ \(pr.text)", font: bodyFont, color: prColor, spacingAfter: 2)
        }
        for note in session.notes {
            cursor.draw("\(strings.notesLabel): \(note)", font: smallFont, color: .darkGray, spacingAfter: 2)
        }

        cursor.y += 6
        cursor.drawRule()
    }

    private static func statusColor(_ status: TrainerReportSessionStatus) -> UIColor {
        switch status {
        case .done: doneColor
        case .missed: missedColor
        case .moved: movedColor
        }
    }

    // MARK: - Exercise table

    private static func columnX() -> [CGFloat] {
        [margin, margin + contentWidth * 0.30, margin + contentWidth * 0.62]
    }

    private static func columnWidths() -> [CGFloat] {
        [contentWidth * 0.28, contentWidth * 0.30, contentWidth * 0.38]
    }

    private static func drawExerciseTableHeader(strings: TrainerReportStrings, cursor: Cursor) {
        cursor.ensureSpace(14)
        let x = columnX()
        let attrs: [NSAttributedString.Key: Any] = [.font: tableHeaderFont, .foregroundColor: UIColor.gray]
        (strings.exerciseHeader as NSString).draw(at: CGPoint(x: x[0], y: cursor.y), withAttributes: attrs)
        (strings.prescribedHeader as NSString).draw(at: CGPoint(x: x[1], y: cursor.y), withAttributes: attrs)
        (strings.actualHeader as NSString).draw(at: CGPoint(x: x[2], y: cursor.y), withAttributes: attrs)
        cursor.y += 12
    }

    private static func drawExerciseRow(_ exercise: TrainerReportExerciseLine, strings: TrainerReportStrings, cursor: Cursor) {
        let x = columnX()
        let widths = columnWidths()
        let attrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.black]
        let cells = [exercise.name, exercise.prescriptionText, exercise.actualText]

        func height(_ text: String, width: CGFloat) -> CGFloat {
            (text as NSString).boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs,
                context: nil
            ).height.rounded(.up)
        }

        let rowHeight = zip(cells, widths).map(height).max() ?? 12
        cursor.ensureSpace(rowHeight + 14)

        for (index, cell) in cells.enumerated() {
            (cell as NSString).draw(
                in: CGRect(x: x[index], y: cursor.y, width: widths[index], height: rowHeight),
                withAttributes: attrs
            )
        }
        cursor.y += rowHeight + 2

        var extraLines: [String] = []
        if let adjustment = exercise.adjustmentText {
            extraLines.append(adjustment)
        }
        if exercise.overrideApplied {
            extraLines.append(strings.overrideLabel)
        }
        if let note = exercise.noteText {
            extraLines.append("\(strings.notesLabel): \(note)")
        }
        for line in extraLines {
            cursor.draw("   \(line)", font: smallFont, color: .darkGray, spacingAfter: 1)
        }
        cursor.y += 3
    }

    // MARK: - Cursor

    /// Tracks the current Y position in a `UIGraphicsPDFRendererContext` and
    /// starts a new page whenever the next block would overflow — the only
    /// pagination logic in the renderer; everything else just asks it to draw.
    private final class Cursor {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = margin
        private(set) var pageCount = 0

        init(context: UIGraphicsPDFRendererContext) {
            self.context = context
        }

        func newPage() {
            context.beginPage()
            pageCount += 1
            y = margin
        }

        func ensureSpace(_ height: CGFloat) {
            if pageCount == 0 || y + height > pageHeight - margin {
                newPage()
            }
        }

        @discardableResult
        func draw(_ text: String, font: UIFont, color: UIColor = .black, spacingAfter: CGFloat = 4) -> CGFloat {
            guard !text.isEmpty else {
                return 0
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let bounding = (text as NSString).boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin],
                attributes: attrs,
                context: nil
            )
            let height = bounding.height.rounded(.up)
            ensureSpace(height + spacingAfter)
            (text as NSString).draw(
                in: CGRect(x: margin, y: y, width: contentWidth, height: height),
                withAttributes: attrs
            )
            y += height + spacingAfter
            return height
        }

        func drawRule() {
            ensureSpace(10)
            let path = UIBezierPath()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            UIColor.lightGray.setStroke()
            path.lineWidth = 0.5
            path.stroke()
            y += 10
        }
    }
}
