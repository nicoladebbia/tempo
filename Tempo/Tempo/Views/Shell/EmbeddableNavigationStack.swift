//
// EmbeddableNavigationStack.swift
// Tempo
//

import SwiftUI

/// A `NavigationStack` that steps aside when the screen is already inside one.
/// A stack nested in a stack loses its pushes (the old Arena "See All" bug).
struct EmbeddableNavigationStack<Content: View>: View {
    let embedded: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }
}
