import SwiftUI

/// Direction B, "Tide". Everything visual is defined here; views never use literals.
enum Tide {
    // Ink and text
    static let ink = Color(red: 0.027, green: 0.043, blue: 0.075)
    static let text = Color.white
    static let text2 = Color.white.opacity(0.68)
    static let text3 = Color.white.opacity(0.44)
    static let hairline = Color.white.opacity(0.12)
    static let fill = Color.white.opacity(0.08)

    // Signal colours
    static let mint = Color(red: 0.42, green: 0.96, blue: 0.80)
    static let ember = Color(red: 1.00, green: 0.66, blue: 0.36)
    static let protein = Color(red: 1.00, green: 0.58, blue: 0.50)
    static let carbs = Color(red: 1.00, green: 0.83, blue: 0.42)
    static let fat = Color(red: 0.62, green: 0.74, blue: 1.00)
    static let water = Color(red: 0.36, green: 0.78, blue: 1.00)

    // 4 pt grid
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16
    static let s5: CGFloat = 20, s6: CGFloat = 24, s8: CGFloat = 32
    static let edge: CGFloat = 20
    static let cardRadius: CGFloat = 28
    static let tileRadius: CGFloat = 20
    static let hit: CGFloat = 44

    // Type
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let title = Font.system(size: 28, weight: .bold)
    static let title2 = Font.system(size: 22, weight: .bold)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let bodyStrong = Font.system(size: 15, weight: .semibold)
    static let caption = Font.system(size: 13, weight: .medium)
    static let label = Font.system(size: 11, weight: .semibold)

    // Motion
    static let snap = Animation.spring(duration: 0.28, bounce: 0.0)
    static let lively = Animation.spring(duration: 0.38, bounce: 0.22)
}

/// The day's state decides the colour of the whole app.
struct Mood: Equatable {
    let glowA: Color, glowB: Color, ember: Color, accent: Color, word: String

    init(score: Int) {
        switch score {
        case 67...:
            glowA = Color(red: 0.04, green: 0.50, blue: 0.47)
            glowB = Color(red: 0.16, green: 0.24, blue: 0.72)
            ember = Color(red: 0.95, green: 0.62, blue: 0.30)
            accent = Tide.mint
            word = "On pace"
        case 34..<67:
            glowA = Color(red: 0.62, green: 0.38, blue: 0.08)
            glowB = Color(red: 0.36, green: 0.18, blue: 0.62)
            ember = Color(red: 0.95, green: 0.42, blue: 0.30)
            accent = Color(red: 1.00, green: 0.80, blue: 0.40)
            word = "Behind"
        default:
            glowA = Color(red: 0.58, green: 0.12, blue: 0.24)
            glowB = Color(red: 0.26, green: 0.10, blue: 0.44)
            ember = Color(red: 0.90, green: 0.36, blue: 0.20)
            accent = Color(red: 1.00, green: 0.56, blue: 0.56)
            word = "Off track"
        }
    }

    static var current: Mood { Mood(score: Lab.score) }
}

enum Lab {
    static let args = ProcessInfo.processInfo.arguments
    static func flag(_ name: String) -> Bool { args.contains(name) }
    static var score: Int {
        guard let i = args.firstIndex(of: "-score"), args.indices.contains(i + 1), let v = Int(args[i + 1]) else {
            return Sample.dayScore
        }
        return v
    }
}

struct TideBackground: View {
    var mood: Mood = .current
    var energy: Double = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            GeometryReader { geo in
                Rectangle()
                    .fill(Tide.ink)
                    .colorEffect(ShaderLibrary.tide(
                        .float2(geo.size),
                        .float(reduceMotion ? 40 : context.date.timeIntervalSince(start) + 40),
                        .color(Tide.ink), .color(mood.glowA), .color(mood.glowB), .color(mood.ember),
                        .float(energy)))
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// A floating glass surface. The ink tint keeps white text readable whatever is behind it.
    func tideCard(padding: CGFloat = Tide.s5, radius: CGFloat = Tide.cardRadius) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(Tide.ink.opacity(0.30)), in: .rect(cornerRadius: radius))
    }

    func tideLabel(_ color: Color = Tide.text2) -> some View {
        self.font(Tide.label).tracking(1.1).textCase(.uppercase).foregroundStyle(color)
    }
}

struct Ring: View {
    var progress: Double
    var width: CGFloat
    var colors: [Color]

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: width)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(colors.last ?? .white,
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (colors.last ?? .white).opacity(0.45), radius: width * 0.9)
        }
        .padding(width / 2)
    }
}

struct Bar: View {
    var progress: Double
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color).frame(width: progress <= 0 ? 0 : max(height, geo.size.width * min(progress, 1)))
            }
        }
        .frame(height: height)
    }
}

struct CheckDot: View {
    var done: Bool
    var color: Color = Tide.mint
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            Circle().strokeBorder(done ? Color.clear : Color.white.opacity(0.36), lineWidth: 1.5)
            if done {
                Circle().fill(color)
                Image(systemName: "checkmark").font(.system(size: size * 0.46, weight: .heavy)).foregroundStyle(Tide.ink)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: size, height: size)
    }
}
