//
// ExtraGymSessionPlanner.swift
// Tempo
//
// "Add gym session" on a soccer day: decides the gym part's focus + intensity
// from what the morning's soccer actually cost (strain / hard minutes / sRPE /
// match), how long ago it ended, the week's needs and tomorrow's plan, and
// explains WHY. Pure and unit-tested — the view model only applies the result.
//

import Foundation

// MARK: - ExtraGymContext

struct ExtraGymContext: Sendable {
    struct Soccer: Sendable {
        /// Minutes since midnight the soccer session started.
        var startMin: Int
        var durationMin: Int?
        var strain: Double?
        var hardMinutes: Double?
        var sessionRPE: Int?
        var isMatch: Bool

        init(
            startMin: Int, durationMin: Int? = nil, strain: Double? = nil,
            hardMinutes: Double? = nil, sessionRPE: Int? = nil, isMatch: Bool = false
        ) {
            self.startMin = startMin
            self.durationMin = durationMin
            self.strain = strain
            self.hardMinutes = hardMinutes
            self.sessionRPE = sessionRPE
            self.isMatch = isMatch
        }
    }

    var soccer: Soccer
    /// Minutes since midnight the gym part starts.
    var gymStartMin: Int
    var acwr: Double?
    var recoveryZone: RecoveryZone?
    /// The safety floor said "recover" (severe tier) this morning.
    var floorSevere: Bool
    var tomorrowIsMatchOrFootball: Bool
    var tomorrowType: WorkoutType?
    var weekDoneTypes: [WorkoutType]
    var weekRemainingTypes: [WorkoutType]
    var requestedFocus: WorkoutType?

    init(
        soccer: Soccer, gymStartMin: Int, acwr: Double? = nil, recoveryZone: RecoveryZone? = nil,
        floorSevere: Bool = false, tomorrowIsMatchOrFootball: Bool = false,
        tomorrowType: WorkoutType? = nil, weekDoneTypes: [WorkoutType] = [],
        weekRemainingTypes: [WorkoutType] = [], requestedFocus: WorkoutType? = nil
    ) {
        self.soccer = soccer
        self.gymStartMin = gymStartMin
        self.acwr = acwr
        self.recoveryZone = recoveryZone
        self.floorSevere = floorSevere
        self.tomorrowIsMatchOrFootball = tomorrowIsMatchOrFootball
        self.tomorrowType = tomorrowType
        self.weekDoneTypes = weekDoneTypes
        self.weekRemainingTypes = weekRemainingTypes
        self.requestedFocus = requestedFocus
    }
}

// MARK: - SoccerLoad

enum SoccerLoad: String, Sendable {
    case easy
    case moderate
    case hard
}

// MARK: - ExtraGymFocusOption

struct ExtraGymFocusOption: Equatable, Sendable {
    let focus: WorkoutType
    let allowed: Bool
    let warning: String?
}

// MARK: - ExtraGymDecision

struct ExtraGymDecision: Equatable, Sendable {
    /// Gym focus; `.mobility` when the body says recover only.
    let focus: WorkoutType
    let intensity: SessionIntensity
    /// `WorkoutPlan.recoveryAdjustment` to build the part with (1.0 = full).
    let loadScale: Double
    /// Drop squat / deadlift / lunge-pattern compounds (heavy lower never on a soccer day).
    let excludeHeavyLower: Bool
    let headline: String
    let reasons: [String]
    let options: [ExtraGymFocusOption]
    let soccerLoad: SoccerLoad
    /// Hours between soccer end and gym start (negative = gym first).
    let gapHours: Double
}

// MARK: - ExtraGymSessionPlanner

