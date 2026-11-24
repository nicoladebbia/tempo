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
    @Environment(\.tideMood)
    private var mood

    func body(content: Content) -> some View {
        content
            .environment(\.tideInsidePage, true)
            .scrollContentBackground(.hidden)
            .background {
                if !inside {
                    TideBackground(energy: energy)
                }
            }
            // A sheet opened from inside a page inherits "this page already has
            // a field" and would draw none. Nested here, the field goes behind
            // the sheet itself. On a page that is not a sheet root this does
            // nothing, and a sheet that draws its own field is unaffected: the
            // same field is behind it either way.
            .tideSheetField(energy: energy, mood: mood, active: inside)
    }
}

extension View {
    /// The field as the background of the sheet or cover this view is the root
    /// of, when `active`. Ignored when the view is not presented.
    @ViewBuilder
    fileprivate func tideSheetField(energy: Double, mood: TideMood, active: Bool) -> some View {
        if active {
            // The presentation sits above the page: the mood travels in by hand.
            presentationBackground {
                TideBackground(energy: energy).environment(\.tideMood, mood)
            }
        } else {
            self
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

    @Environment(\.tideMood)
    private var mood

    var body: some View {
        if inside {
            // Nothing to draw here, but a sheet needs the field behind it.
            Color.clear.tideSheetField(energy: Tide.sheetEnergy, mood: mood, active: true)
        } else {
            TideBackground(energy: Tide.sheetEnergy)
        }
    }
}
