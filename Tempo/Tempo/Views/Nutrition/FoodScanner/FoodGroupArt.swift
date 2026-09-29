//
// FoodGroupArt.swift
// Tempo
//
// Placeholder art for a food with no picture yet — a tinted gradient plus an
// SF Symbol for its shelf (`FoodGroup`). Shown while a real photo loads and
// whenever one can't be found, so search results and the product page never
// show a blank tile.
//

import SwiftUI

// MARK: - FoodGroup → art

extension FoodGroup {
    /// SF Symbol standing in for this shelf. All iOS 17-safe.
    var artSymbol: String {
        switch self {
        case .dairy: "cup.and.saucer.fill"
        case .meat: "fork.knife"
        case .fish: "fish.fill"
        case .eggs: "oval.portrait.fill"
        case .grains: "laurel.leading"
        case .bread: "laurel.leading"
        case .pasta: "fork.knife"
        case .legumes: "carrot.fill"
        case .nuts: "leaf.fill"
        case .fruit: "basket.fill"
        case .vegetables: "carrot.fill"
        case .snacks: "popcorn.fill"
        case .sweets: "birthday.cake.fill"
        case .drinks: "mug.fill"
        case .oils: "drop.fill"
        case .sauces: "drop.fill"
        case .meals: "fork.knife"
        case .other: "fork.knife"
        }
    }

    /// Tint driving the gradient + symbol colour.
    var artTint: Color {
        switch self {
        case .dairy: .tempoInfo
        case .meat: .tempoError
        case .fish: .tempoElectric
        case .eggs: .tempoAmber
        case .grains: .tempoMacroCarbs
        case .bread: .tempoWarning
        case .pasta: .tempoMacroCarbs
        case .legumes: .tempoRecoveryGreen
        case .nuts: .tempoMacroFat
        case .fruit: .tempoSuccess
        case .vegetables: .tempoRecoveryGreen
        case .snacks: .tempoViolet
        case .sweets: .tempoSignal
        case .drinks: .tempoElectric
        case .oils: .tempoMacroFat
        case .sauces: .tempoAmber
        case .meals: .tempoSteel
        case .other: .tempoConcrete
        }
    }
}

// MARK: - FoodGroupArt

/// A tinted gradient tile with a centred SF Symbol — the placeholder shown
/// for any product with no photo, sized to fill its container. Takes the
/// food's name (optional) purely for cosmetic variety — a search result full
/// of same-shelf placeholders (20 dairy tiles) isn't visually identical: a
/// subtle per-name hue shift on the gradient, plus the food's initial under
/// the symbol on tiles big enough to read it.
struct FoodGroupArt: View {
    let group: FoodGroup
    var name: String = ""

    /// Stable, deterministic per-name shift in roughly [-16°, 16°] — same
    /// product always renders the same, different products in the same
    /// group rarely land on the exact same tint. Uses a plain content hash
    /// (not `String.hashValue`, which Swift randomizes per process launch)
    /// so the tint is stable across app relaunches, not just within one.
    private var hueShift: Angle {
        guard !name.isEmpty else {
            return .zero
        }
        var hash: UInt64 = 5381
        for scalar in name.lowercased().unicodeScalars {
            hash = 33 &* hash &+ UInt64(scalar.value)
        }
        let degrees = Int(hash % 33) - 16
        return .degrees(Double(degrees))
    }

    private var initial: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first.isLetter || first.isNumber else {
            return nil
        }
        return String(first).uppercased()
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(
                    colors: [group.artTint.opacity(TempoOpacity.o40), group.artTint.opacity(TempoOpacity.o10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .hueRotation(hueShift)
                VStack(spacing: side * 0.05) {
                    Image(systemName: group.artSymbol)
                        .font(.system(size: side * 0.34, weight: .light))
                        .foregroundStyle(group.artTint.opacity(TempoOpacity.o70))
                    if side > 56, let initial {
                        Text(initial)
                            .font(.system(size: max(side * 0.13, 10), weight: .semibold, design: .rounded))
                            .foregroundStyle(group.artTint.opacity(TempoOpacity.o50))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color.tempoBgTertiary)
        .accessibilityHidden(true)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
        ForEach(FoodGroup.allCases, id: \.self) { group in
            FoodGroupArt(group: group)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }
    .padding()
    .background(Color.tempoBgPrimary)
}
