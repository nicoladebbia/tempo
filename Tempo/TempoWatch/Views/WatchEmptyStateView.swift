//
// WatchEmptyStateView.swift
// Tempo
//
// Created by Tempo on 9/23/26.
//
//

import SwiftUI

struct WatchEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("OPEN TEMPO ON IPHONE")
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
            Text("Your real numbers land here once the app syncs.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
    }
}
