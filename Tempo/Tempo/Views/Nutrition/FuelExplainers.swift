//
// FuelExplainers.swift
// Tempo
//
// What each Fuel and Kitchen score, target and estimate means, in three short
// answers. Every "how it's worked out" is taken from the real calculation
// (named in the comment above it), never invented. Attach with `.explains(_:)`
// on the number itself, or `.explainerSheet(_:)` where a row already acts on tap.
//

import Foundation

extension Explainer {
    // MARK: - Targets (NutritionTargetCalculator, NutritionEngine.adjustedTargets)

    /// The big calories number on Fuel today.
    static let fuelCalorieTarget = Explainer(
        id: "fuel-calorie-target",
        title: "Calorie target",
        what: "How much you should eat today. The big number is what you have eaten so far, out of today's target. What is left shows above it.",
        how: "It is today's planned meals added up. With no plan for today it is an estimate of what your body burns from your height, weight, age and activity, moved toward your goal. Recovery, rest days and yesterday's gap can change it a little.",
        action: "Plan your meals for the week, or open Fuel setup and check your weight and goal, so the target fits you.",
        systemImage: "flame"
    )

    /// The three macro columns (P, C, F).
    static let fuelMacroTargets = Explainer(
        id: "fuel-macro-targets",
        title: "Protein, carbs and fat",
        what: "P is protein, C is carbs and F is fat. Each shows grams eaten so far out of today's target.",
        how: "They come from the same plan as your calorie target. Your recovery, rest days and training can move them during the day.",
        action: "Look at the one that is furthest behind and pick your next meal to fill it.",
        systemImage: "chart.pie"
    )

    /// The "Target adjusted" line under the macros.
    static let fuelTargetAdjusted = Explainer(
        id: "fuel-target-adjusted",
        title: "Why today's target moved",
        what: "Your target is not always the plain plan number. This line says what changed it today.",
        how: "A rest day cuts calories and carbs by 15% when no plan covers the day, unless recovery is red. Red recovery adds 10% calories and 15% protein. Green recovery on a training day adds 20% carbs, yellow 10%. Yesterday's shortfall of 200 kcal or more comes back, up to 150 kcal, unless it looks like missed logging.",
        action: "Nothing to fix. Eat to the new number, and log your meals so tomorrow's target is right.",
        systemImage: "slider.horizontal.3"
    )

    /// The water card.
    static let fuelWaterTarget = Explainer(
        id: "fuel-water-target",
        title: "Water target",
        what: "How much you should drink today, with what you have logged so far.",
        how: "It starts from 35 ml for every kg you weigh, or 2,500 ml if Tempo does not know your weight. Red recovery adds 20% and green recovery on a training day adds 15%. A logged workout adds more, based on the calories you burned and how long it lasted.",
        action: "Tap +250 ml each time you finish a glass, and drink more on hot or hard training days.",
        systemImage: "drop.fill"
    )

    // MARK: - Today's summary (NutritionEngine)

    /// "In / Out / balance" card.
    static let fuelEnergyBalance = Explainer(
        id: "fuel-energy-balance",
        title: "Energy balance",
        what: "Calories in against calories out today. A minus means you ate less than you burned, a plus means you ate more.",
        how: "In is what you logged. Out is a resting-burn estimate plus the active calories Apple Health recorded today. Balanced means within 250 kcal for maintaining, a 200 to 800 kcal deficit for cutting, or a 100 to 600 kcal surplus for building.",
        action: "If you are cutting, a small minus is the aim. If it is far off, check that every meal is logged.",
        systemImage: "scalemass"
    )

    /// On track / behind / over chips and "g left".
    static let fuelMacroStatus = Explainer(
        id: "fuel-macro-status",
        title: "On track, behind, over",
        what: "Whether each macro is where it should be for this time of day.",
        how: "Over means more than 5% above your target. Behind means you are under 80% of where you should be at this time, counting the day from 7 AM to 10 PM, so a low number early on is normal. The grams left are the target minus what you ate.",
        action: "For anything behind, plan it into your next meal. For anything over, go lighter on it for the rest of the day.",
        systemImage: "gauge.with.dots.needle.33percent"
    )

    /// "32% of kcal" legend next to the macro rings.
    static let fuelMacroShare = Explainer(
        id: "fuel-macro-share",
        title: "Share of calories",
        what: "How much of this food's energy comes from protein, carbs and fat.",
        how: "Grams are turned into calories at 4 for protein, 4 for carbs and 9 for fat. Each share is that part divided by the three added together, so it can differ slightly from the calories printed.",
        action: "For a muscle goal look for a bigger protein share. For a cut, watch the fat share.",
        systemImage: "chart.pie.fill"
    )

