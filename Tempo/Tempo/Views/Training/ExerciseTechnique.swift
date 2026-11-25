//
// ExerciseTechnique.swift
// Tempo
//
// The form guide for the most common lifts: the two or three cues that matter
// and the mistakes people make most. It is hand-written and bundled in code
// because the exercise library is seeded once on a phone and cannot carry
// new fields to existing installs.
//
// Only standard, widely taught coaching cues belong here. A lift that is not
// in the table shows no guide in the workout, and the exercise page falls back
// to the library's own cues. Nothing is invented for the rest.
//

import Foundation

// MARK: - ExerciseTechnique

struct ExerciseTechnique: Equatable {
    /// The two or three things to think about during the rep.
    let cues: [String]
    /// The two or three mistakes seen most often on this lift.
    let mistakes: [String]
}

// MARK: - ExerciseTechniqueLibrary

enum ExerciseTechniqueLibrary {
    /// The guide for a lift, matched by name (case and spacing do not matter).
    static func technique(forName name: String) -> ExerciseTechnique? {
        table[key(name)]
    }

    static func technique(for exercise: Exercise) -> ExerciseTechnique? {
        technique(forName: exercise.name)
    }

    /// Every lift the guide covers, by its library name.
    static var coveredNames: [String] {
        entries.map(\.name)
    }

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let table: [String: ExerciseTechnique] = Dictionary(
        entries.map { (key($0.name), $0.technique) },
        uniquingKeysWith: { first, _ in first }
    )

    private struct Entry {
        let name: String
        let technique: ExerciseTechnique

        init(_ name: String, cues: [String], mistakes: [String]) {
            self.name = name
            technique = ExerciseTechnique(cues: cues, mistakes: mistakes)
        }
    }

