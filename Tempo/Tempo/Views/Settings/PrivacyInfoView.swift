//
// PrivacyInfoView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - PrivacyInfoView

// Displays Tempo's data practices: what stays on-device, what's sent to AI, and what's never shared.

struct PrivacyInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Label("YOUR DATA, YOUR DEVICE", systemImage: "lock.shield.fill")
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoSuccess)
                    Text("Tempo is built privacy-first. Here's exactly what stays on your device and what doesn't.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                }

                // ON-DEVICE section
                dataSection(
                    title: "STAYS ON YOUR DEVICE",
                    icon: "iphone",
                    color: Color.tempoSuccess,
                    items: [
                        DataItem(name: "Heart rate, HRV, resting HR", detail: "HealthKit — never leaves your device"),
                        DataItem(name: "Sleep stages & duration", detail: "HealthKit — processed locally"),
                        DataItem(name: "Steps & active energy", detail: "HealthKit — local only"),
                        DataItem(name: "Body composition", detail: "Weight, body fat, lean mass — local"),
                        DataItem(name: "Workout history", detail: "Stored in SwiftData on-device"),
                        DataItem(name: "TDEE & macro calculations", detail: "Pure math — no server needed"),
                        DataItem(name: "Adaptive diet adjustments", detail: "Computed locally from your data"),
                        DataItem(name: "Meal logs & photos", detail: "SwiftData — stays on your phone"),
                    ]
                )

                // SENT TO AI section
                dataSection(
                    title: "SENT TO AI (ANONYMIZED)",
                    icon: "brain",
                    color: Color.tempoAmber,
                    items: [
                        DataItem(name: "Macro targets & remaining budget", detail: "Numbers only — no identity attached"),
                        DataItem(name: "Dietary restrictions", detail: "Lactose-free, vegan, etc. — no name"),
                        DataItem(name: "Recovery zone (green/yellow/red)", detail: "Zone label only, not raw scores"),
                        DataItem(name: "Time of day", detail: "For contextual meal suggestions"),
                    ]
                )

                // NEVER SENT section
                dataSection(
                    title: "NEVER SENT ANYWHERE",
                    icon: "xmark.shield.fill",
                    color: Color.tempoError,
                    items: [
                        DataItem(name: "Your name or identity", detail: "AI never knows who you are"),
                        DataItem(name: "Raw biometric sensor data", detail: "Heart rate streams, HRV readings"),
                        DataItem(name: "Location data", detail: "Tempo doesn't track location"),
                        DataItem(name: "Photos", detail: "Analyzed on-device, never uploaded"),
                    ]
                )

                // Token security
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Label("CREDENTIAL SECURITY", systemImage: "key.fill")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(
                        "All authentication tokens (Apple ID, Whoop OAuth) are stored in the iOS Keychain with device-level encryption. They are never accessible to other apps or exported."
                    )
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                }
                .padding(TempoSpacing.md)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl))
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.vertical, TempoSpacing.lg)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Data Section

    private func dataSection(title: String, icon: String, color: Color, items: [DataItem]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Label(title, systemImage: icon)
                .font(.tempoHeadline)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: TempoSpacing.sm) {
                        Circle()
                            .fill(color)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                            Text(item.name)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Text(item.detail)
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                }
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl))
    }
}

// MARK: - DataItem

private struct DataItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
}

#Preview {
    NavigationStack {
        PrivacyInfoView()
    }
}