    /// "Your real maintenance" on weekly habits.
    static let fuelRealMaintenance = Explainer(
        id: "fuel-real-maintenance",
        title: "Your real maintenance",
        what: "The calories that keep your weight steady, worked out from what you actually ate and how your weight moved.",
        how: "It is your average logged intake over the last 28 days, minus your weight trend times 7,700 kcal per kg. It needs at least 10 days of 1,000 kcal or more and 4 weigh-ins over 10 days. The confidence grows with more days and tops out at 80%.",
        action: "Log every meal and weigh in a few times a week so the estimate gets sharper.",
        systemImage: "scope"
    )

    // MARK: - Food check (FoodScore, NutriScore, FoodFit, LabelFacts)

    /// The Tempo score ring on a product page.
    static let fuelTempoScore = Explainer(
        id: "fuel-tempo-score",
        title: "Tempo score",
        what: "A score out of 100 for how good a packaged food is for you. 75 or more is excellent, 50 to 74 good, 25 to 49 poor, under 25 bad.",
        how: "Up to 60 points come from its nutrition (the Nutri-Score), up to 30 from additives (10 off for each moderate one, none if one is high risk) and 10 for an organic label. A high-risk additive keeps the score at 49 or below.",
        action: "Pick the higher-scoring product, or tap Similar to find a better swap.",
        systemImage: "checkmark.seal"
    )

    /// The Nutri-Score letter.
    static let fuelNutriScore = Explainer(
        id: "fuel-nutri-score",
        title: "Nutri-Score",
        what: "A letter from A to E for the nutrition of this food. A is best.",
        how: "It uses the official letter when the product data has one. If not, Tempo works it out from the values per 100 g. Energy, sugars, saturated fat and salt count against it, fibre counts for it, and so does protein when the bad points are low.",
        action: "Prefer A or B for everyday foods, and keep D and E for now and then.",
        systemImage: "a.circle"
    )

    /// The NOVA processing group.
    static let fuelNova = Explainer(
        id: "fuel-nova",
        title: "NOVA processing group",
        what: "How processed this food is, from 1 (raw or simple) to 4 (ultra-processed).",
        how: "The number comes from the product's data source. It is shown as given and does not change the Tempo score.",
        action: "Swap group 4 foods for group 1 or 2 where you can, especially the ones you eat daily.",
        systemImage: "gearshape.2"
    )

    /// The additives list.
    static let fuelAdditives = Explainer(
        id: "fuel-additives",
        title: "Additive risk",
        what: "The E-numbers in this food, each marked High, Moderate, Low or No known risk.",
        how: "Each additive is looked up in a built-in table of European food-safety (EFSA) risk levels. Moderate ones cost 10 points on the Tempo score and a high-risk one removes all 30 additive points.",
        action: "If you see a High, look for a similar product without it.",
        systemImage: "e.circle"
    )

    /// Low, Medium, High lights for fat, saturates, sugars, salt.
    static let fuelTrafficLights = Explainer(
        id: "fuel-traffic-lights",
        title: "Low, medium, high",
        what: "A quick read of fat, saturated fat, sugars and salt in this food.",
        how: "Per 100 g, using the UK front-of-pack bands. Fat is medium above 3 g and high above 17.5 g. Saturates 1.5 g and 5 g, sugars 5 g and 22.5 g, salt 0.3 g and 1.5 g. Drinks use lower limits per 100 ml.",
        action: "Go for green where you can, and have a high only now and then or in a small portion.",
        systemImage: "chart.bar.fill"
    )

    /// The "For you" ticks.
    static let fuelForYou = Explainer(
        id: "fuel-for-you",
        title: "For you",
        what: "How this food fits today and your goal, using your own targets.",
        how: "Fits today compares its calories with what you have left today. High protein means 8 g or more of protein per 100 kcal, low protein under 2 g. On a cut, a food over 350 kcal per 100 g is flagged as calorie-dense.",
        action: "If it does not fit, choose a smaller portion or put it in a later meal.",
        systemImage: "person.fill.checkmark"
    )

