//
// TidePage.swift
// Tempo
//
// The page surface: the living Tide field behind a whole screen. Every page,
// pushed page and sheet root wears `.tidePage()` once. A page nested inside
// another page draws nothing, so there is never a field on top of a field.
//

import SwiftUI

extension EnvironmentValues {
    /// True below a `.tidePage()`: the field is already behind this view.
    @Entry var tideInsidePage = false
}

private struct TidePageModifier: ViewModifier {
    let energy: Double
    @Environment(\.tideInsidePage)
    private var inside

    func body(content: Content) -> some View {
        content
            .environment(\.tideInsidePage, true)
            .scrollContentBackground(.hidden)
            .background {
                if !inside {
                    TideBackground(energy: energy)
                }
            }
    }
}

extension View {
    /// Puts the Tide field behind this screen and clears list and form
    /// backgrounds so it shows through. Detail pages and sheets use the
    /// calmer default; a tab's home page passes `energy: 1`.
    func tidePage(energy: Double = Tide.sheetEnergy) -> some View {
        modifier(TidePageModifier(energy: energy))
    }
}

/// The page surface as a view, for a `ZStack` whose first layer was the old
/// page colour.
struct TidePageBackground: View {
    @Environment(\.tideInsidePage)
    private var inside

    var body: some View {
        if inside {
            Color.clear
        } else {
            TideBackground(energy: Tide.sheetEnergy)
        }
    }
}
