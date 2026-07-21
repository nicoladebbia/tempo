//
// DailyCoachPrompt.swift
// Tempo
//
// THE PROMPT IS THE PRODUCT (docs/INTELLIGENT_TRAINING_SYSTEM.md §5.2-FIX).
// This is not a data dump — it is a specced contract: an embedded JSON output
// schema, worked exemplars (good dual-goal day, recovery day, pre-match day),
// an explicit dual-goal weighting instruction (the concurrent-training
// interference rule, §12), and a hard "JSON only" constraint so the parser
// (DailySessionParser) and the floor (TrainingSafetyFloor) can do their jobs.
//
// Drill-sergeant Tempo voice (Decision #2), body-data-wins (Decision #3),
// dual goal soccer + physique (Decision #1).
//

import Foundation

enum DailyCoachPrompt {

    // MARK: - Exemplars (single source of truth — interpolated into the prompt
    // AND fed through the harness judges in a calibration test, so prompt and
    // test cannot drift. A known-good exemplar that fails its judge = broken judge.)

    /// Good physique-emphasis day, green recovery.
    static let exemplarGreen = #"{"modality":"push","intensity":"hard","durationMin":65,"blocks":[{"kind":"gym","label":"Push — chest/shoulders/triceps","split":"push","cue":"Full range, control the eccentric."}],"shortWhy":"Green. Physique block — earn the volume.","expectedSessionRPE":8}"#

    /// Recovery day, red recovery — picks rest UNAIDED.
    static let exemplarRecovery = #"{"modality":"rest","intensity":"recovery","durationMin":20,"blocks":[{"kind":"mobility","label":"Mobility + walk","cue":"Easy. Nasal breathing only."}],"shortWhy":"Recovery red. You recover today — non-negotiable.","fullWhy":"HRV suppressed, RHR up, recovery in the red. Loading now buys injury, not progress.","expectedSessionRPE":2}"#

    /// Pre-match day (match tomorrow), soccer-emphasis — sharp but NOT heavy legs.
    static let exemplarPreMatch = #"{"modality":"field","intensity":"easy","durationMin":35,"blocks":[{"kind":"field","label":"Activation + short sprints","reps":6,"distanceM":20,"restSec":90,"intensityPct":70,"cue":"Crisp, not maximal. Stay fresh for tomorrow."}],"shortWhy":"Match tomorrow. Prime the legs, don't drain them.","expectedSessionRPE":4}"#

    // MARK: - System prompt

    static var system: String { systemTemplate }

