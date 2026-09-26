import Foundation

// MARK: - MacroSolver

//
// Server-side "exact macros" engine for the weekly meal plan pipeline. An
// earlier AI stage picks meals/foods with rough gram estimates; this solver
// adjusts the scalable items' grams so the day hits its kcal/protein/carbs/fat
// targets as closely as the food list allows.
//
// Pure Swift, no Vapor dependency — unit-testable without booting an
// Application (see MacroSolverTests).
//
// Method: block (Gauss-Seidel) coordinate descent over a convex,
// box-constrained weighted-least-squares objective — weighted squared
// *relative* error on kcal/protein/carbs/fat, plus a small regularizer that
// pulls each item's grams back toward its `initialGrams` so portions stay
// realistic (we don't want the solver to zero out the rice and 10x the olive
// oil just because that minimizes raw error). Each coordinate update has a
// closed-form solution (the 1D minimizer of a convex quadratic), so the
// method is deterministic: fixed iteration order, no randomness, same input
// always produces the same output.

struct MacroTargets: Sendable, Equatable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

/// One food line in a day. Fixed items (restaurant menu items, whole units
/// like "1 egg") are never scaled — their grams stay at `initialGrams`.
struct SolverItem: Sendable, Equatable, Identifiable {
    let id: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let carbsPer100g: Double
    let fatPer100g: Double
    let initialGrams: Double
    let minGrams: Double
    let maxGrams: Double
    let isFixed: Bool

    /// - Parameters:
    ///   - minGrams/maxGrams: box constraints for the solve. When omitted,
    ///     defaults to 0.5x-1.8x `initialGrams`, with the lower bound never
    ///     below 5g. Ignored (both pinned to `initialGrams`) when `isFixed`.
    init(
        id: String,
        kcalPer100g: Double,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        initialGrams: Double,
        minGrams: Double? = nil,
        maxGrams: Double? = nil,
        isFixed: Bool = false
    ) {
        self.id = id
        self.kcalPer100g = max(0, kcalPer100g)
        self.proteinPer100g = max(0, proteinPer100g)
        self.carbsPer100g = max(0, carbsPer100g)
        self.fatPer100g = max(0, fatPer100g)
        let clampedInitial = max(0, initialGrams)
        self.initialGrams = clampedInitial
        self.isFixed = isFixed

        if isFixed {
            self.minGrams = clampedInitial
            self.maxGrams = clampedInitial
        } else {
            let defaultMin = max(5, clampedInitial * 0.5)
            // A near-zero initialGrams (e.g. a newly-added ingredient the AI
            // guessed at 0g) would otherwise collapse 0.5x-1.8x down to the
            // same 5g floor on both ends, pinning a scalable item as if it
            // were fixed. Guarantee some room to actually scale.
            var defaultMax = max(clampedInitial * 1.8, defaultMin)
            if defaultMax <= defaultMin {
                defaultMax = defaultMin * 2
            }
            let lo = minGrams ?? defaultMin
            let hi = maxGrams ?? defaultMax
            self.minGrams = min(lo, hi)
            self.maxGrams = max(lo, hi)
        }
    }
}

/// Solved grams for one item.
struct SolvedItem: Sendable, Equatable {
    let id: String
    let grams: Double
}

/// `achieved - target` for each dimension (signed: positive means over).
struct MacroError: Sendable, Equatable {
    let kcal: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct MacroSolverResult: Sendable, Equatable {
    let items: [SolvedItem]
    let achieved: MacroTargets
    let error: MacroError
    let withinTolerance: Bool
}

/// One day's solve input, for `solveWeek`.
struct MacroSolverDay: Sendable {
    let id: String
    let targets: MacroTargets
    let items: [SolverItem]
}

struct MacroSolverDayResult: Sendable, Equatable {
    let id: String
    let result: MacroSolverResult
}

struct MacroSolver: Sendable {
    /// Default: kcal within ±3%, and each macro within ±5g (or ±5% once the
    /// macro's target exceeds 100g).
    struct Tolerance: Sendable {
        var kcalRelative: Double
        var macroAbsoluteGrams: Double
        var macroRelativeForLargeTargets: Double
        var macroLargeTargetThreshold: Double

        init(
            kcalRelative: Double = 0.03,
            macroAbsoluteGrams: Double = 5,
            macroRelativeForLargeTargets: Double = 0.05,
            macroLargeTargetThreshold: Double = 100
        ) {
            self.kcalRelative = kcalRelative
            self.macroAbsoluteGrams = macroAbsoluteGrams
            self.macroRelativeForLargeTargets = macroRelativeForLargeTargets
            self.macroLargeTargetThreshold = macroLargeTargetThreshold
        }

        static let `default` = Tolerance()
    }

    let tolerance: Tolerance
    /// Weight on the "stay close to initialGrams" regularizer. Small on
    /// purpose — it's a tie-breaker among near-equally-good solutions, not a
    /// hard constraint (the box bounds already limit how far grams can move).
    let regularizationWeight: Double
    let maxSweeps: Int
    /// Sweep stops early once no coordinate moves more than this (grams).
    let convergenceThresholdGrams: Double

