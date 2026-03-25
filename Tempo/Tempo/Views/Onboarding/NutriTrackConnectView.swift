import SwiftUI
import os

// MARK: - NutriTrack Connect View
// Per BUILD_PLAN step 11.3.
// Per INTEGRATION_SPECS.md Section 3.1 — Connection form (URL + PIN).
// Per UX_COPY_BIBLE.md Section 2.9 — All strings.

struct NutriTrackConnectView: View {

    let nutriTrackService: any NutriTrackServiceProtocol
    var onConnected: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var pin = ""
    @State private var connectionState: ConnectState = .idle
    @State private var showInfoSheet = false

    private enum ConnectState: Equatable {
        case idle
        case testing
        case success
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.xxxl) {
                    headerSection
                    formSection
                    errorSection
                    connectButton
                    skipSection
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.xxxl)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Connect NutriTrack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                infoSheet
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: TempoSpacing.md) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.tempoViolet)

            Text("Enter your NutriTrack server address and PIN.")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Form

    private var formSection: some View {
        VStack(spacing: TempoSpacing.md) {
            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("SERVER URL")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)

                TextField("https://nutritrack.example.com", text: $serverURL)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.lg)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .disabled(connectionState == .testing || connectionState == .success)
            }

            VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                Text("PIN")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)

                SecureField("4-8 digit PIN", text: $pin)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .keyboardType(.numberPad)
                    .padding(TempoSpacing.cardPadding)
                    .background(Color.tempoSurfaceCard)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.lg)
                            .stroke(Color.tempoBorder, lineWidth: 1)
                    )
                    .disabled(connectionState == .testing || connectionState == .success)
            }
        }
    }

    // MARK: - Error Display

    @ViewBuilder
    private var errorSection: some View {
        if case .error(let message) = connectionState {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSignal)

                Text(message)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSignal)
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSignal.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md))
        }

        if connectionState == .success {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSuccess)

                // Per UX_COPY_BIBLE: onb_nutritrack_success
                Text("Connected!")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSuccess)
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSuccess.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md))
        }
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            connectAction()
        } label: {
            Group {
                if connectionState == .testing {
                    HStack(spacing: TempoSpacing.sm) {
                        ProgressView()
                            .tint(Color.tempoBone)
                        // Per UX_COPY_BIBLE: onb_nutritrack_testing
                        Text("Testing...")
                            .font(.tempoHeadline)
                    }
                } else if connectionState == .success {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: "checkmark")
                            .font(.tempoHeadline)
                        Text("Done")
                            .font(.tempoHeadline)
                    }
                } else {
                    Text("Connect")
                        .font(.tempoHeadline)
                }
            }
            .foregroundStyle(Color.tempoBone)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                isFormValid && connectionState != .testing
                    ? Color.tempoSignal
                    : Color.tempoSignal.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl))
        }
        .disabled(!isFormValid || connectionState == .testing || connectionState == .success)
    }

    // MARK: - Skip / Info

    private var skipSection: some View {
        VStack(spacing: TempoSpacing.md) {
            // Per UX_COPY_BIBLE: onb_nutritrack_skip
            Button("Skip for now") {
                dismiss()
            }
            .font(.tempoCallout)
            .foregroundStyle(Color.tempoTextSecondary)

            // Per UX_COPY_BIBLE: onb_nutritrack_no_app_link
            Button("Don't have NutriTrack?") {
                showInfoSheet = true
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoElectric)
        }
    }

    // MARK: - Info Sheet

    private var infoSheet: some View {
        NavigationStack {
            VStack(spacing: TempoSpacing.xl) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.tempoElectric)

                // Per UX_COPY_BIBLE: onb_nutritrack_no_app_body
                Text("NutriTrack is a self-hosted nutrition tracking app. Without NutriTrack, Tempo won't track your nutrition automatically. You can still set meal-count non-negotiables and check them off manually.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button("Got it") {
                    showInfoSheet = false
                }
                .buttonStyle(.tempoPrimary)
            }
            .padding(TempoSpacing.screenEdge)
            .background(Color.tempoBgPrimary)
            .navigationTitle("About NutriTrack")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && pin.count >= 4
            && pin.count <= 8
            && pin.allSatisfy(\.isNumber)
    }

    // MARK: - Connect Action

    private func connectAction() {
        guard isFormValid else { return }

        let trimmedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL) else {
            // Per UX_COPY_BIBLE: onb_nutritrack_error_url
            connectionState = .error("Couldn't reach that server. Check the URL and try again.")
            return
        }

        connectionState = .testing
        HapticManager.impact(.light)

        Task {
            do {
                try await nutriTrackService.connect(baseURL: url, pin: pin)
                connectionState = .success
                HapticManager.notification(.success)

                // Auto-dismiss after brief success display
                try? await Task.sleep(for: .seconds(1))
                onConnected?()
                dismiss()
            } catch {
                // Map errors to user-facing messages
                let message: String
                if let nutriError = error as? NutriTrackError {
                    switch nutriError {
                    case .invalidURL:
                        // Per UX_COPY_BIBLE: onb_nutritrack_error_url
                        message = "Couldn't reach that server. Check the URL and try again."
                    case .invalidPIN:
                        // Per UX_COPY_BIBLE: onb_nutritrack_error_pin
                        message = "Invalid PIN. Check your NutriTrack settings."
                    case .serverUnreachable:
                        // Per UX_COPY_BIBLE: onb_nutritrack_error_unreachable
                        message = "Server not responding. Is NutriTrack running?"
                    case .timeout:
                        // Per UX_COPY_BIBLE: onb_nutritrack_error_timeout
                        message = "Connection timed out. Check that NutriTrack is accessible from the internet."
                    default:
                        message = error.localizedDescription
                    }
                } else if let apiError = error as? APIError {
                    switch apiError {
                    case .unauthorized:
                        message = "Invalid PIN. Check your NutriTrack settings."
                    case .notFound, .networkError:
                        message = "Couldn't reach that server. Check the URL and try again."
                    case .timeout:
                        message = "Connection timed out. Check that NutriTrack is accessible from the internet."
                    default:
                        message = "Connection failed. Please try again."
                    }
                } else {
                    message = "Connection failed: \(error.localizedDescription)"
                }

                connectionState = .error(message)
                HapticManager.notification(.error)
            }
        }
    }
}
