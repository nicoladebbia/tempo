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
            case .screens: String(localized: "Screens")
            case .settings: String(localized: "Settings")
            case .exercises: String(localized: "Exercises")
            case .meals: String(localized: "Saved meals")
            case .pantry: String(localized: "Pantry")
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

    /// Search words for one entry, from a single translatable comma-separated list.
    static func words(_ list: String) -> [String] {
        list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static let screens: [AppSearchEntry] = [
        screen("today", String(localized: "Today"), String(localized: "Your day at a glance"), "sun.horizon.fill", words(String(localized: "home, dashboard, score")), .tab(.today)),
        screen("train", String(localized: "Train"), String(localized: "Today's session"), "dumbbell.fill", words(String(localized: "workout, gym, lift, session")), .tab(.train)),
        screen(
            "fuel",
            String(localized: "Fuel"),
            String(localized: "Meals and nutrition"),
            "fork.knife",
            words(String(localized: "food, eat, nutrition, calories, macros, diet")),
            .tab(.fuel)
        ),
        screen("arena", String(localized: "Arena"), String(localized: "Challenges and league"), "trophy.fill", words(String(localized: "compete, league, xp, challenge, friends")), .tab(.arena)),
        screen(
            "recovery",
            String(localized: "Recovery"),
            String(localized: "Sleep, HRV and readiness"),
            "heart.fill",
            words(String(localized: "sleep, hrv, readiness, whoop, rest")),
            .today(.recovery)
        ),
        screen(
            "lockdown",
            String(localized: "Daily tasks"),
            String(localized: "Your non-negotiables"),
            "checklist",
            words(String(localized: "lockdown, non-negotiables, habits, accountability, streak")),
            .today(.lockdown)
        ),
        screen(
            "body",
            String(localized: "Body"),
            String(localized: "Sleep, heart rate and weight"),
            "figure.stand",
            words(String(localized: "weight, body fat, photos, progress photos, strain")),
            .today(.body)
        ),
        screen("move", String(localized: "Move"), String(localized: "Steps and sessions"), "figure.walk", words(String(localized: "steps, activity, history, walk")), .today(.move)),
        screen(
            "mind",
            String(localized: "Study"),
            String(localized: "Focus time and exams"),
            "brain.head.profile",
            words(String(localized: "focus, exam, study time, pomodoro, mind")),
            .today(.mind)
        ),
        screen(
            "fuelToday",
            String(localized: "Today's nutrition"),
            String(localized: "Calories, macros and water"),
            "chart.bar",
            words(String(localized: "water, hydration, protein, carbs, fat")),
            .today(.fuel)
        ),
        screen(
            "day",
            String(localized: "Your day"),
            String(localized: "The full timeline"),
            "calendar.day.timeline.left",
            words(String(localized: "timeline, schedule, plan, agenda, today plan")),
            .today(.day)
        ),
        screen(
            "week",
            String(localized: "Week in review"),
            String(localized: "Training, food, recovery and study"),
            "calendar",
            words(String(localized: "weekly, summary, report, recap, last week")),
            .today(.weekReview)
        ),
        screen("ask", String(localized: "Ask Tempo"), String(localized: "Questions about your day"), "sparkles", words(String(localized: "coach, chat, ai, assistant, help")), .askTempo),
        screen("weekPlan", String(localized: "Week plan"), String(localized: "This week's sessions"), "calendar", words(String(localized: "training week, schedule, split")), .train(.weekPlan)),
        screen(
            "routines",
            String(localized: "My routines"),
            String(localized: "Your saved workouts"),
            "list.bullet.rectangle",
            words(String(localized: "templates, custom workout, saved workouts")),
            .train(.routines)
        ),
        screen(
            "trainer",
            String(localized: "Trainer program"),
            String(localized: "Your coach's plan"),
            "person.crop.circle.badge.checkmark",
            words(String(localized: "program, personal trainer, coach plan")),
            .train(.trainerProgram)
        ),
        screen(
            "away",
            String(localized: "Away from the gym"),
            String(localized: "Travel, injury or a break"),
            "airplane",
            words(String(localized: "travel, injury, pause, holiday, vacation, sick")),
            .train(.awayMode)
        ),
        screen(
            "library",
            String(localized: "Exercise library"),
            String(localized: "Every exercise and its history"),
            "books.vertical",
            words(String(localized: "exercises, movements, form, 1rm, e1rm")),
            .train(.exerciseLibrary)
        ),
        screen(
            "progress",
            String(localized: "Training progress"),
            String(localized: "Charts, records and history"),
            "chart.line.uptrend.xyaxis",
            words(String(localized: "prs, personal records, volume, strength, charts")),
            .train(.progress)
        ),
        screen("plan", String(localized: "Meal plan"), String(localized: "This week's meals"), "list.clipboard", words(String(localized: "menu, weekly plan, meals")), .fuel(.plan, nil)),
        screen("log", String(localized: "Food log"), String(localized: "What you ate"), "square.and.pencil", words(String(localized: "log meal, diary, history, eaten")), .fuel(.log, nil)),
        screen(
            "nutritionCoach",
            String(localized: "Nutrition coach"),
            String(localized: "Ask about food and targets"),
            "bubble.left.and.text.bubble.right",
            words(String(localized: "food coach, nutritionist, diet advice, micronutrients")),
            .fuel(.coach, nil)
        ),
        screen(
            "kitchen",
            String(localized: "Kitchen"),
            String(localized: "Pantry, groceries and receipts"),
            "refrigerator",
            words(String(localized: "pantry, groceries, shopping, receipts")),
            .fuel(.kitchen, .pantry)
        ),
        screen(
            "groceries",
            String(localized: "Groceries"),
            String(localized: "Your shopping list"),
            "cart",
            words(String(localized: "shopping list, buy, store, supermarket")),
            .fuel(.kitchen, .groceries)
        ),
        screen("receipts", String(localized: "Receipts"), String(localized: "Scanned store receipts"), "receipt", words(String(localized: "scan receipt, purchases")), .fuel(.kitchen, .receipts)),
        screen(
            "supplements",
            String(localized: "Supplements"),
            String(localized: "Doses and reminders"),
            "pills",
            words(String(localized: "vitamins, creatine, protein powder, omega, magnesium")),
            .fuel(.kitchen, .supplements)
        ),
        screen(
            "settings",
            String(localized: "Settings"),
            String(localized: "Everything you can change"),
            "gearshape.fill",
            words(String(localized: "preferences, options, ai features, ai consent, privacy")),
            .settingsHome
        ),
    ]

    static let settings: [AppSearchEntry] = [
        setting(
            .schedule,
            String(localized: "Schedule"),
            String(localized: "Wake time, bedtime, evening start"),
            "clock.fill",
            words(String(localized: "wake, wake up, bedtime, sleep time, evening, leisure, wind down, alarm"))
        ),
        setting(
            .training,
            String(localized: "Training"),
            String(localized: "Split, level, usual training time"),
            "dumbbell.fill",
            words(String(localized: "split, experience, level, days per week, football, units, kg, lbs, pounds, rest timer, deload, plate calculator"))
        ),
        setting(.focusTimer, String(localized: "Focus timer"), String(localized: "Session and break lengths"), "timer", words(String(localized: "pomodoro, study timer, break, session length"))),
        setting(.modes, String(localized: "Modes"), String(localized: "Exam mode, weekend mode"), "bolt.fill", words(String(localized: "exam mode, weekend mode, vacation mode"))),
        setting(
            .dietProfile,
            String(localized: "Diet profile"),
            String(localized: "Goal, diet and eating window"),
            "fork.knife",
            words(String(localized: "calories, macros, allergies, vegan, vegetarian, protein target, weight goal, eating window, intermittent fasting, biometrics, height"))
        ),
        setting(
            .weeklyHabits,
            String(localized: "Weekly habits"),
            String(localized: "Sunday planning, routine"),
            "calendar.badge.clock",
            words(String(localized: "sunday, weekly plan, routine, restaurants, cook time"))
        ),
        setting(
            .connections,
            String(localized: "Connections"),
            String(localized: "Whoop, Health, Calendar, location"),
            "link",
            words(String(localized: "whoop, apple health, healthkit, calendar, location, weather, permissions, connect"))
        ),
        setting(.todaysNotifications, String(localized: "Today's notifications"), String(localized: "What was sent today"), "tray.fill", words(String(localized: "inbox, alerts, messages, bell"))),
        setting(
            .notifications,
            String(localized: "Notifications"),
            String(localized: "Reminders and quiet hours"),
            "bell.fill",
            words(String(localized: "reminders, quiet hours, do not disturb, push, alerts, sound, notification level"))
        ),
        setting(
            .subscription,
            String(localized: "Subscription"),
            String(localized: "Your plan"),
            "crown.fill",
            words(String(localized: "pro, premium, upgrade, paywall, restore purchases, billing, trial, cancel"))
        ),
        setting(
            .account,
            String(localized: "Account"),
            String(localized: "Sign-in and deleting your data"),
            "person.crop.circle",
            words(String(localized: "sign in, sign out, log out, apple id, delete account, member since"))
        ),
        setting(
            .exportData,
            String(localized: "Export my data"),
            String(localized: "Download everything"),
            "square.and.arrow.up",
            words(String(localized: "download, backup, csv, gdpr, privacy"))
        ),
        setting(
            .profile,
            String(localized: "Profile"),
            String(localized: "Name, username and identity"),
            "person.fill",
            words(String(localized: "name, username, avatar, identity, birthday, age"))
        ),
        setting(
            .goal,
            String(localized: "Goal"),
            String(localized: "Your focus and a target with a date"),
            "target",
            words(String(localized: "target, target weight, lose weight, gain muscle, bench press goal, 5k goal, deadline"))
        ),
        setting(
            .getSetUp,
            String(localized: "Get set up"),
            String(localized: "The setup checklist"),
            "list.bullet.clipboard",
            words(String(localized: "checklist, onboarding, setup, finish setting up, first steps"))
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
        var allInTitle = true
        for word in words {
            if titleWords.contains(where: { $0.hasPrefix(word) }) {
                total += titleWords.first.map { $0.hasPrefix(word) } == true ? 40 : 30
            } else if keywordTexts.contains(where: { $0.hasPrefix(word) }) || keywordWords.contains(where: { $0.hasPrefix(word) }) {
                total += 20
                allInTitle = false
            } else if title.contains(word) {
                total += 10
                allInTitle = false
            } else {
                return nil
            }
        }
        // What is in the name beats what is only in the keywords ("bench" finds Bench Press
        // before a core move that merely uses a bench).
        if allInTitle {
            total += 25
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
        // The library opens filtered by name, so two rows with one name are one result.
        var seen = Set<String>()
        return rows.filter { seen.insert($0.name).inserted }.map { exercise in
            AppSearchEntry(
                id: "exercise.\(exercise.name)",
                title: exercise.name,
                subtitle: "\(exercise.muscleGroup.displayName) · \(exercise.equipment.displayName)",
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
                subtitle: String(localized: "\(Int(preset.totalCalories.rounded())) kcal · \(Int(preset.totalProtein.rounded())) g protein"),
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
