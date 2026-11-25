//
// AppSearch.swift
// Tempo
//
// Local, instant search over what is in the app: screens, settings (with the
// words people use for them), the exercise library, saved meals and pantry
// items. Nothing leaves the phone and nothing is sent to a server.
//
// Three pure parts, all unit-tested:
//   - `AppSearchCatalog`: the fixed list of screens and settings, each with synonyms.
//   - `AppSearchMatcher`: turns a typed query into a ranked list.
//   - `AppSearchAction`: every destination maps to exactly one way of getting
//     there, through the routing the app already has.
// `AppSearchLoader` reads the person's own rows (exercises, meals, pantry).
//

import Foundation
import SwiftData

// MARK: - SettingsDestination

/// A page inside Settings. Settings is one navigation stack, so each of these
/// is a value pushed on it.
enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case schedule
    case training
    case focusTimer
    case modes
    case dietProfile
    case weeklyHabits
    case connections
    case todaysNotifications
    case notifications
    case subscription
    case account
    case exportData
    case profile
    case goal
    case getSetUp

    var id: String {
        rawValue
    }
}

// MARK: - TrainDestination

/// A page inside Train.
enum TrainDestination: String, CaseIterable, Hashable {
    case weekPlan
    case routines
    case trainerProgram
    case awayMode
    case exerciseLibrary
    case progress
}

// MARK: - AppSearchDestination

enum AppSearchDestination: Hashable {
    case tab(AppTab)
    case today(TodayRoute)
    case settingsHome
    case settings(SettingsDestination)
    case train(TrainDestination)
    /// The Exercise Library, filtered to one exercise.
    case exercise(name: String)
    case fuel(NutritionSection, KitchenSection?)
    case askTempo
}

// MARK: - AppSearchAction

/// The one way each destination is reached. `AppSearchAction` is what the
/// search screen performs; it only uses routing that already exists.
enum AppSearchAction: Equatable {
    case selectTab(AppTab)
    case pushToday(TodayRoute)
    case presentSettings(SettingsDestination?)
    case openTrain(TrainDestination, exercise: String?)
    case openFuel(NutritionSection, KitchenSection?)
    case presentAsk

    static func resolve(_ destination: AppSearchDestination) -> AppSearchAction {
        switch destination {
        case let .tab(tab): .selectTab(tab)
        case let .today(route): .pushToday(route)
        case .settingsHome: .presentSettings(nil)
        case let .settings(page): .presentSettings(page)
        case let .train(page): .openTrain(page, exercise: nil)
        case let .exercise(name): .openTrain(.exerciseLibrary, exercise: name)
        case let .fuel(section, kitchen): .openFuel(section, kitchen)
        case .askTempo: .presentAsk
        }
    }
}

// MARK: - AppSearchEntry

struct AppSearchEntry: Identifiable, Equatable {
    enum Section: Int, CaseIterable, Comparable {
        case screens
        case settings
        case exercises
        case meals
        case pantry

