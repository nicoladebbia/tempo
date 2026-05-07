//
// Font+Tempo.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI
import UIKit

// MARK: - Tempo Typography Scale

// Per DESIGN_SYSTEM.md Section 4 — all sizes, weights, and designs match the canonical spec.

extension Font {
    // MARK: - Display Styles (SF Pro Rounded / SF Mono — Capped Dynamic Type)

    /// Score Display: SF Pro Rounded Bold 64pt — daily composite score on dashboard.
    /// Maps to .largeTitle, capped at 83pt (1.3x).
    static var tempoScoreDisplay: Font {
        scaledRoundedFont(size: 64, weight: .bold, textStyle: .largeTitle, maxSize: 83)
    }

    /// Score Display Small: SF Pro Rounded Bold 48pt — module-specific scores.
    /// Maps to .largeTitle, capped at 62pt (1.3x).
    static var tempoScoreDisplaySmall: Font {
        scaledRoundedFont(size: 48, weight: .bold, textStyle: .largeTitle, maxSize: 62)
    }

    /// XP Display: SF Pro Rounded Bold 36pt — total XP count on profile.
    /// Maps to .title1, capped at 47pt (1.3x).
    static var tempoXPDisplay: Font {
        scaledRoundedFont(size: 36, weight: .bold, textStyle: .title1, maxSize: 47)
    }

    /// Timer Display: SF Mono Bold 56pt — Pomodoro timer, workout rest timer.
    /// Maps to .largeTitle, capped at 67pt (1.2x).
    static var tempoTimerDisplay: Font {
        scaledMonoFont(size: 56, weight: .bold, textStyle: .largeTitle, maxSize: 67)
    }

    /// Timer Display Small: SF Mono Semibold 40pt — elapsed time, set timer.
    /// Maps to .title1, capped at 48pt (1.2x).
    static var tempoTimerDisplaySmall: Font {
        scaledMonoFont(size: 40, weight: .semibold, textStyle: .title1, maxSize: 48)
    }

    // MARK: - Title Styles (SF Pro Display — Unlimited Dynamic Type)

    /// Large Title: SF Pro Display Bold 34pt — top-level screen titles.
    static let tempoLargeTitle: Font = .largeTitle.bold()

    /// Title 1: SF Pro Display Bold 28pt — section headers within scrollable content.
    static let tempoTitle1: Font = .title.bold()

    /// Title 2: SF Pro Display Bold 22pt — card titles, module headers.
    static let tempoTitle2: Font = .title2.bold()

    /// Title 3: SF Pro Display Semibold 20pt — subsection titles, dialog titles.
    static let tempoTitle3: Font = .title3.weight(.semibold)

    // MARK: - Body Styles (SF Pro Text — Unlimited Dynamic Type)

    /// Headline: SF Pro Text Semibold 17pt — list row titles, bold inline labels.
    static let tempoHeadline: Font = .headline

    /// Subheadline: SF Pro Text Regular 15pt — list row subtitles, secondary descriptors.
    static let tempoSubheadline: Font = .subheadline

    /// Body: SF Pro Text Regular 17pt — primary readable text, descriptions.
    static let tempoBody: Font = .body

    /// Body Bold: SF Pro Text Semibold 17pt — emphasized body text, inline labels.
    static let tempoBodyBold: Font = .body.weight(.semibold)

    /// Callout: SF Pro Text Regular 16pt — callout boxes, secondary body text.
    static let tempoCallout: Font = .callout

    /// Caption 1: SF Pro Text Regular 12pt — timestamps, metadata, chart axis labels.
    static let tempoCaption1: Font = .caption

    /// Caption 2: SF Pro Text Regular 11pt — fine print, legal text.
    static let tempoCaption2: Font = .caption2

    /// Footnote: SF Pro Text Regular 13pt — footnotes, help text below inputs.
    static let tempoFootnote: Font = .footnote

    // MARK: - Data Styles (SF Mono — Dynamic Type)

    /// Data Large: SF Mono Bold 24pt — in-card stat values (e.g., "2,340 cal").
    /// Maps to .title2, capped at 31pt (1.3x).
    static var tempoDataLarge: Font {
        scaledMonoFont(size: 24, weight: .bold, textStyle: .title2, maxSize: 31)
    }

