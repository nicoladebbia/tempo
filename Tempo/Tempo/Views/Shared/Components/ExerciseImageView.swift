//
// ExerciseImageView.swift
// Tempo
//

import SwiftUI

// MARK: - ExerciseImageView

//
// Displays the backend-generated AI picture for an exercise (see
// ExerciseImageService), falling back to the equipment SF Symbol on a
// tinted background — same placeholder language as
// TodayWorkoutView+Equipment.equipmentIcon — while loading, offline, or if
// no image is available yet. Never blocks layout and never crashes offline;
// on any failure it just keeps showing the placeholder.
//
// Sizing follows the existing ExerciseDemoImage convention: the caller owns
// the frame via `.frame(...)`. `.thumbnail` ships a sensible 44x44 default
// (a later caller `.frame()` overrides it, same as any SwiftUI modifier
// chain); `.hero` has no default frame or aspect ratio at all — forcing a
// fixed ratio internally would letterbox inside whatever fixed-height box
// the caller already uses (ActiveWorkoutView's 150pt header,
// ExerciseDetailView's 200pt demo area). Neither existing hero call site
// applies an explicit 16:10 `.aspectRatio` today; a future one that wants
// that exact ratio can add it the same way, same as any other view.

struct ExerciseImageView: View {
    enum Style {
        /// Rounded, full-bleed within whatever frame the caller gives it —
        /// active workout header, exercise detail screen (16:10 there).
        case hero
        /// Square, rounded, 44x44 by default (list/card rows, library,
        /// review rows) — override with `.frame()` for the 44-56pt range.
        case thumbnail
    }

    let exercise: any ExerciseImageDescribing
    var style: Style = .thumbnail

    @Environment(ServiceContainer.self) private var container
    @State private var uiImage: UIImage?

    /// Converted once per body evaluation — the Sendable value the service
    /// actually operates on (see ExerciseImageService.swift).
    private var input: ExerciseImageInput {
        exercise.imageInput
    }

    private var slug: String {
        ExerciseImageSlug.make(from: input.name)
    }

    var body: some View {
        ZStack {
            Color.tempoSurfaceElevated
            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.animation(.easeInOut(duration: TempoAnimation.smallDuration)))
            } else {
                placeholder
            }
        }
        .frame(
            width: style == .thumbnail ? 44 : nil,
            height: style == .thumbnail ? 44 : nil
        )
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: slug) {
            // Reset first: `.task(id:)` only restarts on a slug CHANGE, so
            // without this the previous exercise's photo stays on screen
            // under the new exercise's placeholder-or-load state — e.g.
            // ActiveWorkoutView's hero reuses one ExerciseImageView across
            // the whole session as `currentExercise` advances, and
            // TrainerProgramReviewView's thumbnail swaps `matchedExercise`
            // as the user edits a row's name.
            uiImage = nil
            await load()
        }
    }

    private var placeholder: some View {
        Image(systemName: equipmentSymbol)
            .font(.system(size: symbolSize))
            .foregroundStyle(Color.tempoTextTertiary)
    }

    private var cornerRadius: CGFloat {
        style == .hero ? TempoRadius.xl : TempoRadius.md
    }

    private var symbolSize: CGFloat {
        style == .hero ? 40 : 16
    }

    /// Mirrors TodayWorkoutView+Equipment.equipmentIcon's mapping (kept as
    /// its own copy — that one is a private method on a specific view, not
    /// a reusable utility). `Equipment(rawValue:)` is deliberately unwrapped
    /// before switching: Equipment itself declares a literal `case none`,
    /// so switching directly over the `Equipment?` from `rawValue:` makes
    /// `.none` ambiguous between "no match" and `Equipment.none`.
    private var equipmentSymbol: String {
        guard let equipment = Equipment(rawValue: input.equipmentRaw) else {
            return fallbackSymbol
        }
        switch equipment {
        case .barbell:
            return "figure.strengthtraining.traditional"
        case .dumbbell:
            return "dumbbell.fill"
        case .cable:
            return "cable.connector"
        case .machine:
            return "gearshape.fill"
        case .bodyweight:
            return "figure.flexibility"
        case .kettlebell:
            return "figure.strengthtraining.functional"
        default:
            return fallbackSymbol
        }
    }

    private var fallbackSymbol: String {
        switch MuscleGroup(rawValue: input.muscleGroupRaw) {
        case .core:
            "figure.core.training"
        case .fullBody:
            "figure.strengthtraining.functional"
        case .cardio:
            "figure.run"
        default:
            "figure.mixed.cardio"
        }
    }

    private func load() async {
        guard let data = await container.exerciseImages.imageData(for: input) else {
            return
        }
        uiImage = UIImage(data: data)
    }
}
