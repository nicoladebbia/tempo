//
// FoodScannerComponents.swift
// Tempo
//
// Small pieces shared by the product screen, scanner, search and history:
// score badge / ring, product thumbnail, rating + risk colours, the
// FoodProduct → FoodItem mapping used when a product is logged, and a
// camera/library picker.
//

import SwiftUI
import UIKit

// MARK: - Colours

extension FoodScore.Rating {
    var color: Color {
        switch self {
        case .excellent: .tempoSuccess
        case .good: .tempoRecoveryGreen
        case .poor: .tempoAmber
        case .bad: .tempoError
        }
    }
}

extension FoodAdditive.Risk {
    var color: Color {
        switch self {
        case .high: .tempoError
        case .moderate: .tempoAmber
        case .low: .tempoWarning
        case .unknown: .tempoSuccess
        }
    }
}

extension FoodFitCheck.Kind {
    var color: Color {
        switch self {
        case .conflict: .tempoError
        case .warning: .tempoAmber
        case .good: .tempoSuccess
        }
    }

    var icon: String {
        switch self {
        case .conflict: "xmark.octagon.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .good: "checkmark.circle.fill"
        }
    }
}

// MARK: - Logging

extension FoodProduct {
    var dataSource: FoodDataSource {
        switch source {
        case .openFoodFacts: .openFoodFacts
        case .usda: .usda
        case .builtIn: .cached
        case .userAdded: .manual
        }
    }

    /// `grams` of this product as a meal-logging item (totals for the portion).
    func foodItem(grams: Double) -> FoodItem {
        let n = nutrients(forGrams: grams)
        return FoodItem(
            id: UUID(),
            name: name,
            brand: brand,
            servingSize: "\(Int(grams.rounded())) \(isBeverage ? "ml" : "g")",
            servingQuantity: 1,
            calories: Int((n.kcal ?? 0).rounded()),
            protein: n.protein ?? 0,
            carbs: n.carbs ?? 0,
            fat: n.fat ?? 0,
            source: dataSource,
            barcode: barcode
        )
    }

    var unit: String {
        isBeverage ? "ml" : "g"
    }
}

// MARK: - FoodScoreBadge

/// Compact "72" pill in the rating colour; "?" when there isn't enough data.
struct FoodScoreBadge: View {
    let product: FoodProduct

    var body: some View {
        let score = FoodScore.evaluate(product)
        Text(score.map { "\($0.total)" } ?? "–")
            .font(.tempoCaption1)
            .fontWeight(.bold)
            .monospacedDigit()
            .foregroundStyle(score == nil ? Color.tempoTextTertiary : Color.tempoTextInverse)
            .frame(minWidth: 34)
            .padding(.vertical, TempoSpacing.xxs)
            .background(score?.rating.color ?? Color.tempoBgTertiary)
            .clipShape(Capsule())
            .accessibilityLabel(score.map { "Tempo score \($0.total), \($0.rating.label)" } ?? "Not scored")
    }
}

// MARK: - FoodScoreRing

struct FoodScoreRing: View {
    let score: FoodScore

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.tempoBgTertiary, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(score.total) / 100)
                .stroke(score.rating.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score.total)")
                    .font(.tempoTitle1)
                    .monospacedDigit()
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("/100")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tempo score \(score.total) out of 100")
    }
}

// MARK: - FoodProductThumbnail

/// The user's own photo, else the Open Food Facts image, else a symbol.
extension FoodProduct {
    /// A symbol for the product's kind, shown when there's no picture.
    var placeholderSymbol: String {
        // Most specific category first ("peanut-butters" before "spreads"
        // before "plant-based-foods-and-beverages").
        for tag in categories.reversed() {
            if let symbol = Self.categorySymbols[tag] {
                return symbol
            }
        }
        if isBeverage {
            return "takeoutbag.and.cup.and.straw.fill"
        }
        return source == .openFoodFacts || source == .userAdded ? "barcode" : "fork.knife"
    }

    private static let categorySymbols: [String: String] = {
        let groups: [(tags: [String], symbol: String)] = [
            (["waters", "mineral-waters", "spring-waters"], "waterbottle.fill"),
            (["coffees", "teas", "hot-beverages"], "cup.and.saucer.fill"),
            (["alcoholic-beverages", "wines", "beers"], "wineglass.fill"),
            (["beverages", "juices", "fruit-juices", "sodas", "carbonated-drinks"], "takeoutbag.and.cup.and.straw.fill"),
            (["chocolates", "confectioneries", "biscuits", "cakes", "desserts", "pastries", "ice-creams", "sweet-snacks"], "birthday.cake.fill"),
            (["salty-snacks", "crisps", "chips-and-fries", "popcorn"], "popcorn.fill"),
            (["fishes", "seafood"], "fish.fill"),
            (["meats", "sausages", "hams", "poultries"], "frying.pan.fill"),
            (["dairies", "cheeses", "yogurts", "milks"], "drop.fill"),
            (["fruits", "vegetables", "legumes", "fruits-and-vegetables-based-foods"], "carrot.fill"),
            (["nuts", "seeds", "spreads", "nut-butters", "peanut-butters", "breads", "cereals-and-potatoes", "cereals-and-their-products"], "leaf.fill"),
        ]
        var map: [String: String] = [:]
        for group in groups {
            for tag in group.tags {
                map[tag] = group.symbol
            }
        }
        return map
    }()
}

struct FoodProductThumbnail: View {
    let product: FoodProduct
    var photo: Data?
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let url = size > 64 ? (product.imageURL ?? product.imageSmallURL) : (product.imageSmallURL ?? product.imageURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().scaledToFit()
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: product.placeholderSymbol)
            .font(.system(size: size * 0.4))
            .foregroundStyle(Color.tempoTextTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.tempoBgTertiary)
    }
}

// MARK: - FoodProductRow

struct FoodProductRow: View {
    let product: FoodProduct
    var photo: Data?
    var subtitle: String?

    var body: some View {
        HStack(spacing: TempoSpacing.md) {
            FoodProductThumbnail(product: product, photo: photo)
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                Text(product.name)
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(2)
                Text(subtitle ?? detailLine)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: TempoSpacing.sm)
            FoodScoreBadge(product: product)
        }
        .contentShape(Rectangle())
    }

    private var detailLine: String {
        var parts: [String] = []
        if let brand = product.brand, !brand.isEmpty {
            parts.append(brand)
        }
        if let kcal = product.per100g.kcal {
            parts.append("\(Int(kcal.rounded())) kcal / 100 \(product.unit)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - FoodImagePicker

/// Camera (falls back to the library on the simulator) or photo library.
struct FoodImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_: UIImagePickerController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (UIImage?) -> Void

        init(onPick: @escaping (UIImage?) -> Void) {
            self.onPick = onPick
        }

        func imagePickerController(_: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onPick(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_: UIImagePickerController) {
            onPick(nil)
        }
    }
}
