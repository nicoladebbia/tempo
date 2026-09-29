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
        case .fruit: "applelogo"
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
/// for any product with no photo, sized to fill its container.
struct FoodGroupArt: View {
    let group: FoodGroup

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                LinearGradient(
                    colors: [group.artTint.opacity(TempoOpacity.o40), group.artTint.opacity(TempoOpacity.o10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: group.artSymbol)
                    .font(.system(size: side * 0.36, weight: .light))
                    .foregroundStyle(group.artTint.opacity(TempoOpacity.o70))
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