    /// Data Medium: SF Mono Semibold 17pt — inline data values, table cells.
    /// Maps to .body, unlimited scaling.
    static var tempoDataMedium: Font {
        scaledMonoFont(size: 17, weight: .semibold, textStyle: .body, maxSize: nil)
    }

    /// Data Small: SF Mono Medium 13pt — secondary data, chart tooltips.
    /// Maps to .footnote, unlimited scaling.
    static var tempoDataSmall: Font {
        scaledMonoFont(size: 13, weight: .medium, textStyle: .footnote, maxSize: nil)
    }

    // MARK: - Specialized Label Styles

    /// Drill Label: SF Pro Text Bold 12pt, tracking +1.5 — "DRILL SERGEANT" label.
    static var tempoDrillLabel: Font {
        scaledDefaultFont(size: 12, weight: .bold, textStyle: .caption1, maxSize: nil)
    }

    /// Orders Label: SF Pro Text Bold 12pt, tracking +2.0 — "ORDERS" label.
    static var tempoOrdersLabel: Font {
        scaledDefaultFont(size: 12, weight: .bold, textStyle: .caption1, maxSize: nil)
    }

    /// Zone Label: SF Pro Text Bold 12pt, tracking +1.0 — "FOCUS", "BREAK", "REST".
    static var tempoZoneLabel: Font {
        scaledDefaultFont(size: 12, weight: .bold, textStyle: .caption1, maxSize: nil)
    }

    /// Module Tag: SF Pro Text Semibold 10pt, tracking +0.5 — module identifier tags.
    static var tempoModuleTag: Font {
        scaledDefaultFont(size: 10, weight: .semibold, textStyle: .caption2, maxSize: nil)
    }

    // MARK: - Private Helpers

    /// Creates a scaled SF Pro Rounded font using UIFontMetrics for Dynamic Type support.
    private static func scaledRoundedFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        maxSize: CGFloat?
    ) -> Font {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = font.fontDescriptor.withDesign(.rounded) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maxSize {
            return Font(metrics.scaledFont(for: font, maximumPointSize: maxSize))
        }
        return Font(metrics.scaledFont(for: font))
    }

    /// Creates a scaled SF Mono font using UIFontMetrics for Dynamic Type support.
    private static func scaledMonoFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        maxSize: CGFloat?
    ) -> Font {
        var font = UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = font.fontDescriptor.withDesign(.monospaced) {
            font = UIFont(descriptor: descriptor, size: size)
        }
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maxSize {
            return Font(metrics.scaledFont(for: font, maximumPointSize: maxSize))
        }
        return Font(metrics.scaledFont(for: font))
    }

    /// Creates a scaled SF Pro (default design) font using UIFontMetrics for Dynamic Type support.
    private static func scaledDefaultFont(
        size: CGFloat,
        weight: UIFont.Weight,
        textStyle: UIFont.TextStyle,
        maxSize: CGFloat?
    ) -> Font {
        let font = UIFont.systemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: textStyle)
        if let maxSize {
            return Font(metrics.scaledFont(for: font, maximumPointSize: maxSize))
        }
        return Font(metrics.scaledFont(for: font))
    }
}

// MARK: - TempoTracking

// Per DESIGN_SYSTEM.md Section 4.2 — apply via .tracking() view modifier.

enum TempoTracking {
    // Display Styles
    static let scoreDisplay: CGFloat = -1.0
    static let scoreDisplaySmall: CGFloat = -0.8
    static let xpDisplay: CGFloat = -0.5
    static let timerDisplay: CGFloat = 0
    static let timerDisplaySmall: CGFloat = 0

    // Title Styles
    static let largeTitle: CGFloat = 0.37
    static let title1: CGFloat = 0.36
    static let title2: CGFloat = 0.35
    static let title3: CGFloat = 0.38

    // Body Styles
    static let headline: CGFloat = -0.41
    static let subheadline: CGFloat = -0.24
    static let body: CGFloat = -0.41
    static let callout: CGFloat = -0.32
    static let caption1: CGFloat = 0
    static let caption2: CGFloat = 0.07
    static let footnote: CGFloat = -0.08

    // Data Styles
    static let dataLarge: CGFloat = 0
    static let dataMedium: CGFloat = 0
    static let dataSmall: CGFloat = 0

    // Specialized Labels
    static let drillLabel: CGFloat = 1.5
    static let ordersLabel: CGFloat = 2.0
    static let zoneLabel: CGFloat = 1.0
    static let moduleTag: CGFloat = 0.5
}
