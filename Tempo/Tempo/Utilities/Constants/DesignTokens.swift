import SwiftUI

// MARK: - Spacing Tokens
// Per DESIGN_SYSTEM.md Section 5 — base unit 4pt, all values multiples of 4 (except 2xs = 2pt).

enum TempoSpacing {

    // MARK: - Scale

    /// 2pt — icon-to-text gap in tight layouts (exception to 4pt rule).
    static let xxs: CGFloat = 2

    /// 4pt — minimum gap between related elements, inner icon padding.
    static let xs: CGFloat = 4

    /// 8pt — gap between label and value, between stacked icons.
    static let sm: CGFloat = 8

    /// 12pt — card internal element gaps, list item vertical padding.
    static let md: CGFloat = 12

    /// 16pt — standard padding (card padding, screen edge), section gaps.
    static let lg: CGFloat = 16

    /// 20pt — screen edge padding (leading/trailing).
    static let xl: CGFloat = 20

    /// 24pt — between card sections, between major UI groups.
    static let xxl: CGFloat = 24

    /// 32pt — between screen sections, above/below section headers.
    static let xxxl: CGFloat = 32

    /// 40pt — major section separation, dashboard header spacing.
    static let xxxxl: CGFloat = 40

    /// 48pt — top-of-screen spacing (below safe area), screen bottom padding.
    static let xxxxxl: CGFloat = 48

    // MARK: - Component-Specific

    /// 16pt — standard card padding all sides.
    static let cardPadding: CGFloat = 16

    /// 12pt — compact card padding (dashboard quadrants).
    static let cardPaddingCompact: CGFloat = 12

    /// 12pt — gap between elements inside a card.
    static let cardGap: CGFloat = 12

    /// 24pt — primary/secondary button horizontal padding.
    static let buttonPaddingH: CGFloat = 24

    /// 14pt — primary/secondary button vertical padding.
    static let buttonPaddingV: CGFloat = 14

    /// 12pt — small button horizontal padding.
    static let buttonPaddingHSmall: CGFloat = 12

    /// 8pt — small button vertical padding.
    static let buttonPaddingVSmall: CGFloat = 8

    /// 20pt — screen edge padding (leading/trailing).
    static let screenEdge: CGFloat = 20

    /// 16pt — screen edge on iPhone SE.
    static let screenEdgeCompact: CGFloat = 16

    /// 24pt — screen edge on iPad.
    static let screenEdgeIPad: CGFloat = 24

    /// 32pt — gap between screen sections.
    static let sectionGap: CGFloat = 32

    /// 32pt — top padding for section headers.
    static let sectionHeaderTop: CGFloat = 32

    /// 8pt — bottom padding for section headers.
    static let sectionHeaderBottom: CGFloat = 8

    /// 12pt — list item vertical padding.
    static let listItemVertical: CGFloat = 12

    /// 16pt — list item horizontal padding.
    static let listItemHorizontal: CGFloat = 16

    /// 20pt — bottom sheet horizontal padding.
    static let sheetHorizontal: CGFloat = 20

    /// 16pt — bottom sheet top padding (below grabber).
    static let sheetTop: CGFloat = 16

    /// 34pt — bottom sheet bottom padding (above home indicator).
    static let sheetBottom: CGFloat = 34

    /// 20pt — modal horizontal padding.
    static let modalHorizontal: CGFloat = 20

    /// 24pt — modal top padding.
    static let modalTop: CGFloat = 24

    /// 12pt — text field horizontal padding.
    static let inputHorizontal: CGFloat = 12

    /// 12pt — text field vertical padding.
    static let inputVertical: CGFloat = 12

    /// 8pt — gap between label and input.
    static let inputLabelGap: CGFloat = 8

    /// 4pt — gap between input and helper/error text.
    static let inputHelperGap: CGFloat = 4

    /// 16pt — gap between chart and legend.
    static let chartLegendGap: CGFloat = 16

    /// 12pt — vertical spacing between stacked buttons.
    static let buttonStackVertical: CGFloat = 12

    /// 8pt — horizontal spacing between side-by-side buttons.
    static let buttonStackHorizontal: CGFloat = 8

    /// 48pt — bottom safe area padding.
    static let bottomSafe: CGFloat = 48
}

// MARK: - Corner Radius Tokens
// Per DESIGN_SYSTEM.md Section 2.2 — Corner Radius Tokens.

enum TempoRadius {

    /// 3pt — heatmap cells.
    static let xs: CGFloat = 3

    /// 6pt — skeleton rects, segmented inner.
    static let sm: CGFloat = 6

    /// 8pt — segmented control, photo thumbnails.
    static let md: CGFloat = 8

    /// 10pt — search bar, ghost button.
    static let lg: CGFloat = 10

    /// 12pt — text fields, stat cards, icon buttons, exercise cards.
    static let xl: CGFloat = 12

    /// 14pt — primary/secondary buttons, toast.
    static let xxl: CGFloat = 14

    /// 16pt — standard cards, workout cards, prescription cards.
    static let xxxl: CGFloat = 16

    /// 20pt — bottom sheets, modal alerts.
    static let xxxxl: CGFloat = 20

    /// 9999pt — pill badges (half-height).
    static let pill: CGFloat = 9999
}

// MARK: - Opacity Tokens
// Per DESIGN_SYSTEM.md Section 2.2 — Opacity Tokens.

enum TempoOpacity {

