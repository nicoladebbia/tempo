//
// WarmupRoutine.swift
// Tempo
//
// Workout-specific warm-up + mobility routines shown as a guided block before
// the first working set. Each routine adapts to the day's training (Pull/Push/
// Legs/etc.) and layers in elbow + biceps-tendon prep on every day because of
// a current tendon issue. This is the SINGLE source of warm-up content — both
// the pre-session block (ActiveWorkoutView) and the WeekPlanView mobility card
// read from it, so the two surfaces never diverge.
//
// Static value data: no SwiftData schema, nothing logged or persisted. The
// general block is mobility/activation — there is nothing to recover, so it
// deliberately lives OUTSIDE WorkoutSessionState.
//

import Foundation

// MARK: - WarmupMove

/// One move in a warm-up routine, with a detailed how-to so the user knows
/// exactly what to do — not just a name and a duration.
struct WarmupMove: Identifiable, Equatable {
    let id = UUID()
    /// Move name, e.g. "Band pull-aparts".
    let name: String
    /// Dose, e.g. "2 × 15", "30s/side", "1 min".
    let dose: String
    /// Step-by-step explanation of how to perform it.
    let howTo: String
    /// Optional one-line coaching cue.
    let cue: String?
    /// True for the elbow/biceps-tendon prep layered into every day.
    let isTendonPrep: Bool
    /// Structured duration in seconds for TIMED moves (the guided flow runs a
    /// countdown and auto-advances). Nil = rep-based: the user reads `dose` and
    /// taps Next when done (no timer can know how long curls take).
    let durationSeconds: Int?

    init(
        name: String,
        dose: String,
        howTo: String,
        cue: String? = nil,
        isTendonPrep: Bool = false,
        durationSeconds: Int? = nil
    ) {
        self.name = name
        self.dose = dose
        self.howTo = howTo
        self.cue = cue
        self.isTendonPrep = isTendonPrep
        self.durationSeconds = durationSeconds
    }

