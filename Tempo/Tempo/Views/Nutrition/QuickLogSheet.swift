//
// QuickLogSheet.swift
// Tempo
//
// Today's Quick Log: type what you ate, and the Confirm Meal sheet opens on
// top of this one. You never leave Today (no jump to the Log tab); once the
// meal is saved both sheets close and the toast shows on Today.
//

import SwiftUI

struct QuickLogSheet: View {
    @Environment(\.dismiss)
    private var dismiss
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var text = ""
    @State
    private var isParsing = false
    @State
    private var request: MealReviewRequest?
    @State
    private var message: String?
    @State
    private var aiBlocker: AIBlocker?
    @FocusState
    private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Text("WHAT DID YOU EAT?")
                    .font(.tempoModuleTag)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)
                HStack(spacing: TempoSpacing.sm) {
                    TextField("2 eggs, toast with butter", text: $text, axis: .vertical)
                        .font(.tempoBody)
                        .lineLimit(1 ... 4)
                        .padding(.horizontal, TempoSpacing.md)
                        .frame(minHeight: 48)
                        .background(Color.tempoBgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(submit)
                        .disabled(isParsing)
                        .accessibilityIdentifier("quickLogField")
                    Button(action: submit) {
                        if isParsing {
                            ProgressView().frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(canSubmit ? Color.tempoSignal : Color.tempoTextDisabled)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .disabled(!canSubmit)
                    .accessibilityLabel("Parse")
                    .accessibilityIdentifier("quickLogGo")
                }
                if let message {
                    Text(message)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Text("Add a time or meal if you like: \"pasta at 1pm\", \"yesterday dinner\".")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                Spacer()
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Quick Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
            .mealReview($request) { dismiss() }
            .aiBlockerAlert($aiBlocker) { submit() }
        }
        .presentationDetents([.medium, .large])
    }

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty && !isParsing
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isParsing else {
            return
        }
        HapticManager.lightImpact()
        focused = false
        message = nil
        isParsing = true
        Task {
            defer { isParsing = false }
            do {
                if let parsed = try await MealReviewRequest.parsing(trimmed, apiClient: services.apiClient) {
                    request = parsed
                } else {
                    message = "Couldn't parse that. Try being more specific."
                }
            } catch {
                if let blocker = AIBlocker(error) {
                    aiBlocker = blocker
                } else {
                    message = "Couldn't parse that: \(AIBlocker.message(for: error))"
                }
            }
        }
    }
}
