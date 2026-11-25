//
// ShareCard.swift
// Tempo
//
// Created by Tempo on 24/11/2026.
//
//

import SwiftUI
import UIKit

// MARK: - ShareCardContent

// A share card is a picture of a real number: a finished workout, a personal
// record, a streak, a week. One reusable view draws all four, from this plain
// value, so any screen can offer "Share" with one line:
//
//     ShareCard.present(.workout(title: "Push day", minutes: 52, exercises: 6, sets: 22, volumeKg: 8420))
//
// The card is flat: gradients and type only (no glass, material or shaders), so
// `ImageRenderer` draws it exactly. Only numbers the caller read from the
// user's own records go on it; nothing is filled in for an empty field.

struct ShareCardContent: Equatable {
    enum Layout: Equatable {
        case workout
        case record
        case streak
        case week

        fileprivate var tint: Color {
            switch self {
            case .workout: TideTone.mint
            case .record: TideTone.gold
            case .streak: Tide.streak
            case .week: TideTone.sky
            }
        }

        fileprivate var symbol: String {
            switch self {
            case .workout: "dumbbell.fill"
            case .record: "trophy.fill"
            case .streak: "flame.fill"
            case .week: "calendar"
            }
        }
    }

    struct Stat: Equatable {
        let label: String
        let value: String
    }

    var layout: Layout
    /// The small caps line above the title: "Workout", "Personal record".
    var eyebrow: String
    /// What it is about: the session, the lift, a line under the streak, the week.
    var title: String
    /// The one big number.
    var hero: String
    /// What the big number counts: "kg", "days", "XP".
    var heroUnit: String?
    /// Up to three supporting numbers.
    var stats: [Stat]
    /// The date line at the bottom.
    var footer: String
}

// MARK: - Four layouts, one call each

extension ShareCardContent {
    /// A finished workout. Leave out what you do not have: it is simply not shown.
    static func workout(
        title: String, minutes: Int? = nil, exercises: Int, sets: Int, volumeKg: Double? = nil, date: Date = Date()
    ) -> ShareCardContent {
        var stats = [
            Stat(label: String(localized: "Exercises"), value: "\(exercises)"),
            Stat(label: String(localized: "Sets"), value: "\(sets)"),
        ]
        if let volumeKg, volumeKg > 0 {
            stats.append(Stat(label: String(localized: "Volume"), value: "\(Int(volumeKg.rounded()).formatted()) kg"))
        }
        return ShareCardContent(
            layout: .workout, eyebrow: String(localized: "Workout done"), title: title,
            hero: minutes.map { "\($0)" } ?? "\(sets)",
            heroUnit: minutes == nil
                ? (sets == 1 ? String(localized: "set") : String(localized: "sets"))
                : (minutes == 1 ? String(localized: "minute") : String(localized: "minutes")),
            stats: minutes == nil ? Array(stats.dropFirst(2)) : stats,
            footer: date.formatted(date: .complete, time: .omitted)
        )
    }

    /// A personal record: the new best and, when known, the one it beat.
    static func record(
        exercise: String, value: String, unit: String? = nil, previous: String? = nil, date: Date = Date()
    ) -> ShareCardContent {
        ShareCardContent(
            layout: .record, eyebrow: String(localized: "New personal record"), title: exercise, hero: value, heroUnit: unit,
            stats: previous.map { [Stat(label: String(localized: "Before"), value: $0)] } ?? [],
            footer: date.formatted(date: .complete, time: .omitted)
        )
    }

    /// An achievement unlocked: its name, its XP and how rare it is.
    static func achievement(name: String, xp: Int, rarity: String, date: Date = Date()) -> ShareCardContent {
        ShareCardContent(
            layout: .record, eyebrow: String(localized: "Achievement unlocked"), title: name, hero: "+\(xp.formatted())", heroUnit: "XP",
            stats: [Stat(label: String(localized: "Rarity"), value: rarity)],
            footer: date.formatted(date: .complete, time: .omitted)
        )
    }

