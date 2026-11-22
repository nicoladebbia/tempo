import SwiftUI
import UIKit

/// Direction C palette: five flat inks on paper. Each section owns one.
enum Ink {
    static let paper = Color(red: 0.953, green: 0.937, blue: 0.898)      // Bone
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.047)        // Press black
    static let flare = Color(red: 1.0, green: 0.286, blue: 0.098)        // Today
    static let acid = Color(red: 0.878, green: 1.0, blue: 0.165)         // Train
    static let moss = Color(red: 0.039, green: 0.404, blue: 0.263)       // Fuel
    static let cobalt = Color(red: 0.137, green: 0.212, blue: 1.0)       // Arena, water
}

/// 4 pt grid.
enum Grid {
    static let u: CGFloat = 4
    static let margin: CGFloat = 20
    static let gap: CGFloat = 12
    static let block: CGFloat = 32
}

/// Display type: compressed, black, caps and numerals only. The frame is trimmed to the
/// cap height so blocks align to the letterforms, not to the font's line box.
struct Poster: View {
    let text: String
    let size: CGFloat
    var weight: UIFont.Weight = .black
    var width: UIFont.Width = .compressed

    init(_ text: String, _ size: CGFloat, weight: UIFont.Weight = .black, width: UIFont.Width = .compressed) {
        self.text = text; self.size = size; self.weight = weight; self.width = width
    }

    var body: some View {
        let f = UIFont.systemFont(ofSize: size, weight: weight, width: width)
        Text(text)
            .font(Font(f))
            .tracking(-size * 0.012)
            .lineLimit(1)
            .fixedSize()
            .padding(.top, -(f.ascender - f.capHeight) - f.leading / 2)
            .padding(.bottom, f.descender - f.leading / 2)
            .padding(.leading, -size * 0.016)   // optical: cancel the left side bearing
    }
}

/// Small running label: expanded, bold, tracked caps.
struct Label11: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold).width(.expanded))
            .tracking(0.9)
            .lineLimit(1)
            .fixedSize()
    }
}

struct Rule: View {
    var weight: CGFloat = 2
    var body: some View { Rectangle().frame(height: weight) }
}

/// Flat proportional bar. No rounding, no gradient.
struct FlatBar: View {
    let value: Double
    var height: CGFloat = 8
    var track: Double = 0.22
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().opacity(track)
                Rectangle().frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

extension View {
    /// Prints a second ink over a flat block as a halftone ramp with paper grain.
    func printed(ink: Color, amount: Double = 1, cell: Double = 7, angle: Double = 0.42) -> some View {
        visualEffect { content, proxy in
            content.colorEffect(ShaderLibrary.halftone(
                .float2(proxy.size), .float(cell), .float(angle), .color(ink), .float(amount), .float(0.035)))
        }
    }
}

/// Press feedback for flat blocks: a quick sink, no bounce.
struct BlockPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}

func thousands(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
    return f.string(from: n as NSNumber) ?? "\(n)"
}
