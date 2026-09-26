@testable import App
import Testing

// MARK: - MacroSolver tests

struct MacroSolverTests {
    // MARK: - Realistic cutting day, AI ~15% off

    /// 4 items standing in for 4 meals of a cutting day. `trueGrams` is the
    /// exact combination that hits `target`; the AI's `initialGrams` guess
    /// is 15% off (mixed high/low) from that, the way a rough first-pass meal
    /// plan would be. The solver should claw it back within tolerance.
    @Test func cuttingDayFifteenPercentOffIsFixedWithinTolerance() throws {
        let chicken = SolverItem(
            id: "chicken-breast-grilled",
            kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6,
            initialGrams: 515.2 // true 448g, AI guessed +15%
        )
        let rice = SolverItem(
            id: "basmati-rice-cooked",
            kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3,
            initialGrams: 340 // true 400g, AI guessed -15%
        )
        let oil = SolverItem(
            id: "olive-oil",
            kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100,
            initialGrams: 46 // true 40g, AI guessed +15%
        )
        let broccoli = SolverItem(
            id: "broccoli-steamed",
            kcalPer100g: 35, proteinPer100g: 2.4, carbsPer100g: 7, fatPer100g: 0.4,
            initialGrams: 408 // true 480g, AI guessed -15%
        )

        // Totals of the "true" grams (448, 400, 40, 480) — an exactly
        // achievable target given the items above.
        let target = MacroTargets(kcal: 1780.8, proteinG: 161.2, carbsG: 145.6, fatG: 59.248)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [chicken, rice, oil, broccoli])

        #expect(result.withinTolerance)
        #expect(abs(result.achieved.kcal - target.kcal) <= 0.03 * target.kcal)
        #expect(abs(result.achieved.proteinG - target.proteinG) <= 5)
        #expect(abs(result.achieved.carbsG - target.carbsG) <= 5)
        #expect(abs(result.achieved.fatG - target.fatG) <= 5)

        // Every item stayed inside its own box.
        let itemsByID = Dictionary(uniqueKeysWithValues: [chicken, rice, oil, broccoli].map { ($0.id, $0) })
        for solved in result.items {
            let item = try #require(itemsByID[solved.id])
            #expect(solved.grams >= item.minGrams - 0.001)
            #expect(solved.grams <= item.maxGrams + 0.001)
        }

