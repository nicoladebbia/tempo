import SwiftUI
import WidgetKit

// MARK: - Widget Views
// Per BUILD_PLAN 17.2 — Small, Medium, Large widget views.
// Per WIREFRAMES.md Screens 49-52.

// MARK: - Small Widget
// Per WIREFRAMES.md Screen 49 — 158x158pt
// "TEMPO" header top-left, score ring (52pt dia, 4pt stroke) centered,
// bottom row: recovery % with dot left, sleep hours right.

struct SmallWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TEMPO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Spacer()

            // Score ring — 52pt diameter, 4pt stroke, zone color
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                    .stroke(data.scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(data.dailyScore)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 52, height: 52)

            Spacer()

            // Bottom row — recovery left, sleep right
            HStack {
                HStack(spacing: 3) {
                    Circle()
                        .fill(data.zoneColor)
                        .frame(width: 6, height: 6)
                    Text("\(data.recoveryScore)% rec")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                Spacer()
                HStack(spacing: 3) {
                    Text(String(format: "%.1fh", data.sleepHours))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "moon.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.black)
        .widgetURL(URL(string: "tempo://dashboard"))
    }
}

// MARK: - Medium Widget
// Per WIREFRAMES.md Screen 50 — 338x158pt
// "TEMPO" top-left, date top-right
// 30/70 split: ring (48pt, 4pt stroke) left, 2x2 quadrant grid right
// Quadrant names: 9pt bold, accent per quadrant
// Dividers: 1pt hairline

struct MediumWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TEMPO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                // Left 30% — Score ring (48pt, 4pt stroke)
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                        .stroke(data.scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(data.dailyScore)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 48, height: 48)
                .frame(maxWidth: .infinity)

                // Right 70% — 2x2 quadrant grid
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        // BODY quadrant
                        quadrantCell(
                            name: "BODY",
                            color: .green,
                            line1: "\(data.recoveryScore)%",
                            line2: "Sleep \(String(format: "%.1fh", data.sleepHours))"
                        )

                        dividerV

                        // FUEL quadrant
                        quadrantCell(
                            name: "FUEL",
                            color: .orange,
                            line1: "\(data.caloriesConsumed)/\(data.caloriesTarget)",
                            line2: "P:\(data.protein) C:\(data.carbs) F:\(data.fat)"
                        )
                    }

                    dividerH

                    HStack(spacing: 0) {
                        // MIND quadrant
                        quadrantCell(
                            name: "MIND",
                            color: .purple,
                            line1: data.studyTimeFormatted,
                            line2: "\(data.streakCount)d streak"
                        )

                        dividerV

                        // MOVE quadrant
                        quadrantCell(
                            name: "MOVE",
                            color: .blue,
                            line1: data.workoutDone ? "✓ Done" : "Pending",
                            line2: "\(formatted(data.stepCount)) steps"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 2)
        }
        .padding(12)
        .background(Color.black)
        .widgetURL(URL(string: "tempo://dashboard"))
    }

    private func quadrantCell(name: String, color: Color, line1: String, line2: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            Text(line1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Text(line2)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private var dividerV: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(width: 1)
    }

    private var dividerH: some View {
        Rectangle()
            .fill(Color.white.opacity(0.15))
            .frame(height: 1)
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Large Widget
// Per WIREFRAMES.md Screen 51 — 338x354pt
// "TEMPO" top-left, date top-right
// Score ring (56pt, 5pt stroke) centered
// 2x2 quadrant cards: systemFill bg, 8pt radius, 6pt padding, 3 lines each
// Non-negotiables progress bar: 4pt height, 2pt radius

struct LargeWidgetView: View {
    let data: WidgetData

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text("TEMPO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Date.now, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            // Score ring — 56pt diameter, 5pt stroke
            HStack(spacing: 8) {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: CGFloat(data.dailyScore) / 100)
                        .stroke(data.scoreColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(data.dailyScore)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 56, height: 56)
                Text("Daily Score")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 2x2 quadrant cards
            HStack(spacing: 8) {
                // BODY card
                quadrantCard(
                    name: "BODY", color: .green,
                    lines: [
                        "\(data.zoneIcon) \(data.recoveryScore)% Recovery",
                        "HRV \(String(format: "%.1f", data.hrv))  RHR \(data.rhr)",
                        "Sleep \(String(format: "%.1fh", data.sleepHours))"
                    ]
                )
                // FUEL card
                quadrantCard(
                    name: "FUEL", color: .orange,
                    lines: [
                        "\(formatted(data.caloriesConsumed))/\(formatted(data.caloriesTarget)) kcal",
                        "P:\(data.protein) C:\(data.carbs)",
                        "F:\(data.fat)  \(data.mealsLogged)/\(data.mealsTarget) meals"
                    ]
                )
            }

            HStack(spacing: 8) {
                // MIND card
                quadrantCard(
                    name: "MIND", color: .purple,
                    lines: [
                        "\(data.studyTimeFormatted) / \(data.studyTargetFormatted)",
                        data.nextExam,
                        "🔥 \(data.streakCount)d"
                    ]
                )
                // MOVE card
                quadrantCard(
                    name: "MOVE", color: .blue,
                    lines: [
                        data.workoutDone ? "✓ Done" : "Pending",
                        "\(formatted(data.stepCount)) steps",
                        "\(data.activeCalories) active cal"
                    ]
                )
            }

            // Non-negotiables progress bar — 4pt height, 2pt radius
            HStack(spacing: 6) {
                Text("\(data.nnCompleted)/\(data.nnTotal) non-negotiables")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.orange)
                            .frame(width: data.nnTotal > 0 ? geo.size.width * CGFloat(data.nnCompleted) / CGFloat(data.nnTotal) : 0, height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(12)
        .background(Color.black)
        .widgetURL(URL(string: "tempo://dashboard"))
    }

    private func quadrantCard(name: String, color: Color, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(.regularMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func formatted(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Zone Icon Helper

extension WidgetData {
    var zoneIcon: String {
        switch recoveryZone {
        case "green": return "🟢"
        case "yellow": return "🟡"
        case "red": return "🔴"
        default: return "🟢"
        }
    }
}
