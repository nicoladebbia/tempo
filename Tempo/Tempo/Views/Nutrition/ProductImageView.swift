//
// ProductImageView.swift
// Tempo
//
// Product photo with a small in-memory cache and a placeholder. Only ever
// given a URL that passed `ReceiptProductPhoto.url` (confident match); with
// no URL it draws the category icon.
//

import SwiftUI
import UIKit

// MARK: - ProductImageCache

enum ProductImageCache {
    nonisolated(unsafe) private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 150
        return cache
    }()

    static func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    static func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url as NSURL)
    }

    static func load(_ url: URL) async -> UIImage? {
        if let hit = image(for: url) {
            return hit
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data)
        else {
            return nil
        }
        store(image, for: url)
        return image
    }
}

// MARK: - ProductImageView

struct ProductImageView: View {
    let url: URL?
    let fallbackIcon: String
    var size: CGFloat = 44

    @State
    private var image: UIImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
        ZStack {
            Tide.fill
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: fallbackIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.4, height: size * 0.4)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Tide.hairline, lineWidth: 1))
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            if let cached = ProductImageCache.image(for: url) {
                image = cached
                return
            }
            let loaded = await ProductImageCache.load(url)
            withAnimation(.easeOut(duration: 0.15)) { image = loaded }
        }
        .accessibilityHidden(true)
    }
}
