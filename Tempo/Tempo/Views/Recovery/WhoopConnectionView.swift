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
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var isConnecting = false
    @State
    private var isDisconnecting = false
    @State
    private var isSyncing = false
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
        TideScrollPage(spacing: Tide.s5) {
            // Status section
            statusSection

            if isConnected {
                // Data preview
                dataPreviewSection

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
                HStack(alignment: .top, spacing: Tide.s3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.danger)
                        .accessibilityHidden(true)
                    Text(errorMessage)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .tideTintedCard(Tide.danger, padding: Tide.s4, radius: Tide.tileRadius)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                .transition(.opacity)
            }

            // Footnote
            if isConnected {
                Text("Whoop data refreshes every 15 min in the background via BGAppRefresh.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .multilineTextAlignment(.center)
                    .padding(.top, Tide.s2)
            }
        }
        // The step that moves things on stays under the thumb.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinnedAction
        }
        .navigationTitle("Whoop Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TideCloseButton { dismiss() }
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
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Whoop integration")

            VStack(alignment: .leading, spacing: Tide.s3) {
                // Connection status: the state in the colour of the state
                HStack(spacing: Tide.s3) {
                    TideAreaIconTile(systemName: "sensor.tag.radiowaves.forward.fill", tint: statusDotColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text("Status").tideLabel(Tide.text3)
                        HStack(spacing: Tide.s2) {
                            Circle()
                                .fill(statusDotColor)
                                .frame(width: Tide.s2, height: Tide.s2)
                                .accessibilityHidden(true)
                            Text(statusText)
                                .font(Tide.headline)
                                .foregroundStyle(Tide.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: Tide.s2)

                    if whoop.isDemoMode, isConnected {
                        TideStatusPill(text: "Demo", tint: TideTone.amber)
                    }
                }
                .accessibilityElement(children: .combine)

                if isConnected {
                    TideDivider()
                    let row = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
                        : AnyLayout(HStackLayout(spacing: Tide.s2))
                    row {
                        Text("Last sync")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                        if !typeSize.isAccessibilitySize {
                            Spacer(minLength: Tide.s2)
                        }
                        Text(lastSyncText)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .tideCard()
        }
        .padding(.top, Tide.s2)
    }

    // MARK: - Data Preview Section

    private var dataPreviewSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Latest data")

            VStack(spacing: 0) {
                dataRow(icon: "heart.fill", label: "Recovery", value: "Available")
                TideDivider()
                dataRow(icon: "bed.double.fill", label: "Sleep", value: "Available")
                TideDivider()
                dataRow(icon: "flame.fill", label: "Strain", value: "Available")
                TideDivider()
                dataRow(icon: "waveform.path.ecg", label: "HRV", value: "Available")
                TideDivider()
                dataRow(icon: "drop.fill", label: "SpO2", value: "Available")
                TideDivider()
                dataRow(icon: "thermometer.medium", label: "Skin Temp", value: "Available")
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func dataRow(icon: String, label: String, value: String) -> some View {
        let stacks = typeSize.isAccessibilitySize
        let layout = stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s1))
            : AnyLayout(HStackLayout(spacing: Tide.s3))
        return layout {
            HStack(spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text2)
                    .frame(width: Tide.icon)
                    .accessibilityHidden(true)

                Text(label)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !stacks {
                Spacer(minLength: Tide.s2)
            }

            HStack(spacing: Tide.s2) {
                Image(systemName: "checkmark")
                    .font(Tide.label)
                    .foregroundStyle(TideTone.mint)
                    .accessibilityHidden(true)

                Text(value)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
            }
            .padding(.leading, stacks ? Tide.icon + Tide.s3 : 0)
        }
        .frame(minHeight: Tide.hit, alignment: .leading)
        .padding(.vertical, stacks ? Tide.s2 : 0)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Credential Setup Section

    private var credentialSetupSection: some View {
        VStack(spacing: Tide.s5) {
            VStack(spacing: Tide.s3) {
                TideAreaIconTile(systemName: "key.fill", tint: Tide.text2, size: Tide.avatarLarge)
                    .accessibilityHidden(true)

                Text("Whoop developer setup")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)

                Text("To connect your Whoop, you need API credentials from the Whoop Developer Portal.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Tide.s2)

            // Instructions
            VStack(alignment: .leading, spacing: Tide.s3) {
                instructionRow(number: "1", text: "Go to developer.whoop.com")
                instructionRow(number: "2", text: "Create an application")
                instructionRow(number: "3", text: "Set redirect URI to:\ntempo://whoop/callback")
                instructionRow(number: "4", text: "Copy the Client ID and Client Secret below")
            }
            .tideCard()

            // Input fields
            VStack(spacing: Tide.s4) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Client ID").tideLabel()
                    TextField("Paste your Client ID", text: $clientIDInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tideField()
                }

                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Client secret").tideLabel()
                    SecureField("Paste your Client Secret", text: $clientSecretInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .tideField()
                }
            }

            // Demo mode fallback — DEBUG only: demo numbers are mock data and
            // must never reach App Store users (display-only; see
            // WhoopServiceProtocol.providesRealData).
            #if DEBUG
                Button("Skip — use demo data") {
                    Task {
                        await whoop.connectDemo()
                        dismiss()
                    }
                }
                .buttonStyle(.tideGlass)
            #endif
        }
        .padding(.top, Tide.s2)
    }

    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: Tide.s3) {
            Text(number)
                .font(Tide.numeral(Tide.numeralS - Tide.s1, .bold))
                .foregroundStyle(Tide.ink)
                .frame(width: Tide.s6, height: Tide.s6)
                .background(Tide.text, in: .circle)
                .accessibilityHidden(true)

            Text(text)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(text)")
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
        VStack(spacing: Tide.s5) {
            VStack(spacing: Tide.s3) {
                TideAreaIconTile(
                    systemName: "sensor.tag.radiowaves.forward.fill", tint: Tide.text2, size: Tide.avatarLarge
                )
                .accessibilityHidden(true)

                Text("Connect your Whoop")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)

                Text("Tap Connect to log in to your Whoop account. Tempo will access your recovery, sleep, strain, and HRV data.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Tide.s6)

            // Change credentials
            Button("Change API credentials") {
                showCredentialSetup = true
            }
            .buttonStyle(.tideGlass)

            // Demo mode fallback — DEBUG only: demo numbers are mock data and
            // must never reach App Store users (display-only; see
            // WhoopServiceProtocol.providesRealData).
            #if DEBUG
                Button("Use demo data instead") {
                    Task {
                        await whoop.connectDemo()
                        dismiss()
                    }
                }
                .buttonStyle(.tideGlass)
            #endif
        }
    }

    // MARK: - Pinned action

    /// The one step that fits where the page is: save the keys, connect, or sync.
    @ViewBuilder
    private var pinnedAction: some View {
        VStack(spacing: Tide.s2) {
            if isConnected {
                syncButton
            } else if showCredentialSetup || !whoop.hasCredentials {
                Button("Save & continue") {
                    saveCredentials()
                }
                .buttonStyle(.tidePrimary)
                .disabled(!canSave)
            } else {
                Button {
                    Task { await performConnect() }
                } label: {
                    HStack(spacing: Tide.s2) {
                        if isConnecting {
                            ProgressView()
                                .tint(Tide.ink)
                        }
                        Text(isConnecting ? "Connecting..." : "Connect Whoop")
                    }
                }
                .buttonStyle(.tidePrimary)
                .disabled(isConnecting)
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Sync Button

    private var syncButton: some View {
        Button(isSyncing ? "Syncing..." : "Sync now") {
            Task {
                isSyncing = true
                try? await whoop.syncAll()
                isSyncing = false
            }
        }
        .buttonStyle(.tidePrimary)
        .disabled(isSyncing)
    }

    // MARK: - Disconnect Button

    private var disconnectButton: some View {
        Button(role: .destructive) {
            showDisconnectConfirmation = true
        } label: {
            Text(isDisconnecting ? "Disconnecting..." : "Disconnect Whoop")
                .foregroundStyle(Tide.danger)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
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
        case .connected: TideTone.mint
        case .connecting: TideTone.amber
        case .disconnected: Tide.text3
        case .error: Tide.danger
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
