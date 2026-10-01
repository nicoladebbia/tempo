//
// AIFeaturesSettingsCard.swift
// Tempo
//
// The "AI features" switch in Settings. Mirrors the consent the backend
// enforces (`ai_consent_at`): off means every AI request is refused with
// "AI is off", on lets Pro users reach plans, Quick Log, photo, voice, etc.
//

import OSLog
import SwiftUI

struct AIFeaturesSettingsCard: View {
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var isOn = AIConsentStore.cachedValue() ?? false
    @State
    private var isSaving = false
    @State
    private var errorMessage: String?

    var body: some View {
        SettingsFormCard(
            title: "AI features",
            footnote: errorMessage ?? "Plans, Quick Log, photo and voice logging, receipts and coaching send "
                + "what you type or snap to Tempo's AI. Turn off to keep everything on the device. "
                + "Needs Tempo Pro."
        ) {
            SettingsControlRow(label: "Use AI features", icon: "sparkles", iconTint: .tempoViolet) {
                Toggle("Use AI features", isOn: binding)
                    .labelsHidden()
                    .tint(Color.tempoSignal)
                    .disabled(isSaving)
                    .accessibilityIdentifier("aiFeaturesToggle")
            }
        }
        .task { await refresh() }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { newValue in
                let previous = isOn
                isOn = newValue
                Task { await save(newValue, revertTo: previous) }
            }
        )
    }

    private func refresh() async {
        guard let value = try? await AIConsentStore.fetch(apiClient: services.apiClient) else {
            return
        }
        isOn = value
    }

    private func save(_ value: Bool, revertTo previous: Bool) async {
        isSaving = true
        errorMessage = nil
        do {
            try await AIConsentStore.set(value, apiClient: services.apiClient)
        } catch {
            Logger.nutrition.error("AI consent change failed: \(error.localizedDescription, privacy: .public)")
            isOn = previous
            errorMessage = "Couldn't change that. Check your connection and try again."
        }
        isSaving = false
    }
}