    static let o10: Double = 0.10
    static let o15: Double = 0.15
    static let o20: Double = 0.20
    static let o40: Double = 0.40
    static let o50: Double = 0.50
    static let o70: Double = 0.70
    static let o80: Double = 0.80
    static let disabled: Double = 0.40
    static let overlayLight: Double = 0.40
    static let overlayDark: Double = 0.50
    static let pressedPrimary: Double = 0.85
    static let pressedGhost: Double = 0.08
    static let skeleton: Double = 1.0
}

// MARK: - Motion / Animation Tokens
// Per DESIGN_SYSTEM.md Section 2.2 — Motion Tokens.

enum TempoAnimation {

    // MARK: - Durations

    /// 0.1s — micro interactions (button press feedback, toggle switch).
    static let microDuration: Double = 0.1

    /// 0.2s — small transitions (icon changes, opacity fades).
    static let smallDuration: Double = 0.2

    /// 0.3s — medium transitions (card expand/collapse, sheet present).
    static let mediumDuration: Double = 0.3

    /// 0.5s — large transitions (screen transitions, complex reveals).
    static let largeDuration: Double = 0.5

    /// 0.7s — data animation mid-point (chart bars, ring fills).
    static let dataDuration: Double = 0.7

    /// 1.0s — standard celebration (Dashboard non-neg completion).
    static let celebrationDuration: Double = 1.0

    /// 2.0s — major celebration (Training PR).
    static let celebrationMajorDuration: Double = 2.0

    /// 3.0s — epic celebration (all-time 1RM, all non-negs complete).
    static let celebrationEpicDuration: Double = 3.0

    // MARK: - Stagger Delays

    /// 60ms — stagger between card animations.
    static let staggerCard: Double = 0.06

    /// 50ms — stagger between bar chart segments.
    static let staggerBar: Double = 0.05

    /// 20ms — stagger between dots/indicators.
    static let staggerDot: Double = 0.02

    /// 150ms — stagger between ring animation segments.
    static let staggerRing: Double = 0.15

    // MARK: - Spring Animations

    /// Medium spring: response 0.3, damping 0.8. Card expand/collapse, sheet present.
    static let springMedium: Animation = .spring(response: 0.3, dampingFraction: 0.8)

    /// Large spring: response 0.5, damping 0.7. Screen transitions, complex reveals.
    static let springLarge: Animation = .spring(response: 0.5, dampingFraction: 0.7)

    /// Data spring: response 0.6, damping 0.8. Chart animations, ring fills.
    static let springData: Animation = .spring(response: 0.6, dampingFraction: 0.8)

    /// Celebration spring: response 0.4, damping 0.5. Bouncy celebration effects.
    static let springCelebration: Animation = .spring(response: 0.4, dampingFraction: 0.5)

    // MARK: - Easing Animations

    /// Micro: 100ms ease-out. Button press, toggle.
    static let micro: Animation = .easeOut(duration: 0.1)

    /// Small: 200ms ease-in-out. Icon changes, opacity fades.
    static let small: Animation = .easeInOut(duration: 0.2)
}

// MARK: - Shadow Definitions
// Per DESIGN_SYSTEM.md Section 6 — Depth & Elevation System.

struct TempoShadow {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum TempoElevation {

    // MARK: - Card (Elevation 2)

    /// Card shadow — light mode: y:2, blur:8 (radius:4), ink @ 6%.
    static let cardLight = TempoShadow(
        color: Color.tempoInk.opacity(0.06),
        radius: 4,
        x: 0,
        y: 2
    )

    /// Card border — dark mode: 0.5pt border (no shadow).
    static let cardDarkBorderWidth: CGFloat = 0.5

    // MARK: - Sheet / Floating (Elevation 3)

    /// Sheet shadow — light mode: y:-4, blur:20 (radius:10), ink @ 15%.
    static let sheetLight = TempoShadow(
        color: Color.tempoInk.opacity(0.15),
        radius: 10,
        x: 0,
        y: -4
    )

    /// Sheet shadow — dark mode: blur:4 (radius:2), black @ 40%.
    static let sheetDark = TempoShadow(
        color: Color.black.opacity(0.40),
        radius: 2,
        x: 0,
        y: 0
    )

    /// FAB shadow — light mode: y:4, blur:12 (radius:6), ink @ 20%.
    static let fabLight = TempoShadow(
        color: Color.tempoInk.opacity(0.20),
        radius: 6,
        x: 0,
        y: 4
    )

    /// FAB shadow — dark mode: y:4, blur:12 (radius:6), black @ 40%.
    static let fabDark = TempoShadow(
        color: Color.black.opacity(0.40),
        radius: 6,
        x: 0,
        y: 4
    )

    // MARK: - Popover (Elevation 4)

    /// Popover shadow — light mode: y:8, blur:32 (radius:16), ink @ 18%.
    static let popoverLight = TempoShadow(
        color: Color.tempoInk.opacity(0.18),
        radius: 16,
        x: 0,
        y: 8
    )

    /// Popover shadow — dark mode: y:2, blur:8 (radius:4), black @ 50%.
    static let popoverDark = TempoShadow(
        color: Color.black.opacity(0.50),
        radius: 4,
        x: 0,
        y: 2
    )

    // MARK: - Overlay Scrim (Elevation 5)

    /// Modal scrim — light mode: ink @ 40%.
    static let scrimLight = Color.tempoInk.opacity(0.40)

    /// Modal scrim — dark mode: black @ 50%.
    static let scrimDark = Color.black.opacity(0.50)
}
