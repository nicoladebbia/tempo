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