    // swiftlint:disable function_body_length
    private static let entries: [Entry] = [
        // MARK: Chest

        Entry(
            "Barbell Bench Press",
            cues: [
                String(localized: "Shoulder blades pinched back and down"),
                String(localized: "Feet planted, drive them into the floor"),
                String(localized: "Bar to mid-chest, forearms vertical at the bottom"),
            ],
            mistakes: [
                String(localized: "Bouncing the bar off your chest"),
                String(localized: "Flaring your elbows straight out to the sides"),
                String(localized: "Hips lifting off the bench"),
            ]
        ),
        Entry(
            "Dumbbell Flat Bench Press",
            cues: [
                String(localized: "Shoulder blades pinched back and down"),
                String(localized: "Elbows about 45 to 60 degrees from your sides"),
                String(localized: "Press up and slightly together over your chest"),
            ],
            mistakes: [
                String(localized: "Letting the dumbbells drift wide and low"),
                String(localized: "Flaring your elbows out to the sides"),
                String(localized: "Arching so hard your hips leave the bench"),
            ]
        ),
        Entry(
            "Incline Dumbbell Press",
            cues: [
                String(localized: "Bench at about 30 degrees"),
                String(localized: "Lower to a deep stretch with your elbows slightly tucked"),
                String(localized: "Press up and slightly in over your upper chest"),
            ],
            mistakes: [
                String(localized: "Bench set too steep, so it becomes a shoulder press"),
                String(localized: "Bouncing out of the bottom"),
                String(localized: "Shrugging your shoulders toward your ears"),
            ]
        ),
        Entry(
            "Push-Up",
            cues: [
                String(localized: "Hands under your shoulders, body in one straight line"),
                String(localized: "Squeeze your glutes and brace your abs"),
                String(localized: "Elbows about 45 degrees from your sides, chest to the floor"),
            ],
            mistakes: [
                String(localized: "Hips sagging or piking up"),
                String(localized: "Flaring your elbows straight out"),
                String(localized: "Stopping well short of full range"),
            ]
        ),
        Entry(
            "Dumbbell Fly",
            cues: [
                String(localized: "Slight bend in your elbows, held the same all rep"),
                String(localized: "Open your arms like a hug until your chest stretches"),
                String(localized: "Stop at shoulder level, no deeper"),
            ],
            mistakes: [
                String(localized: "Bending and straightening your elbows like a press"),
                String(localized: "Lowering so far that your shoulders take the strain"),
                String(localized: "Going so heavy the form falls apart"),
            ]
        ),
        Entry(
            "Cable Fly",
            cues: [
                String(localized: "Slight bend in your elbows, held the same all rep"),
                String(localized: "Sweep your hands together in a wide arc"),
                String(localized: "Squeeze your chest where your hands meet"),
            ],
            mistakes: [
                String(localized: "Turning the fly into a press"),
                String(localized: "Leaning in with your whole body"),
                String(localized: "Letting your shoulders roll forward"),
            ]
        ),
        Entry(
            "Chest Dip",
            cues: [
                String(localized: "Lean your torso forward to load the chest"),
                String(localized: "Lower until your upper arms are about parallel to the floor"),
                String(localized: "Shoulders down, not up around your ears"),
            ],
            mistakes: [
                String(localized: "Dropping so deep your shoulders roll forward"),
                String(localized: "Swinging your legs for momentum"),
                String(localized: "Staying fully upright, which shifts the work to your triceps"),
            ]
        ),

        // MARK: Shoulders

        Entry(
            "Overhead Press",
            cues: [
                String(localized: "Squeeze your glutes and brace before you press"),
                String(localized: "Keep the bar close to your face, then push your head through"),
                String(localized: "Lock out with the bar over your mid-foot"),
            ],
            mistakes: [
                String(localized: "Leaning back so it becomes an incline press"),
                String(localized: "Pressing the bar forward, away from your body"),
                String(localized: "Ribs flared and glutes loose"),
            ]
        ),
        Entry(
            "Dumbbell Shoulder Press",
            cues: [
                String(localized: "Ribs down, glutes tight"),
                String(localized: "Forearms vertical, wrists stacked over your elbows"),
                String(localized: "Press straight up and finish with your biceps by your ears"),
            ],
            mistakes: [
                String(localized: "Arching your lower back"),
                String(localized: "Pressing in front of you instead of straight up"),
                String(localized: "Cutting the lowering short"),
            ]
        ),
        Entry(
            "Lateral Raise",
            cues: [
                String(localized: "Lead with your elbows, not your hands"),
                String(localized: "Raise to shoulder height, no higher"),
                String(localized: "Slight bend in your elbows, control the way down"),
            ],
            mistakes: [
                String(localized: "Swinging the weight up with your body"),
                String(localized: "Shrugging your traps toward your ears"),
                String(localized: "Going so heavy the range shrinks"),
            ]
        ),
        Entry(
            "Face Pull",
            cues: [
                String(localized: "Set the rope at face height and pull toward your eyes"),
                String(localized: "Split the rope and keep your elbows high"),
                String(localized: "Squeeze your shoulder blades together at the end"),
            ],
            mistakes: [
                String(localized: "Going so heavy you lean back to pull"),
                String(localized: "Pulling to your chest instead of your face"),
                String(localized: "Letting your elbows drop below your hands"),
            ]
        ),

        // MARK: Back

        Entry(
            "Conventional Deadlift",
            cues: [
                String(localized: "Bar over your mid-foot, close to your shins"),
                String(localized: "Pull the slack out of the bar before it leaves the floor"),
                String(localized: "Push the floor away and keep the bar against your legs"),
            ],
            mistakes: [
                String(localized: "Rounding your lower back"),
                String(localized: "Jerking the bar off the floor"),
                String(localized: "Hips shooting up first, so it becomes a stiff-leg pull"),
            ]
        ),
        Entry(
            "Trap Bar Deadlift",
            cues: [
                String(localized: "Stand in the middle of the bar with your chest up"),
                String(localized: "Push the floor away and keep your back flat"),
                String(localized: "Stand tall and squeeze your glutes at the top"),
            ],
            mistakes: [
                String(localized: "Rounding your upper back"),
                String(localized: "Jerking the bar off the floor"),
                String(localized: "Leaning back at lockout"),
            ]
        ),
        Entry(
            "Sumo Deadlift",
            cues: [
                String(localized: "Toes out, push your knees out over your toes"),
                String(localized: "Chest tall, pull the slack out of the bar"),
                String(localized: "Push the floor apart as you stand"),
            ],
            mistakes: [
                String(localized: "Knees caving in"),
                String(localized: "Hips shooting up before the bar moves"),
                String(localized: "Letting the bar drift away from your legs"),
            ]
        ),
        Entry(
            "Barbell Row",
            cues: [
                String(localized: "Hinge until your torso is near parallel and hold it there"),
                String(localized: "Pull the bar to your lower ribs"),
                String(localized: "Lead with your elbows and squeeze your shoulder blades"),
            ],
            mistakes: [
                String(localized: "Standing up a little each rep to heave the weight"),
                String(localized: "Rounding your lower back"),
                String(localized: "Pulling with your hands instead of your back"),
            ]
        ),
        Entry(
            "Single-Arm Dumbbell Row",
            cues: [
                String(localized: "Flat back, braced hand under your shoulder"),
                String(localized: "Pull your elbow toward your hip"),
                String(localized: "Pause at the top and lower under control"),
            ],
            mistakes: [
                String(localized: "Twisting your torso to swing the weight"),
                String(localized: "Shrugging the weight up instead of pulling"),
                String(localized: "Cutting the stretch at the bottom short"),
            ]
        ),
        Entry(
            "Seated Cable Row",
            cues: [
                String(localized: "Sit tall with your chest proud"),
                String(localized: "Pull the handle to your lower ribs"),
                String(localized: "Let your shoulder blades stretch forward, then squeeze back"),
            ],
            mistakes: [
                String(localized: "Rocking back to move the weight"),
                String(localized: "Shrugging your shoulders toward your ears"),
                String(localized: "Slumping your whole torso forward at the start of each rep"),
            ]
        ),
        Entry(
            "Pull-Up",
            cues: [
                String(localized: "Start from a full hang with your shoulders pulled down"),
                String(localized: "Drive your elbows toward your hips"),
                String(localized: "Chin over the bar, then lower under control"),
            ],
            mistakes: [
                String(localized: "Kipping or swinging for momentum"),
                String(localized: "Half reps that never reach a full hang"),
                String(localized: "Craning your neck to get your chin over"),
            ]
        ),
        Entry(
            "Chin-Up",
            cues: [
                String(localized: "Palms toward you, hands about shoulder width"),
                String(localized: "Lead with your chest toward the bar"),
                String(localized: "Lower to a full hang under control"),
            ],
            mistakes: [
                String(localized: "Kipping or swinging for momentum"),
                String(localized: "Stopping short of a full hang"),
                String(localized: "Shrugging your shoulders up around your ears"),
            ]
        ),
        Entry(
            "Lat Pulldown",
            cues: [
                String(localized: "Lean back slightly with your chest up"),
                String(localized: "Pull the bar to your upper chest"),
                String(localized: "Drive your elbows down and in"),
            ],
            mistakes: [
                String(localized: "Pulling the bar behind your neck"),
                String(localized: "Leaning way back to swing the weight"),
                String(localized: "Letting the bar yank your arms straight at the top"),
            ]
        ),

        // MARK: Legs

        Entry(
            "Barbell Back Squat",
            cues: [
                String(localized: "Big breath and brace before every rep"),
                String(localized: "Knees track out over your toes"),
                String(localized: "Whole foot planted, drive up through your mid-foot"),
            ],
            mistakes: [
                String(localized: "Knees caving inward"),
                String(localized: "Hips rising first while your chest drops"),
                String(localized: "Heels lifting off the floor"),
            ]
        ),
        Entry(
            "Front Squat",
            cues: [
                String(localized: "Elbows high, upper arms near parallel to the floor"),
                String(localized: "Stay tall with your chest up"),
                String(localized: "Knees out, sit straight down"),
            ],
            mistakes: [
                String(localized: "Elbows dropping so the bar rolls forward"),
                String(localized: "Rounding your upper back"),
                String(localized: "Heels coming off the floor"),
            ]
        ),
        Entry(
            "Goblet Squat",
            cues: [
                String(localized: "Hold the weight tight against your chest"),
                String(localized: "Elbows inside your knees at the bottom"),
                String(localized: "Chest tall, push your knees out"),
            ],
            mistakes: [
                String(localized: "Letting your chest fall forward"),
                String(localized: "Heels lifting off the floor"),
                String(localized: "Knees caving in"),
            ]
        ),
        Entry(
            "Leg Press",
            cues: [
                String(localized: "Feet about shoulder width, in the middle of the platform"),
                String(localized: "Lower until your knees reach about 90 degrees or a bit deeper"),
                String(localized: "Press through your whole foot with knees tracking over your toes"),
            ],
            mistakes: [
                String(localized: "Lower back peeling off the pad at the bottom"),
                String(localized: "Locking your knees hard at the top"),
                String(localized: "Letting your knees cave in"),
            ]
        ),
        Entry(
            "Bulgarian Split Squat",
            cues: [
                String(localized: "Front foot far enough forward to keep your heel down"),
                String(localized: "Torso slightly forward, weight on the front foot"),
                String(localized: "Lower straight down and drive up through the front leg"),
            ],
            mistakes: [
                String(localized: "Pushing off the back foot instead of the front leg"),
                String(localized: "Front foot too close, so your heel lifts"),
                String(localized: "Front knee caving inward"),
            ]
        ),
        Entry(
            "Walking Lunge",
            cues: [
                String(localized: "Take a long step with your torso upright"),
                String(localized: "Drop your back knee straight down toward the floor"),
                String(localized: "Drive through your front foot to step forward"),
            ],
            mistakes: [
                String(localized: "Steps so short your front heel lifts"),
                String(localized: "Front knee caving in"),
                String(localized: "Leaning forward and rushing the reps"),
            ]
        ),
        Entry(
            "Romanian Deadlift",
            cues: [
                String(localized: "Soft knees, push your hips straight back"),
                String(localized: "Bar slides down your thighs the whole way"),
                String(localized: "Stop at a full hamstring stretch with your back flat"),
            ],
            mistakes: [
                String(localized: "Squatting it down instead of hinging"),
                String(localized: "Rounding your back to reach lower"),
                String(localized: "Letting the bar drift away from your legs"),
            ]
        ),
        Entry(
            "Dumbbell Romanian Deadlift",
            cues: [
                String(localized: "Soft knees, push your hips straight back"),
                String(localized: "Dumbbells slide down your thighs"),
                String(localized: "Stop at a full hamstring stretch with your back flat"),
            ],
            mistakes: [
                String(localized: "Squatting it down instead of hinging"),
                String(localized: "Rounding your back to reach lower"),
                String(localized: "Letting the dumbbells drift away from your legs"),
            ]
        ),
        Entry(
            "Hip Thrust",
            cues: [
                String(localized: "Chin tucked and ribs down"),
                String(localized: "Shins vertical at the top, drive through your heels"),
                String(localized: "Squeeze your glutes and pause at the top"),
            ],
            mistakes: [
                String(localized: "Arching your lower back to finish the rep"),
                String(localized: "Feet too far away, so your hamstrings take over"),
                String(localized: "Pushing through your toes"),
            ]
        ),
        Entry(
            "Leg Curl",
            cues: [
                String(localized: "Hips pressed into the pad"),
                String(localized: "Curl your heels toward your glutes"),
                String(localized: "Lower slowly through the full range"),
            ],
            mistakes: [
                String(localized: "Hips lifting off the pad"),
                String(localized: "Swinging the weight up"),
                String(localized: "Cutting the stretch at the bottom short"),
            ]
        ),
        Entry(
            "Leg Extension",
            cues: [
                String(localized: "Pad just above your ankles"),
                String(localized: "Squeeze your quads at the top"),
                String(localized: "Lower slowly, no dropping"),
            ],
            mistakes: [
                String(localized: "Kicking the weight up with momentum"),
                String(localized: "Hips lifting off the seat"),
                String(localized: "Slamming the weight stack at the bottom"),
            ]
        ),
        Entry(
            "Standing Calf Raise",
            cues: [
                String(localized: "Full stretch at the bottom, full squeeze at the top"),
                String(localized: "Pause for a second at each end"),
                String(localized: "Keep your knees steady so your ankles do the work"),
            ],
            mistakes: [
                String(localized: "Bouncing out of the bottom"),
                String(localized: "Short half reps"),
                String(localized: "Bending and straightening your knees"),
            ]
        ),
        Entry(
            "Kettlebell Swing",
            cues: [
                String(localized: "Hinge at your hips and hike the bell back"),
                String(localized: "Snap your hips forward and squeeze your glutes"),
                String(localized: "Your arms are ropes, the bell floats to chest height"),
            ],
            mistakes: [
                String(localized: "Squatting it instead of hinging"),
                String(localized: "Lifting the bell with your arms"),
                String(localized: "Leaning back at the top"),
            ]
        ),

        // MARK: Arms

        Entry(
            "Barbell Curl",
            cues: [
                String(localized: "Elbows pinned at your sides"),
                String(localized: "Curl with control, no swinging"),
                String(localized: "Squeeze at the top and lower slowly"),
            ],
            mistakes: [
                String(localized: "Swinging your torso to lift the weight"),
                String(localized: "Elbows drifting forward"),
                String(localized: "Dropping the bar fast on the way down"),
            ]
        ),
        Entry(
            "Dumbbell Curl",
            cues: [
                String(localized: "Elbows pinned at your sides"),
                String(localized: "Turn your palm up as you curl"),
                String(localized: "Lower all the way down under control"),
            ],
            mistakes: [
                String(localized: "Swinging your body to get the weight up"),
                String(localized: "Elbows moving forward"),
                String(localized: "Half reps that skip the bottom"),
            ]
        ),
        Entry(
            "Hammer Curl",
            cues: [
                String(localized: "Thumbs up, palms facing each other"),
                String(localized: "Elbows pinned at your sides"),
                String(localized: "Lower slowly, no swinging"),
            ],
            mistakes: [
                String(localized: "Swinging with your lower back"),
                String(localized: "Letting your elbows drift forward"),
                String(localized: "Bending your wrists"),
            ]
        ),
        Entry(
            "Tricep Pushdown",
            cues: [
                String(localized: "Elbows pinned to your sides"),
                String(localized: "Push down until your arms are fully straight"),
                String(localized: "Control the way up, forearms no higher than parallel"),
            ],
            mistakes: [
                String(localized: "Leaning over the bar to push with your body weight"),
                String(localized: "Elbows flaring or drifting forward"),
                String(localized: "Shoulders hunching up"),
            ]
        ),
        Entry(
            "Skull Crusher",
            cues: [
                String(localized: "Elbows pointing at the ceiling, not flared"),
                String(localized: "Lower toward your forehead under control"),
                String(localized: "Extend until your arms are straight"),
            ],
            mistakes: [
                String(localized: "Elbows flaring wide"),
                String(localized: "Upper arms swinging back and forth like a pullover"),
                String(localized: "Going so heavy your wrists bend"),
            ]
        ),
        Entry(
            "Overhead Tricep Extension",
            cues: [
                String(localized: "Elbows pointing forward, close to your head"),
                String(localized: "Lower for a deep stretch behind your head"),
                String(localized: "Brace your core so your ribs do not flare"),
            ],
            mistakes: [
                String(localized: "Elbows flaring out wide"),
                String(localized: "Arching your lower back"),
                String(localized: "Using momentum from your legs"),
            ]
        ),
        Entry(
            "Close-Grip Bench Press",
            cues: [
                String(localized: "Hands about shoulder width, not narrower"),
                String(localized: "Elbows tucked closer to your sides than a regular bench"),
                String(localized: "Lower to your lower chest with forearms vertical"),
            ],
            mistakes: [
                String(localized: "A grip so narrow your wrists hurt"),
                String(localized: "Letting your elbows flare"),
                String(localized: "Bouncing the bar off your chest"),
            ]
        ),

        // MARK: Core

        Entry(
            "Plank",
            cues: [
                String(localized: "Elbows under your shoulders, body in one straight line"),
                String(localized: "Squeeze your glutes and tuck your pelvis slightly"),
                String(localized: "Breathe steadily with your ribs down"),
            ],
            mistakes: [
                String(localized: "Hips sagging toward the floor"),
                String(localized: "Hips piking up high"),
                String(localized: "Holding your breath"),
            ]
        ),
        Entry(
            "Hanging Leg Raise",
            cues: [
                String(localized: "Start from a still, full hang with your shoulders engaged"),
                String(localized: "Curl your pelvis up as your legs rise"),
                String(localized: "Lower slowly, no swinging"),
            ],
            mistakes: [
                String(localized: "Swinging to build momentum"),
                String(localized: "Lifting only your legs without curling your pelvis"),
                String(localized: "Dropping fast on the way down"),
            ]
        ),
        Entry(
            "Ab Wheel Rollout",
            cues: [
                String(localized: "Tuck your pelvis and brace your abs"),
                String(localized: "Roll out only as far as you can keep your back flat"),
                String(localized: "Pull back with your abs, not your hips"),
            ],
            mistakes: [
                String(localized: "Lower back sagging into an arch"),
                String(localized: "Piking your hips up on the way back"),
                String(localized: "Rolling out farther than you can control"),
            ]
        ),
        Entry(
            "Dead Bug",
            cues: [
                String(localized: "Press your lower back into the floor"),
                String(localized: "Move the opposite arm and leg slowly"),
                String(localized: "Breathe out as you reach"),
            ],
            mistakes: [
                String(localized: "Lower back arching off the floor"),
                String(localized: "Moving too fast"),
                String(localized: "Holding your breath"),
            ]
        ),
    ]
    // swiftlint:enable function_body_length
}
