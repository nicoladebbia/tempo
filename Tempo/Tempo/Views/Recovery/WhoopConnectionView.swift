import SwiftUI

// MARK: - Whoop Connection View
// Per WIREFRAMES.md Screen 35 — Whoop Connection Management.
// Shows connection status, last sync, data preview, sync/disconnect actions.

struct WhoopConnectionView: View {

    @Environment(ServiceContainer.self) private var services
    @State private var isConnecting = false
    @State private var isDisconnecting = false
    @State private var showDisconnectConfirmation = false
    @State private var errorMessage: String?

    private var whoop: any WhoopServiceProtocol { services.whoop }
    private var isConnected: Bool { whoop.connectionState == .connected }

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
            .padding(.bottom, 50)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Whoop Connection")
        .navigationBarTitleDisplayMode(.inline)
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
    // Per WIREFRAMES.md Screen 35 — Status card

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
                }

                if isConnected {
                    HStack(spacing: TempoSpacing.sm) {
                        Text("Last sync:")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                        Text("Just now")
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

                Text("Track recovery, sleep, strain, and HRV. Tempo uses Whoop data to optimize your training.")
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
                .frame(height: 56)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .disabled(isConnecting)
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
        } catch {
            if case WhoopError.userCancelled = error {
                // User cancelled — no error to show
            } else {
                errorMessage = "Connection failed. Please try again."
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
        case .connected: return Color.tempoSuccess
        case .connecting: return Color.tempoWarning
        case .disconnected: return Color.tempoTextTertiary
        case .error: return Color.tempoError
        }
    }

    private var statusText: String {
        switch whoop.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Not Connected"
        case .error(let msg): return "Error: \(msg)"
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
            .environment({
                let container = ServiceContainer.mock()
                return container
            }())
    }
}
