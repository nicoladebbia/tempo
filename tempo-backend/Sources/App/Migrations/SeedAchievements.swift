import Fluent

// MARK: - Seed Achievement Definitions
// Per MODULE_ARENA.md Section 21 — 108 achievements across 7 categories and 5 tiers.
// Per TECHNICAL_FEASIBILITY_AUDIT.md Section 6 — Ship full set, expand post-launch.

struct SeedAchievements: AsyncMigration {
    func prepare(on database: Database) async throws {
        let achievements = Self.allAchievements()
        for ach in achievements {
            try await ach.create(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await AchievementDefinition.query(on: database).delete()
    }

    // MARK: - All 108 Achievement Definitions

    private static func allAchievements() -> [AchievementDefinition] {
        var all: [AchievementDefinition] = []
        all.append(contentsOf: trainingAchievements())
        all.append(contentsOf: studyAchievements())
        all.append(contentsOf: nutritionAchievements())
        all.append(contentsOf: recoveryAchievements())
        all.append(contentsOf: streakAchievements())
        all.append(contentsOf: socialAchievements())
        all.append(contentsOf: stepsAchievements())
        // Milestone / composite
        all.append(contentsOf: milestoneAchievements())
        return all
    }

    // MARK: - Training (15)

    private static func trainingAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_first_rep", name: "First Rep", description: "Complete your first workout.", category: "training", tier: "common", xpReward: 25, criteriaType: "workout_count", criteriaThreshold: 1, flavorText: "Everyone starts somewhere."),
            .init(id: "ach_iron_will", name: "Iron Will", description: "Complete 10 workouts.", category: "training", tier: "common", xpReward: 50, criteriaType: "workout_count", criteriaThreshold: 10, flavorText: "The habit is forming."),
            .init(id: "ach_gym_rat", name: "Gym Rat", description: "Complete 50 workouts.", category: "training", tier: "rare", xpReward: 150, criteriaType: "workout_count", criteriaThreshold: 50, flavorText: "The gym knows your name."),
            .init(id: "ach_centurion_lifts", name: "Centurion of Lifts", description: "Complete 100 workouts.", category: "training", tier: "epic", xpReward: 500, criteriaType: "workout_count", criteriaThreshold: 100, flavorText: "100 sessions. You're built different."),
            .init(id: "ach_iron_veteran", name: "Iron Veteran", description: "Complete 250 workouts.", category: "training", tier: "legendary", xpReward: 1500, criteriaType: "workout_count", criteriaThreshold: 250, flavorText: "A quarter thousand sessions. Respect."),
            .init(id: "ach_500_club", name: "500 Club", description: "Complete 500 workouts.", category: "training", tier: "mythic", xpReward: 5000, criteriaType: "workout_count", criteriaThreshold: 500, flavorText: "Half a thousand. Legend status."),
            .init(id: "ach_first_pr", name: "New Personal Best", description: "Set your first personal record.", category: "training", tier: "common", xpReward: 50, criteriaType: "pr_count", criteriaThreshold: 1, flavorText: "Stronger than yesterday."),
            .init(id: "ach_pr_hunter", name: "PR Hunter", description: "Set 10 personal records.", category: "training", tier: "rare", xpReward: 200, criteriaType: "pr_count", criteriaThreshold: 10, flavorText: "You keep breaking your own limits."),
            .init(id: "ach_pr_machine", name: "PR Machine", description: "Set 50 personal records.", category: "training", tier: "epic", xpReward: 750, criteriaType: "pr_count", criteriaThreshold: 50, flavorText: "The records don't stand a chance."),
            .init(id: "ach_early_bird_workout", name: "Dawn Patrol", description: "Complete a workout before 7 AM.", category: "training", tier: "common", xpReward: 30, criteriaType: "early_workout", criteriaThreshold: 1, flavorText: "While they sleep, you grind."),
            .init(id: "ach_5am_club", name: "5 AM Club", description: "Complete 10 workouts before 6 AM.", category: "training", tier: "rare", xpReward: 200, criteriaType: "early_workout", criteriaThreshold: 10, flavorText: "Discipline has a wake-up time."),
            .init(id: "ach_recovery_warrior", name: "Recovery Warrior", description: "Complete a workout on a red recovery day.", category: "training", tier: "common", xpReward: 40, criteriaType: "red_day_workout", criteriaThreshold: 1, flavorText: "Showed up when it was hardest."),
            .init(id: "ach_perfect_week_training", name: "Training Streak", description: "Complete all planned workouts in a week.", category: "training", tier: "rare", xpReward: 150, criteriaType: "perfect_training_week", criteriaThreshold: 1, flavorText: "Not a single workout missed."),
            .init(id: "ach_variety_pack", name: "Variety Pack", description: "Complete workouts of 5 different types.", category: "training", tier: "common", xpReward: 50, criteriaType: "workout_type_variety", criteriaThreshold: 5, flavorText: "Well-rounded athlete."),
            .init(id: "ach_football_ready", name: "Football Ready", description: "Complete 20 workouts with football-aware scheduling.", category: "training", tier: "rare", xpReward: 150, criteriaType: "football_aware_workouts", criteriaThreshold: 20, flavorText: "The pitch is your priority."),
        ]
    }

