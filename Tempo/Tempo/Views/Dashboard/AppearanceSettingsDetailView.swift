//
// AppearanceSettingsDetailView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftUI

// MARK: - AppearanceSettingsDetailView

// Accent color picker — lets user choose between Signal Red, Electric Blue, Success Green.
// Stored in UserDefaults via @AppStorage and applied globally.

struct AppearanceSettingsDetailView: View {
    @AppStorage("accentColorChoice")
    private var accentColorChoice: String = AccentColorOption.signalRed.rawValue

    var body: some View {
        List {
            Section {
                ForEach(AccentColorOption.allCases) { option in
                    Button {
                        withAnimation(.easeInOut(duration: TempoAnimation.smallDuration)) {
                            accentColorChoice = option.rawValue
                        }
                    } label: {
                        HStack(spacing: TempoSpacing.md) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 28, height: 28)
                                .overlay {
                                    Circle()
                                        .stroke(Color.tempoBorder, lineWidth: 1)
                                }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.displayName)
                                    .font(.tempoCallout)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.tempoTextPrimary)

                                Text(option.hexString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Color.tempoTextTertiary)
                            }

                            Spacer()

                            if accentColorChoice == option.rawValue {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.tempoTitle3)
                                    .foregroundStyle(option.color)
                            }
                        }
                        .padding(.vertical, TempoSpacing.xs)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text("The accent color is used for buttons, toggles, and highlights throughout the app.")
                    .font(.tempoCaption1)
            }
            .listRowBackground(Color.tempoSurfaceCard)

            // Preview section
            Section("Preview") {
                VStack(spacing: TempoSpacing.md) {
                    HStack {
                        Text("Sample Button")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.tempoTextInverse)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(selectedColor)
                            .clipShape(Capsule())

                        Spacer()

                        Toggle("", isOn: .constant(true))
                            .tint(selectedColor)
                            .labelsHidden()
                    }

                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(selectedColor)
                        Text("Active indicator")
                            .font(.tempoCallout)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                    }

                    LinearProgressBar(
                        progress: 0.65,
                        color: selectedColor,
                        height: 4,
                        showPercentage: false
                    )
                }
                .padding(.vertical, TempoSpacing.xs)
            }
            .listRowBackground(Color.tempoSurfaceCard)
        }
        .scrollContentBackground(.hidden)
        .background(Color.tempoBgPrimary)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var selectedColor: Color {
        AccentColorOption(rawValue: accentColorChoice)?.color ?? Color.tempoSignal
    }
}

// MARK: - AccentColorOption

enum AccentColorOption: String, CaseIterable, Identifiable {
    case signalRed = "signal_red"
    case electricBlue = "electric_blue"
    case successGreen = "success_green"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .signalRed: "Signal Red"
        case .electricBlue: "Electric Blue"
        case .successGreen: "Success Green"
        }
    }

    var hexString: String {
        switch self {
        case .signalRed: "#FF3B30"
        case .electricBlue: "#007AFF"
        case .successGreen: "#34C759"
        }
    }

    var color: Color {
        switch self {
        case .signalRed: Color.tempoSignal
        case .electricBlue: Color.tempoElectric
        case .successGreen: Color.tempoSuccess
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AppearanceSettingsDetailView()
    }
}