        // Rounding grid: items over 50g land on a multiple of 5.
        for solved in result.items where solved.grams > 50 {
            let remainder = solved.grams.truncatingRemainder(dividingBy: 5)
            #expect(abs(remainder) < 0.001 || abs(remainder - 5) < 0.001)
        }
    }

    // MARK: - Fixed restaurant item (never scaled)

    @Test func fixedPaneraItemIsNeverScaled() throws {
        // Panera Bacon Turkey Bravo, whole sandwich (~330g), fixed.
        let sandwich = SolverItem(
            id: "panera-bacon-turkey-bravo",
            kcalPer100g: 242.4, proteinPer100g: 13.64, carbsPer100g: 18.18, fatPer100g: 13.64,
            initialGrams: 330,
            isFixed: true
        )
        // A scalable side to soak up the rest of the day's target.
        let chips = SolverItem(
            id: "kettle-chips",
            kcalPer100g: 536, proteinPer100g: 6.8, carbsPer100g: 52, fatPer100g: 34,
            initialGrams: 50
        )

        let target = MacroTargets(kcal: 1200, proteinG: 50, carbsG: 110, fatG: 65)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [sandwich, chips])

        let sandwichSolved = try #require(result.items.first { $0.id == "panera-bacon-turkey-bravo" })
        #expect(sandwichSolved.grams == 330, "fixed items must never be scaled")

        let chipsSolved = try #require(result.items.first { $0.id == "kettle-chips" })
        #expect(chipsSolved.grams >= chips.minGrams)
        #expect(chipsSolved.grams <= chips.maxGrams)
        #expect(chipsSolved.grams.isFinite)

        // Achieved totals must include the fixed item's full contribution.
        let fixedKcal = sandwich.kcalPer100g / 100 * 330
        #expect(result.achieved.kcal >= fixedKcal - 0.001)
    }

    // MARK: - Infeasible target: best effort, no crash

    @Test func infeasibleTargetReturnsBestEffortNotWithinTolerance() {
        // A single fixed, low-calorie item can't possibly reach a 5000 kcal
        // target — there's nothing scalable to close the gap.
        let egg = SolverItem(
            id: "egg-whole",
            kcalPer100g: 143, proteinPer100g: 12.6, carbsPer100g: 0.7, fatPer100g: 9.5,
            initialGrams: 50,
            isFixed: true
        )
        let target = MacroTargets(kcal: 5000, proteinG: 300, carbsG: 400, fatG: 150)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [egg])

        #expect(!result.withinTolerance)
        #expect(result.items.count == 1)
        #expect(result.items[0].grams == 50)
        #expect(result.achieved.kcal.isFinite)
        #expect(!result.achieved.kcal.isNaN)
    }

    @Test func infeasibleTargetWithScalableItemStillBounded() throws {
        // Scalable, but capped low enough that the target is unreachable.
        let lettuce = SolverItem(
            id: "lettuce",
            kcalPer100g: 15, proteinPer100g: 1.4, carbsPer100g: 2.9, fatPer100g: 0.2,
            initialGrams: 50, minGrams: 10, maxGrams: 100
        )
        let target = MacroTargets(kcal: 3000, proteinG: 200, carbsG: 300, fatG: 100)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [lettuce])

        #expect(!result.withinTolerance)
        let grams = try #require(result.items.first).grams
        #expect(grams >= 10 && grams <= 100)
    }

    // MARK: - Determinism

    @Test func solveIsDeterministic() {
        let items = [
            SolverItem(id: "a", kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, initialGrams: 300),
            SolverItem(id: "b", kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3, initialGrams: 250),
            SolverItem(id: "c", kcalPer100g: 884, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 100, initialGrams: 20),
            SolverItem(id: "d", kcalPer100g: 35, proteinPer100g: 2.4, carbsPer100g: 7, fatPer100g: 0.4, initialGrams: 200),
        ]
        let target = MacroTargets(kcal: 1600, proteinG: 140, carbsG: 130, fatG: 50)

        let solver = MacroSolver()
        let result1 = solver.solve(targets: target, items: items)
        let result2 = solver.solve(targets: target, items: items)

        #expect(result1 == result2)
    }

    @Test func solveWeekIsDeterministicAndPerDay() {
        let day1Items = [
            SolverItem(id: "a", kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, initialGrams: 300),
        ]
        let day2Items = [
            SolverItem(id: "b", kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3, initialGrams: 250),
        ]
        let days = [
            MacroSolverDay(id: "2026-09-28", targets: MacroTargets(kcal: 500, proteinG: 90, carbsG: 0, fatG: 10), items: day1Items),
            MacroSolverDay(id: "2026-09-29", targets: MacroTargets(kcal: 300, proteinG: 6, carbsG: 65, fatG: 1), items: day2Items),
        ]

        let solver = MacroSolver()
        let results = solver.solveWeek(days: days)
        #expect(results.count == 2)
        #expect(results[0].id == "2026-09-28")
        #expect(results[1].id == "2026-09-29")

        let resultsAgain = solver.solveWeek(days: days)
        #expect(results == resultsAgain)
    }

    // MARK: - Edge cases

    @Test func allItemsFixedNoCrash() {
        let items = [
            SolverItem(id: "a", kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, initialGrams: 200, isFixed: true),
            SolverItem(id: "b", kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3, initialGrams: 150, isFixed: true),
        ]
        let target = MacroTargets(kcal: 500, proteinG: 66, carbsG: 42, fatG: 8)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: items)

        #expect(result.items.map(\.grams) == [200, 150])
        let expectedKcal = 165.0 / 100 * 200 + 130.0 / 100 * 150
        #expect(result.achieved.kcal == expectedKcal)
    }

    @Test func zeroKcalItemDoesNotCrashOrProduceNaN() throws {
        let chicken = SolverItem(id: "chicken", kcalPer100g: 165, proteinPer100g: 31, carbsPer100g: 0, fatPer100g: 3.6, initialGrams: 300)
        // Water: zero everything.
        let water = SolverItem(id: "water", kcalPer100g: 0, proteinPer100g: 0, carbsPer100g: 0, fatPer100g: 0, initialGrams: 250)
        let target = MacroTargets(kcal: 500, proteinG: 93, carbsG: 0, fatG: 11)

        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [chicken, water])

        for solved in result.items {
            #expect(solved.grams.isFinite)
            #expect(!solved.grams.isNaN)
        }
        #expect(!result.achieved.kcal.isNaN)
        // Water has no macro pull; regularizer should keep it near its
        // initial grams rather than pushing it to a bound.
        let waterSolved = try #require(result.items.first { $0.id == "water" })
        #expect(waterSolved.grams >= water.minGrams)
        #expect(waterSolved.grams <= water.maxGrams)
    }

    @Test func emptyItemsListNoCrash() {
        let target = MacroTargets(kcal: 2000, proteinG: 150, carbsG: 200, fatG: 60)
        let solver = MacroSolver()
        let result = solver.solve(targets: target, items: [])
        #expect(result.items.isEmpty)
        #expect(!result.withinTolerance)
    }

    // MARK: - Default bounds

    @Test func defaultBoundsAreHalfToOneEightWithFiveGramFloor() {
        let item = SolverItem(id: "spice", kcalPer100g: 250, proteinPer100g: 10, carbsPer100g: 40, fatPer100g: 5, initialGrams: 4)
        // 0.5 * 4 = 2, floored to the 5g minimum.
        #expect(item.minGrams == 5)
        #expect(item.maxGrams == 7.2)
        let normal = SolverItem(id: "rice", kcalPer100g: 130, proteinPer100g: 2.7, carbsPer100g: 28, fatPer100g: 0.3, initialGrams: 200)
        #expect(normal.minGrams == 100)
        #expect(normal.maxGrams == 360)
    }

    /// A scalable item starting at 0g (e.g. a newly-added ingredient) must
    /// not collapse min==max at the 5g floor — it needs room to actually scale.
    @Test func zeroInitialGramsScalableItemStillHasRoomToScale() {
        let item = SolverItem(id: "new-ingredient", kcalPer100g: 100, proteinPer100g: 10, carbsPer100g: 10, fatPer100g: 5, initialGrams: 0)
        #expect(item.minGrams == 5)
        #expect(item.maxGrams > item.minGrams)
    }
}
