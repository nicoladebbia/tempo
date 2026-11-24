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
        SettingsModeCard(
            icon: "sparkles",
            title: "Use AI features",
            detail: "Plans, Quick Log, photo and voice logging, receipts and coaching.",
            identifier: "aiFeaturesToggle",
            isDisabled: isSaving,
            isOn: binding
        ) {
            Text(errorMessage ?? "They send what you type or snap to Tempo's AI. Turn off to keep everything "
                + "on the device. Needs Tempo Pro.")
                .font(Tide.caption)
                .foregroundStyle(errorMessage == nil ? Tide.text2 : Tide.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sensoryFeedback(.selection, trigger: isOn)
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
            errorMessage = "Couldn't change that. \(AIBlocker.readableDescription(error))"
        }
        isSaving = false
    }
}
