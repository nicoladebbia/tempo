//
// TempoTextField.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Tempo Text Field

// Label above, a soft Tide field below (52 pt, accent ring while focused,
// danger ring on error), helper or error text under it.

struct TempoTextField: View {
    let label: String
    let placeholder: String
    @Binding
    var text: String
    var leadingIcon: String?
    var helperText: String?
    var errorText: String?

    @FocusState
    private var isFocused: Bool

    private var hasError: Bool {
        errorText?.isEmpty == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            if !label.isEmpty {
                Text(label)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }

            HStack(spacing: Tide.s3) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }

                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Tide.text3))
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text)
                    .focused($isFocused)

                if isFocused, !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text3)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(label.isEmpty ? "text" : label)")
                    .padding(.trailing, -Tide.s3)
                }
            }
            .tideFieldSurface(focused: isFocused, invalid: hasError)

            if let error = errorText, !error.isEmpty {
                Text(error)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let helper = helperText, !helper.isEmpty {
                Text(helper)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    @Previewable @State
    var text = "Nicola"

    VStack(spacing: Tide.s5) {
        TempoTextField(label: "Name", placeholder: "Your name", text: $text, leadingIcon: "person", helperText: "Shown on the leaderboard")
        TempoTextField(label: "Username", placeholder: "@username", text: $text, errorText: "Already taken")
    }
    .padding(Tide.edge)
    .tidePage()
}