    /// "Salt 1.2 g" style warnings about the printed label.
    static let fuelLabelCheck = Explainer(
        id: "fuel-label-check",
        title: "Label check",
        what: "A warning that the printed numbers on this product do not add up.",
        how: "Protein and carbs count 4 kcal per gram and fat 9. Tempo warns when that total is more than 40 kcal and 30% away from the printed calories, when the printed number is above 900 kcal per 100 g, or when a zero or diet drink prints more than 20 kcal.",
        action: "Check the label in your hand. If it differs, use the values you can read.",
        systemImage: "exclamationmark.triangle"
    )

    /// "87%" on a photo-logged food.
    static let fuelPhotoConfidence = Explainer(
        id: "fuel-photo-confidence",
        title: "Photo confidence",
        what: "How sure the photo reader is about this food.",
        how: "It is the reader's own score, shown as a percent. 80% or more is high, 50 to 79 medium, below that low. A tick means the numbers were rechecked against Tempo's food table. Under 60% it asks you a question.",
        action: "Check anything marked medium or low, and fix the name or portion before you log.",
        systemImage: "camera.viewfinder"
    )

    // MARK: - Kitchen (groceries, pantry, spending, receipts, supplements)

    /// The grocery list total.
    static let fuelGroceryTotal = Explainer(
        id: "fuel-grocery-total",
        title: "List total",
        what: "What this shopping list should cost.",
        how: "It adds up the price of every item still on the list. A price comes from what you paid before, then a saved estimate, then a new estimate. Items with no price yet count as zero, and a leading ≈ means at least one price is an estimate.",
        action: "Log your receipts so more of the prices come from what you really paid.",
        systemImage: "cart"
    )

    /// The budget bar on the grocery list.
    static let fuelGroceryBudget = Explainer(
        id: "fuel-grocery-budget",
        title: "Weekly budget",
        what: "Your grocery budget for the week, and how much of it this list uses.",
        how: "The bar is the list total divided by the budget you set, and it turns red when the list is over it.",
        action: "If it is red, tap Cheaper swaps or take off what you do not need this week.",
        systemImage: "dollarsign.circle"
    )

    /// "Use soon" count and shelf bar on the pantry.
    static let fuelPantryUseSoon = Explainer(
        id: "fuel-pantry-use-soon",
        title: "Use soon",
        what: "Food in your pantry that should be eaten in the next few days.",
        how: "It counts items whose use-by date is today or within 3 days. Most dates are Tempo's estimate from the food and where you store it, not a printed date.",
        action: "Plan these into your next meals, or freeze them.",
        systemImage: "clock.badge.exclamationmark"
    )

    /// This week's spend on the Spending page.
    static let fuelSpendingWeek = Explainer(
        id: "fuel-spending-week",
        title: "This week's spending",
        what: "What you have spent on food since Monday, against your weekly budget.",
        how: "It adds the prices you entered by hand and the totals of your receipts, which include tax. A receipt you scanned twice counts once, and one still being read does not count yet.",
        action: "Scan every receipt so the total is the real one.",
        systemImage: "creditcard"
    )

    /// "Average $84 a week · 1 week over budget".
    static let fuelSpendingAverage = Explainer(
        id: "fuel-spending-average",
        title: "Weekly average",
        what: "Your average weekly spend, and how many weeks went over budget.",
        how: "The average is over the weeks since you first had spend, skipping empty weeks at the start. Each week is compared with your budget as it is now.",
        action: "If many weeks are over, raise the budget to something you will keep, or shop with the list.",
        systemImage: "chart.bar"
    )

    /// "Needs a look" on a receipt.
    static let fuelReceiptNeedsLook = Explainer(
        id: "fuel-receipt-needs-look",
        title: "Needs a look",
        what: "Receipt lines that Tempo is not sure it read right.",
        how: "A line is flagged when the scan was under 75% sure, the name is shorter than 2 letters, the price or quantity is zero or less, or the product match was weak. A banner also shows when the lines do not add up to the printed subtotal or total.",
        action: "Open each flagged line and fix the name, quantity or price before you add it to your pantry.",
        systemImage: "eye"
    )

    /// "Saved $6.20" on a receipt.
    static let fuelReceiptSaved = Explainer(
        id: "fuel-receipt-saved",
        title: "Saved on this receipt",
        what: "The savings the store printed on your receipt.",
        how: "Tempo reads it off the receipt. It does not work it out, and it is not part of what you spent.",
        action: "Nothing to do. If it looks wrong, compare it with the paper receipt.",
        systemImage: "tag"
    )

