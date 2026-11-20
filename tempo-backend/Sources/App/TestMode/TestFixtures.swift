import Foundation

// MARK: - Claude fixtures (test mode)

//
// TestModeClient asks `claudeFeature(forRequestBody:)` which Tempo feature an
// Anthropic request belongs to — matched on a unique phrase of its system
// prompt (or user message), the only thing that identifies it — and gets
// back a realistic reply in the exact shape that feature's decoder expects,
// plus a "broken" variant for the parse-failure path.
//
// Rules the replies follow (see each service's decoder):
// - JSON replies are bare (start with `{`), no fences or preamble.
// - Prose replies never contain `{` or `}`.
// - Features keyed by phrases in the iOS prompts too (proxy/text, /vision),
//   so changing a prompt's opening line means updating its matcher here.

enum TestFixtures {
    struct ClaudeContext {
        let system: String
        /// All text blocks of the first user message, joined.
        let userText: String
        let imageCount: Int
        let hasTools: Bool
    }

    struct ClaudeFeature {
        let name: String
        let model: String
        let reply: @Sendable (ClaudeContext) -> String
        /// Truncated / malformed variant for AI mode `broken`.
        let broken: String
    }

    // MARK: - Matching

    static func context(fromRequestBody body: String) -> ClaudeContext {
        guard let data = body.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return ClaudeContext(system: "", userText: "", imageCount: 0, hasTools: false)
        }
        let system = json["system"] as? String ?? ""
        var texts: [String] = []
        var images = 0
        if let messages = json["messages"] as? [[String: Any]],
           let first = messages.first(where: { ($0["role"] as? String) == "user" })
        {
            if let content = first["content"] as? String {
                texts.append(content)
            } else if let blocks = first["content"] as? [[String: Any]] {
                for block in blocks {
                    if block["type"] as? String == "image" {
                        images += 1
                    }
                    if let text = block["text"] as? String {
                        texts.append(text)
                    }
                }
            }
        }
        let hasTools = (json["tools"] as? [Any])?.isEmpty == false
        return ClaudeContext(system: system, userText: texts.joined(separator: "\n"), imageCount: images, hasTools: hasTools)
    }

    static func claudeFeature(forRequestBody body: String) -> ClaudeFeature {
        claudeFeature(for: context(fromRequestBody: body))
    }

    static func claudeFeature(for ctx: ClaudeContext) -> ClaudeFeature {
        if ctx.hasTools {
            return coachChat
        }
        for (phrase, inUserText, feature) in matchers {
            let haystack = inUserText ? ctx.userText : ctx.system
            if haystack.contains(phrase) {
                return feature
            }
        }
        if ctx.system.contains("You analyze meal data and biometric data") {
            return nutritionCoach(for: ctx.userText)
        }
        return unknown
    }

    /// (phrase, match in user message instead of system, feature). First match wins.
    private static let matchers: [(String, Bool, ClaudeFeature)] = [
        ("You generate structured, macro-precise weekly meal plans", false, weeklyPlan),
        ("You are a culinary assistant for a nutrition app called Tempo", false, recipe),
        ("You transcribe pages of a personal trainer's training program", false, programTranscribe),
        ("You extract a personal trainer's training program", false, programStructure),
        ("You read a personal trainer's short message", false, programFeedback),
        ("grocery RECEIPT extraction system", false, receipt),
        ("You are an elite performance analyst inside the Tempo app.", false, weeklyReport),
        ("behavioral pattern detection", false, patterns),
        ("You deliver motivational push based on the user's current data.", false, prose("drill_sergeant", drillSergeantLine)),
        ("You are a sports science advisor inside the Tempo app.", false, recoveryPrescription),
        ("You deliver a daily morning briefing to a university student-athlete", false, prose("morning_briefing", "Exam in three days, recovery is yellow and you slept under six hours. Train light, eat on time, and put the phone away by 23:00. Study block first, then the session.")),
        ("You are a strength coach inside the Tempo app.", false, json("training_adjustment", #"{"volume_adjustment":-0.2,"keep_exercises":["Back Squat","Bench Press"],"drop_exercises":["Leg Extension"],"note":"Yellow recovery. Keep the big lifts, cut the accessories."}"#)),
        ("You generate dashboard insight cards", false, json("dashboard_insights", #"{"insights":[{"icon":"flame.fill","title":"Protein streak","body":"Five days over target. Keep lunch heavy."},{"icon":"moon.fill","title":"Sleep debt","body":"Two late nights. Bed by 23:00 tonight."}]}"#)),
        ("You program 7-day training weeks", false, trainingProgram),
        ("You build study schedules for university students.", false, json("study_schedule", #"{"exam_id":"exam-test","sessions":[{"day_offset":0,"topic":"Chapters 1-2","minutes":50},{"day_offset":1,"topic":"Chapters 3-4","minutes":50},{"day_offset":2,"topic":"Practice exam","minutes":90}],"rationale":"Spread the load, test yourself before the exam."}"#)),
        ("You generate ONE celebration sentence", false, prose("achievement_copy", "Seven days straight. That is not luck, that is discipline.")),
        ("You recommend optimal meal times for a student-athlete.", false, json("meal_timing", #"{"suggested_time":"12:30","note":"Two hours before training. Carbs now, protein after."}"#)),
        ("You generate batch notification copy for a fitness", false, drillBatch),
        ("You are a supplements buying guide.", false, json("supplement_picks", #"{"look_for":"Third-party tested, single ingredient, no proprietary blends.","picks":[{"brand":"Test Labs","product":"Creatine Monohydrate","form":"powder","certifications":["NSF Certified for Sport"],"why":"Cheapest per gram and tested.","approx_price_per_serving_usd":0.18}]}"#)),
        ("Explain macro adjustments in 1", false, prose("explain_adjustment", "Training moved to the evening, so carbs shift to lunch and the afternoon snack. Same total, better timing.")),
        ("Suggest exactly ONE realistic meal", false, prose("suggest_meal", "Chicken rice bowl with broccoli and a drizzle of olive oil. About 650 kcal and 50 g protein.")),
        ("This is the user's first day or there's no", false, prose("recovery_cold_start", "First day of data. Sleep was fine, resting heart rate normal. Train as planned and let the baseline build.")),
        ("OPPOSITE: explain today using the data WHOOP CANNOT see", false, prose("recovery_daily", "Recovery is down because dinner was late and heavy, not because of training. Eat earlier tonight and hydrate.")),
        ("WEEKLY review on Monday", false, prose("recovery_weekly", "Average recovery 61 percent, up 4 from last week. Two late nights cost you. Lock bedtime at 23:00 this week.")),
        ("You are Tempo's daily training coach.", false, json("daily_coach", #"{"modality":"push","intensity":"hard","durationMin":65,"blocks":[{"kind":"gym","label":"Push — chest/shoulders/triceps","split":"push","cue":"Full range, control the eccentric."}],"shortWhy":"Green. Physique block — earn the volume.","expectedSessionRPE":8}"#)),
        ("You are Tempo's monthly training coach", false, prose("monthly_review", "TRAINING\nFourteen sessions, two missed.\n\nSTRENGTH\nSquat up 7.5 kg, bench flat.\n\nBODY\nWeight steady, waist down 1 cm.\n\nREADINESS\nRecovery averaged 64 percent.")),
        ("You are a conversation summarizer.", false, prose("coach_summary", "The athlete asked about protein at lunch. The coach set a 45 g target. They agreed to log it tonight.")),
        ("You extract preferences from chat transcripts.", false, json("coach_preferences", #"[{"text":"No fish on weekdays","subject":"fish","confidence":0.8,"source":"explicit","polarity":"negative","scope":"weekday","turnIndex":0}]"#)),
        ("redistribute the macros of a SKIPPED meal", false, json("meal_redistribution", #"{"adjustments":[],"totalDropped":{"calories":0,"protein":0,"carbs":0,"fat":0},"reasoning":"Skipped meal dropped; the rest of the day already covers protein."}"#)),
        ("You are a food macro parser for a fitness nutrition app.", false, json("nl_parse", #"{"meal_type":"lunch","eaten_at":"13:00","items":[{"name":"chicken breast","quantityGrams":150,"calories":248,"proteinG":46.5,"carbsG":0,"fatG":5.4},{"name":"white rice","quantityGrams":200,"calories":260,"proteinG":5.4,"carbsG":56.4,"fatG":0.6}]}"#)),
        ("You are a recipe parser. Convert a free-text recipe description into", false, json("recipe_parser", #"{"name":"Test Chicken Bowl","servings":2,"prepMinutes":10,"cookMinutes":20,"ingredients":[{"name":"chicken breast","displayQuantity":"300 g","quantityGrams":300},{"name":"white rice","displayQuantity":"1 cup","quantityGrams":185}],"steps":[{"instruction":"Cook the rice.","durationMinutes":15},{"instruction":"Grill the chicken and slice it.","durationMinutes":10}]}"#)),
        ("description and find ambiguous portions or eating times", false, json("voice_meal_extract", #"{"questions":[]}"#)),
        ("You are Tempo's voice nutrition parser. Given a meal description", false, json("voice_meal_resolve", #"{"items":[{"name":"scrambled eggs","quantity_g":150,"calories":220,"protein_g":15,"carbs_g":2,"fat_g":16,"confidence":"high"},{"name":"whole wheat toast","quantity_g":60,"calories":150,"protein_g":7,"carbs_g":25,"fat_g":2,"confidence":"low"}]}"#)),
        ("You are Tempo's voice PANTRY parser.", false, json("voice_pantry", #"{"items":[{"name":"eggs","intent":"add","quantity":12,"unit":"pieces","storage":"fridge","brand":"","components":[],"confidence":0.9},{"name":"rice","intent":"set","quantity":2,"unit":"kg","storage":"pantry","brand":"","components":[],"confidence":0.8}]}"#)),
        ("You are Tempo's grocery price estimator.", false, groceryPrices),
        ("You are Tempo's drill-sergeant grocery coach.", false, json("grocery_swaps", #"{"swaps":["Store-brand oats instead of the name brand saves about $2.","Frozen broccoli is half the price of fresh and keeps all week."]}"#)),
        ("You are Tempo's food shelf-life estimator.", false, shelfLife),
        ("You turn a person's description of their life and week", false, json("fuel_setup", #"{"profile":{},"followUps":[]}"#)),
        ("You read food packaging photos", false, json("label_reader", #"{"name":"Protein Bar (test)","brand":"Test Labs","serving_g":60,"is_beverage":false,"per_100g":{"kcal":360,"protein":33,"carbs":38,"sugars":5,"fat":10,"saturated_fat":4,"fiber":8,"salt":0.5},"ingredients":"Milk protein, oats, cocoa.","allergens":["milk"]}"#)),
        ("Analyze this meal photo. Identify each food item", true, json("photo_analysis", #"{"items":[{"name":"Grilled chicken breast","portion":"150 g","calories":248,"protein":46,"carbs":0,"fat":5,"confidence":0.85},{"name":"White rice","portion":"1 cup","calories":205,"protein":4,"carbs":45,"fat":0,"confidence":0.7,"alternatives":[{"name":"Jasmine rice","portion":"1 cup","calories":210,"protein":4,"carbs":46,"fat":0,"confidence":0.4}]}],"confidence":0.78,"verdict":"Solid post-training plate. Add a vegetable."}"#)),
    ]

    /// Every fixture, for tests that check they all parse.
    static var allFixtures: [ClaudeFeature] {
        matchers.map(\.2) + [coachChat, weeklyPlan, recipe, unknown]
            + ["photo", "barcode", "summary", "anything"].map(nutritionCoach(for:))
    }

    // MARK: - Builders

    static func prose(_ name: String, _ text: String, model: String = "claude-haiku-4-5-20251001") -> ClaudeFeature {
        ClaudeFeature(name: name, model: model, reply: { _ in text }, broken: String(text.prefix(12)))
    }

    static func json(_ name: String, _ text: String, model: String = "claude-haiku-4-5-20251001") -> ClaudeFeature {
        ClaudeFeature(name: name, model: model, reply: { _ in text }, broken: String(text.prefix(text.count / 2)))
    }

    static let unknown = prose("unknown", "Test mode has no fixture for this prompt yet. Add one in TestFixtures.swift.")

    static let drillSergeantLine = "Recovery is green and you have no excuse left. Hit the session at 18:00, eat the protein you planned, and be in bed by 23:00. Tomorrow you will thank yourself for doing it today."

    static let coachChat = ClaudeFeature(
        name: "coach_chat",
        model: "claude-sonnet-4-6",
        reply: { _ in "Copy that. Protein first at lunch — hit 45 g and we're on track. Log it when you're done." },
        broken: "Copy th"
    )

    static func nutritionCoach(for user: String) -> ClaudeFeature {
        if user.hasPrefix("Analyze this week's nutrition data") {
            return json("nutrition_weekly_review", #"{"verdict":"Protein on target five of seven days.","analysis":"Weekends slipped: late breakfasts pushed lunch to 15:00 and dinner ran short.","fix":"Set the weekend breakfast alarm for 09:00 and prep Sunday lunch on Saturday."}"#)
        }
        if user.contains("\"tips\": [") || user.contains("\"tips\":[") {
            return json("nutrition_recovery_tips", #"{"message":"Yellow recovery. Eat on time and front-load carbs.","tips":["Carbs at breakfast","Two litres of water by 15:00","No caffeine after 14:00"]}"#)
        }
        if user.hasPrefix("Suggest") {
            return json("nutrition_suggestions", #"{"suggestions":[{"name":"Greek yogurt bowl","calories":320,"protein":28,"carbs":38,"fat":6,"prep_time":"3 min","description":"Yogurt, banana, oats."},{"name":"Turkey wrap","calories":450,"protein":35,"carbs":40,"fat":14,"prep_time":"5 min","description":"Tortilla, turkey, spinach."}]}"#)
        }
        if user.hasPrefix("Generate") {
            return prose("nutrition_summary", "You hit protein and stayed within twenty kilocalories of target. Dinner was late again. Tomorrow eat by 20:30 and keep the same lunch.")
        }
        if user.hasPrefix("Training in") {
            return prose("nutrition_pre_training", "Carbs are low with training coming up. Eat a banana and a slice of toast now, then train.")
        }
        return prose("nutrition_meal_feedback", "Good protein, low on vegetables. Add a handful of spinach next time and keep the portion of rice the same.")
    }

    // MARK: - Weekly plan (dynamic)

    /// Seven days in AIWeeklyPlanResponse shape (camelCase, plain decoder).
    /// Day types come from the prompt's target lines so every day has a
    /// target to solve against; meal count honours "give EXACTLY n meals".
    static let weeklyPlan = ClaudeFeature(
        name: "weekly_plan",
        model: "claude-sonnet-4-6",
        reply: { ctx in weeklyPlanJSON(prompt: ctx.userText) },
        broken: #"{"days":[{"dayIndex":0,"dayType":"strength","meals":[{"mealNumber":1,"mealName":"Breakf"#
    )

    static func weeklyPlanJSON(prompt: String) -> String {
        let names: [(String, String)] = [("Strength", "strength"), ("Cardio", "cardio"), ("Soccer", "soccer"), ("Double Session", "double"), ("Rest", "rest")]
        let targetBlock = prompt.components(separatedBy: "<macro_targets_by_day_type>").dropFirst().first?
            .components(separatedBy: "</macro_targets_by_day_type>").first ?? ""
        var available = names.filter { targetBlock.contains("- \($0.0):") }.map(\.1)
        if available.isEmpty {
            available = ["strength", "rest"]
        }
        func pick(_ preferred: String) -> String {
            available.contains(preferred) ? preferred : available[0]
        }
        let week = [pick("strength"), pick("cardio"), pick("strength"), pick("soccer"), pick("strength"), pick("double"), pick("rest")]

        var mealCount = 4
        if let range = prompt.range(of: #"give EXACTLY (\d) meals per day"#, options: .regularExpression),
           let n = Int(prompt[range].filter(\.isNumber))
        {
            mealCount = n
        }

        typealias Food = (String, Double)
        let breakfasts: [[Food]] = [[("oats", 80), ("greek yogurt", 200), ("blueberries", 100)], [("eggs", 150), ("whole wheat bread", 80), ("banana", 120)]]
        let lunches: [[Food]] = [[("chicken breast", 180), ("white rice", 220), ("broccoli", 150), ("olive oil", 10)], [("turkey breast", 150), ("flour tortilla", 90), ("spinach", 60), ("black beans", 120)]]
        let dinners: [[Food]] = [[("salmon", 170), ("sweet potato", 250), ("spinach", 80), ("olive oil", 8)], [("lean ground beef", 160), ("pasta", 250), ("tomato sauce", 150)]]
        let snacks: [[Food]] = [[("cottage cheese", 200), ("apple", 150)], [("whey protein", 30), ("milk", 300), ("banana", 120)], [("almonds", 30), ("greek yogurt", 170)]]
        let slots: [(Int, String, String, [[Food]])] = [
            (1, "Breakfast", "07:30", breakfasts),
            (2, "Lunch", "13:00", lunches),
            (3, "Dinner", "20:00", dinners),
            (4, "Afternoon Snack", "16:30", snacks),
            (5, "Evening Snack", "21:30", snacks),
            (6, "Late Snack", "22:00", snacks),
        ]

        let per100 = Dictionary(uniqueKeysWithValues: foods.map { ($0.name, $0) })
        func foodJSON(_ food: Food) -> String {
            let f = per100[food.0]!
            let k = food.1 / 100
            return #"{"name":"\#(food.0)","quantityGrams":\#(Int(food.1)),"calories":\#(Int(f.kcal * k)),"proteinG":\#(Int(f.protein * k)),"carbsG":\#(Int(f.carbs * k)),"fatG":\#(Int(f.fat * k)),"source":"home"}"#
        }
        let usedSlots = slots.filter { $0.0 <= max(3, min(mealCount, 6)) }
        let days = week.enumerated().map { index, dayType -> String in
            let meals = usedSlots.map { slot -> String in
                let options = slot.3
                let foodsJSON = options[(index + slot.0) % options.count].map(foodJSON).joined(separator: ",")
                return #"{"mealNumber":\#(slot.0),"mealName":"\#(slot.1)","scheduledTime":"\#(slot.2)","foods":[\#(foodsJSON)]}"#
            }.joined(separator: ",")
            return #"{"dayIndex":\#(index),"dayType":"\#(dayType)","meals":[\#(meals)],"supplements":[]}"#
        }
        return #"{"days":["# + days.joined(separator: ",") + "]}"
    }

    // MARK: - Recipe (dynamic)

    /// Echoes the meal's own foods (lines "- name: 150g (300 kcal, P30 C20 F10)")
    /// as ingredients, so recipe amounts match the plan like the real thing.
    static let recipe = ClaudeFeature(
        name: "meal_recipe",
        model: "claude-haiku-4-5-20251001",
        reply: { ctx in recipeJSON(prompt: ctx.userText) },
        broken: #"{"name":"Test Bowl","servings":1,"ingredients":[{"name":"chick"#
    )

    static func recipeJSON(prompt: String) -> String {
        let mealName = prompt.components(separatedBy: "\n").first { $0.hasPrefix("Meal: ") }?.dropFirst(6).trimmingCharacters(in: .whitespaces) ?? "Test Meal"
        let pattern = #"- (.+?): (\d+)g \((\d+) kcal, P(\d+) C(\d+) F(\d+)\)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let ns = prompt as NSString
        var ingredients: [String] = []
        var totals = (kcal: 0, p: 0, c: 0, f: 0)
        for match in regex?.matches(in: prompt, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let g = { (i: Int) in ns.substring(with: match.range(at: i)) }
            let name = g(1).lowercased().replacingOccurrences(of: "\"", with: "")
            let grams = Int(g(2)) ?? 0
            let kcal = Int(g(3)) ?? 0, p = Int(g(4)) ?? 0, c = Int(g(5)) ?? 0, f = Int(g(6)) ?? 0
            totals = (totals.kcal + kcal, totals.p + p, totals.c + c, totals.f + f)
            let storage = ["chicken breast", "salmon", "lean ground beef", "turkey breast"].contains(name) ? "fridge" : "pantry"
            ingredients.append(#"{"name":"\#(name)","displayName":"\#(name.capitalized)","quantityGrams":\#(grams),"displayQuantity":"\#(grams) g \#(name)","calories":\#(kcal),"proteinGrams":\#(p),"carbsGrams":\#(c),"fatGrams":\#(f),"storageLocation":"\#(storage)","defrostLeadTimeHours":0}"#)
        }
        if ingredients.isEmpty {
            ingredients = [#"{"name":"chicken breast","displayName":"Chicken Breast","quantityGrams":150,"displayQuantity":"150 g chicken breast","calories":248,"proteinGrams":46,"carbsGrams":0,"fatGrams":5,"storageLocation":"fridge","defrostLeadTimeHours":0}"#]
            totals = (248, 46, 0, 5)
        }
        let safeName = mealName.replacingOccurrences(of: "\"", with: "")
        return #"{"name":"\#(safeName) (test recipe)","description":"Quick test-mode recipe built from the planned foods.","cuisine":"","servings":1,"prepTimeMinutes":10,"cookTimeMinutes":15,"difficulty":"easy","equipment":["pan"],"dietaryTags":[],"ingredients":["# + ingredients.joined(separator: ",") + #"],"steps":[{"order":1,"instruction":"Weigh every ingredient.","durationMinutes":3},{"order":2,"instruction":"Cook the protein in a hot pan.","durationMinutes":10},{"order":3,"instruction":"Plate with the sides and eat.","durationMinutes":2}],"macrosPerServing":{"calories":\#(totals.kcal),"protein":\#(totals.p),"carbs":\#(totals.c),"fat":\#(totals.f)}}"#
    }

    // MARK: - Trainer program import

    static let programTranscribe = ClaudeFeature(
        name: "program_transcribe",
        model: "claude-sonnet-4-6",
        reply: { ctx in
            let pages = max(ctx.imageCount, 1)
            let days = ["Squat 4x6 @75%\nRomanian Deadlift 3x8\nWalking Lunge 3x10 each", "Bench Press 4x6 @75%\nPull-up 4x8\nDumbbell Shoulder Press 3x10", "Deadlift 3x5 @80%\nBarbell Row 4x8\nPlank 3x45s"]
            return (1 ... pages).map { "=== PAGE \($0) ===\nDay \($0)\n\(days[($0 - 1) % days.count])" }.joined(separator: "\n\n")
        },
        broken: "=== PAGE"
    )

    static let programStructure = json(
        "program_structure",
        #"{"name":"Test Strength Block","weeks":[{"days":[{"weekday":1,"title":"Lower","focus":"strength","exercises":[{"name":"Back Squat","sets":4,"reps_low":6,"reps_high":6,"percent_1rm":75,"rest_seconds":180},{"name":"Romanian Deadlift","sets":3,"reps_low":8,"reps_high":8,"rest_seconds":120},{"name":"Walking Lunge","sets":3,"reps_low":10,"reps_high":10,"per_side":true,"rest_seconds":90}]},{"weekday":3,"title":"Upper","focus":"strength","exercises":[{"name":"Bench Press","sets":4,"reps_low":6,"reps_high":6,"percent_1rm":75,"rest_seconds":180},{"name":"Pull-up","sets":4,"reps_low":8,"reps_high":8,"rest_seconds":120}]},{"weekday":5,"title":"Full","focus":"strength","exercises":[{"name":"Deadlift","sets":3,"reps_low":5,"reps_high":5,"percent_1rm":80,"rest_seconds":180},{"name":"Barbell Row","sets":4,"reps_low":8,"reps_high":8,"rest_seconds":120}]}]}]}"#,
        model: "claude-sonnet-4-6"
    )

    static let programFeedback = json("program_feedback", #"{"edits":[{"type":"update_exercise","exercise_name":"Back Squat","weight_delta_kg":5,"reason":"Trainer: add 5 kg to squats."}]}"#, model: "claude-sonnet-4-6")

    // MARK: - Receipt

    static let receipt = json(
        "receipt_structure",
        #"{"store":"Publix","store_chain":"Publix","purchase_date":"2026-09-28T18:20:00Z","currency":"USD","subtotal_amount":31.47,"tax_amount":0.88,"total_amount":32.35,"payment_method":"Visa","line_items":[{"raw_text":"PUBLIX CHKN BRST BNLS","canonical_food_name":"chicken breast","display_name":"Chicken Breast","quantity":1.2,"unit":"lb","quantity_grams":544,"unit_price":5.99,"total_price":7.19,"on_sale":false,"confidence":0.92,"category_hint":"meat"},{"raw_text":"BROCCOLI CROWNS","canonical_food_name":"broccoli","display_name":"Broccoli","quantity":1,"unit":"unit","total_price":2.49,"confidence":0.9,"category_hint":"produce"},{"raw_text":"GV OATS OLD FASH 42OZ","canonical_food_name":"oats","display_name":"Old Fashioned Oats","quantity":1,"unit":"unit","quantity_grams":1190,"total_price":4.98,"on_sale":true,"sale_note":"BOGO","line_discount":1.00,"confidence":0.85,"category_hint":"grains"},{"raw_text":"CHOBANI GRK YGRT 32OZ","canonical_food_name":"greek yogurt","display_name":"Greek Yogurt","quantity":2,"unit":"unit","quantity_grams":1814,"total_price":11.98,"confidence":0.88,"category_hint":"dairy"},{"raw_text":"BAG FEE","canonical_food_name":"bag fee","display_name":"Bag Fee","quantity":1,"unit":"unit","total_price":0.10,"is_fee":true,"confidence":0.99},{"raw_text":"TIDE PODS 42CT","canonical_food_name":"laundry detergent","display_name":"Laundry Detergent","quantity":1,"unit":"unit","total_price":4.73,"is_non_food":true,"confidence":0.95}],"notes":null}"#
    )

    // MARK: - Insights

    static let weeklyReport = json(
        "weekly_report",
        #"{"title":"Solid week, sloppy weekend","summary":"Training and protein were on point Monday to Friday. Saturday and Sunday undid some of it.","sections":[{"title":"Training","icon":"figure.strengthtraining.traditional","body":"5 of 6 sessions done. Squat up 2.5 kg.","sentiment":"positive"},{"title":"Recovery","icon":"heart.fill","body":"Average 62 percent, two red days after late nights.","sentiment":"neutral"},{"title":"Nutrition","icon":"fork.knife","body":"Protein hit 5 of 7 days. Weekend calories ran 600 over.","sentiment":"negative"}],"action_items":["Bed by 23:00 Friday and Saturday","Prep Sunday lunch on Saturday"],"compared_to_last_week":{"recovery_avg_change":4,"sleep_avg_change_min":-12,"workout_count_change":1,"xp_change":120,"protein_adherence_change":10,"study_avg_change_min":15,"completion_pct_change":6}}"#,
        model: "claude-sonnet-4-6"
    )

    static let patterns = json("patterns", #"{"patterns":[{"id":"p1","type":"sleep_recovery","trigger":"Bedtime after 00:30","outcome":"Next-day recovery under 40 percent","confidence":0.82,"occurrences":4,"recommendation":"Lights out by 23:30 on training eves.","correlation_r":-0.61}],"data_quality":{"total_days":28,"days_with_recovery":26,"days_with_nutrition":22,"days_with_study":18,"sufficient_for_analysis":true},"top_insight":"Late nights cost you a third of your recovery."}"#, model: "claude-sonnet-4-6")

    static let recoveryPrescription = json("recovery_prescription", #"{"training_recommendation":"Moderate session, cap RPE at 7.","training_intensity":"moderate","volume_adjustment":-0.15,"meal_timing":"Carbs at lunch and the pre-training snack.","bedtime_target":"22:45","wake_target":"07:00","hydration_target_ml":3200,"caffeine_cutoff":"14:00","warnings":["HRV down 18 percent from baseline"],"top_priority":"Sleep. Everything else is secondary tonight."}"#)

    static let trainingProgram = json("training_program", #"{"week_start":"2026-10-05","days":[{"day":"monday","workout_type":"strength","volume_adjustment":0},{"day":"tuesday","workout_type":"conditioning","volume_adjustment":0},{"day":"wednesday","workout_type":"strength","volume_adjustment":-0.1},{"day":"thursday","workout_type":"football","volume_adjustment":0},{"day":"friday","workout_type":"strength","volume_adjustment":0},{"day":"saturday","workout_type":"football","volume_adjustment":0},{"day":"sunday","workout_type":"rest","volume_adjustment":0}],"rationale":"Match on Saturday, so the heavy day moves to Monday and Friday stays light."}"#)

    static let drillBatch = json("drill_batch", {
        let days = (0 ..< 3).map { offset in
            #"{"day_offset":\#(offset),"copy":{"morning":"Up. Day \#(offset + 1) does not care how you feel.","afternoon":"Halfway. Protein check.","evening":"Session done or excuse ready? Pick one.","bedtime":"Screens off. Recovery is training.","celebration":"Clean day. Bank it.","weekly_summary":"Week in. Read your numbers."}}"#
        }
        return #"{"batch_start":"2026-10-04","days":["# + days.joined(separator: ",") + "]}"
    }())

    // MARK: - Grocery (echo inputs)

    static let groceryPrices = ClaudeFeature(
        name: "grocery_prices",
        model: "claude-haiku-4-5-20251001",
        reply: { ctx in
            var names: [String] = []
            if let open = ctx.userText.range(of: ": ["), let close = ctx.userText.range(of: "]", range: open.upperBound ..< ctx.userText.endIndex) {
                let list = ctx.userText[open.upperBound ..< close.lowerBound]
                names = list.components(separatedBy: "\", \"").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }.filter { !$0.isEmpty }
            }
            let items = names.enumerated().map { index, name in
                #"{"name":"\#(name.replacingOccurrences(of: "\"", with: ""))","price_usd":\#(String(format: "%.2f", 1.49 + Double((index * 37) % 900) / 100))}"#
            }
            return #"{"items":["# + items.joined(separator: ",") + "]}"
        },
        broken: #"{"items":[{"name":"#
    )

    static let shelfLife = ClaudeFeature(
        name: "shelf_life",
        model: "claude-haiku-4-5-20251001",
        reply: { ctx in
            let regex = try? NSRegularExpression(pattern: #"key: "([^"]+)""#)
            let ns = ctx.userText as NSString
            let keys = (regex?.matches(in: ctx.userText, range: NSRange(location: 0, length: ns.length)) ?? []).map { ns.substring(with: $0.range(at: 1)) }
            let estimates = keys.enumerated().map { index, key in #"{"key":"\#(key)","days":\#([3, 5, 7, 14, 30][index % 5])}"# }
            return #"{"estimates":["# + estimates.joined(separator: ",") + "]}"
        },
        broken: #"{"estimates":[{"key""#
    )

    // MARK: - Anthropic envelopes

    static func anthropicMessage(text: String, model: String) -> String {
        let escaped = String(decoding: (try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed])) ?? Data("[\"\"]".utf8), as: UTF8.self)
        let textJSON = String(escaped.dropFirst().dropLast())
        return #"{"id":"msg_test_\#(UUID().uuidString.prefix(12))","type":"message","role":"assistant","model":"\#(model)","content":[{"type":"text","text":\#(textJSON)}],"stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":1200,"output_tokens":\#(max(1, text.count / 4))}}"#
    }

    static func anthropicError(type: String, message: String) -> String {
        #"{"type":"error","error":{"type":"\#(type)","message":"\#(message)"}}"#
    }
}