    private static let systemTemplate = """
    You are Tempo's daily training coach. You prescribe ONE session for today — \
    no menus, no options. Drill-sergeant tone: direct, terse, no coddling, but \
    never abusive. You coach a university student who plays soccer AND trains for \
    physique. Both goals matter. Body data wins: if recovery markers are poor, you \
    prescribe recovery — readiness beats motivation, always.

    READINESS — WHEN TO PRESCRIBE RECOVERY (read the body data FIRST, every day; \
    these are the dangerous-edge rules — when ANY fire, prescribe recovery/rest/ \
    mobility regardless of goal, and say why plainly):
    - Recovery score in the red (< 34) → recover. Non-negotiable.
    - Sleep debt >= 4h AND recovery not green (< 67) → recover. Severe sleep debt \
    on an already-suppressed day is the dangerous combination; do NOT "moderate- \
    load through it."
    - Respiratory rate elevated >= +2 br/min vs baseline AND recovery not green → \
    treat as early ILLNESS and recover. An elevated breathing rate is the \
    pre-symptomatic tell; training hard while incubating illness is the worst call \
    you can make. Weigh this signal even when the recovery score looks "only" yellow.
    - HRV crashed (well below baseline) AND resting HR spiked together → recover.
    Outside these triggers a yellow recovery day is a TRAIN day at moderate load — \
    do not over-cry recovery. Green + no flags → train as the goal demands.

    DUAL-GOAL INTERFERENCE (non-negotiable training science):
    - Soccer conditioning and hypertrophy interfere (concurrent-training effect). \
    High sprint/running volume blunts hypertrophy; heavy leg strength blunts sprint/agility.
    - You CANNOT maximize both in one day. The user's current block has an emphasis \
    (soccer or physique). Prescribe FOR the emphasis; hold the other goal at maintenance.
    - Never stack heavy lower-body strength AND high-intensity conditioning on the \
    same day. Space them or alternate days.
    - No heavy legs within 48h before a logged match.

    PLANNED MODALITY (when the user message states "TODAY'S PLANNED SESSION"): \
    the weekly planner already chose today's modality. KEEP it — your job that \
    day is to set its INTENSITY to readiness, not to re-pick the modality. \
    Override the planned modality ONLY when readiness forces recovery/rest, or a \
    hard constraint applies (match T-1 → no heavy legs; a pain flag on the muscle \
    it would load). Any override stays in-emphasis (e.g. physique-week legs→upper, \
    not legs→pool unless readiness forces it).

    AVAILABLE MODALITIES: gym (push/pull/legs/upper/lower/full_body), field \
    (sprint/agility), run, pool, bodyweight (home), mobility, rest.

    GYM IS A POINTER, NOT A PRESCRIPTION. For a gym day emit ONLY \
    {"kind":"gym","split":"<push|pull|legs|upper|lower|full_body>"}. Do NOT emit \
    weights, sets, or specific exercises — a separate engine fills those. Emitting \
    gym weights is an ERROR.

    TWO-A-DAY (optional, only when context earns it): you MAY prescribe two \
    time-separated parts in one day — e.g. lift in the afternoon plus easy field \
    work in the evening — when the venue/match context supports it (a usual \
    evening field slot, or a same-day match needing a morning primer). Rules, \
    non-negotiable: tag EVERY block with "scheduledMin" (minutes after midnight; \
    blocks sharing a value form one part) — an untimed two-a-day is an error; \
    parts must be >= 6h apart; at most ONE part above moderate effort (a hard \
    lift means the second part is easy — mobility, or field/run blocks at \
    intensityPct <= 75); NEVER heavy legs + field sprint/agility in the same \
    day; no second part at all when the load ratio is already high or readiness \
    is yellow-or-worse. When in doubt, prescribe ONE session — a second part is \
    a bonus, not a default. Single sessions need no scheduledMin.

    OUTPUT: Return ONE JSON object and NOTHING else. No prose before or after, no \
    markdown fences. Schema:
    {
      "modality": "<string>",                  // one modality label
      "intensity": "recovery|easy|moderate|hard|max",
      "durationMin": <int>,
      "blocks": [                              // >= 1 block
        {
          "kind": "gym|field|pool|run|bodyweight|mobility|rest",
          "label": "<short string>",
          "cue": "<one technique cue>",        // optional but encouraged
          "scheduledMin": <int>,               // two-a-day only: part start, minutes after midnight
          "split": "<gym only: push|pull|legs|upper|lower|full_body>",
          "reps": <int>, "distanceM": <num>, "restSec": <int>, "intensityPct": <num>,
          "durationSec": <int>, "stroke": "<pool>", "runType": "<run: tempo|interval|long>",
          "paceSecPerKm": <num>, "sets": <int>
        }
      ],
      "shortWhy": "<<= 120 chars, drill-sergeant>",
      "fullWhy": "<optional longer reasoning>",
      "expectedStrain": <num optional>,        // your strain prediction for non-gym work
      "expectedSessionRPE": <int 1-10 optional> // your whole-session RPE prediction
    }
    Per-kind required fields: gym needs split; field needs reps OR distanceM; pool \
    needs distanceM OR durationSec; run needs runType AND (distanceM OR durationSec); \
    bodyweight needs reps OR durationSec; mobility/rest need only a label.

    EXEMPLARS (target shape — do not copy verbatim):

    [Good physique-emphasis day, green recovery]
    \(exemplarGreen)

    [Recovery day, red recovery — you pick rest UNAIDED, do not wait to be told]
    \(exemplarRecovery)

    [Pre-match day (match tomorrow), soccer-emphasis — sharp but NOT heavy legs]
    \(exemplarPreMatch)
    """

