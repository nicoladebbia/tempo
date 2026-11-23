//
// privacy_new.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - PrivacyInfoView

// Displays Tempo's data practices: what stays on-device, what's sent to AI, and what's never shared.

struct PrivacyInfoView: View {
    @Environment(\.tideMood)
    private var mood

    var body: some View {
        TideSettingsPage {
            // Header
            VStack(alignment: .leading, spacing: Tide.s3) {
                Label {
                    Text("Your data, your device")
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "lock.shield.fill")
                        .font(Tide.title2)
                        .foregroundStyle(mood.accent)
                }
                .accessibilityAddTraits(.isHeader)
                Text("Tempo is built privacy-first. Here's exactly what stays on your device and what doesn't.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tide.s2)

            // ON-DEVICE section
            dataSection(
                title: "Stays on your device",
                icon: "iphone",
                color: mood.accent,
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
                title: "Sent to AI (anonymized)",
                icon: "brain",
                color: Tide.streak,
                items: [
                    DataItem(name: "Macro targets & remaining budget", detail: "Numbers only — no identity attached"),
                    DataItem(name: "Dietary restrictions", detail: "Lactose-free, vegan, etc. — no name"),
                    DataItem(name: "Recovery zone (green/yellow/red)", detail: "Zone label only, not raw scores"),
                    DataItem(name: "Time of day", detail: "For contextual meal suggestions"),
                ]
            )

            // NEVER SENT section
            dataSection(
                title: "Never sent anywhere",
                icon: "xmark.shield.fill",
                color: Tide.danger,
                items: [
                    DataItem(name: "Your name or identity", detail: "AI never knows who you are"),
                    DataItem(name: "Raw biometric sensor data", detail: "Heart rate streams, HRV readings"),
                    DataItem(name: "Location data", detail: "Tempo doesn't track location"),
                    DataItem(name: "Photos", detail: "Analyzed on-device, never uploaded"),
                ]
            )

            // Token security
            VStack(alignment: .leading, spacing: Tide.s2) {
                Label("Credential security", systemImage: "key.fill")
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Text(
                    "All authentication tokens (Apple ID, Whoop OAuth) are stored in the iOS Keychain with device-level encryption. They are never accessible to other apps or exported."
                )
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            }
            .tideCard(padding: Tide.s5)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Data Section

    private func dataSection(title: String, icon: String, color: Color, items: [DataItem]) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            Label(title, systemImage: icon)
                .font(Tide.headline)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Tide.s3) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: Tide.s3) {
                        Circle()
                            .fill(color)
                            .frame(width: Tide.s2, height: Tide.s2)
                            .padding(.top, Tide.s2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Tide.hair) {
                            Text(item.name)
                                .font(Tide.bodyStrong)
                                .foregroundStyle(Tide.text)
                            Text(item.detail)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .tideCard(padding: Tide.s5)
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
