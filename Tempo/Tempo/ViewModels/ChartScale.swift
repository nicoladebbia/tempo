//
// ChartScale.swift
// Tempo
//
// The vertical range of a line chart whose values sit in a narrow band far from
// zero (weight 81 to 83 kg, HRV 60 to 80 ms). Without it the chart starts at
// zero and the line looks flat. Pure maths on plain values.
//

import Foundation

enum ChartScale {
    /// The part of the range kept above and below the data, as a share of the spread.
    static let padding = 0.2

    /// The smallest spread drawn, as a share of the largest value, so a handful
    /// of near-identical readings do not become a dramatic zig-zag.
    static let minimumSpreadShare = 0.04

    /// A range that holds every value with some room around it. Nil with no values.
    /// It never dips below zero when every value is positive, and a single value
    /// or a flat series gets a small band either side.
    static func fitted(_ values: [Double]) -> ClosedRange<Double>? {
        let finite = values.filter(\.isFinite)
        guard let low = finite.min(), let high = finite.max() else {
            return nil
        }
        let spread = max(high - low, max(abs(high), 1) * minimumSpreadShare)
        let centre = (high + low) / 2
        let half = spread / 2 * (1 + padding * 2)
        var lower = centre - half
        let upper = centre + half
        if low >= 0, lower < 0 {
            lower = 0
        }
        return lower ... upper
    }
}