    // MARK: - User message (the serialized picture)

    /// - Parameters:
    ///   - plannedModality: today's WorkoutPlan modality (the weekly planner's
    ///     choice — §8: weekly OWNS the modality-default). The brain KEEPS this
    ///     unless readiness forces recovery or a hard constraint forces an
    ///     in-emphasis override. nil only in cold-start before a plan exists.
    ///   - plannedSecondary: §21 requirement (b) — when the weekly planner marked
    ///     today a gym+cardio TWO-A-DAY, this is the second session's easy-cardio
    ///     modality ("run"/"pool"). Carries the planner's DECISION so the brain
    ///     KEEPS/refines the second part with full context rather than inventing
    ///     one — while still free to DROP it on poor readiness (the system
    ///     prompt's two-a-day rules govern how). nil = ordinary single session.
    ///     Already readiness-gated upstream: the deterministic candidate this is
    ///     derived from is single-part on an eased morning, so nil arrives here.
    static func userMessage(for p: ReadinessPicture, plannedModality: String? = nil,
                            plannedSecondary: String? = nil) -> String {
        var lines: [String] = []
        lines.append("TODAY'S BODY DATA:")
        lines.append("- Recovery score: \(Int(p.recoveryScore))/100")

        if p.hasBaselineForBrain {
            if let z = p.hrvZScore {
                lines.append("- HRV: z=\(fmt(z)) vs 30d baseline (\(p.hrvTrend7d.rawValue) over 7d)")
            }
            if let d = p.rhrDeltaBpm { lines.append("- Resting HR: \(fmt(d)) bpm vs baseline") }
            if let rd = p.respDeltaBrMin { lines.append("- Respiratory rate: \(fmt(rd)) br/min vs baseline") }
            if let td = p.skinTempDeltaC, abs(td) >= 0.5 { lines.append("- Skin temp: \(fmt(td))°C vs baseline\(td >= 1.0 ? " — illness watch" : "")") }
            if let ox = p.spo2, ox < 95 { lines.append("- Blood oxygen: \(Int(ox))% — below normal") }
            if let acwr = p.acuteChronicStrainRatio { lines.append("- Acute:chronic strain: \(fmt(acwr))") }
        } else {
            lines.append("- TRENDS BUILDING (day \(p.historyDayCount)/\(ReadinessPicture.minBrainHistoryDays)) — do NOT claim trend-based reasoning yet; use recovery score + sleep only.")
        }

        if let debt = p.sleepDebt { lines.append("- Sleep debt: \(fmt(debt))h") }
        if let sh = p.sleepHours { lines.append("- Slept: \(fmt(sh))h") }
        // Timing regularity — a coaching lever, not a floor signal. Only
        // surfaced when it's actually bad; the drill-sergeant should call it.
        if let sc = p.sleepConsistencyPct, sc < 60 {
            lines.append("- Sleep consistency: \(Int(sc))% — bed/wake timing is chaotic. Call it out; a consistent window IS training.")
        }

        if !p.yesterdaySessions.isEmpty {
            let y = p.yesterdaySessions.map { s in
                let hard = s.hardMinutes.map { ", \(Int($0))min Z4+" } ?? ""
                return "\(s.type) (strain \(s.strain.map { fmt($0) } ?? "?")\(hard))"
            }.joined(separator: ", ")
            // §14 #3 — felt cost beside measured load: strain says what the
            // body did, sRPE says what it cost. A gap between them is signal.
            let felt = p.yesterdaySessionRPE.map { " — felt RPE \($0)/10 (user-reported)" } ?? ""
            lines.append("- Yesterday: \(y)\(felt)")
        } else if let rpe = p.yesterdaySessionRPE {
            // No Whoop activity row, but the user still rated the session.
            lines.append("- Yesterday: session felt RPE \(rpe)/10 (user-reported).")
        }


        if let ci = p.checkIn {
            var parts: [String] = []
            if let m = ci.mood { parts.append("mood \(m)/5") }
            if let s = ci.stress { parts.append("stress \(s)/10") }
            if !ci.painFlags.isEmpty { parts.append("PAIN: \(ci.painFlags.joined(separator: ", ")) — route away from loading these") }
            if !parts.isEmpty { lines.append("- Check-in: \(parts.joined(separator: ", "))") }
        }

        lines.append("")
        lines.append("CONTEXT:")
        if let d = p.daysUntilNextMatch {
            lines.append("- Next match: \(d == 0 ? "TODAY" : d == 1 ? "TOMORROW (T-1: no heavy legs)" : "in \(d) days")")
        } else {
            lines.append("- No match scheduled.")
        }
        // §5 calendar awareness — academic crunch is load the body pays for.
        // Silence when the week is clear; the prompt stays calibrated.
        if let exam = p.examsSoon.first {
            let when = exam.daysUntil == 0 ? "TODAY" : exam.daysUntil == 1 ? "TOMORROW" : "in \(exam.daysUntil) days"
            let more = p.examsSoon.count > 1 ? " (+\(p.examsSoon.count - 1) more within 7 days)" : ""
            lines.append("- Exam: \(exam.subject) \(when)\(more) — exam stress counts as load; keep sessions efficient, protect sleep over volume.")
        }
        if let busy = p.busyHoursToday, busy >= 6 {
            lines.append("- Packed day: \(fmt(busy))h of calendar events — prescribe something short and low-logistics.")
        }
        // The system prompt teaches the emphasis-week semantics (prescribe FOR
        // the emphasis, hold the other at maintenance); this line carries the
        // value. nil = no TrainingBlock declared → the pre-D3 default, verbatim.
        if let emphasis = p.blockEmphasis {
            lines.append("- Block emphasis: \(emphasis.rawValue).")
        } else {
            lines.append("- Block emphasis: physique (default).")
        }
        // §16 venue context. Confidence-tiered phrasing (§16.3): a confirmed
        // answer is fact; an established pattern may assert the usual time; an
        // early pattern only names the venue. No line at all below 3 samples —
        // silence beats a guess.
        if let v = p.venueToday {
            let dur = v.durationMin.map { ", ~\($0) min" } ?? ""
            if v.confirmed {
                let time = v.startMin.map { " at \(VenuePatternMath.clockLabel($0))" } ?? ""
                lines.append("- Venue today: \(v.venueRaw)\(time)\(dur) (user-confirmed). Prescribe for this venue; home/bodyweight is always a fallback.")
            } else if v.assertsTime, let start = v.startMin {
                lines.append("- Venue today (usual pattern): \(v.venueRaw) around \(VenuePatternMath.clockLabel(start))\(dur). Prescribe for this venue unless readiness forces otherwise.")
            } else {
                lines.append("- Venue today (early pattern, low confidence): likely \(v.venueRaw).")
            }
        }
        if let planned = plannedModality {
            if let second = plannedSecondary {
                lines.append("- TODAY'S PLANNED SESSION: a TWO-A-DAY — \(planned) (the lift) PLUS an easy \(second) second session. The weekly planner decided today has the headroom for both. KEEP both parts: prescribe the lift, then an EASY \(second) block scheduled >= 6h later, each tagged with scheduledMin. The second part stays easy (intensityPct <= 75 / mobility-grade) — never a second hard effort. DROP the second part and prescribe the lift ALONE if readiness is yellow-or-worse, the acute:chronic load ratio is already high, or a pain flag loads that work. When you keep the lift, its own INTENSITY still follows today's readiness.")
            } else {
                lines.append("- TODAY'S PLANNED SESSION: \(planned). This is the week's plan for today — KEEP this modality. Adjust only its INTENSITY to today's readiness. Override the modality ONLY if readiness forces recovery, or a hard constraint applies (match T-1 → no heavy legs; a pain flag on the muscle this would load). Any override stays in-emphasis.")
            }
        }

        lines.append("")
        lines.append("Prescribe today's session. JSON only.")
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ d: Double) -> String {
        String(format: d.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", d)
    }
}
