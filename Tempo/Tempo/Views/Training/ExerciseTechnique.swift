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
                "Shoulder blades pinched back and down",
                "Feet planted, drive them into the floor",
                "Bar to mid-chest, forearms vertical at the bottom",
            ],
            mistakes: [
                "Bouncing the bar off your chest",
                "Flaring your elbows straight out to the sides",
                "Hips lifting off the bench",
            ]
        ),
        Entry(
            "Dumbbell Flat Bench Press",
            cues: [
                "Shoulder blades pinched back and down",
                "Elbows about 45 to 60 degrees from your sides",
                "Press up and slightly together over your chest",
            ],
            mistakes: [
                "Letting the dumbbells drift wide and low",
                "Flaring your elbows out to the sides",
                "Arching so hard your hips leave the bench",
            ]
        ),
        Entry(
            "Incline Dumbbell Press",
            cues: [
                "Bench at about 30 degrees",
                "Lower to a deep stretch with your elbows slightly tucked",
                "Press up and slightly in over your upper chest",
            ],
            mistakes: [
                "Bench set too steep, so it becomes a shoulder press",
                "Bouncing out of the bottom",
                "Shrugging your shoulders toward your ears",
            ]
        ),
        Entry(
            "Push-Up",
            cues: [
                "Hands under your shoulders, body in one straight line",
                "Squeeze your glutes and brace your abs",
                "Elbows about 45 degrees from your sides, chest to the floor",
            ],
            mistakes: [
                "Hips sagging or piking up",
                "Flaring your elbows straight out",
                "Stopping well short of full range",
            ]
        ),
        Entry(
            "Dumbbell Fly",
            cues: [
                "Slight bend in your elbows, held the same all rep",
                "Open your arms like a hug until your chest stretches",
                "Stop at shoulder level, no deeper",
            ],
            mistakes: [
                "Bending and straightening your elbows like a press",
                "Lowering so far that your shoulders take the strain",
                "Going so heavy the form falls apart",
            ]
        ),
        Entry(
            "Cable Fly",
            cues: [
                "Slight bend in your elbows, held the same all rep",
                "Sweep your hands together in a wide arc",
                "Squeeze your chest where your hands meet",
            ],
            mistakes: [
                "Turning the fly into a press",
                "Leaning in with your whole body",
                "Letting your shoulders roll forward",
            ]
        ),
        Entry(
            "Chest Dip",
            cues: [
                "Lean your torso forward to load the chest",
                "Lower until your upper arms are about parallel to the floor",
                "Shoulders down, not up around your ears",
            ],
            mistakes: [
                "Dropping so deep your shoulders roll forward",
                "Swinging your legs for momentum",
                "Staying fully upright, which shifts the work to your triceps",
            ]
        ),

        // MARK: Shoulders

        Entry(
            "Overhead Press",
            cues: [
                "Squeeze your glutes and brace before you press",
                "Keep the bar close to your face, then push your head through",
                "Lock out with the bar over your mid-foot",
            ],
            mistakes: [
                "Leaning back so it becomes an incline press",
                "Pressing the bar forward, away from your body",
                "Ribs flared and glutes loose",
            ]
        ),
        Entry(
            "Dumbbell Shoulder Press",
            cues: [
                "Ribs down, glutes tight",
                "Forearms vertical, wrists stacked over your elbows",
                "Press straight up and finish with your biceps by your ears",
            ],
            mistakes: [
                "Arching your lower back",
                "Pressing in front of you instead of straight up",
                "Cutting the lowering short",
            ]
        ),
        Entry(
            "Lateral Raise",
            cues: [
                "Lead with your elbows, not your hands",
                "Raise to shoulder height, no higher",
                "Slight bend in your elbows, control the way down",
            ],
            mistakes: [
                "Swinging the weight up with your body",
                "Shrugging your traps toward your ears",
                "Going so heavy the range shrinks",
            ]
        ),
        Entry(
            "Face Pull",
            cues: [
                "Set the rope at face height and pull toward your eyes",
                "Split the rope and keep your elbows high",
                "Squeeze your shoulder blades together at the end",
            ],
            mistakes: [
                "Going so heavy you lean back to pull",
                "Pulling to your chest instead of your face",
                "Letting your elbows drop below your hands",
            ]
        ),

        // MARK: Back

        Entry(
            "Conventional Deadlift",
            cues: [
                "Bar over your mid-foot, close to your shins",
                "Pull the slack out of the bar before it leaves the floor",
                "Push the floor away and keep the bar against your legs",
            ],
            mistakes: [
                "Rounding your lower back",
                "Jerking the bar off the floor",
                "Hips shooting up first, so it becomes a stiff-leg pull",
            ]
        ),
        Entry(
            "Trap Bar Deadlift",
            cues: [
                "Stand in the middle of the bar with your chest up",
                "Push the floor away and keep your back flat",
                "Stand tall and squeeze your glutes at the top",
            ],
            mistakes: [
                "Rounding your upper back",
                "Jerking the bar off the floor",
                "Leaning back at lockout",
            ]
        ),
        Entry(
            "Sumo Deadlift",
            cues: [
                "Toes out, push your knees out over your toes",
                "Chest tall, pull the slack out of the bar",
                "Push the floor apart as you stand",
            ],
            mistakes: [
                "Knees caving in",
                "Hips shooting up before the bar moves",
                "Letting the bar drift away from your legs",
            ]
        ),
        Entry(
            "Barbell Row",
            cues: [
                "Hinge until your torso is near parallel and hold it there",
                "Pull the bar to your lower ribs",
                "Lead with your elbows and squeeze your shoulder blades",
            ],
            mistakes: [
                "Standing up a little each rep to heave the weight",
                "Rounding your lower back",
                "Pulling with your hands instead of your back",
            ]
        ),
        Entry(
            "Single-Arm Dumbbell Row",
            cues: [
                "Flat back, braced hand under your shoulder",
                "Pull your elbow toward your hip",
                "Pause at the top and lower under control",
            ],
            mistakes: [
                "Twisting your torso to swing the weight",
                "Shrugging the weight up instead of pulling",
                "Cutting the stretch at the bottom short",
            ]
        ),
        Entry(
            "Seated Cable Row",
            cues: [
                "Sit tall with your chest proud",
                "Pull the handle to your lower ribs",
                "Let your shoulder blades stretch forward, then squeeze back",
            ],
            mistakes: [
                "Rocking back to move the weight",
                "Shrugging your shoulders toward your ears",
                "Slumping your whole torso forward at the start of each rep",
            ]
        ),
        Entry(
            "Pull-Up",
            cues: [
                "Start from a full hang with your shoulders pulled down",
                "Drive your elbows toward your hips",
                "Chin over the bar, then lower under control",
            ],
            mistakes: [
                "Kipping or swinging for momentum",
                "Half reps that never reach a full hang",
                "Craning your neck to get your chin over",
            ]
        ),
        Entry(
            "Chin-Up",
            cues: [
                "Palms toward you, hands about shoulder width",
                "Lead with your chest toward the bar",
                "Lower to a full hang under control",
            ],
            mistakes: [
                "Kipping or swinging for momentum",
                "Stopping short of a full hang",
                "Shrugging your shoulders up around your ears",
            ]
        ),
        Entry(
            "Lat Pulldown",
            cues: [
                "Lean back slightly with your chest up",
                "Pull the bar to your upper chest",
                "Drive your elbows down and in",
            ],
            mistakes: [
                "Pulling the bar behind your neck",
                "Leaning way back to swing the weight",
                "Letting the bar yank your arms straight at the top",
            ]
        ),

        // MARK: Legs

        Entry(
            "Barbell Back Squat",
            cues: [
                "Big breath and brace before every rep",
                "Knees track out over your toes",
                "Whole foot planted, drive up through your mid-foot",
            ],
            mistakes: [
                "Knees caving inward",
                "Hips rising first while your chest drops",
                "Heels lifting off the floor",
            ]
        ),
        Entry(
            "Front Squat",
            cues: [
                "Elbows high, upper arms near parallel to the floor",
                "Stay tall with your chest up",
                "Knees out, sit straight down",
            ],
            mistakes: [
                "Elbows dropping so the bar rolls forward",
                "Rounding your upper back",
                "Heels coming off the floor",
            ]
        ),
        Entry(
            "Goblet Squat",
            cues: [
                "Hold the weight tight against your chest",
                "Elbows inside your knees at the bottom",
                "Chest tall, push your knees out",
            ],
            mistakes: [
                "Letting your chest fall forward",
                "Heels lifting off the floor",
                "Knees caving in",
            ]
        ),
        Entry(
            "Leg Press",
            cues: [
                "Feet about shoulder width, in the middle of the platform",
                "Lower until your knees reach about 90 degrees or a bit deeper",
                "Press through your whole foot with knees tracking over your toes",
            ],
            mistakes: [
                "Lower back peeling off the pad at the bottom",
                "Locking your knees hard at the top",
                "Letting your knees cave in",
            ]
        ),
        Entry(
            "Bulgarian Split Squat",
            cues: [
                "Front foot far enough forward to keep your heel down",
                "Torso slightly forward, weight on the front foot",
                "Lower straight down and drive up through the front leg",
            ],
            mistakes: [
                "Pushing off the back foot instead of the front leg",
                "Front foot too close, so your heel lifts",
                "Front knee caving inward",
            ]
        ),
        Entry(
            "Walking Lunge",
            cues: [
                "Take a long step with your torso upright",
                "Drop your back knee straight down toward the floor",
                "Drive through your front foot to step forward",
            ],
            mistakes: [
                "Steps so short your front heel lifts",
                "Front knee caving in",
                "Leaning forward and rushing the reps",
            ]
        ),
        Entry(
            "Romanian Deadlift",
            cues: [
                "Soft knees, push your hips straight back",
                "Bar slides down your thighs the whole way",
                "Stop at a full hamstring stretch with your back flat",
            ],
            mistakes: [
                "Squatting it down instead of hinging",
                "Rounding your back to reach lower",
                "Letting the bar drift away from your legs",
            ]
        ),
        Entry(
            "Dumbbell Romanian Deadlift",
            cues: [
                "Soft knees, push your hips straight back",
                "Dumbbells slide down your thighs",
                "Stop at a full hamstring stretch with your back flat",
            ],
            mistakes: [
                "Squatting it down instead of hinging",
                "Rounding your back to reach lower",
                "Letting the dumbbells drift away from your legs",
            ]
        ),
        Entry(
            "Hip Thrust",
            cues: [
                "Chin tucked and ribs down",
                "Shins vertical at the top, drive through your heels",
                "Squeeze your glutes and pause at the top",
            ],
            mistakes: [
                "Arching your lower back to finish the rep",
                "Feet too far away, so your hamstrings take over",
                "Pushing through your toes",
            ]
        ),
        Entry(
            "Leg Curl",
            cues: [
                "Hips pressed into the pad",
                "Curl your heels toward your glutes",
                "Lower slowly through the full range",
            ],
            mistakes: [
                "Hips lifting off the pad",
                "Swinging the weight up",
                "Cutting the stretch at the bottom short",
            ]
        ),
        Entry(
            "Leg Extension",
            cues: [
                "Pad just above your ankles",
                "Squeeze your quads at the top",
                "Lower slowly, no dropping",
            ],
            mistakes: [
                "Kicking the weight up with momentum",
                "Hips lifting off the seat",
                "Slamming the weight stack at the bottom",
            ]
        ),
        Entry(
            "Standing Calf Raise",
            cues: [
                "Full stretch at the bottom, full squeeze at the top",
                "Pause for a second at each end",
                "Keep your knees steady so your ankles do the work",
            ],
            mistakes: [
                "Bouncing out of the bottom",
                "Short half reps",
                "Bending and straightening your knees",
            ]
        ),
        Entry(
            "Kettlebell Swing",
            cues: [
                "Hinge at your hips and hike the bell back",
                "Snap your hips forward and squeeze your glutes",
                "Your arms are ropes, the bell floats to chest height",
            ],
            mistakes: [
                "Squatting it instead of hinging",
                "Lifting the bell with your arms",
                "Leaning back at the top",
            ]
        ),

        // MARK: Arms

        Entry(
            "Barbell Curl",
            cues: [
                "Elbows pinned at your sides",
                "Curl with control, no swinging",
                "Squeeze at the top and lower slowly",
            ],
            mistakes: [
                "Swinging your torso to lift the weight",
                "Elbows drifting forward",
                "Dropping the bar fast on the way down",
            ]
        ),
        Entry(
            "Dumbbell Curl",
            cues: [
                "Elbows pinned at your sides",
                "Turn your palm up as you curl",
                "Lower all the way down under control",
            ],
            mistakes: [
                "Swinging your body to get the weight up",
                "Elbows moving forward",
                "Half reps that skip the bottom",
            ]
        ),
        Entry(
            "Hammer Curl",
            cues: [
                "Thumbs up, palms facing each other",
                "Elbows pinned at your sides",
                "Lower slowly, no swinging",
            ],
            mistakes: [
                "Swinging with your lower back",
                "Letting your elbows drift forward",
                "Bending your wrists",
            ]
        ),
        Entry(
            "Tricep Pushdown",
            cues: [
                "Elbows pinned to your sides",
                "Push down until your arms are fully straight",
                "Control the way up, forearms no higher than parallel",
            ],
            mistakes: [
                "Leaning over the bar to push with your body weight",
                "Elbows flaring or drifting forward",
                "Shoulders hunching up",
            ]
        ),
        Entry(
            "Skull Crusher",
            cues: [
                "Elbows pointing at the ceiling, not flared",
                "Lower toward your forehead under control",
                "Extend until your arms are straight",
            ],
            mistakes: [
                "Elbows flaring wide",
                "Upper arms swinging back and forth like a pullover",
                "Going so heavy your wrists bend",
            ]
        ),
        Entry(
            "Overhead Tricep Extension",
            cues: [
                "Elbows pointing forward, close to your head",
                "Lower for a deep stretch behind your head",
                "Brace your core so your ribs do not flare",
            ],
            mistakes: [
                "Elbows flaring out wide",
                "Arching your lower back",
                "Using momentum from your legs",
            ]
        ),
        Entry(
            "Close-Grip Bench Press",
            cues: [
                "Hands about shoulder width, not narrower",
                "Elbows tucked closer to your sides than a regular bench",
                "Lower to your lower chest with forearms vertical",
            ],
            mistakes: [
                "A grip so narrow your wrists hurt",
                "Letting your elbows flare",
                "Bouncing the bar off your chest",
            ]
        ),

        // MARK: Core

        Entry(
            "Plank",
            cues: [
                "Elbows under your shoulders, body in one straight line",
                "Squeeze your glutes and tuck your pelvis slightly",
                "Breathe steadily with your ribs down",
            ],
            mistakes: [
                "Hips sagging toward the floor",
                "Hips piking up high",
                "Holding your breath",
            ]
        ),
        Entry(
            "Hanging Leg Raise",
            cues: [
                "Start from a still, full hang with your shoulders engaged",
                "Curl your pelvis up as your legs rise",
                "Lower slowly, no swinging",
            ],
            mistakes: [
                "Swinging to build momentum",
                "Lifting only your legs without curling your pelvis",
                "Dropping fast on the way down",
            ]
        ),
        Entry(
            "Ab Wheel Rollout",
            cues: [
                "Tuck your pelvis and brace your abs",
                "Roll out only as far as you can keep your back flat",
                "Pull back with your abs, not your hips",
            ],
            mistakes: [
                "Lower back sagging into an arch",
                "Piking your hips up on the way back",
                "Rolling out farther than you can control",
            ]
        ),
        Entry(
            "Dead Bug",
            cues: [
                "Press your lower back into the floor",
                "Move the opposite arm and leg slowly",
                "Breathe out as you reach",
            ],
            mistakes: [
                "Lower back arching off the floor",
                "Moving too fast",
                "Holding your breath",
            ]
        ),
    ]
    // swiftlint:enable function_body_length
}