    /// "5d left" on a supplement.
    static let fuelSupplementDaysLeft = Explainer(
        id: "fuel-supplement-days-left",
        title: "Days left",
        what: "About how many days until this supplement runs out.",
        how: "It is the servings left divided by how often you take it, counted from your doses logged in the last 14 days. A daily supplement with no logs yet counts as one a day. Seven days or fewer shows as low.",
        action: "Tap the supplement to reorder before it runs out, and tick your doses so the estimate stays right.",
        systemImage: "pills"
    )

    // MARK: - Recovery coach (server estimate)

    /// Recovery %, HRV and RHR on the Fuel coach.
    static let fuelRecoveryStats = Explainer(
        id: "fuel-recovery-stats",
        title: "Recovery, HRV and RHR",
        what: "Recovery is a score from 0 to 100 for how ready your body is today. HRV is heart-rate variability in milliseconds, and RHR is your resting heart rate in beats per minute.",
        how: "Tempo shows the numbers Whoop reports. Green is 67 or more, yellow 34 to 66 and red below 34. Fuel uses that colour to adjust today's calories, protein, carbs and water.",
        action: "On red, eat the extra protein and calories it suggests. On green, train hard and fuel it.",
        systemImage: "heart.circle"
    )

    /// "You sweated about 1.5 to 1.8 L".
    static let fuelSweatLoss = Explainer(
        id: "fuel-sweat-loss",
        title: "Sweat estimate",
        what: "About how much fluid you lost as sweat in the session.",
        how: "It is the weight you lost between your two weigh-ins, plus what you drank, minus what you passed as urine. Then a share is taken off, usually 5 to 15%, because some weight loss is breath and burned fuel, not sweat. That is why it is a range. With no drink amount it says at least.",
        action: "Weigh in within 30 minutes before and after, and say what you drank, to tighten the range.",
        systemImage: "drop.degreesign"
    )

    /// "+/- 11% (95% range)".
    static let fuelSweatMargin = Explainer(
        id: "fuel-sweat-margin",
        title: "Margin of error",
        what: "How far off the sweat estimate could be.",
        how: "The server adds up three uncertainties: how precise your scale is, the unknown non-sweat share, and an assumed 10% error on what you said you drank. 95% means the real figure should be inside the range 19 times out of 20. Within 5% shows only when the range is that tight.",
        action: "Treat it as a good estimate, not a measurement.",
        systemImage: "plusminus"
    )

    /// "You lost 1.2 kg (1.6% of your weight)".
    static let fuelWeightLost = Explainer(
        id: "fuel-weight-lost",
        title: "Weight lost",
        what: "How much body weight you lost across the session, as a share of your starting weight.",
        how: "It is your first weigh-in minus your second, divided by your first. The bar fills toward 5% and turns red at 5% or more. Over 4% the coach asks you to weigh again, as that is rare.",
        action: "If you are near 5%, drink more during the next session.",
        systemImage: "scalemass.fill"
    )

    /// Drink / carbs / protein / sodium plan after a session.
    static let fuelRecoveryPlan = Explainer(
        id: "fuel-recovery-plan",
        title: "Recovery plan",
        what: "What to drink and eat after the session to recover.",
        how: "The server sizes the fluid from the weight you lost, about 1.5 times that when you train again soon, otherwise about the same as you lost. Sodium comes from your sweat estimate and an average salt level in sweat. Carbs and protein are set per kg of your body weight.",
        action: "Follow it over the next hours, with a normal meal, and log it so Tempo knows.",
        systemImage: "heart.text.square"
    )
}

extension Explainer {
    /// Every Fuel explainer, so a test can check each one is complete and has its own id.
    static let allFuel: [Explainer] = [
        .fuelCalorieTarget,
        .fuelMacroTargets,
        .fuelTargetAdjusted,
        .fuelWaterTarget,
        .fuelEnergyBalance,
        .fuelMacroStatus,
        .fuelMacroShare,
        .fuelRealMaintenance,
        .fuelTempoScore,
        .fuelNutriScore,
        .fuelNova,
        .fuelAdditives,
        .fuelTrafficLights,
        .fuelForYou,
        .fuelLabelCheck,
        .fuelPhotoConfidence,
        .fuelGroceryTotal,
        .fuelGroceryBudget,
        .fuelPantryUseSoon,
        .fuelSpendingWeek,
        .fuelSpendingAverage,
        .fuelReceiptNeedsLook,
        .fuelReceiptSaved,
        .fuelSupplementDaysLeft,
        .fuelRecoveryStats,
        .fuelSweatLoss,
        .fuelSweatMargin,
        .fuelWeightLost,
        .fuelRecoveryPlan,
    ]
}
