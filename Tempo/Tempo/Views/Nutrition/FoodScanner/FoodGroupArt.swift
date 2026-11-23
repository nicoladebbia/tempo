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
        case .dairy: Tide.fat
        case .meat: Tide.danger
        case .fish: Tide.fat
        case .eggs: Tide.Kitchen.warn
        case .grains: Tide.carbs
        case .bread: Tide.Kitchen.warn
        case .pasta: Tide.carbs
        case .legumes: Tide.Kitchen.good
        case .nuts: Tide.fat
        case .fruit: Tide.Kitchen.good
        case .vegetables: Tide.Kitchen.good
        case .snacks: Tide.protein
        case .sweets: Tide.protein
        case .drinks: Tide.fat
        case .oils: Tide.fat
        case .sauces: Tide.Kitchen.warn
        case .meals: Tide.text2
        case .other: Tide.text3
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
                    colors: [group.artTint.opacity(0.40), group.artTint.opacity(0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .hueRotation(hueShift)
                VStack(spacing: side * 0.05) {
                    Image(systemName: group.artSymbol)
                        .resizable()
                        .scaledToFit()
                        .frame(width: side * 0.34, height: side * 0.34)
                        .foregroundStyle(group.artTint.opacity(0.70))
                    if side > 56, let initial {
                        Text(initial)
                            .font(side > 96 ? Tide.bodyStrong : Tide.label)
                            .foregroundStyle(group.artTint.opacity(0.50))
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Tide.fill)
        .accessibilityHidden(true)
    }
}

#Preview {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))]) {
        ForEach(FoodGroup.allCases, id: \.self) { group in
            FoodGroupArt(group: group)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
        }
    }
    .padding()
    .tidePage()
}
