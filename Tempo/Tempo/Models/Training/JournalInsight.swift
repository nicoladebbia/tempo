//
// JournalInsight.swift
// Tempo
//
// One persisted habit↔recovery association computed from the Whoop journal
// export ("Have any alcoholic drinks?" → −7.2 recovery pts, n=350). The
// public Whoop API does NOT expose journal data, so these can only come from
// the account-data CSV export; rows are replaced wholesale on each import.
//
// Association on one person's data, never causation — every surface phrases
// these as "your pattern", never "proof". Only reportable correlations are
// stored (both arms ≥ WhoopExportParser.minSamplesPerArm, |delta| ≥
// minReportableDelta), so readers can render every row without re-filtering.
//

import Foundation
import SwiftData

@Model
final class JournalInsight {
    @Attribute(.unique)
    var id: UUID

    /// The Whoop journal question, verbatim ("Consumed caffeine?").
    var question: String

    var yesCount: Int
    var noCount: Int
    var yesMeanRecovery: Double
    var noMeanRecovery: Double

    var computedAt: Date

    init(
        question: String,
        yesCount: Int,
        noCount: Int,
        yesMeanRecovery: Double,
        noMeanRecovery: Double,
        computedAt: Date = Date()
    ) {
        id = UUID()
        self.question = question
        self.yesCount = yesCount
        self.noCount = noCount
        self.yesMeanRecovery = yesMeanRecovery
        self.noMeanRecovery = noMeanRecovery
        self.computedAt = computedAt
    }

    /// Positive = the habit is associated with BETTER recovery for this user.
    @Transient
    var delta: Double { yesMeanRecovery - noMeanRecovery }
}