        var title: String {
            switch self {
            case .screens: "Screens"
            case .settings: "Settings"
            case .exercises: "Exercises"
            case .meals: "Saved meals"
            case .pantry: "Pantry"
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    let id: String
    let title: String
    let subtitle: String?
    let section: Section
    let icon: String
    /// Other words people use for it ("bedtime" finds Schedule).
    let keywords: [String]
    let destination: AppSearchDestination
}

// MARK: - AppSearchCatalog

enum AppSearchCatalog {
    static func screen(
        _ id: String, _ title: String, _ subtitle: String?, _ icon: String,
        _ keywords: [String], _ destination: AppSearchDestination
    ) -> AppSearchEntry {
        AppSearchEntry(
            id: "screen.\(id)", title: title, subtitle: subtitle, section: .screens,
            icon: icon, keywords: keywords, destination: destination
        )
    }

    static func setting(
        _ page: SettingsDestination, _ title: String, _ subtitle: String, _ icon: String, _ keywords: [String]
    ) -> AppSearchEntry {
        AppSearchEntry(
            id: "setting.\(page.rawValue)", title: title, subtitle: subtitle, section: .settings,
            icon: icon, keywords: keywords, destination: .settings(page)
        )
    }

    static let screens: [AppSearchEntry] = [
        screen("today", "Today", "Your day at a glance", "sun.horizon.fill", ["home", "dashboard", "score"], .tab(.today)),
        screen("train", "Train", "Today's session", "dumbbell.fill", ["workout", "gym", "lift", "session"], .tab(.train)),
        screen(
            "fuel",
            "Fuel",
            "Meals and nutrition",
            "fork.knife",
            ["food", "eat", "nutrition", "calories", "macros", "diet"],
            .tab(.fuel)
        ),
        screen("arena", "Arena", "Challenges and league", "trophy.fill", ["compete", "league", "xp", "challenge", "friends"], .tab(.arena)),
        screen(
            "recovery",
            "Recovery",
            "Sleep, HRV and readiness",
            "heart.fill",
            ["sleep", "hrv", "readiness", "whoop", "rest"],
            .today(.recovery)
        ),
        screen(
            "lockdown",
            "Daily tasks",
            "Your non-negotiables",
            "checklist",
            ["lockdown", "non-negotiables", "habits", "accountability", "streak"],
            .today(.lockdown)
        ),
        screen(
            "body",
            "Body",
            "Sleep, heart rate and weight",
            "figure.stand",
            ["weight", "body fat", "photos", "progress photos", "strain"],
            .today(.body)
        ),
        screen("move", "Move", "Steps and sessions", "figure.walk", ["steps", "activity", "history", "walk"], .today(.move)),
        screen(
            "mind",
            "Study",
            "Focus time and exams",
            "brain.head.profile",
            ["focus", "exam", "study time", "pomodoro", "mind"],
            .today(.mind)
        ),
        screen(
            "fuelToday",
            "Today's nutrition",
            "Calories, macros and water",
            "chart.bar",
            ["water", "hydration", "protein", "carbs", "fat"],
            .today(.fuel)
        ),
        screen(
            "day",
            "Your day",
            "The full timeline",
            "calendar.day.timeline.left",
            ["timeline", "schedule", "plan", "agenda", "today plan"],
            .today(.day)
        ),
        screen(
            "week",
            "Week in review",
            "Training, food, recovery and study",
            "calendar",
            ["weekly", "summary", "report", "recap", "last week"],
            .today(.weekReview)
        ),
        screen("ask", "Ask Tempo", "Questions about your day", "sparkles", ["coach", "chat", "ai", "assistant", "help"], .askTempo),
        screen("weekPlan", "Week plan", "This week's sessions", "calendar", ["training week", "schedule", "split"], .train(.weekPlan)),
        screen(
            "routines",
            "My routines",
            "Your saved workouts",
            "list.bullet.rectangle",
            ["templates", "custom workout", "saved workouts"],
            .train(.routines)
        ),
        screen(
            "trainer",
            "Trainer program",
            "Your coach's plan",
            "person.crop.circle.badge.checkmark",
            ["program", "personal trainer", "coach plan"],
            .train(.trainerProgram)
        ),
        screen(
            "away",
            "Away from the gym",
            "Travel, injury or a break",
            "airplane",
            ["travel", "injury", "pause", "holiday", "vacation", "sick"],
            .train(.awayMode)
        ),
        screen(
            "library",
            "Exercise library",
            "Every exercise and its history",
            "books.vertical",
            ["exercises", "movements", "form", "1rm", "e1rm"],
            .train(.exerciseLibrary)
        ),
        screen(
            "progress",
            "Training progress",
            "Charts, records and history",
            "chart.line.uptrend.xyaxis",
            ["prs", "personal records", "volume", "strength", "charts"],
            .train(.progress)
        ),
        screen("plan", "Meal plan", "This week's meals", "list.clipboard", ["menu", "weekly plan", "meals"], .fuel(.plan, nil)),
        screen("log", "Food log", "What you ate", "square.and.pencil", ["log meal", "diary", "history", "eaten"], .fuel(.log, nil)),
        screen(
            "nutritionCoach",
            "Nutrition coach",
            "Ask about food and targets",
            "bubble.left.and.text.bubble.right",
            ["food coach", "nutritionist", "diet advice", "micronutrients"],
            .fuel(.coach, nil)
        ),
        screen(
            "kitchen",
            "Kitchen",
            "Pantry, groceries and receipts",
            "refrigerator",
            ["pantry", "groceries", "shopping", "receipts"],
            .fuel(.kitchen, .pantry)
        ),
        screen(
            "groceries",
            "Groceries",
            "Your shopping list",
            "cart",
            ["shopping list", "buy", "store", "supermarket"],
            .fuel(.kitchen, .groceries)
        ),
        screen("receipts", "Receipts", "Scanned store receipts", "receipt", ["scan receipt", "purchases"], .fuel(.kitchen, .receipts)),
        screen(
            "supplements",
            "Supplements",
            "Doses and reminders",
            "pills",
            ["vitamins", "creatine", "protein powder", "omega", "magnesium"],
            .fuel(.kitchen, .supplements)
        ),
        screen(
            "settings",
            "Settings",
            "Everything you can change",
            "gearshape.fill",
            ["preferences", "options", "ai features", "ai consent", "privacy"],
            .settingsHome
        ),
    ]

    static let settings: [AppSearchEntry] = [
        setting(
            .schedule,
            "Schedule",
            "Wake time, bedtime, evening start",
            "clock.fill",
            ["wake", "wake up", "bedtime", "sleep time", "evening", "leisure", "wind down", "alarm"]
        ),
        setting(
            .training,
            "Training",
            "Split, level, usual training time",
            "dumbbell.fill",
            [
                "split",
                "experience",
                "level",
                "days per week",
                "football",
                "units",
                "kg",
                "lbs",
                "pounds",
                "rest timer",
                "deload",
                "plate calculator",
            ]
        ),
        setting(.focusTimer, "Focus timer", "Session and break lengths", "timer", ["pomodoro", "study timer", "break", "session length"]),
        setting(.modes, "Modes", "Exam mode, weekend mode", "bolt.fill", ["exam mode", "weekend mode", "vacation mode"]),
        setting(
            .dietProfile,
            "Diet profile",
            "Goal, diet and eating window",
            "fork.knife",
            [
                "calories",
                "macros",
                "allergies",
                "vegan",
                "vegetarian",
                "protein target",
                "weight goal",
                "eating window",
                "intermittent fasting",
                "biometrics",
                "height",
            ]
        ),
        setting(
            .weeklyHabits,
            "Weekly habits",
            "Sunday planning, routine",
            "calendar.badge.clock",
            ["sunday", "weekly plan", "routine", "restaurants", "cook time"]
        ),
        setting(
            .connections,
            "Connections",
            "Whoop, Health, Calendar, location",
            "link",
            ["whoop", "apple health", "healthkit", "calendar", "location", "weather", "permissions", "connect"]
        ),
        setting(.todaysNotifications, "Today's notifications", "What was sent today", "tray.fill", ["inbox", "alerts", "messages", "bell"]),
        setting(
            .notifications,
            "Notifications",
            "Reminders and quiet hours",
            "bell.fill",
            ["reminders", "quiet hours", "do not disturb", "push", "alerts", "sound", "notification level"]
        ),
        setting(
            .subscription,
            "Subscription",
            "Your plan",
            "crown.fill",
            ["pro", "premium", "upgrade", "paywall", "restore purchases", "billing", "trial", "cancel"]
        ),
        setting(
            .account,
            "Account",
            "Sign-in and deleting your data",
            "person.crop.circle",
            ["sign in", "sign out", "log out", "apple id", "delete account", "member since"]
        ),
        setting(
            .exportData,
            "Export my data",
            "Download everything",
            "square.and.arrow.up",
            ["download", "backup", "csv", "gdpr", "privacy"]
        ),
        setting(
            .profile,
            "Profile",
            "Name, username and identity",
            "person.fill",
            ["name", "username", "avatar", "identity", "birthday", "age"]
        ),
        setting(
            .goal,
            "Goal",
            "Your focus and a target with a date",
            "target",
            ["target", "target weight", "lose weight", "gain muscle", "bench press goal", "5k goal", "deadline"]
        ),
        setting(
            .getSetUp,
            "Get set up",
            "The setup checklist",
            "list.bullet.clipboard",
            ["checklist", "onboarding", "setup", "finish setting up", "first steps"]
        ),
    ]

    static var all: [AppSearchEntry] {
        screens + settings
    }
}

// MARK: - AppSearchMatcher

enum AppSearchMatcher {
    /// How many results a query returns at most.
    static let limit = 30

    /// Lower-cased, accent-free, one space between words.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }

    /// Ranks `entries` for `query`. Every word typed must match the start of a
    /// word in the title or a keyword (so "ben pre" finds Bench Press).
    /// An empty query returns nothing.
    static func results(for query: String, in entries: [AppSearchEntry], limit: Int = limit) -> [AppSearchEntry] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return []
        }
        let scored: [(entry: AppSearchEntry, score: Int)] = entries.compactMap { entry in
            score(words: words, query: words.joined(separator: " "), entry: entry).map { (entry, $0) }
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                if lhs.entry.section != rhs.entry.section {
                    return lhs.entry.section < rhs.entry.section
                }
                return lhs.entry.title.localizedCaseInsensitiveCompare(rhs.entry.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// nil when a typed word matches nothing in the entry.
    private static func score(words: [String], query: String, entry: AppSearchEntry) -> Int? {
        let title = normalize(entry.title)
        let titleWords = title.split(separator: " ").map(String.init)
        let keywordTexts = entry.keywords.map(normalize)
        let keywordWords = keywordTexts.flatMap { $0.split(separator: " ").map(String.init) }

        var total = 0
        for word in words {
            if titleWords.contains(where: { $0.hasPrefix(word) }) {
                total += titleWords.first.map { $0.hasPrefix(word) } == true ? 40 : 30
            } else if keywordTexts.contains(where: { $0.hasPrefix(word) }) || keywordWords.contains(where: { $0.hasPrefix(word) }) {
                total += 20
            } else if title.contains(word) {
                total += 10
            } else {
                return nil
            }
        }
        if title == query {
            total += 100
        } else if title.hasPrefix(query) {
            total += 50
        } else if keywordTexts.contains(query) {
            total += 30
        }
        return total
    }
}

// MARK: - AppSearchLoader

/// The person's own rows, as search entries.
@MainActor
enum AppSearchLoader {
    static func entries(in context: ModelContext) -> [AppSearchEntry] {
        AppSearchCatalog.all + exercises(in: context) + meals(in: context) + pantry(in: context)
    }

    static func exercises(in context: ModelContext) -> [AppSearchEntry] {
        let rows = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return rows.map { exercise in
            AppSearchEntry(
                id: "exercise.\(exercise.name)",
                title: exercise.name,
                subtitle: "\(exercise.muscleGroup.rawValue.capitalized) · \(exercise.equipment.rawValue.capitalized)",
                section: .exercises,
                icon: "figure.strengthtraining.traditional",
                keywords: [exercise.muscleGroup.rawValue, exercise.equipment.rawValue],
                destination: .exercise(name: exercise.name)
            )
        }
    }

    static func meals(in context: ModelContext) -> [AppSearchEntry] {
        let rows = (try? context.fetch(FetchDescriptor<MealPreset>())) ?? []
        return rows.map { preset in
            AppSearchEntry(
                id: "meal.\(preset.id.uuidString)",
                title: preset.name,
                subtitle: "\(Int(preset.totalCalories.rounded())) kcal · \(Int(preset.totalProtein.rounded())) g protein",
                section: .meals,
                icon: "fork.knife",
                keywords: [],
                destination: .fuel(.log, nil)
            )
        }
    }

    static func pantry(in context: ModelContext) -> [AppSearchEntry] {
        let rows = (try? context.fetch(FetchDescriptor<PantryItem>())) ?? []
        return rows.map { item in
            AppSearchEntry(
                id: "pantry.\(item.id.uuidString)",
                title: item.displayName,
                subtitle: item.brand.isEmpty ? nil : item.brand,
                section: .pantry,
                icon: "refrigerator",
                keywords: [item.canonicalName],
                destination: .fuel(.kitchen, .pantry)
            )
        }
    }
}
