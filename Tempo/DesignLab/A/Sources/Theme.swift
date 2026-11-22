import SwiftUI

/// Signal: tokens. Three inks, three text levels, one accent.
enum S {
    static let ink0 = Color(red: 0.020, green: 0.024, blue: 0.027)
    static let ink1 = Color(red: 0.050, green: 0.058, blue: 0.066)
    static let ink2 = Color(red: 0.090, green: 0.102, blue: 0.114)
    static let line = Color.white.opacity(0.07)
    static let text = Color(red: 0.95, green: 0.96, blue: 0.96)
    static let dim = Color(red: 0.58, green: 0.62, blue: 0.65)
    static let faint = Color(red: 0.36, green: 0.39, blue: 0.42)
    static let accent = Color(red: 0.80, green: 1.0, blue: 0.24)
    static let onAccent = Color(red: 0.05, green: 0.08, blue: 0.0)

    static let edge: CGFloat = 20
    static let gap: CGFloat = 12
    static let pad: CGFloat = 20
    static let radius: CGFloat = 24

    static let snap = Animation.spring(duration: 0.26, bounce: 0)
    static let settle = Animation.spring(duration: 0.5, bounce: 0.1)
    static let sweep = Animation.spring(duration: 1.1, bounce: 0)
}

extension Font {
    /// Condensed tabular numerals: the voice of the instrument.
    static func sNum(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed).monospacedDigit()
    }
    static let sLabel = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let sTitle = Font.system(size: 28, weight: .semibold).width(.condensed)
    static let sHead = Font.system(size: 17, weight: .semibold)
    static let sBody = Font.system(size: 16, weight: .regular)
    static let sNote = Font.system(size: 14, weight: .regular)
}

struct SLabel: View {
    let text: String
    var color: Color = S.dim
    init(_ text: String, color: Color = S.dim) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(.sLabel).tracking(1.3).foregroundStyle(color).lineLimit(1).fixedSize()
    }
}

struct Panel: ViewModifier {
    var padding: CGFloat = S.pad
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(S.ink1, in: RoundedRectangle(cornerRadius: S.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: S.radius, style: .continuous).strokeBorder(S.line, lineWidth: 1))
    }
}
extension View {
    func panel(padding: CGFloat = S.pad) -> some View { modifier(Panel(padding: padding)) }
}

/// Background with grain and one pool of light, drawn by the shader.
struct SBackground: View {
    var lightY: CGFloat = 0.3
    var body: some View {
        Rectangle().fill(S.ink0)
            .visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.signalGrain(
                    .float2(proxy.size), .float2(proxy.size.width / 2, proxy.size.height * lightY),
                    .float(0.022), .color(S.accent)))
            }
            .ignoresSafeArea()
    }
}

/// Shader-lit level bar.
struct LevelBar: View, Animatable {
    var progress: Double
    var height: CGFloat = 4
    nonisolated var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        let p = progress
        Capsule().fill(.white).frame(height: height)
            .visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.signalBar(.float2(proxy.size), .float(p), .color(S.accent)))
            }
            .clipShape(Capsule())
    }
}

/// Discrete steps (tasks, sets, exercises).
struct StepBar: View {
    let total: Int
    let done: Int
    var current: Int? = nil
    var currentColor: Color = S.text.opacity(0.55)
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule().fill(i < done ? S.accent : (i == current ? currentColor : Color.white.opacity(0.1)))
                    .frame(height: 4)
            }
        }
    }
}

/// Shader ring with an animatable value.
struct SignalRing: View, Animatable {
    var progress: Double
    var time: Double
    nonisolated var animatableData: Double { get { progress } set { progress = newValue } }
    var body: some View {
        let p = progress, t = time
        Rectangle().fill(.white)
            .visualEffect { content, proxy in
                content.colorEffect(ShaderLibrary.signalRing(.float2(proxy.size), .float(p), .float(t), .color(S.accent)))
            }
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(S.snap, value: configuration.isPressed)
    }
}

/// 44 pt circular check control.
struct CheckDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            Circle().strokeBorder(on ? S.accent : S.faint, lineWidth: 1.5).frame(width: 24, height: 24)
            if on {
                Circle().fill(S.accent).frame(width: 24, height: 24)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(S.onAccent)
            }
        }
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
}
