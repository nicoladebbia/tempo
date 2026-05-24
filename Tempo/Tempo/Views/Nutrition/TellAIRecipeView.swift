//
// TellAIRecipeView.swift
// Tempo
//
// Natural-language recipe creation: the user types or dictates a free-text
// recipe ("Pasta carbonara — 200g spaghetti, 100g pancetta, 2 eggs,
// parmesan, pepper. Boil pasta 10 min, render pancetta, toss with egg +
// cheese off heat") and Haiku parses it into a structured Recipe with
// ordered ingredients + steps. The parsed result lands in a confirmation
// sheet (WriteRecipeView's preview pattern would be nice but lift later —
// for now we save directly on Parse-and-Save).
//

import SwiftUI

struct TellAIRecipeView: View {
    let apiClient: APIClient
    var onSave: (Recipe) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State private var text: String = ""
    @State private var service: RecipeParserService?
    @State private var isParsing: Bool = false
    @State private var errorText: String?

    @FocusState
    private var textFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                Text("Describe your recipe — ingredients with amounts, then steps. The AI will structure it.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.screenEdge)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextTertiary)
                            .padding(.horizontal, TempoSpacing.md + 4)
                            .padding(.vertical, TempoSpacing.md + 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, TempoSpacing.md)
                        .padding(.vertical, TempoSpacing.md)
                        .focused($textFocused)
                        .disabled(isParsing)
                }
                .frame(minHeight: 220)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous)
                        .stroke(Color.tempoBorder, lineWidth: 1)
                )
                .padding(.horizontal, TempoSpacing.screenEdge)

                if let errorText {
                    Text(errorText)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .padding(.horizontal, TempoSpacing.screenEdge)
                }

                Spacer()
            }
            .padding(.vertical, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Tell AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isParsing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await parseAndSave() }
                    } label: {
                        if isParsing {
                            ProgressView()
                        } else {
                            Text("Parse & Save")
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || isParsing)
                }
            }
            .onAppear { textFocused = true }
        }
    }

    private var placeholder: String {
        """
        Pasta carbonara, serves 2.
        Ingredients: 200g spaghetti, 100g pancetta, 2 eggs, 40g pecorino, pepper.
        Steps: Boil pasta 10 min. Render pancetta crisp, ~6 min. Whisk eggs + pecorino. Drain pasta, toss off heat with pancetta + egg sauce. Finish with cracked pepper.
        """
    }

    @MainActor
    private func parseAndSave() async {
        guard !isParsing else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        textFocused = false
        isParsing = true
        errorText = nil
        defer { isParsing = false }

        let svc = service ?? RecipeParserService(apiClient: apiClient)
        service = svc
        do {
            let recipe = try await svc.parse(trimmed)
            onSave(recipe)
            dismiss()
        } catch {
            errorText = (error as? RecipeParseError)?.errorDescription
                ?? error.localizedDescription
            HapticManager.notification(.error)
        }
    }
}
