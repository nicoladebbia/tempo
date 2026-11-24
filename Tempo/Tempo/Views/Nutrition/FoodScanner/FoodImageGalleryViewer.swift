//
// FoodImageGalleryViewer.swift
// Tempo
//
// Full-screen, swipeable, pinch-to-zoom viewer for a product's photos —
// opened by tapping the hero image on the product page.
//

import SwiftUI

// MARK: - FoodImageGalleryViewer

struct FoodImageGalleryViewer: View {
    let sources: [FoodHeroSource]
    /// Used only for the placeholder art shown if a remote photo fails to load.
    var product: FoodProduct?
    @Binding var page: Int

    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        ZStack {
            TidePageBackground()
            // Bar, photo, caption: stacked, so a large caption pushes the photo
            // up instead of hiding behind it.
            VStack(spacing: 0) {
                topBar
                TabView(selection: $page) {
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        ZoomableImage {
                            photoCard(source)
                        }
                        .padding(.horizontal, Tide.edge)
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                bottomBar
                    .padding(.top, Tide.s3)
            }
        }
    }

    /// Where you are in the set, on glass so it reads over any photo; Close on the right.
    private var topBar: some View {
        HStack {
            if sources.count > 1 {
                Text("\(page + 1) of \(sources.count)")
                    .font(Tide.bodyStrong.monospacedDigit())
                    .foregroundStyle(Tide.text)
                    .padding(.horizontal, Tide.s4)
                    .frame(minHeight: Tide.hit)
                    .glassEffect(.regular, in: .capsule)
                    .contentTransition(.numericText())
                    .animation(Tide.snap, value: page)
                    .accessibilityLabel("Photo \(page + 1) of \(sources.count)")
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .frame(width: Tide.hit, height: Tide.hit)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .accessibilityLabel("Close")
        }
        .padding(Tide.s4)
    }

    /// The product's name, and a strip of thumbnails to jump between photos.
    private var bottomBar: some View {
        VStack(spacing: Tide.s3) {
            if let product {
                VStack(spacing: Tide.hair) {
                    Text(product.name)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, Tide.edge)
            }
            if sources.count > 1 {
                thumbnails
            }
        }
        .padding(.bottom, Tide.s4)
    }

    private var thumbnails: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Tide.s2) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    let shape = RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous)
                    Button {
                        withAnimation(Tide.snap) { page = index }
                    } label: {
                        photo(source)
                            .frame(width: Tide.Kitchen.row, height: Tide.Kitchen.row)
                            .background(Color.white)
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(index == page ? mood.accent : Tide.hairline, lineWidth: index == page ? 2 : 1))
                            .opacity(index == page ? 1 : 0.7)
                            .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1)")
                    .accessibilityAddTraits(index == page ? .isSelected : [])
                }
            }
            .padding(.horizontal, Tide.edge)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The photo on a white card: product shots are cut out on white, so the
    /// card is what they were made for, and it zooms with the photo.
    private func photoCard(_ source: FoodHeroSource) -> some View {
        photo(source)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func photo(_ source: FoodHeroSource) -> some View {
        switch source {
        case let .local(data):
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        case let .remote(url):
            FoodRemoteImage(url: url, product: product, contentMode: .fit)
        }
    }
}

// MARK: - ZoomableImage

/// Pinch-to-zoom + pan wrapper; double-tap toggles between fit and 2.5×.
private struct ZoomableImage<Content: View>: View {
    @ViewBuilder
    let content: Content

    @State
    private var scale: CGFloat = 1
    @State
    private var lastScale: CGFloat = 1
    @State
    private var offset: CGSize = .zero
    @State
    private var lastOffset: CGSize = .zero

    var body: some View {
        Group {
            if scale > 1 {
                // Zoomed in: claim the pan with high priority so it doesn't
                // also trigger the parent TabView's page-swipe.
                content
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
                    .highPriorityGesture(drag)
            } else {
                // Not zoomed: no competing drag gesture, so the TabView's
                // own swipe-to-page gesture works normally.
                content
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnification)
            }
        }
        .onTapGesture(count: 2, perform: toggleZoom)
        .animation(Tide.snap, value: scale)
        .animation(Tide.snap, value: offset)
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, 1), 4)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= 1 {
                    resetOffset()
                }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else {
                    return
                }
                offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func toggleZoom() {
        if scale > 1 {
            scale = 1
            lastScale = 1
            resetOffset()
        } else {
            scale = 2.5
            lastScale = 2.5
        }
    }

    private func resetOffset() {
        offset = .zero
        lastOffset = .zero
    }
}
