//
// SupplementShelfBoard.swift
// Tempo
//
// The Kitchen > Supplements shelf as plain data: every supplement on the
// shelf grouped by the SAME time-of-day sections as Today's card (it uses the
// schedule engine's resolved dose and `SupplementPeriod`), each row carrying
// its schedule line, stock line and reorder flag. Pure — the view only draws it.
//

import Foundation

// MARK: - SupplementShelfRow

struct SupplementShelfRow: Identifiable {
    let supplement: Supplement
    let dose: SupplementDose
    /// Estimated days of supply left (nil = untracked / no signal).
    let daysLeft: Int?
    /// Same rule as the Today chip and the reorder banner.
    let needsReorder: Bool

    var id: UUID {
        supplement.id
    }

    /// "08:00 · With breakfast".
    var scheduleLine: String {
        "\(dose.timeLabel) · \(dose.timingLabel)"
    }

    /// "Brand · 5 g".
    var brandDoseLine: String {
        var parts: [String] = []
        if let brand = supplement.brand, !brand.isEmpty {
            parts.append(brand)
        }
        if !supplement.dosePerServing.isEmpty {
            parts.append(supplement.dosePerServing)
        }
        return parts.isEmpty ? supplement.kind.displayName : parts.joined(separator: " · ")
    }

    /// "34 days left" / "Out" / "40 servings left" / nil when nothing is tracked.
    var stockLine: String? {
        if let daysLeft {
            if daysLeft <= 0 { return "Out" }
            return "\(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        }
        if supplement.servingsRemaining > 0 {
            return "\(Int(supplement.servingsRemaining)) servings left"
        }
        return nil
    }
}

// MARK: - SupplementShelfSection

struct SupplementShelfSection: Identifiable {
    let period: SupplementPeriod
    let rows: [SupplementShelfRow]

    var id: Int {
        period.rawValue
    }
}

// MARK: - SupplementShelfBoard

enum SupplementShelfBoard {
    static func build(
        supplements: [Supplement],
        doses: [SupplementDose],
        recentLogs: [SupplementIntakeLog]
    ) -> [SupplementShelfSection] {
        let doseByID = Dictionary(doses.map { ($0.supplementID, $0) }, uniquingKeysWith: { first, _ in first })
        let rows: [(SupplementPeriod, SupplementShelfRow)] = supplements.compactMap { supplement in
            guard !supplement.isArchived, let dose = doseByID[supplement.id] else { return nil }
            let row = SupplementShelfRow(
                supplement: supplement,
                dose: dose,
                daysLeft: SupplementReorderService.daysLeft(for: supplement, recentLogs: recentLogs),
                needsReorder: SupplementReorderService.needsReorder(for: supplement, recentLogs: recentLogs)
            )
            return (SupplementPeriod.period(for: dose), row)
        }
        return SupplementPeriod.allCases.compactMap { period in
            let inPeriod = rows.filter { $0.0 == period }.map(\.1)
                .sorted { ($0.dose.minutes, $0.supplement.name) < ($1.dose.minutes, $1.supplement.name) }
            return inPeriod.isEmpty ? nil : SupplementShelfSection(period: period, rows: inPeriod)
        }
    }
}

// MARK: - SupplementHistory

/// "Took it" history for one supplement's detail page.
struct SupplementHistory: Equatable {
    /// Newest first.
    let recent: [Date]
    let takenDays: Int
    let windowDays: Int

    static func summary(
        logs: [SupplementIntakeLog],
        supplementID: UUID,
        supplementName: String,
        windowDays: Int = 14,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SupplementHistory {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        let mine = logs.filter {
            ($0.supplementID.map { $0 == supplementID } ?? ($0.supplementName == supplementName))
                && $0.day >= start
        }
        let days = Set(mine.map { calendar.startOfDay(for: $0.day) })
        return SupplementHistory(
            recent: mine.map(\.takenAt).sorted(by: >),
            takenDays: days.count,
            windowDays: windowDays
        )
    }
}