    init(
        tolerance: Tolerance = .default,
        regularizationWeight: Double = 0.02,
        maxSweeps: Int = 200,
        convergenceThresholdGrams: Double = 0.01
    ) {
        self.tolerance = tolerance
        self.regularizationWeight = regularizationWeight
        self.maxSweeps = maxSweeps
        self.convergenceThresholdGrams = convergenceThresholdGrams
    }

    // MARK: - Solve

    func solve(targets: MacroTargets, items: [SolverItem]) -> MacroSolverResult {
        guard !items.isEmpty else {
            let achieved = MacroTargets(kcal: 0, proteinG: 0, carbsG: 0, fatG: 0)
            return MacroSolverResult(
                items: [],
                achieved: achieved,
                error: errorFor(achieved: achieved, targets: targets),
                withinTolerance: isWithinTolerance(achieved: achieved, targets: targets)
            )
        }

        // Per-gram macro coefficients (per-100g values / 100).
        let k = items.map { $0.kcalPer100g / 100 }
        let p = items.map { $0.proteinPer100g / 100 }
        let c = items.map { $0.carbsPer100g / 100 }
        let f = items.map { $0.fatPer100g / 100 }

        func totals(_ grams: [Double]) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
            var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
            for i in items.indices {
                kcal += k[i] * grams[i]
                protein += p[i] * grams[i]
                carbs += c[i] * grams[i]
                fat += f[i] * grams[i]
            }
            return (kcal, protein, carbs, fat)
        }

        // Starting point: fixed items pinned at initialGrams, scalable items
        // clamped into their own box (initialGrams is usually already inside
        // it, but a caller-supplied bound might not include it).
        var grams = items.map { min(max($0.initialGrams, $0.minGrams), $0.maxGrams) }
        let scalableIndices = items.indices.filter { !items[$0].isFixed }

        guard !scalableIndices.isEmpty else {
            let t = totals(grams)
            let achieved = MacroTargets(kcal: t.kcal, proteinG: t.protein, carbsG: t.carbs, fatG: t.fat)
            return MacroSolverResult(
                items: zip(items, grams).map { SolvedItem(id: $0.0.id, grams: $0.1) },
                achieved: achieved,
                error: errorFor(achieved: achieved, targets: targets),
                withinTolerance: isWithinTolerance(achieved: achieved, targets: targets)
            )
        }

        // Normalizers for the relative-error terms. Floored at 1 so a
        // zero (or near-zero) target — e.g. a strict-keto carbsG target —
        // doesn't divide by zero; it just falls back to an absolute-gram
        // penalty instead of a percentage one for that dimension.
        let dK2 = pow(max(targets.kcal, 1), 2)
        let dP2 = pow(max(targets.proteinG, 1), 2)
        let dC2 = pow(max(targets.carbsG, 1), 2)
        let dF2 = pow(max(targets.fatG, 1), 2)
        let lambda = regularizationWeight

        var (K, P, C, F) = totals(grams)

        for _ in 0 ..< maxSweeps {
            var maxChange = 0.0
            for i in scalableIndices {
                let current = grams[i]
                let s2 = pow(max(items[i].initialGrams, 1), 2)

                // Pull item i's own contribution out of the running totals,
                // solve the 1D quadratic minimizer for x_i in closed form,
                // then clamp to the item's box and put it back.
                let kWithout = K - k[i] * current
                let pWithout = P - p[i] * current
                let cWithout = C - c[i] * current
                let fWithout = F - f[i] * current
                let residualK = kWithout - targets.kcal
                let residualP = pWithout - targets.proteinG
                let residualC = cWithout - targets.carbsG
                let residualF = fWithout - targets.fatG

                let denom = (k[i] * k[i]) / dK2 + (p[i] * p[i]) / dP2 + (c[i] * c[i]) / dC2 + (f[i] * f[i]) / dF2 + lambda / s2
                let numer = -((k[i] * residualK) / dK2 + (p[i] * residualP) / dP2 + (c[i] * residualC) / dC2 + (f[i] * residualF) / dF2)
                    + (lambda * items[i].initialGrams) / s2

                var updated = denom > 1e-12 ? numer / denom : items[i].initialGrams
                updated = min(max(updated, items[i].minGrams), items[i].maxGrams)

                maxChange = max(maxChange, abs(updated - current))

                K = kWithout + k[i] * updated
                P = pWithout + p[i] * updated
                C = cWithout + c[i] * updated
                F = fWithout + f[i] * updated
                grams[i] = updated
            }
            if maxChange < convergenceThresholdGrams {
                break
            }
        }

        let continuousAchieved = MacroTargets(kcal: K, proteinG: P, carbsG: C, fatG: F)
        let continuousWithinTolerance = isWithinTolerance(achieved: continuousAchieved, targets: targets)

        var roundedGrams = items.indices.map { i -> Double in
            items[i].isFixed ? items[i].initialGrams : Self.roundGrams(grams[i])
        }

