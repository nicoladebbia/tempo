//
// AIBlockerCard.swift
// Tempo
//
// The one place an AI feature explains it is blocked: "needs Pro" -> See Pro
// (PaywallView), "AI is off" -> Turn on AI (records consent, then retries
// where the caller can). `AIBlockerCard` is the inline form; `.aiBlockerAlert`
// is the same thing as an alert for surfaces that only had a toast.
//

import OSLog
import SwiftUI

// MARK: - AIBlockerCard

struct AIBlockerCard: View {
    let blocker: AIBlocker
    /// Feature-specific wording; defaults to the blocker's generic message.
    var message: String?
    /// Called after consent was recorded so the caller can retry.
    var onConsentGranted: (() -> Void)?

    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var isWorking = false
    @State
    private var consentError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "lock.fill")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoAmber)
                Text(message ?? blocker.message)
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
            }
            if let consentError {
                Text(consentError)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoError)
            }
            Button {
                act()
            } label: {
                Text(isWorking ? "Working…" : blocker.actionTitle)
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoSignal)
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("aiBlockerAction")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoAmber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        .accessibilityIdentifier("aiBlockerCard")
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    private func act() {
        switch blocker {
        case .proRequired:
            showPaywall = true
        case .aiConsentRequired:
            isWorking = true
            consentError = nil
            Task {
                do {
                    try await AIConsentStore.set(true, apiClient: services.apiClient)
                    onConsentGranted?()
                } catch {
                    Logger.nutrition.error("AI consent failed: \(error.localizedDescription, privacy: .public)")
                    consentError = "Couldn't turn on AI features. Try again."
                }
                isWorking = false
            }
        }
    }
}

// MARK: - .aiBlockerAlert

private struct AIBlockerAlertModifier: ViewModifier {
    @Binding
    var blocker: AIBlocker?
    var onConsentGranted: (() -> Void)?

    @Environment(ServiceContainer.self)
    private var services
    @State
    private var showPaywall = false
    @State
    private var consentFailed = false

    func body(content: Content) -> some View {
        content
            .alert(
                blocker?.title ?? "",
                isPresented: Binding(
                    get: { blocker != nil },
                    set: { if !$0 { blocker = nil } }
                ),
                presenting: blocker
            ) { current in
                Button(current.actionTitle) {
                    act(on: current)
                }
                Button("Not now", role: .cancel) {}
            } message: { current in
                Text(current.message)
            }
            .alert("Couldn't turn on AI features", isPresented: $consentFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and try again.")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
    }

    private func act(on current: AIBlocker) {
        switch current {
        case .proRequired:
            showPaywall = true
        case .aiConsentRequired:
            let client = services.apiClient
            let retry = onConsentGranted
            Task {
                do {
                    try await AIConsentStore.set(true, apiClient: client)
                    retry?()
                } catch {
                    Logger.nutrition.error("AI consent failed: \(error.localizedDescription, privacy: .public)")
                    consentFailed = true
                }
            }
        }
    }
}

extension View {
    /// Presents the shared "needs Pro / AI is off" alert whenever `blocker`
    /// becomes non-nil. "Turn on AI" records consent and calls
    /// `onConsentGranted` so the caller can retry.
    func aiBlockerAlert(_ blocker: Binding<AIBlocker?>, onConsentGranted: (() -> Void)? = nil) -> some View {
        modifier(AIBlockerAlertModifier(blocker: blocker, onConsentGranted: onConsentGranted))
    }
}
