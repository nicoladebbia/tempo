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

// MARK: - FoodProduct → StagedPantryItem

extension StagedPantryItem {
    /// Prefills name, brand, package size (quantity + unit), and a guessed
    /// storage location — all still editable before the user saves. Shared by
    /// the pantry barcode scanner and the product page's "Add to pantry".
    init(product: FoodProduct) {
        let parsedSize = PackageSizeParser.parse(product.quantityLabel)
        self.init(
            name: product.name,
            quantity: parsedSize?.quantity ?? 1,
            unit: parsedSize?.unit ?? .pieces,
            location: PantryStorageGuesser.guess(for: product),
            totalPaidUSD: nil,
            brand: product.brand ?? ""
        )
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

/// The user's own photo, else the product's picture (cached to disk), else a
/// generic photo for basics/USDA foods, else `FoodGroupArt` — never a blank
/// tile.
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
                    .frame(width: size, height: size)
                    .background(Color.white)
            } else {
                let url = size > 64 ? (product.imageURL ?? product.imageSmallURL) : (product.imageSmallURL ?? product.imageURL)
                FoodRemoteImage(url: url, product: product)
                    .frame(width: size, height: size)
                    .background(url == nil ? Color.clear : Color.white)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
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
                if let subtitle {
                    Text(subtitle)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .lineLimit(1)
                } else {
                    detailLine
                }
            }
            Spacer(minLength: TempoSpacing.sm)
            FoodScoreBadge(product: product)
        }
        .contentShape(Rectangle())
    }

    /// Brand + kcal on one line. When space is tight, the brand truncates —
    /// the kcal figure never does, so a row never reads as "82 kcal / 10…"
    /// (picky-QA item 13).
    @ViewBuilder
    private var detailLine: some View {
        let brand = product.brand?.isEmpty == false ? product.brand : nil
        let kcalText = product.per100g.kcal.map { "\(Int($0.rounded())) kcal / 100 \(product.unit)" }
        HStack(spacing: TempoSpacing.xxs) {
            if let brand {
                Text(brand)
                    .lineLimit(1)
                    .layoutPriority(0)
            }
            if let kcalText {
                if brand != nil {
                    Text("·")
                        .layoutPriority(1)
                }
                Text(kcalText)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
        }
        .font(.tempoCaption1)
        .foregroundStyle(Color.tempoTextSecondary)
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
