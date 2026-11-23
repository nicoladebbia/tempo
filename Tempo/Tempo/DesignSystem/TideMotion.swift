//
// TideMotion.swift
// Tempo
//
// One place that decides whether shaders may animate, and that compiles them
// before their first use.
//

import SwiftUI

/// Tracks Low Power Mode. Reduce Motion and scene phase come from the environment.
@MainActor
@Observable
final class TidePower {
    static let shared = TidePower()

    private(set) var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    private init() {
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                TidePower.shared.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }
}

extension EnvironmentValues {
    /// True while a sheet or cover sits over this view. SwiftUI still counts
    /// a covered view as visible, so whoever presents says so here (see
    /// `tideCovered(_:)`) and the shaders underneath stop.
    @Entry var tideCovered = false
}

private struct TideCoveredModifier: ViewModifier {
    let covered: Bool
    @Environment(\.tideCovered)
    private var inherited

    func body(content: Content) -> some View {
        content.environment(\.tideCovered, covered || inherited)
    }
}

extension View {
    /// Stops Tide shaders in this view while `covered` is true. Apply it
    /// below the `.sheet`/`.fullScreenCover` it describes, so the presented
    /// content keeps its own clock.
    func tideCovered(_ covered: Bool) -> some View {
        modifier(TideCoveredModifier(covered: covered))
    }
}

/// Runs `content` with a clock for shaders. The clock stops (and the shader
/// renders one still frame) under Reduce Motion, in Low Power Mode, when the
/// app is not active, while the view is off screen (another tab, scrolled
/// away) and while a sheet or cover is over it.
struct TideClock<Content: View>: View {
    var fps: Double = 30
    @ViewBuilder var content: (_ time: Double) -> Content

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.scenePhase)
    private var scenePhase
    @Environment(\.tideCovered)
    private var covered
    @State
    private var isVisible = false
    @State
    private var start = Date()

    /// The frame shown whenever the clock is stopped.
    static var stillTime: Double { 40 }

    private var paused: Bool {
        reduceMotion || TidePower.shared.isLowPower || scenePhase != .active || !isVisible || covered
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: paused)) { context in
            content(reduceMotion ? Self.stillTime : context.date.timeIntervalSince(start) + Self.stillTime)
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
    }
}

enum TideShaders {
    /// Compiles every Tide shader off the main thread so the first screen that
    /// uses one does not stall. Call after the first frame is on screen.
    static func prewarm() {
        Task.detached(priority: .utility) {
            let size = Shader.Argument.float2(CGSize(width: 100, height: 100))
            let c = Shader.Argument.color(.white)
            let shaders: [Shader] = [
                ShaderLibrary.tideField(size, .float(0), c, c, c, c, .float(1)),
                ShaderLibrary.tideDial(size, .float(0.5), .float(0), c),
                ShaderLibrary.tideLevel(size, .float(0.5), c),
                ShaderLibrary.tideLiquid(size, .float(0), .float(0.5), c, c),
            ]
            for shader in shaders {
                try? await shader.compile(as: .colorEffect)
            }
        }
    }
}