    // MARK: - Study (12)

    private static func studyAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_first_session", name: "First Session", description: "Complete your first study session.", category: "study", tier: "common", xpReward: 25, criteriaType: "study_sessions", criteriaThreshold: 1, flavorText: "Knowledge is power."),
            .init(id: "ach_10_hours", name: "10 Hours In", description: "Accumulate 10 hours of study time.", category: "study", tier: "common", xpReward: 50, criteriaType: "study_hours", criteriaThreshold: 10, flavorText: "The foundation is being laid."),
            .init(id: "ach_100_hours", name: "Scholar", description: "Accumulate 100 hours of study time.", category: "study", tier: "rare", xpReward: 200, criteriaType: "study_hours", criteriaThreshold: 100, flavorText: "100 hours of pure focus."),
            .init(id: "ach_500_hours", name: "Academic Weapon", description: "Accumulate 500 hours of study time.", category: "study", tier: "epic", xpReward: 750, criteriaType: "study_hours", criteriaThreshold: 500, flavorText: "They call you the weapon."),
            .init(id: "ach_1000_hours", name: "Grandmaster", description: "Accumulate 1,000 hours of study time.", category: "study", tier: "legendary", xpReward: 3000, criteriaType: "study_hours", criteriaThreshold: 1000, flavorText: "Mastery level."),
            .init(id: "ach_study_target", name: "On Target", description: "Hit your daily study target 7 days in a row.", category: "study", tier: "common", xpReward: 50, criteriaType: "study_target_streak", criteriaThreshold: 7, flavorText: "Consistency is king."),
            .init(id: "ach_study_streak_14", name: "Two-Week Scholar", description: "Hit your daily study target 14 days straight.", category: "study", tier: "rare", xpReward: 200, criteriaType: "study_target_streak", criteriaThreshold: 14, flavorText: "Two weeks of discipline."),
            .init(id: "ach_study_streak_100", name: "Centurion Scholar", description: "Hit your daily study target 100 days straight.", category: "study", tier: "mythic", xpReward: 5000, criteriaType: "study_target_streak", criteriaThreshold: 100, flavorText: "100 consecutive days. Unstoppable."),
            .init(id: "ach_exam_survivor", name: "Exam Survivor", description: "Complete exam mode (5+ days of 4h+ study).", category: "study", tier: "rare", xpReward: 150, criteriaType: "exam_mode_completion", criteriaThreshold: 1, flavorText: "You survived. They didn't."),
            .init(id: "ach_pomodoro_master", name: "Pomodoro Master", description: "Complete 100 Pomodoro sessions.", category: "study", tier: "rare", xpReward: 100, criteriaType: "pomodoro_count", criteriaThreshold: 100, flavorText: "25 minutes at a time."),
            .init(id: "ach_deep_focus", name: "Deep Focus", description: "Complete a 2-hour uninterrupted study session.", category: "study", tier: "common", xpReward: 40, criteriaType: "long_study_session", criteriaThreshold: 120, flavorText: "Flow state unlocked."),
            .init(id: "ach_midnight_oil", name: "Midnight Oil", description: "Study past midnight 5 times.", category: "study", tier: "common", xpReward: 30, criteriaType: "late_study", criteriaThreshold: 5, hidden: true, flavorText: "Burning it at both ends."),
        ]
    }

    // MARK: - Nutrition (12)

    private static func nutritionAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_first_meal", name: "Fueled Up", description: "Log your first meal.", category: "nutrition", tier: "common", xpReward: 25, criteriaType: "meals_logged", criteriaThreshold: 1, flavorText: "Food is fuel."),
            .init(id: "ach_meal_streak_7", name: "Consistent Eater", description: "Log all meals for 7 consecutive days.", category: "nutrition", tier: "common", xpReward: 50, criteriaType: "meal_log_consistency", criteriaThreshold: 7, flavorText: "A week of fueling right."),
            .init(id: "ach_meal_streak_30", name: "Meal Prep King", description: "Log all meals for 30 consecutive days.", category: "nutrition", tier: "rare", xpReward: 200, criteriaType: "meal_log_consistency", criteriaThreshold: 30, flavorText: "A month of perfect logging."),
            .init(id: "ach_protein_target", name: "Protein Target", description: "Hit your protein target 7 days in a row.", category: "nutrition", tier: "common", xpReward: 50, criteriaType: "protein_target_days", criteriaThreshold: 7, flavorText: "Muscles need protein."),
            .init(id: "ach_protein_month", name: "Protein Machine", description: "Hit your protein target for 30 consecutive days.", category: "nutrition", tier: "epic", xpReward: 500, criteriaType: "protein_target_days", criteriaThreshold: 30, flavorText: "30 days of hitting protein. Gains incoming."),
            .init(id: "ach_macro_master_7", name: "Macro Balance", description: "Hit all macro targets for 7 consecutive days.", category: "nutrition", tier: "rare", xpReward: 150, criteriaType: "macro_target_days", criteriaThreshold: 7, flavorText: "Balanced nutrition."),
            .init(id: "ach_macro_master_30", name: "Macro Architect", description: "Hit all macro targets for 30 consecutive days.", category: "nutrition", tier: "epic", xpReward: 750, criteriaType: "macro_target_days", criteriaThreshold: 30, flavorText: "Perfectly calibrated."),
            .init(id: "ach_early_breakfast", name: "Breakfast Champion", description: "Log breakfast before 9 AM for 14 days.", category: "nutrition", tier: "common", xpReward: 40, criteriaType: "early_breakfast", criteriaThreshold: 14, flavorText: "The most important meal."),
            .init(id: "ach_calorie_target_week", name: "Calorie Control", description: "Hit calorie target (within 10%) for 7 consecutive days.", category: "nutrition", tier: "rare", xpReward: 100, criteriaType: "calorie_target_days", criteriaThreshold: 7, flavorText: "Precision fueling."),
            .init(id: "ach_hydration_hero", name: "Hydration Hero", description: "Log water intake for 14 consecutive days.", category: "nutrition", tier: "common", xpReward: 40, criteriaType: "hydration_streak", criteriaThreshold: 14, flavorText: "Stay hydrated, stay sharp."),
            .init(id: "ach_no_junk_week", name: "Clean Eating", description: "Stay within calorie target for 14 consecutive days.", category: "nutrition", tier: "rare", xpReward: 150, criteriaType: "calorie_target_days", criteriaThreshold: 14, flavorText: "Two weeks of discipline."),
            .init(id: "ach_100_meals", name: "Century Meals", description: "Log 100 total meals.", category: "nutrition", tier: "common", xpReward: 50, criteriaType: "meals_logged", criteriaThreshold: 100, flavorText: "100 meals tracked."),
        ]
    }

    // MARK: - Recovery (10)

    private static func recoveryAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_first_green", name: "Green Light", description: "Achieve your first green recovery day.", category: "recovery", tier: "common", xpReward: 25, criteriaType: "green_recovery_days", criteriaThreshold: 1, flavorText: "Your body is ready."),
            .init(id: "ach_green_week", name: "Green Week", description: "7 green recovery days.", category: "recovery", tier: "common", xpReward: 50, criteriaType: "green_recovery_days", criteriaThreshold: 7, flavorText: "A week of optimal recovery."),
            .init(id: "ach_green_month", name: "Recovery Master", description: "30 green recovery days.", category: "recovery", tier: "rare", xpReward: 200, criteriaType: "green_recovery_days", criteriaThreshold: 30, flavorText: "Your body loves you back."),
            .init(id: "ach_green_90", name: "Recovery Elite", description: "90 green recovery days.", category: "recovery", tier: "epic", xpReward: 500, criteriaType: "green_recovery_days", criteriaThreshold: 90, flavorText: "Three months of green. Elite status."),
            .init(id: "ach_green_300", name: "Green Machine", description: "300 green recovery days.", category: "recovery", tier: "legendary", xpReward: 2000, criteriaType: "green_recovery_days", criteriaThreshold: 300, flavorText: "Your body is a temple."),
            .init(id: "ach_sleep_80", name: "Good Sleep", description: "Achieve a sleep score of 80+.", category: "recovery", tier: "common", xpReward: 25, criteriaType: "sleep_score", criteriaThreshold: 80, flavorText: "Rest well, perform well."),
            .init(id: "ach_sleep_90", name: "Sleep Champion", description: "Achieve a sleep score of 90+.", category: "recovery", tier: "rare", xpReward: 100, criteriaType: "sleep_score", criteriaThreshold: 90, flavorText: "Perfect rest."),
            .init(id: "ach_sleep_90_streak", name: "Sleep Perfectionist", description: "Score 90+ sleep for 7 consecutive nights.", category: "recovery", tier: "epic", xpReward: 500, criteriaType: "sleep_90_streak", criteriaThreshold: 7, flavorText: "A week of perfect sleep. Rare."),
            .init(id: "ach_first_sleep_log", name: "Sleep Tracked", description: "Log your first night of sleep.", category: "recovery", tier: "common", xpReward: 25, criteriaType: "sleep_logged", criteriaThreshold: 1, flavorText: "Recovery starts with sleep."),
            .init(id: "ach_hrv_pr", name: "HRV Personal Record", description: "Set a new HRV personal record.", category: "recovery", tier: "common", xpReward: 40, criteriaType: "hrv_pr", criteriaThreshold: 1, flavorText: "Your nervous system is thriving."),
        ]
    }

    // MARK: - Streaks (7)

    private static func streakAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_streak_3", name: "3-Day Streak", description: "Maintain a 3-day streak.", category: "streaks", tier: "common", xpReward: 25, criteriaType: "streak_days", criteriaThreshold: 3, flavorText: "The flame ignites."),
            .init(id: "ach_streak_7", name: "Perfect Week", description: "Maintain a 7-day streak.", category: "streaks", tier: "common", xpReward: 100, criteriaType: "streak_days", criteriaThreshold: 7, flavorText: "One full week. The habit is real."),
            .init(id: "ach_streak_14", name: "Two-Week Warrior", description: "Maintain a 14-day streak.", category: "streaks", tier: "rare", xpReward: 200, criteriaType: "streak_days", criteriaThreshold: 14, flavorText: "Two weeks of fire."),
            .init(id: "ach_streak_30", name: "Monthly Champion", description: "Maintain a 30-day streak.", category: "streaks", tier: "epic", xpReward: 500, criteriaType: "streak_days", criteriaThreshold: 30, flavorText: "A full month. You're not stopping."),
            .init(id: "ach_streak_60", name: "Two-Month Titan", description: "Maintain a 60-day streak.", category: "streaks", tier: "legendary", xpReward: 1500, criteriaType: "streak_days", criteriaThreshold: 60, flavorText: "60 days straight. Titanium will."),
            .init(id: "ach_streak_90", name: "Quarterly Legend", description: "Maintain a 90-day streak.", category: "streaks", tier: "legendary", xpReward: 2500, criteriaType: "streak_days", criteriaThreshold: 90, flavorText: "90 days. You've transcended."),
            .init(id: "ach_streak_365", name: "Year of Fire", description: "Maintain a 365-day streak.", category: "streaks", tier: "mythic", xpReward: 5000, criteriaType: "streak_days", criteriaThreshold: 365, flavorText: "An entire year. Mythic."),
        ]
    }

    // MARK: - Social (12)

    private static func socialAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_first_friend", name: "Battle Buddy", description: "Add your first friend.", category: "social", tier: "common", xpReward: 25, criteriaType: "friend_count", criteriaThreshold: 1, flavorText: "Together we rise."),
            .init(id: "ach_5_friends", name: "Squad", description: "Have 5 friends.", category: "social", tier: "common", xpReward: 50, criteriaType: "friend_count", criteriaThreshold: 5, flavorText: "Your crew is growing."),
            .init(id: "ach_20_friends", name: "Social Butterfly", description: "Have 20 friends.", category: "social", tier: "rare", xpReward: 150, criteriaType: "friend_count", criteriaThreshold: 20, flavorText: "Everyone knows your name."),
            .init(id: "ach_50_friends", name: "Commander", description: "Have 50 friends.", category: "social", tier: "epic", xpReward: 500, criteriaType: "friend_count", criteriaThreshold: 50, flavorText: "You lead an army."),
            .init(id: "ach_first_challenge_win", name: "Victor", description: "Win your first challenge.", category: "social", tier: "common", xpReward: 50, criteriaType: "challenge_wins", criteriaThreshold: 1, flavorText: "First blood."),
            .init(id: "ach_10_challenge_wins", name: "Champion", description: "Win 10 challenges.", category: "social", tier: "rare", xpReward: 200, criteriaType: "challenge_wins", criteriaThreshold: 10, flavorText: "A proven champion."),
            .init(id: "ach_25_challenge_wins", name: "Undefeated", description: "Win 25 challenges.", category: "social", tier: "epic", xpReward: 750, criteriaType: "challenge_wins", criteriaThreshold: 25, flavorText: "They fear your name."),
            .init(id: "ach_5_win_streak", name: "Winning Streak", description: "Win 5 challenges in a row.", category: "social", tier: "epic", xpReward: 500, criteriaType: "challenge_win_streak", criteriaThreshold: 5, flavorText: "Five in a row. Unstoppable."),
            .init(id: "ach_10_win_streak", name: "Invincible", description: "Win 10 challenges in a row.", category: "social", tier: "legendary", xpReward: 2000, criteriaType: "challenge_win_streak", criteriaThreshold: 10, flavorText: "10 straight wins. Legendary."),
            .init(id: "ach_5_challenges_done", name: "Competitor", description: "Complete 5 challenges (win or lose).", category: "social", tier: "common", xpReward: 50, criteriaType: "challenges_completed", criteriaThreshold: 5, flavorText: "You showed up."),
            .init(id: "ach_challenge_creator", name: "Gamemaster", description: "Create your first challenge.", category: "social", tier: "common", xpReward: 30, criteriaType: "challenges_created", criteriaThreshold: 1, flavorText: "You set the rules."),
            .init(id: "ach_group_win", name: "Group Domination", description: "Win a group challenge with 5+ participants.", category: "social", tier: "rare", xpReward: 200, criteriaType: "group_challenge_wins", criteriaThreshold: 1, flavorText: "Top of the pile."),
        ]
    }

    // MARK: - Steps & Movement (10)

    private static func stepsAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_5k_steps", name: "Getting Moving", description: "Hit 5,000 steps in a day.", category: "steps", tier: "common", xpReward: 25, criteriaType: "step_threshold", criteriaThreshold: 5000, flavorText: "Every step counts."),
            .init(id: "ach_10k_steps", name: "10K Steps", description: "Hit 10,000 steps in a day.", category: "steps", tier: "common", xpReward: 50, criteriaType: "step_threshold", criteriaThreshold: 10000, flavorText: "The gold standard."),
            .init(id: "ach_15k_steps", name: "Active Day", description: "Hit 15,000 steps in a day.", category: "steps", tier: "rare", xpReward: 100, criteriaType: "step_threshold", criteriaThreshold: 15000, flavorText: "Above and beyond."),
            .init(id: "ach_20k_steps", name: "Marathon Day", description: "Hit 20,000 steps in a day.", category: "steps", tier: "rare", xpReward: 150, criteriaType: "step_threshold", criteriaThreshold: 20000, flavorText: "A day on your feet."),
            .init(id: "ach_42k_steps", name: "Marathon Walker", description: "Hit 42,000 steps in a day.", category: "steps", tier: "epic", xpReward: 500, criteriaType: "step_threshold", criteriaThreshold: 42000, flavorText: "A full marathon distance."),
            .init(id: "ach_1m_total", name: "Million Steps", description: "Accumulate 1,000,000 total steps.", category: "steps", tier: "epic", xpReward: 750, criteriaType: "total_steps", criteriaThreshold: 1000000, flavorText: "One million steps. Incredible."),
            .init(id: "ach_10k_streak_7", name: "Step Streak", description: "Hit 10K+ steps for 7 consecutive days.", category: "steps", tier: "rare", xpReward: 150, criteriaType: "step_streak", criteriaThreshold: 7, flavorText: "A week of walking."),
            .init(id: "ach_10k_streak_30", name: "Step Machine", description: "Hit 10K+ steps for 30 consecutive days.", category: "steps", tier: "legendary", xpReward: 1500, criteriaType: "step_streak", criteriaThreshold: 30, flavorText: "30 days of 10K. Incredible consistency."),
            .init(id: "ach_5m_total", name: "5 Million Steps", description: "Accumulate 5,000,000 total steps.", category: "steps", tier: "legendary", xpReward: 2000, criteriaType: "total_steps", criteriaThreshold: 5000000, flavorText: "Five million. You've walked the earth."),
            .init(id: "ach_10m_total", name: "World Walker", description: "Accumulate 10,000,000 total steps.", category: "steps", tier: "mythic", xpReward: 5000, criteriaType: "total_steps", criteriaThreshold: 10000000, flavorText: "Ten million steps. Planet-scale."),
        ]
    }

    // MARK: - Milestones / Composite (30)

    private static func milestoneAchievements() -> [AchievementDefinition] {
        [
            .init(id: "ach_perfect_day", name: "Perfect Day", description: "Complete all 5 categories in one day.", category: "training", tier: "rare", xpReward: 200, criteriaType: "perfect_days", criteriaThreshold: 1, flavorText: "Workout, study, meals, sleep, steps. All in one day."),
            .init(id: "ach_perfect_week", name: "Perfect Week", description: "7 consecutive perfect days.", category: "training", tier: "epic", xpReward: 750, criteriaType: "perfect_day_streak", criteriaThreshold: 7, flavorText: "An entire week of perfection."),
            .init(id: "ach_perfect_month", name: "Perfect Month", description: "30 consecutive perfect days.", category: "training", tier: "mythic", xpReward: 5000, criteriaType: "perfect_day_streak", criteriaThreshold: 30, flavorText: "30 flawless days. You're a myth."),
            .init(id: "ach_level_5", name: "Contender", description: "Reach Level 5.", category: "training", tier: "common", xpReward: 50, criteriaType: "level_reached", criteriaThreshold: 5, flavorText: "You're in the game now."),
            .init(id: "ach_level_10", name: "Rising Star", description: "Reach Level 10.", category: "training", tier: "common", xpReward: 100, criteriaType: "level_reached", criteriaThreshold: 10, flavorText: "Double digits."),
            .init(id: "ach_level_20", name: "Gladiator", description: "Reach Level 20.", category: "training", tier: "rare", xpReward: 200, criteriaType: "level_reached", criteriaThreshold: 20, flavorText: "Welcome to the arena."),
            .init(id: "ach_level_30", name: "Captain", description: "Reach Level 30.", category: "training", tier: "epic", xpReward: 500, criteriaType: "level_reached", criteriaThreshold: 30, flavorText: "You lead from the front."),
            .init(id: "ach_level_40", name: "Titan", description: "Reach Level 40.", category: "training", tier: "legendary", xpReward: 1500, criteriaType: "level_reached", criteriaThreshold: 40, flavorText: "Among the titans."),
            .init(id: "ach_level_50", name: "Legend", description: "Reach Level 50.", category: "training", tier: "mythic", xpReward: 5000, criteriaType: "level_reached", criteriaThreshold: 50, flavorText: "Maximum level. True legend."),
            .init(id: "ach_first_prestige", name: "Prestige I", description: "Prestige for the first time.", category: "training", tier: "mythic", xpReward: 5000, criteriaType: "prestige_count", criteriaThreshold: 1, flavorText: "You reset to prove you can do it again."),
            .init(id: "ach_comeback", name: "The Comeback", description: "Achieve a perfect day after 3+ consecutive missed days.", category: "training", tier: "rare", xpReward: 150, criteriaType: "comeback_days", criteriaThreshold: 3, flavorText: "You fell. You got back up."),
            .init(id: "ach_app_7_days", name: "Week One", description: "Open Tempo for 7 consecutive days.", category: "training", tier: "common", xpReward: 25, criteriaType: "app_open_streak", criteriaThreshold: 7, flavorText: "First week done."),
            .init(id: "ach_app_30_days", name: "Monthly User", description: "Open Tempo for 30 consecutive days.", category: "training", tier: "rare", xpReward: 150, criteriaType: "app_open_streak", criteriaThreshold: 30, flavorText: "A month of showing up."),
            .init(id: "ach_app_100_days", name: "Centurion User", description: "Open Tempo for 100 consecutive days.", category: "training", tier: "epic", xpReward: 500, criteriaType: "app_open_streak", criteriaThreshold: 100, flavorText: "100 days. It's part of you now."),
            .init(id: "ach_app_365_days", name: "Year of Tempo", description: "Open Tempo for 365 consecutive days.", category: "training", tier: "legendary", xpReward: 3000, criteriaType: "app_open_streak", criteriaThreshold: 365, flavorText: "A full year. Tempo IS your life."),
            .init(id: "ach_total_xp_10k", name: "10K XP", description: "Earn 10,000 total XP.", category: "training", tier: "common", xpReward: 50, criteriaType: "total_xp", criteriaThreshold: 10000, flavorText: "Five figures."),
            .init(id: "ach_total_xp_50k", name: "50K XP", description: "Earn 50,000 total XP.", category: "training", tier: "rare", xpReward: 200, criteriaType: "total_xp", criteriaThreshold: 50000, flavorText: "Climbing fast."),
            .init(id: "ach_total_xp_100k", name: "100K Club", description: "Earn 100,000 total XP.", category: "training", tier: "epic", xpReward: 500, criteriaType: "total_xp", criteriaThreshold: 100000, flavorText: "Six figures of effort."),
            .init(id: "ach_weekend_warrior", name: "Weekend Warrior", description: "Complete all non-negotiables on a Saturday and Sunday.", category: "training", tier: "common", xpReward: 40, criteriaType: "weekend_completion", criteriaThreshold: 1, flavorText: "No days off."),
            .init(id: "ach_night_owl", name: "Night Owl", description: "Complete all tasks after 8 PM.", category: "training", tier: "common", xpReward: 30, criteriaType: "late_completion", criteriaThreshold: 1, hidden: true, flavorText: "Better late than never."),
            .init(id: "ach_triple_threat", name: "Triple Threat", description: "Complete workout, study target, and all meals in one day.", category: "training", tier: "common", xpReward: 40, criteriaType: "triple_completion", criteriaThreshold: 1, flavorText: "Body, mind, and fuel."),
            .init(id: "ach_10_perfect_days", name: "Perfectionist", description: "10 total perfect days.", category: "training", tier: "rare", xpReward: 150, criteriaType: "perfect_days", criteriaThreshold: 10, flavorText: "10 days of pure excellence."),
            .init(id: "ach_50_perfect_days", name: "Hall of Fame", description: "50 total perfect days.", category: "training", tier: "legendary", xpReward: 2000, criteriaType: "perfect_days", criteriaThreshold: 50, flavorText: "50 perfect days. Hall of fame material."),
            .init(id: "ach_leaderboard_top_10", name: "Top 10", description: "Reach the top 10 on the weekly leaderboard.", category: "social", tier: "rare", xpReward: 200, criteriaType: "leaderboard_rank", criteriaThreshold: 10, flavorText: "Top 10 in the world."),
            .init(id: "ach_leaderboard_top_3", name: "Podium", description: "Reach the top 3 on the weekly leaderboard.", category: "social", tier: "epic", xpReward: 750, criteriaType: "leaderboard_rank", criteriaThreshold: 3, flavorText: "On the podium."),
            .init(id: "ach_leaderboard_1", name: "Number One", description: "Reach #1 on the weekly leaderboard.", category: "social", tier: "legendary", xpReward: 2000, criteriaType: "leaderboard_rank", criteriaThreshold: 1, flavorText: "The very best."),
            .init(id: "ach_all_integrations", name: "Fully Connected", description: "Connect Whoop, NutriTrack, HealthKit, and Calendar.", category: "training", tier: "common", xpReward: 50, criteriaType: "integration_count", criteriaThreshold: 4, flavorText: "All systems online."),
            .init(id: "ach_rest_day_earned", name: "Earned Rest", description: "Take a rest day after a 7+ day streak.", category: "recovery", tier: "common", xpReward: 30, criteriaType: "earned_rest_day", criteriaThreshold: 1, flavorText: "Rest is part of the plan."),
            .init(id: "ach_freeze_save", name: "Saved by the Freeze", description: "Use a streak freeze to save a 14+ day streak.", category: "streaks", tier: "common", xpReward: 40, criteriaType: "freeze_save", criteriaThreshold: 1, flavorText: "Close call."),
            .init(id: "ach_daily_cap", name: "Max Effort", description: "Hit the daily XP cap.", category: "training", tier: "epic", xpReward: 300, criteriaType: "daily_xp_cap", criteriaThreshold: 1, flavorText: "You maxed out a day."),
        ]
    }
}