    /// Days in a row, with the best run when it is longer.
    static func streak(days: Int, longest: Int? = nil, level: Int? = nil, date: Date = Date()) -> ShareCardContent {
        var stats: [Stat] = []
        if let longest, longest > days {
            stats.append(Stat(label: String(localized: "Best run"), value: ArenaText.days(longest)))
        }
        if let level {
            stats.append(Stat(label: String(localized: "Level"), value: "\(level)"))
        }
        return ShareCardContent(
            layout: .streak, eyebrow: String(localized: "Streak"),
            title: days == 1 ? String(localized: "One day down") : String(localized: "Showing up every day"),
            hero: "\(days)", heroUnit: days == 1 ? String(localized: "day") : String(localized: "days"), stats: stats,
            footer: date.formatted(date: .complete, time: .omitted)
        )
    }

    /// A week's XP, sessions and focus time, and where it ranked among friends.
    static func week(
        xp: Int, workouts: Int, studyMinutes: Int, rank: Int? = nil, friends: Int = 0, weekStart: Date
    ) -> ShareCardContent {
        let end = ArenaCalendar.addingDays(6, to: weekStart)
        var stats = [
            Stat(label: workouts == 1 ? String(localized: "Workout") : String(localized: "Workouts"), value: "\(workouts)"),
            Stat(
                label: String(localized: "Study"),
                value: studyMinutes >= 60
                    ? String(localized: "\(studyMinutes / 60)h \(studyMinutes % 60)m")
                    : String(localized: "\(studyMinutes)m")
            ),
        ]
        if let rank, friends > 0 {
            stats.append(Stat(label: String(localized: "Rank"), value: ArenaText.rank(rank, of: friends + 1)))
        }
        let startText = weekStart.formatted(.dateTime.day().month(.abbreviated))
        let endText = end.formatted(.dateTime.day().month(.abbreviated))
        let weekNumber = ArenaCalendar.calendar().component(.weekOfYear, from: weekStart)
        let yearText = weekStart.formatted(.dateTime.year())
        let range = String(localized: "\(startText) to \(endText)")
        return ShareCardContent(
            layout: .week, eyebrow: String(localized: "My week"), title: range, hero: xp.formatted(), heroUnit: "XP", stats: stats,
            footer: String(localized: "Week \(weekNumber), \(yearText)")
        )
    }
}

// MARK: - ShareCardView

/// The card itself, 360 x 450 points (1080 x 1350 pixels at 3x), the 4:5 shape
/// every feed shows without cropping.
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    let content: ShareCardContent

    var body: some View {
        let tint = content.layout.tint
        ZStack(alignment: .topLeading) {
            // Flat field: two gradients, no blur, no material.
            LinearGradient(
                colors: [Tide.ink, Color(red: 0.07, green: 0.10, blue: 0.20)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [tint.opacity(0.34), tint.opacity(0)],
                center: .topTrailing, startRadius: 0, endRadius: 360
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: content.layout.symbol)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.18), in: .circle)
                    Text(content.eyebrow.uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(tint)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Tide.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(content.hero)
                            .font(Tide.numeral(96, .heavy))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                        if let unit = content.heroUnit {
                            Text(unit)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Tide.text2)
                        }
                    }
                }

                if !content.stats.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(Array(content.stats.prefix(3).enumerated()), id: \.offset) { _, stat in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stat.label.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(Tide.text3)
                                Text(stat.value)
                                    .font(Tide.numeral(22, .bold))
                                    .foregroundStyle(Tide.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 24)
                }

                Spacer(minLength: 0)

                Rectangle().fill(Tide.hairline).frame(height: 1)
                HStack {
                    Text(content.footer)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Tide.text3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Text("TEMPO")
                        .font(Tide.numeral(15, .heavy))
                        .tracking(3)
                        .foregroundStyle(Tide.text)
                }
                .padding(.top, 12)
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }
}

// MARK: - ShareCard

@MainActor
enum ShareCard {
    /// The card as a picture, 1080 x 1350.
    static func image(for content: ShareCardContent) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(content: content).environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage
    }

    /// Opens the system share sheet with the card. One call from anywhere:
    /// `ShareCard.present(.streak(days: 14))`.
    static func present(_ content: ShareCardContent) {
        guard let image = image(for: content) else {
            return
        }
        let sheet = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        guard let top = topViewController() else {
            return
        }
        // On iPad a share sheet needs somewhere to point.
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
        )
        sheet.popoverPresentationController?.permittedArrowDirections = []
        top.present(sheet, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
