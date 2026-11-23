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
    @Environment(\.tideMood)
    private var mood
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
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text("What did you eat?").tideLabel()
                HStack(spacing: Tide.s2) {
                    TextField("2 eggs, toast with butter", text: $text, axis: .vertical)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .lineLimit(1 ... 4)
                        .fuelField()
                        .focused($focused)
                        .submitLabel(.send)
                        .onSubmit(submit)
                        .disabled(isParsing)
                        .accessibilityIdentifier("quickLogField")
                    Button(action: submit) {
                        Group {
                            if isParsing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(Tide.title)
                                    .foregroundStyle(canSubmit ? mood.accent : Tide.text3)
                            }
                        }
                        .frame(width: Tide.hit, height: Tide.hit)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .accessibilityLabel("Parse")
                    .accessibilityIdentifier("quickLogGo")
                }
                if let message {
                    Text(message)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Add a time or meal if you like: \"pasta at 1pm\", \"yesterday dinner\".")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s5)
            .tidePage()
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
