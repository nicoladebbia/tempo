//
// WhoopConnectionView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Whoop Connection View

// Connects directly to Whoop's API via OAuth2.
// User enters developer.whoop.com credentials, then taps Connect to log in.

struct WhoopConnectionView: View {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.dismiss)
    private var dismiss
    @State
    private var isConnecting = false
    @State
    private var isDisconnecting = false
    @State
    private var showDisconnectConfirmation = false
    @State
    private var errorMessage: String?
    @State
    private var showCredentialSetup = false

    /// Credential input fields
    @State
    private var clientIDInput = ""
    @State
    private var clientSecretInput = ""

    private var whoop: any WhoopServiceProtocol {
        services.whoop
    }

    private var isConnected: Bool {
        whoop.connectionState == .connected
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                // Status section
                statusSection

                if isConnected {
                    // Data preview
                    dataPreviewSection

                    // Sync button
                    syncButton

                    // Disconnect button
                    disconnectButton
                } else if showCredentialSetup || !whoop.hasCredentials {
                    // Credential setup
                    credentialSetupSection
                } else {
                    // Connect CTA
                    connectSection
                }

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TempoSpacing.lg)
                }

                // Footnote
                if isConnected {
                    Text("Whoop data refreshes every 15 min in the background via BGAppRefresh.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.top, TempoSpacing.sm)
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Whoop Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
        .confirmationDialog(
            "Disconnect Whoop?",
            isPresented: $showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Connected", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await performDisconnect() }
            }
        } message: {
            Text("This will revoke Whoop access and remove synced data. You can reconnect anytime.")
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("WHOOP INTEGRATION")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                // Connection status row
                HStack(spacing: TempoSpacing.sm) {
                    Text("Status:")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    Circle()
                        .fill(statusDotColor)
                        .frame(width: 8, height: 8)

                    Text(statusText)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)

                    if whoop.isDemoMode, isConnected {
                        Text("DEMO")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.tempoAmber)
                            .clipShape(Capsule())
                    }
                }

                if isConnected {
                    HStack(spacing: TempoSpacing.sm) {
                        Text("Last sync:")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text(lastSyncText)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
        .padding(.top, TempoSpacing.lg)
    }

    // MARK: - Data Preview Section

    private var dataPreviewSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("LATEST DATA")
                .font(.tempoModuleTag)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                dataRow(icon: "heart.fill", label: "Recovery", value: "Available")
                dataRow(icon: "bed.double.fill", label: "Sleep", value: "Available")
                dataRow(icon: "flame.fill", label: "Strain", value: "Available")
                dataRow(icon: "waveform.path.ecg", label: "HRV", value: "Available")
                dataRow(icon: "drop.fill", label: "SpO2", value: "Available")
                dataRow(icon: "thermometer.medium", label: "Skin Temp", value: "Available")
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
        }
    }

    private func dataRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .frame(width: 24)

            Text("\(label):")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()

            Image(systemName: "checkmark")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSuccess)

            Text(value)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Credential Setup Section

    private var credentialSetupSection: some View {
        VStack(spacing: TempoSpacing.xl) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: TempoSpacing.sm) {
                Text("Whoop Developer Setup")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("To connect your Whoop, you need API credentials from the Whoop Developer Portal.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            // Instructions
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                instructionRow(number: "1", text: "Go to developer.whoop.com")
                instructionRow(number: "2", text: "Create an application")
                instructionRow(number: "3", text: "Set redirect URI to:\ntempo://whoop/callback")
                instructionRow(number: "4", text: "Copy the Client ID and Client Secret below")
            }
            .padding(TempoSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)

            // Input fields
            VStack(spacing: TempoSpacing.md) {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Client ID")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    TextField("Paste your Client ID", text: $clientIDInput)
                        .font(.tempoBody)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(TempoSpacing.md)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                                .stroke(Color.tempoTextTertiary.opacity(0.3), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    Text("Client Secret")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    SecureField("Paste your Client Secret", text: $clientSecretInput)
                        .font(.tempoBody)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(TempoSpacing.md)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                                .stroke(Color.tempoTextTertiary.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            // Save credentials button
            Button {
                saveCredentials()
            } label: {
                Text("Save & Continue")
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSave ? Color.tempoSignal : Color.tempoTextTertiary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .disabled(!canSave)

            // Demo mode fallback — DEBUG only: demo numbers are mock data and
            // must never reach App Store users (display-only; see
            // WhoopServiceProtocol.providesRealData).
            #if DEBUG
                Button {
                    Task {
                        await whoop.connectDemo()
                        dismiss()
                    }
                } label: {
                    Text("Skip — Use Demo Data")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            #endif
        }
        .padding(.top, TempoSpacing.lg)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Text(number)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color.tempoSignal)
                .clipShape(Circle())

            Text(text)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    private var canSave: Bool {
        !clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveCredentials() {
        let id = clientIDInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try whoop.saveCredentials(clientID: id, clientSecret: secret)
            showCredentialSetup = false
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save credentials."
        }
    }

    // MARK: - Connect Section

    private var connectSection: some View {
        VStack(spacing: TempoSpacing.xl) {
            Image(systemName: "sensor.tag.radiowaves.forward.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: TempoSpacing.sm) {
                Text("Connect Your Whoop")
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                Text("Tap Connect to log in to your Whoop account. Tempo will access your recovery, sleep, strain, and HRV data.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            Button {
                Task { await performConnect() }
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    if isConnecting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isConnecting ? "Connecting..." : "Connect Whoop")
                        .font(.tempoHeadline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .disabled(isConnecting)

            // Change credentials
            Button {
                showCredentialSetup = true
            } label: {
                Text("Change API Credentials")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // Demo mode fallback — DEBUG only: demo numbers are mock data and
            // must never reach App Store users (display-only; see
            // WhoopServiceProtocol.providesRealData).
            #if DEBUG
                Button {
                    Task {
                        await whoop.connectDemo()
                        dismiss()
                    }
                } label: {
                    Text("Use Demo Data Instead")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            #endif
        }
        .padding(.top, TempoSpacing.xxxl)
    }

    // MARK: - Sync Button

    private var syncButton: some View {
        Button {
            Task {
                try? await whoop.syncAll()
            }
        } label: {
            Text("Sync Now")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
    }

    // MARK: - Disconnect Button

    private var disconnectButton: some View {
        Button {
            showDisconnectConfirmation = true
        } label: {
            Text(isDisconnecting ? "Disconnecting..." : "Disconnect Whoop")
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .foregroundStyle(Color.tempoError)
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                        .stroke(Color.tempoError, lineWidth: 1)
                )
        }
        .disabled(isDisconnecting)
    }

    // MARK: - Actions

    private func performConnect() async {
        isConnecting = true
        errorMessage = nil
        do {
            try await whoop.connect()
            dismiss()
        } catch {
            switch error {
            case WhoopError.userCancelled:
                break
            case WhoopError.noCredentials:
                showCredentialSetup = true
            default:
                errorMessage = "Connection failed: \(error.localizedDescription)"
            }
        }
        isConnecting = false
    }

    private func performDisconnect() async {
        isDisconnecting = true
        errorMessage = nil
        do {
            try await whoop.disconnect()
        } catch {
            errorMessage = "Disconnect failed. Please try again."
        }
        isDisconnecting = false
    }

    // MARK: - Computed

    private var statusDotColor: Color {
        switch whoop.connectionState {
        case .connected: Color.tempoSuccess
        case .connecting: Color.tempoWarning
        case .disconnected: Color.tempoTextTertiary
        case .error: Color.tempoError
        }
    }

    private var lastSyncText: String {
        guard let syncDate = whoop.lastSyncDate else {
            return "Never"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: syncDate, relativeTo: Date())
    }

    private var statusText: String {
        switch whoop.connectionState {
        case .connected: "Connected"
        case .connecting: "Connecting..."
        case .disconnected: "Not Connected"
        case let .error(msg): "Error: \(msg)"
        }
    }
}

// MARK: - Preview

#Preview("Connected") {
    NavigationStack {
        WhoopConnectionView()
            .environment(ServiceContainer.mock())
    }
}

#Preview("Disconnected") {
    NavigationStack {
        WhoopConnectionView()
            .environment(ServiceContainer.mock())
    }
}