        // Rounding onto the 5g/1g grid can nudge a tolerance-passing
        // continuous solution just outside tolerance. If the continuous
        // solve was within tolerance, try to claw it back with small
        // single-item adjustments before giving up.
        if continuousWithinTolerance {
            roundedGrams = nudgeToTolerance(
                grams: roundedGrams, items: items, targets: targets,
                k: k, p: p, c: c, f: f, scalableIndices: scalableIndices
            )
        }

        let t = totals(roundedGrams)
        let achieved = MacroTargets(kcal: t.kcal, proteinG: t.protein, carbsG: t.carbs, fatG: t.fat)
        return MacroSolverResult(
            items: zip(items, roundedGrams).map { SolvedItem(id: $0.0.id, grams: $0.1) },
            achieved: achieved,
            error: errorFor(achieved: achieved, targets: targets),
            withinTolerance: isWithinTolerance(achieved: achieved, targets: targets)
        )
    }

    func solveWeek(days: [MacroSolverDay]) -> [MacroSolverDayResult] {
        days.map { day in
            MacroSolverDayResult(id: day.id, result: solve(targets: day.targets, items: day.items))
        }
    }

    // MARK: - Rounding grid

    /// >50g rounds to the nearest 5g; at or below that, nearest 1g.
    private static func roundGrams(_ grams: Double) -> Double {
        if grams > 50 {
            return (grams / 5).rounded() * 5
        }
        return max(0, grams.rounded())
    }

    // MARK: - Post-rounding nudge

    /// Greedy single-step local search on the rounding grid: repeatedly
    /// tries nudging one scalable item by ±1 grid unit and keeps whichever
    /// single move reduces weighted squared error the most, stopping once
    /// tolerance is met, no improving move exists, or the iteration cap is
    /// hit. Deterministic — items are tried in a fixed order and ties keep
    /// the first (lowest-index) improving move.
    private func nudgeToTolerance(
        grams: [Double],
        items: [SolverItem],
        targets: MacroTargets,
        k: [Double], p: [Double], c: [Double], f: [Double],
        scalableIndices: [Int]
    ) -> [Double] {
        guard !scalableIndices.isEmpty else { return grams }
        var g = grams

        func totals(_ g: [Double]) -> (Double, Double, Double, Double) {
            var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
            for i in items.indices {
                kcal += k[i] * g[i]
                protein += p[i] * g[i]
                carbs += c[i] * g[i]
                fat += f[i] * g[i]
            }
            return (kcal, protein, carbs, fat)
        }

        let dK2 = pow(max(targets.kcal, 1), 2)
        let dP2 = pow(max(targets.proteinG, 1), 2)
        let dC2 = pow(max(targets.carbsG, 1), 2)
        let dF2 = pow(max(targets.fatG, 1), 2)

        func weightedError(_ t: (Double, Double, Double, Double)) -> Double {
            pow(t.0 - targets.kcal, 2) / dK2 + pow(t.1 - targets.proteinG, 2) / dP2
                + pow(t.2 - targets.carbsG, 2) / dC2 + pow(t.3 - targets.fatG, 2) / dF2
        }

        for _ in 0 ..< 50 {
            let t = totals(g)
            let achieved = MacroTargets(kcal: t.0, proteinG: t.1, carbsG: t.2, fatG: t.3)
            if isWithinTolerance(achieved: achieved, targets: targets) {
                break
            }

            var bestIndex: Int?
            var bestGrams = 0.0
            var bestError = weightedError(t)

            for i in scalableIndices {
                let unit: Double = g[i] > 50 ? 5 : 1
                for delta in [unit, -unit] {
                    let candidate = min(max(g[i] + delta, items[i].minGrams), items[i].maxGrams)
                    if candidate == g[i] {
                        continue
                    }
                    var trial = g
                    trial[i] = candidate
                    let err = weightedError(totals(trial))
                    if err < bestError {
                        bestError = err
                        bestIndex = i
                        bestGrams = candidate
                    }
                }
            }

            guard let idx = bestIndex else { break }
            g[idx] = bestGrams
        }

        return g
    }

    // MARK: - Tolerance / error

    private func isWithinTolerance(achieved: MacroTargets, targets: MacroTargets) -> Bool {
        let kcalTolerance = max(tolerance.kcalRelative * targets.kcal, 0.01)
        guard abs(achieved.kcal - targets.kcal) <= kcalTolerance else { return false }

        func macroOK(_ achievedValue: Double, _ target: Double) -> Bool {
            let macroTolerance = target > tolerance.macroLargeTargetThreshold
                ? tolerance.macroRelativeForLargeTargets * target
                : tolerance.macroAbsoluteGrams
            return abs(achievedValue - target) <= macroTolerance
        }

        return macroOK(achieved.proteinG, targets.proteinG)
            && macroOK(achieved.carbsG, targets.carbsG)
            && macroOK(achieved.fatG, targets.fatG)
    }

    private func errorFor(achieved: MacroTargets, targets: MacroTargets) -> MacroError {
        MacroError(
            kcal: achieved.kcal - targets.kcal,
            proteinG: achieved.proteinG - targets.proteinG,
            carbsG: achieved.carbsG - targets.carbsG,
            fatG: achieved.fatG - targets.fatG
        )
    }
}
