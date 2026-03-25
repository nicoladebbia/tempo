import SwiftUI
import WidgetKit

// MARK: - Widget Views
// Per BUILD_PLAN 17.2 — Small, Medium, Large widget views.
// Stub implementations for 17.1 target setup; full designs in 17.2.

// MARK: - Small Widget
// Daily score ring + current streak count

struct SmallWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(spacing: 6) {
            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(data.dailyScore)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 60, height: 60)

            // Streak
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
                Text("\(data.streakCount)d")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scoreColor: Color {
        if data.dailyScore >= 80 { return .green }
        if data.dailyScore >= 50 { return .orange }
        return .red
    }
}

// MARK: - Medium Widget
// 4 mini stats (recovery, calories, study, steps)

struct MediumWidgetView: View {
    let data: WidgetData

    var body: some View {
        HStack(spacing: 0) {
            // Score ring on left
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(data.dailyScore)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 50)

                Text("SCORE")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)

            // Stats grid
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    miniStat(icon: "heart.fill", value: "\(data.recoveryScore)%", label: "Recovery", color: .green)
                    miniStat(icon: "flame.fill", value: "\(data.caloriesBurned)", label: "Cal", color: .orange)
                }
                HStack(spacing: 12) {
                    miniStat(icon: "book.fill", value: "\(data.studyMinutes)m", label: "Study", color: .purple)
                    miniStat(icon: "figure.walk", value: "\(data.stepCount)", label: "Steps", color: .blue)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func miniStat(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var scoreColor: Color {
        if data.dailyScore >= 80 { return .green }
        if data.dailyScore >= 50 { return .orange }
        return .red
    }
}

// MARK: - Large Widget
// Mini dashboard — score ring + 4 quadrant summaries

struct LargeWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Text("TEMPO")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                    Text("\(data.streakCount)d streak")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            // Score ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                    .stroke(scoreColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(data.dailyScore)")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text("DAILY SCORE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 80, height: 80)

            // 4 quadrants
            HStack(spacing: 8) {
                quadrantCard(icon: "heart.fill", title: "BODY", value: "\(data.recoveryScore)%", color: .green)
                quadrantCard(icon: "fork.knife", title: "FUEL", value: data.nnProgress, color: .orange)
            }
            HStack(spacing: 8) {
                quadrantCard(icon: "book.fill", title: "MIND", value: "\(data.studyMinutes)m", color: .purple)
                quadrantCard(icon: "figure.run", title: "MOVE", value: "\(data.stepCount)", color: .blue)
            }

            // Next task
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text("Next: \(data.nextTaskName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func quadrantCard(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var scoreColor: Color {
        if data.dailyScore >= 80 { return .green }
        if data.dailyScore >= 50 { return .orange }
        return .red
    }
}
