import SwiftUI

// MARK: - Tempo Text Field
// Per DESIGN_SYSTEM.md Section 8.5 — Text Field:
// 48pt height, 12pt radius, focus animation, error state, optional leading icon.

struct TempoTextField: View {

    let label: String
    let placeholder: String
    @Binding var text: String
    var leadingIcon: String?
    var helperText: String?
    var errorText: String?

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool

    private var hasError: Bool {
        errorText != nil && !errorText!.isEmpty
    }

    private var fieldBackground: Color {
        colorScheme == .dark
            ? Color(red: 38 / 255, green: 38 / 255, blue: 38 / 255)  // #262626
            : Color(red: 243 / 255, green: 244 / 255, blue: 246 / 255)  // #F3F4F6
    }

    private var borderColor: Color {
        if hasError {
            return colorScheme == .dark
                ? Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
                : Color.tempoError
        }
        if isFocused {
            return colorScheme == .dark ? Color.tempoBone : Color.tempoInk
        }
        return colorScheme == .dark
            ? Color(red: 56 / 255, green: 56 / 255, blue: 58 / 255)
            : Color.tempoBorder
    }

    private var borderWidth: CGFloat {
        (isFocused || hasError) ? 2 : 1
    }

    private var placeholderColor: Color {
        colorScheme == .dark
            ? Color(red: 82 / 255, green: 82 / 255, blue: 91 / 255)
            : Color.tempoTextDisabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.inputLabelGap) {
            // Label
            if !label.isEmpty {
                Text(label)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            // Field
            HStack(spacing: TempoSpacing.inputHorizontal) {
                if let icon = leadingIcon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.tempoConcrete)
                }

                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(placeholderColor))
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .focused($isFocused)

                if isFocused && !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.tempoAsh)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.inputHorizontal)
            .frame(height: 48)
            .background(fieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
            .animation(.easeInOut(duration: 0.2), value: hasError)

            // Helper / Error text
            if let error = errorText, !error.isEmpty {
                Text(error)
                    .font(.tempoFootnote)
                    .foregroundStyle(colorScheme == .dark
                        ? Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
                        : Color.tempoError)
            } else if let helper = helperText, !helper.isEmpty {
                Text(helper)
                    .font(.tempoFootnote)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
    }
}
