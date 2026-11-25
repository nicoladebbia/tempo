import Foundation

/// Realistic sample day shared by every direction, so the three looks are compared on identical content.
/// Values mirror the `athlete` scenario. The lab never touches the real app's data.
enum Sample {
    static let name = "Nico"
    static let dateLine = "Sunday 22 November"

    // Recovery
    static let recovery = 78            // 0-100
    static let hrv = 74                 // ms
    static let restingHR = 52           // bpm
    static let sleepHours = "7h 40m"
    static let sleepScore = 91
    static let strain = 11.4            // 0-21
    static let recoveryWeek: [Int] = [64, 71, 58, 83, 77, 69, 78]

    // Training
    static let workoutName = "Push Day"
    static let workoutTime = "17:00"
    static let workoutDuration = "62 min"
    static let workoutExerciseCount = 6
    static let exercises: [Exercise] = [
        .init(name: "Barbell Bench Press", target: "4 × 6", lastBest: "92.5 kg × 6", sets: [
            .init(weight: 92.5, reps: 6, done: true), .init(weight: 92.5, reps: 6, done: true),
            .init(weight: 95, reps: 6, done: false), .init(weight: 95, reps: 6, done: false)]),
        .init(name: "Incline Dumbbell Press", target: "3 × 10", lastBest: "34 kg × 10", sets: [
            .init(weight: 34, reps: 10, done: false), .init(weight: 34, reps: 10, done: false),
            .init(weight: 34, reps: 10, done: false)]),
        .init(name: "Overhead Press", target: "3 × 8", lastBest: "57.5 kg × 8", sets: []),
        .init(name: "Cable Fly", target: "3 × 12", lastBest: "22.5 kg × 12", sets: []),
        .init(name: "Lateral Raise", target: "4 × 15", lastBest: "12 kg × 15", sets: []),
        .init(name: "Triceps Pushdown", target: "3 × 12", lastBest: "32.5 kg × 12", sets: []),
    ]
    static let restSeconds = 120
    static let elapsed = "18:42"
    static let weekPlan: [(day: String, label: String, done: Bool)] = [
        ("M", "Pull", true), ("T", "Legs", true), ("W", "Rest", true), ("T", "Push", true),
        ("F", "Run", true), ("S", "Rest", true), ("S", "Push", false)]

    // Fuel
    static let kcalEaten = 1420, kcalTarget = 2600
    static let protein = Macro(name: "Protein", eaten: 112, target: 190)
    static let carbs = Macro(name: "Carbs", eaten: 148, target: 336)
    static let fat = Macro(name: "Fat", eaten: 41, target: 64)
    static let waterMl = 1750, waterTargetMl = 3300
    static let meals: [Meal] = [
        .init(slot: "Breakfast", time: "08:10", title: "Oats, whey, blueberries", kcal: 540, protein: 42, eaten: true),
        .init(slot: "Lunch", time: "13:00", title: "Chicken rice bowl, avocado", kcal: 760, protein: 58, eaten: true),
        .init(slot: "Snack", time: "16:00", title: "Greek yogurt, honey, walnuts", kcal: 310, protein: 24, eaten: false),
        .init(slot: "Dinner", time: "20:00", title: "Salmon, potatoes, green beans", kcal: 820, protein: 54, eaten: false),
    ]
    static let recentFoods = ["Greek yogurt 200 g", "Banana", "Whey shake", "Chicken rice bowl", "Espresso"]

    // Accountability and Arena
    static let streakDays = 12
    static let tasksLeft = 2, tasksTotal = 5
    static let tasks: [(title: String, done: Bool)] = [
        ("Train", false), ("Hit protein", false), ("Study 90 min", true), ("Sleep by 23:30", true), ("3 L water", true)]
    static let level = 14, xp = 8300, rank = 3, rankOf = 12
    static let dayScore = 72            // 0-100, the one headline number

    struct Exercise: Identifiable { let id = UUID(); let name, target, lastBest: String; var sets: [WorkSet] }
    struct WorkSet: Identifiable { let id = UUID(); var weight: Double; var reps: Int; var done: Bool }
    struct Macro { let name: String; let eaten, target: Int }
    struct Meal: Identifiable { let id = UUID(); let slot, time, title: String; let kcal, protein: Int; var eaten: Bool }
}

/// Which screen a launch should open on: `-screen today|logger|food` (default today).
enum LabScreen: String {
    case today, logger, food
    static var requested: LabScreen {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screen"), args.indices.contains(i + 1) else { return .today }
        return LabScreen(rawValue: args[i + 1]) ?? .today
    }
}
