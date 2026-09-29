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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $page) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    ZoomableImage {
                        sourceImage(source)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: sources.count > 1 ? .always : .never))
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white, Color.black.opacity(TempoOpacity.o40))
                    }
                    .padding(TempoSpacing.lg)
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func sourceImage(_ source: FoodHeroSource) -> some View {
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
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: scale)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: offset)
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
