//
// OfflineBannerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Offline Banner

// A slim glass capsule: "you're offline". Amber symbol, one line.

struct OfflineBannerView: View {
    var body: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "wifi.slash")
                .font(Tide.bodyStrong)
                .foregroundStyle(Color.tempoWarning)
                .accessibilityHidden(true)

            Text("You're offline. Data may be stale.")
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tide.s5)
        .padding(.vertical, Tide.s2)
        .frame(minHeight: Tide.hit + Tide.s2)
        .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
        .padding(.horizontal, Tide.edge)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OfflineBannerView()
        .tidePage()
}
