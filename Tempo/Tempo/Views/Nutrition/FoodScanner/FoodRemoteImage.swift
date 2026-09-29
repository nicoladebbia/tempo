//
// FoodRemoteImage.swift
// Tempo
//
// The single place that loads a product photo: disk-cached via
// `FoodImageCache`, falling back to a generic photo (`GenericFoodImages`)
// when the product has no picture of its own, and to `FoodGroupArt` while
// loading or on a miss. Used by the search/history thumbnail, the product
// hero and the full-screen gallery viewer.
//

import SwiftUI

// MARK: - FoodRemoteImage

struct FoodRemoteImage: View {
    /// Explicit photo to load (e.g. one gallery page). When `nil`, falls
    /// back to a generic photo for `product`.
    var url: URL?
    /// Used for the placeholder art and the generic-photo fallback.
    var product: FoodProduct?
    var contentMode: ContentMode = .fit
    /// A blurred, scaled-to-fill copy of the same image behind the
    /// scaled-to-fit foreground — Apple-Music-style — instead of flat colour
    /// letterboxing either side of a tall/narrow product photo. Only makes
    /// sense with `contentMode == .fit`; callers opt in for hero-sized art.
    var showsBlurredBackdrop = false

    @State
    private var image: UIImage?
    @State
    private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                if showsBlurredBackdrop, contentMode == .fit {
                    // In an overlay on Color.clear so the fill image can't
                    // widen the layout past the screen (it would push every
                    // card on the product page off the left edge).
                    Color.clear
                        .overlay {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .blur(radius: 24)
                        }
                        .overlay(Color.black.opacity(TempoOpacity.o40))
                        .clipped()
                        .transition(.opacity)
                }
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .padding(showsBlurredBackdrop ? TempoSpacing.lg : 0)
                    .transition(.opacity)
            } else if let product {
                FoodGroupArt(group: product.foodGroup, name: product.name)
                    .padding(showsBlurredBackdrop ? TempoSpacing.lg : 0)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .tint(Color.tempoTextTertiary)
                        }
                    }
            } else {
                Color.tempoBgTertiary
            }
        }
        .animation(.easeOut(duration: TempoAnimation.smallDuration), value: image == nil)
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        url?.absoluteString ?? product?.id ?? "none"
    }

    private func load() async {
        image = nil
        guard url != nil || product != nil else {
            return
        }
        isLoading = true
        defer { isLoading = false }
        var effectiveURL = url
        if effectiveURL == nil, let product {
            effectiveURL = await GenericFoodImages.imageURL(for: product)
        }
        guard let effectiveURL else {
            return
        }
        guard let data = await FoodImageCache.shared.data(for: effectiveURL), let loaded = UIImage(data: data) else {
            return
        }
        image = loaded
    }
}