    /// Stable, filename-safe identifier for the pre-rendered audio clip
    /// (e.g. "Band pull-aparts" → "band_pull_aparts"). Deterministic so the
    /// generation script and the runtime lookup agree.
    var slug: String {
        let lowered = name.lowercased()
        let allowed = lowered.map { ch -> Character in
            ch.isLetter || ch.isNumber ? ch : "_"
        }
        var s = String(allowed)
        while s.contains("__") {
            s = s.replacingOccurrences(of: "__", with: "_")
        }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

// MARK: - WarmupRoutine

/// A complete warm-up routine for a workout type: an ordered list of moves plus
/// an estimated total duration.
struct WarmupRoutine {
    let title: String
    /// "10–15 min" style estimate, shown in the header.
    let estimatedDuration: String
    let moves: [WarmupMove]

    /// Resolve the routine for a given workout type. Strength days get an
    /// activation/mobility sequence specific to the muscles trained, then the
    /// shared elbow + biceps-tendon prep block.
    static func routine(for type: WorkoutType) -> WarmupRoutine {
        let specific: [WarmupMove]
        let title: String

        switch type {
        case .pull:
            title = "Pull Warm-Up"
            specific = [
                WarmupMove(
                    name: "Arm circles + band pass-throughs",
                    dose: "1 min + 10 reps",
                    howTo: "Big slow arm circles forward and back to raise shoulder temperature, then hold a band shoulder-width and pass it overhead front-to-back with straight arms.",
                    cue: "Keep elbows long — don't bend to cheat the pass.",
                    durationSeconds: 60
                ),
                WarmupMove(
                    name: "Scapular pull-ups / scap retractions",
                    dose: "2 × 8",
                    howTo: "Hang from the bar (or hold a band) with straight arms and pull your shoulder blades down and together without bending the elbows. Lifts your body a few centimetres.",
                    cue: "Think 'put your shoulder blades in your back pockets'."
                ),
                WarmupMove(
                    name: "Band pull-aparts",
                    dose: "2 × 15",
                    howTo: "Hold a light band in front at shoulder height, arms straight, and pull it apart until it touches your chest, squeezing the mid-back. Control the return.",
                    cue: "Lead with the elbows, not the hands."
                ),
                WarmupMove(
                    name: "Cat-cow + thoracic rotations",
                    dose: "10 reps",
                    howTo: "On all fours, alternate arching and rounding the spine; then reach one hand to the ceiling, rotating the upper back, eyes following the hand.",
                    cue: "Move from the upper back, keep hips still."
                ),
            ]
        case .push:
            title = "Push Warm-Up"
            specific = [
                WarmupMove(
                    name: "Arm circles + shoulder dislocates",
                    dose: "1 min + 10 reps",
                    howTo: "Arm circles to warm the shoulders, then with a band held wide, pass it from in front of your hips up and over behind you with straight arms, widening grip if it's tight.",
                    cue: "Only go as wide as you can WITHOUT shrugging.",
                    durationSeconds: 60
                ),
                WarmupMove(
                    name: "Scapular push-ups",
                    dose: "2 × 10",
                    howTo: "In a push-up plank with straight arms, let your chest sink slightly between the shoulder blades, then push the floor away to spread them apart. Elbows stay locked.",
                    cue: "All the movement is the shoulder blades, not the elbows."
                ),
                WarmupMove(
                    name: "Rotator-cuff external rotations",
                    dose: "2 × 12/side",
                    howTo: "Elbow tucked to your side at 90°, hold a light band and rotate your forearm outward away from your belly, keeping the elbow pinned.",
                    cue: "Slow and small — this primes the cuff, not the biceps."
                ),
                WarmupMove(
                    name: "Wall slides",
                    dose: "2 × 10",
                    howTo: "Back to a wall, forearms and wrists on the wall, slide arms overhead keeping contact, then back down squeezing the mid-back.",
                    cue: "Ribs down, don't let your lower back arch off the wall."
                ),
            ]
        case .legs, .lower:
            title = "Leg Warm-Up"
            specific = [
                WarmupMove(
                    name: "Leg swings (front/back + side)",
                    dose: "10 each/side",
                    howTo: "Hold support and swing one leg forward and back, then across your body and out, keeping the torso tall. Loosens hips in both planes.",
                    cue: "Controlled range — don't ballistic-bounce at the end."
                ),
                WarmupMove(
                    name: "90/90 hip switches",
                    dose: "8/side",
                    howTo: "Sit with one shin in front and one out to the side, both knees at 90°, and rotate the knees from one side to the other without using your hands.",
                    cue: "Sit tall, drive the rotation from the hips."
                ),
                WarmupMove(
                    name: "Ankle rocks + deep squat hold",
                    dose: "10 reps + 30s",
                    howTo: "In a half-kneel, rock the front knee forward over the toes to mobilise the ankle; then drop into a deep bodyweight squat and hold, prying the knees out with the elbows.",
                    cue: "Heels stay flat on the floor the whole time."
                ),
                WarmupMove(
                    name: "Glute bridges",
                    dose: "2 × 15",
                    howTo: "On your back, knees bent, drive through the heels and squeeze the glutes to lift the hips, pausing at the top. Wakes up the posterior chain before squatting/hinging.",
                    cue: "Squeeze the glutes, don't arch the lower back."
                ),
            ]
        case .upper:
            title = "Upper Warm-Up"
            specific = [
                WarmupMove(
                    name: "Arm circles + band pass-throughs",
                    dose: "1 min + 10 reps",
                    howTo: "Arm circles both directions, then band pass-throughs overhead front-to-back with straight arms to open the shoulders for both pressing and pulling.",
                    cue: "Keep elbows long.",
                    durationSeconds: 60
                ),
                WarmupMove(
                    name: "Band pull-aparts",
                    dose: "2 × 15",
                    howTo: "Light band at shoulder height, arms straight, pull apart to the chest squeezing the mid-back, control the return.",
                    cue: "Lead with the elbows."
                ),
                WarmupMove(
                    name: "Scapular push-ups + scap pulls",
                    dose: "2 × 10",
                    howTo: "Alternate scapular push-ups (spread the blades in a plank) and scapular pulls (retract on a bar/band) to prime both push and pull patterns.",
                    cue: "Movement is the shoulder blades only."
                ),
                WarmupMove(
                    name: "Wall slides",
                    dose: "2 × 10",
                    howTo: "Forearms on a wall, slide overhead keeping contact, then down squeezing the mid-back.",
                    cue: "Ribs down, no lower-back arch."
                ),
            ]
        case .fullBody:
            title = "Full-Body Warm-Up"
            specific = [
                WarmupMove(
                    name: "Easy cardio (bike/row/jog)",
                    dose: "3 min",
                    howTo: "Light continuous effort to raise core temperature and heart rate before loading.",
                    cue: "Conversational pace — you're warming up, not training.",
                    durationSeconds: 180
                ),
                WarmupMove(
                    name: "World's greatest stretch",
                    dose: "5/side",
                    howTo: "From a lunge, drop the same-side elbow toward the floor inside the front foot, then rotate that arm up to the ceiling. Hits hips, T-spine and hamstrings.",
                    cue: "Reach tall through the top hand."
                ),
                WarmupMove(
                    name: "Band pull-aparts",
                    dose: "2 × 15",
                    howTo: "Light band, arms straight at shoulder height, pull apart to the chest and control back.",
                    cue: "Lead with the elbows."
                ),
                WarmupMove(
                    name: "Glute bridges + deep squat hold",
                    dose: "15 reps + 30s",
                    howTo: "Glute bridges to fire the posterior chain, then a deep squat hold to open the hips and ankles.",
                    cue: "Heels flat, glutes on."
                ),
            ]
        default:
            title = "Warm-Up"
            specific = [
                WarmupMove(
                    name: "Easy cardio",
                    dose: "3 min",
                    howTo: "Light bike, row or brisk walk to raise heart rate and core temperature.",
                    cue: "Conversational pace.",
                    durationSeconds: 180
                ),
                WarmupMove(
                    name: "Full-body mobility flow",
                    dose: "5 min",
                    howTo: "Move every major joint through its range: neck, shoulders, T-spine, hips, knees, ankles.",
                    cue: "Smooth and controlled.",
                    durationSeconds: 300
                ),
            ]
        }

        return WarmupRoutine(
            title: title,
            estimatedDuration: "10–15 min",
            moves: specific + tendonPrep
        )
    }

    /// Elbow + biceps-tendon prep, appended to every strength day because of a
    /// current biceps-tendon issue. Light, blood-flow and tolerance focused.
    private static let tendonPrep: [WarmupMove] = [
        WarmupMove(
            name: "Wrist/forearm circles + flexor stretch",
            dose: "30s + 30s",
            howTo: "Circle the wrists both directions, then gently extend one arm, palm up, and use the other hand to draw the fingers back, stretching the forearm flexors and the biceps-tendon line.",
            cue: "Stretch to mild tension, never pain.",
            isTendonPrep: true,
            durationSeconds: 60
        ),
        WarmupMove(
            name: "Light biceps-tendon glides",
            dose: "2 × 12",
            howTo: "With a very light band or no weight, slowly curl and lower through a full range, then slowly straighten the arm fully. Warms the tendon through its whole length before any heavy pulling.",
            cue: "Slow eccentrics — control the lowering. Stop if the tendon pinches.",
            isTendonPrep: true
        ),
    ]
}

// MARK: - MobilityFlow (§10 mobility / rest-day flows)

/// A standalone guided mobility flow for rest and mobility days. Reuses
/// `WarmupMove` (same player mechanics: timed moves auto-advance, rep-based
/// wait for a tap) but lives apart from the pre-lift warm-up routine — these
/// are recovery sessions, not session prep. Same static-value-data rule:
/// nothing persisted, no schema.
struct MobilityFlow: Identifiable, Equatable {
    let id: String
    let name: String
    /// One-line focus, shown under the name in the picker.
    let focus: String
    let moves: [WarmupMove]

    /// "~8 min" style estimate from the timed moves (rep-based counted at 45s).
    var estimatedDuration: String {
        let seconds = moves.reduce(0) { $0 + ($1.durationSeconds ?? 45) }
        return "~\(max(1, Int((Double(seconds) / 60).rounded()))) min"
    }

    static let all: [MobilityFlow] = [fullBodyReset, hipsHamstrings, shouldersTSpine, legsFlush]

    static let fullBodyReset = MobilityFlow(
        id: "full_body_reset",
        name: "Full-Body Reset",
        focus: "Head-to-toe — the default when nothing specific hurts.",
        moves: [
            WarmupMove(
                name: "Cat-cow",
                dose: "1 min",
                howTo: "On all fours, alternate slowly between arching the spine up (chin tucked) and letting it sag (chest forward, eyes up). Move with the breath — exhale up, inhale down.",
                cue: "Segment the spine — one vertebra at a time, no rushing.",
                durationSeconds: 60
            ),
            WarmupMove(
                name: "World's greatest stretch",
                dose: "45s per side",
                howTo: "Long lunge, back knee down. Drop the inside elbow toward the front foot, then rotate that arm up to the ceiling following it with your eyes. Flow between the two positions.",
                cue: "The rotation comes from the mid-back, not the shoulder.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Downward dog → cobra flow",
                dose: "1 min",
                howTo: "From a push-up position, push hips up and back into an inverted V, pedal the heels, then lower and slide through to a cobra — hips down, chest up. Flow between the two.",
                cue: "In the dog, push the floor away; in the cobra, keep the glutes soft.",
                durationSeconds: 60
            ),
            WarmupMove(
                name: "Deep squat hold",
                dose: "1 min",
                howTo: "Feet shoulder-width, sink into the deepest squat you can keep your heels down in. Elbows inside the knees, gently pry them out. Shift weight side to side.",
                cue: "Chest tall — use a doorframe for balance if you tip back.",
                durationSeconds: 60
            ),
            WarmupMove(
                name: "Hamstring flow",
                dose: "45s per side",
                howTo: "Kneel on one knee, straighten the front leg, hands on the floor either side. Rock the hips back to load the stretch, then ease off. Keep the front foot flexed.",
                cue: "Hinge from the hips — a flat back finds the hamstring faster.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Thread the needle",
                dose: "45s per side",
                howTo: "On all fours, slide one arm under the other, palm up, until the shoulder and ear rest on the floor. Reach through, hold, then unwind and reach that arm to the ceiling.",
                cue: "Let the upper back do the twisting — hips stay square.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Child's pose + breathing",
                dose: "1 min",
                howTo: "Knees wide, big toes together, sit back onto the heels and walk the hands long. Forehead down. Slow nasal breaths — in for 4, out for 6.",
                cue: "Every exhale, sink a little heavier into the floor.",
                durationSeconds: 60
            ),
        ]
    )

    static let hipsHamstrings = MobilityFlow(
        id: "hips_hamstrings",
        name: "Hips & Hamstrings",
        focus: "For heavy leg days, long sitting, or tight sprint hips.",
        moves: [
            WarmupMove(
                name: "90/90 hip switches",
                dose: "1 min",
                howTo: "Sit with both knees bent at 90° — one leg in front, one to the side. Keeping the chest tall, rotate both knees together over to the other side and back. Hands down for support if needed.",
                cue: "Lead with the knees, keep the heels planted.",
                durationSeconds: 60
            ),
            WarmupMove(
                name: "Pigeon stretch",
                dose: "1 min per side",
                howTo: "Front shin angled on the floor, back leg long behind. Square the hips, then fold the chest over the front shin. Breathe into the glute.",
                cue: "If the front knee complains, pull the foot closer to the hip.",
                durationSeconds: 120
            ),
            WarmupMove(
                name: "Couch stretch",
                dose: "45s per side",
                howTo: "Back foot up against a wall or couch, knee on the floor close to it, front foot planted. Squeeze the glute of the back leg and lift the chest tall.",
                cue: "The glute squeeze is the stretch — no arching the lower back.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Hamstring flow",
                dose: "45s per side",
                howTo: "Kneel on one knee, straighten the front leg, hands on the floor either side. Rock the hips back to load the stretch, then ease off. Keep the front foot flexed.",
                cue: "Hinge from the hips — a flat back finds the hamstring faster.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Deep squat hold",
                dose: "1 min",
                howTo: "Feet shoulder-width, sink into the deepest squat you can keep your heels down in. Elbows inside the knees, gently pry them out. Shift weight side to side.",
                cue: "Chest tall — use a doorframe for balance if you tip back.",
                durationSeconds: 60
            ),
        ]
    )

    static let shouldersTSpine = MobilityFlow(
        id: "shoulders_tspine",
        name: "Shoulders & T-Spine",
        focus: "For push/pull days and desk-hunched study blocks.",
        moves: [
            WarmupMove(
                name: "Arm circles",
                dose: "1 min",
                howTo: "Big, slow circles — forward, then backward. Let the circles grow to full range as the shoulders warm.",
                cue: "Slow and tall — no shrugging into the ears.",
                durationSeconds: 60
            ),
            WarmupMove(
                name: "Thread the needle",
                dose: "45s per side",
                howTo: "On all fours, slide one arm under the other, palm up, until the shoulder and ear rest on the floor. Reach through, hold, then unwind and reach that arm to the ceiling.",
                cue: "Let the upper back do the twisting — hips stay square.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Wall slides",
                dose: "2 × 10",
                howTo: "Back flat on a wall, arms in a goalpost. Slide the arms up overhead keeping wrists and elbows on the wall, then pull the elbows down and in.",
                cue: "Ribs down — don't let the lower back peel off the wall."
            ),
            WarmupMove(
                name: "Doorway pec stretch",
                dose: "45s per side",
                howTo: "Forearm on a doorframe, elbow at shoulder height. Step through the doorway until the chest opens. Vary the elbow height to hit different fibers.",
                cue: "Lean from the hips — the whole body steps through, not just the shoulder.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Prone swimmers",
                dose: "1 min",
                howTo: "Lie face down, arms long overhead. Lift the arms slightly, sweep them in a wide arc down toward the hips, then back overhead — like a slow backstroke in reverse.",
                cue: "Keep the forehead down; the arms hover the whole way.",
                durationSeconds: 60
            ),
        ]
    )

    static let legsFlush = MobilityFlow(
        id: "legs_flush",
        name: "Legs Flush",
        focus: "Post-football or post-legs: easy blood flow, nothing intense.",
        moves: [
            WarmupMove(
                name: "Standing quad stretch",
                dose: "45s per side",
                howTo: "Stand tall, pull one heel to the glute, knees together. Squeeze the glute of the standing leg to deepen the front-of-thigh stretch. Hold something for balance.",
                cue: "Knee points at the floor — don't let it drift forward.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Wall calf stretch",
                dose: "45s per side",
                howTo: "Hands on a wall, one leg back with the heel pressed down. Hold with a straight knee, then bend it slightly to move the stretch lower into the soleus.",
                cue: "The heel never leaves the floor — small stance changes, big difference.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Hamstring flow",
                dose: "45s per side",
                howTo: "Kneel on one knee, straighten the front leg, hands on the floor either side. Rock the hips back to load the stretch, then ease off. Keep the front foot flexed.",
                cue: "Hinge from the hips — a flat back finds the hamstring faster.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Figure-4 glute stretch",
                dose: "45s per side",
                howTo: "Lie on your back, cross one ankle over the other knee, then pull the bottom thigh toward the chest. Keep the crossed knee pushed gently away.",
                cue: "Head stays down — pull with the arms, not the neck.",
                durationSeconds: 90
            ),
            WarmupMove(
                name: "Legs up + slow breathing",
                dose: "2 min",
                howTo: "Lie on your back with legs up a wall or on a couch. Arms wide, palms up. Nasal breathing — in for 4, hold 2, out for 6. Let the legs drain.",
                cue: "This is the recovery part — actually slow the breath down.",
                durationSeconds: 120
            ),
        ]
    )
}