nonisolated enum ExtraGymSessionPlanner {
    static let defaultSoccerMinutes = 90
    static let focusChoices: [WorkoutType] = [.push, .pull, .upper, .legs, .fullBody]

    static func soccerLoad(_ s: ExtraGymContext.Soccer) -> SoccerLoad {
        if s.isMatch {
            return .hard
        }
        if (s.strain ?? 0) >= 14 || (s.hardMinutes ?? 0) >= 20 || (s.sessionRPE ?? 0) >= 7 {
            return .hard
        }
        let hasData = s.strain != nil || s.hardMinutes != nil || s.sessionRPE != nil
        if hasData, (s.strain ?? 0) < 8, (s.hardMinutes ?? 0) < 10, (s.sessionRPE ?? 0) <= 4 {
            return .easy
        }
        return .moderate
    }

    static func decide(_ c: ExtraGymContext) -> ExtraGymDecision {
        let soccerEnd = c.soccer.startMin + (c.soccer.durationMin ?? defaultSoccerMinutes)
        let gapMin = c.gymStartMin - soccerEnd
        let gapHours = Double(gapMin) / 60
        let gymFirst = c.gymStartMin < c.soccer.startMin
        let load = soccerLoad(c.soccer)
        let veryHard = (c.soccer.strain ?? 0) >= 16 || (c.soccer.sessionRPE ?? 0) >= 8

        var reasons: [String] = []
        var mobilityOnly = false
        var tier: SessionIntensity = .moderate

        // 1. Hard vetoes.
        if c.floorSevere {
            mobilityOnly = true
            reasons.append("your recovery floor says recover today, mobility only")
        } else if let acwr = c.acwr, acwr > 1.3 {
            mobilityOnly = true
            reasons.append("your load is spiking (acute:chronic \(String(format: "%.1f", acwr))), mobility only")
        }

        // 2. Gap to soccer sets the ceiling.
        if !mobilityOnly {
            if gymFirst {
                tier = .easy
                reasons.append("gym comes before soccer, so keep it easy and upper to save your legs")
            } else if gapHours < 3 {
                tier = load == .hard ? .recovery : .easy
                if tier == .recovery {
                    mobilityOnly = true
                }
                reasons.append(String(
                    format: "only %.1f h after soccer, %@",
                    max(0, gapHours),
                    tier == .recovery ? "soccer was hard so mobility only" : "easy upper work only"
                ))
            } else if gapHours < 6 {
                tier = .moderate
                reasons.append(String(format: "%.1f h after soccer, moderate upper work is fine", gapHours))
            } else {
                tier = .moderate
                reasons.append(String(format: "%.0f h after soccer, enough rest for a moderate session", gapHours))
            }
        }

        // 3. At most one part above moderate: soccer hard caps the gym at moderate
        // (already the ceiling); a very hard match drops the gym one more tier.
        if !mobilityOnly {
            if load == .hard {
                reasons.append("soccer was hard, so the gym part stays capped at moderate")
            }
            if veryHard {
                switch tier {
                case .moderate:
                    tier = .easy
                    reasons.append("soccer was very hard, dropping the gym part one tier to easy")
                case .easy:
                    tier = .recovery
                    mobilityOnly = true
                    reasons.append("soccer was very hard, mobility only")
                default: break
                }
            }
        }

        // 4. Recovery zone red also pulls it down.
        if !mobilityOnly, c.recoveryZone == .red {
            if tier == .moderate {
                tier = .easy
            }
            reasons.append("recovery is red, going easy")
        }

        // Options per focus.
        let options = focusChoices.map { option(
            for: $0,
            c: c,
            gapHours: gapHours,
            mobilityOnly: mobilityOnly,
            gymFirst: gymFirst,
            load: load
        ) }

        // Focus.
        var focus: WorkoutType
        if mobilityOnly {
            focus = .mobility
        } else if let req = c.requestedFocus, options.first(where: { $0.focus == req })?.allowed == true {
            focus = req
            if let warn = options.first(where: { $0.focus == req })?.warning {
                reasons.append(warn.prefix(1).lowercased() + warn.dropFirst())
            }
        } else {
            focus = defaultFocus(c, options: options)
        }
        if !mobilityOnly, tier == .recovery {
            tier = .easy
        }
        if mobilityOnly {
            tier = .recovery
        }

        // Folded into the first (gap) reason so the legs point is made once.
        if !mobilityOnly, focus != .legs, !reasons.isEmpty {
            reasons[0] += ", legs already worked so no heavy lower"
        }

        let scale = switch tier {
        case .moderate: 0.9
        case .easy: 0.7
        default: 0.6
        }

        return ExtraGymDecision(
            focus: focus,
            intensity: tier,
            loadScale: scale,
            excludeHeavyLower: true,
            headline: headline(focus: focus, tier: tier),
            reasons: reasons.map { $0.prefix(1).uppercased() + $0.dropFirst() },
            options: options,
            soccerLoad: load,
            gapHours: gapHours
        )
    }

    // MARK: - Helpers

    private static func headline(focus: WorkoutType, tier: SessionIntensity) -> String {
        switch focus {
        case .mobility:
            return "Mobility only"
        case .legs:
            return "Light legs, \(tier.rawValue)"
        case .upper:
            return "Upper body, \(tier.rawValue)"
        case .fullBody:
            return "Full body, \(tier.rawValue)"
        default:
            return "\(focus.displayName), \(tier.rawValue)"
        }
    }

    private static func conflictsWithTomorrow(_ focus: WorkoutType, _ tomorrow: WorkoutType?) -> Bool {
        guard let t = tomorrow else {
            return false
        }
        if t == focus || t == .fullBody {
            return t.isGymWorkout
        }
        let upperish: Set<WorkoutType> = [.push, .pull, .upper]
        if focus == .upper {
            return upperish.contains(t)
        }
        if t == .upper {
            return upperish.contains(focus)
        }
        return false
    }

    private static func option(
        for focus: WorkoutType, c: ExtraGymContext, gapHours: Double,
        mobilityOnly: Bool, gymFirst: Bool, load: SoccerLoad
    ) -> ExtraGymFocusOption {
        if mobilityOnly {
            return .init(focus: focus, allowed: false, warning: "Blocked today. Body says recover")
        }
        var warning: String?
        switch focus {
        case .legs:
            if gymFirst || gapHours < 6 {
                return .init(focus: focus, allowed: false, warning: "Blocked. Under 6 h after soccer")
            }
            if c.soccer.isMatch {
                return .init(focus: focus, allowed: false, warning: "Blocked. Legs took a match today")
            }
            if c.tomorrowIsMatchOrFootball {
                return .init(focus: focus, allowed: false, warning: "Blocked. Football tomorrow")
            }
            warning = "Light legs only. No squats or deadlifts"
        case .fullBody:
            if gymFirst || gapHours < 3 {
                return .init(focus: focus, allowed: false, warning: "Blocked. Too soon after soccer")
            }
            warning = gapHours < 6 ? "Under 6 h after soccer. No heavy legs" : "No heavy legs"
        default:
            if conflictsWithTomorrow(focus, c.tomorrowType), let t = c.tomorrowType {
                warning = "Tomorrow is \(t.displayName). Tomorrow will adjust"
            }
        }
        return .init(focus: focus, allowed: true, warning: warning)
    }

    private static func defaultFocus(_ c: ExtraGymContext, options: [ExtraGymFocusOption]) -> WorkoutType {
        let allowed = Set(options.filter(\.allowed).map(\.focus))
        let preference: [WorkoutType] = [.upper, .push, .pull].filter { allowed.contains($0) }
        let owed = { (t: WorkoutType) in
            c.weekRemainingTypes.contains(t) && !c.weekDoneTypes.contains(t)
        }
        let clear = { (t: WorkoutType) in !conflictsWithTomorrow(t, c.tomorrowType) }
        return preference.first { owed($0) && clear($0) }
            ?? preference.first(where: clear)
            ?? preference.first { owed($0) }
            ?? .upper
    }
}
