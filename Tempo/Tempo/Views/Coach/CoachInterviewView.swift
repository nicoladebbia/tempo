//
// CoachInterviewView.swift
// Tempo
//
// Coach v2.1 Phase 7.5 — six-question interview that runs once before
// the first Coach chat. Each question is individually skippable; the
// global "Skip rest" closes the interview with whatever priors the user
// has already given.
//
// Per .plans/coach-v2.1/05-ui-surfaces.md §1.
//

import SwiftData
import SwiftUI

// MARK: - CoachInterviewView

struct CoachInterviewView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    /// Called after persist completes. Caller decides what to do next —
    /// typically: dismiss the sheet and route to Coach chat.
    let onComplete: (CoachInterviewService.RunReport) -> Void

    @State private var answers = CoachInterviewAnswers()
    @State private var currentQuestion = 1
    @State private var isSaving = false
    @State private var saveError: String?

    private let totalQuestions = 6

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                progressBar
                ScrollView {
                    VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                        questionBlock
                    }
                    .padding(.horizontal, TempoSpacing.screenEdge)
                    .padding(.top, TempoSpacing.xl)
                    .padding(.bottom, TempoSpacing.xxxxl)
                }
                Spacer()
                footer
            }
            .background(Color.tempoBgPrimary)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Skip rest") { skipRest() }
                .buttonStyle(.tempoGhost)

            Spacer()

            if currentQuestion < totalQuestions {
                Button("Skip this") { advanceWithoutAnswer() }
                    .buttonStyle(.tempoGhost)
            }
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Progress

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("Question \(currentQuestion) of \(totalQuestions)")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.tempoSurfaceCard)
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.tempoSignal)
                        .frame(
                            width: proxy.size.width * CGFloat(currentQuestion) / CGFloat(totalQuestions),
                            height: 4
                        )
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Question dispatch

    @ViewBuilder
    private var questionBlock: some View {
        switch currentQuestion {
        case 1: tiredModeQuestion
        case 2: toneQuestion
        case 3: silentTrackQuestion
        case 4: failedHabitQuestion
        case 5: hardDayQuestion
        case 6: scheduleQuestion
        default: EmptyView()
        }
    }

    // MARK: - Q1

    private var tiredModeQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("When you're tired, do you want me to…")
            ForEach(TiredMode.allCases, id: \.self) { mode in
                radioRow(
                    label: mode.displayName,
                    isSelected: answers.tiredMode == mode
                ) {
                    answers.tiredMode = mode
                }
            }
        }
    }

    // MARK: - Q2

    private var toneQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("Pick your tone")
            ForEach(TonePreference.allCases, id: \.self) { tone in
                radioRow(
                    label: tone.displayName,
                    isSelected: answers.tonePreference == tone
                ) {
                    answers.tonePreference = tone
                }
            }
        }
    }

    // MARK: - Q3

    private var silentTrackQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("What should I track silently?")
            Text("Choose any that apply.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            ForEach(SilentTrackOption.allCases, id: \.self) { option in
                multiSelectRow(
                    label: option.displayName,
                    isSelected: answers.silentTrack.contains(option)
                ) {
                    if answers.silentTrack.contains(option) {
                        answers.silentTrack.remove(option)
                    } else {
                        answers.silentTrack.insert(option)
                    }
                }
            }
        }
    }

    // MARK: - Q4

    private var failedHabitQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("What's a habit you've tried and failed at?")
            Text("Optional — I'll never suggest it.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField(
                "e.g. intermittent fasting",
                text: Binding(
                    get: { answers.failedHabit ?? "" },
                    set: { answers.failedHabit = $0 }
                )
            )
            .textInputAutocapitalization(.sentences)
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Q5

    private var hardDayQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("On a hard day, what should I NEVER suggest?")
            Text("Optional.")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField(
                "e.g. cold showers, big breakfasts",
                text: Binding(
                    get: { answers.hardDayNeverSuggest ?? "" },
                    set: { answers.hardDayNeverSuggest = $0 }
                )
            )
            .textInputAutocapitalization(.sentences)
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Q6

    private var scheduleQuestion: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            questionTitle("Anything weird about your schedule?")
            Text("e.g. shift work, fasting on Fridays, dual time zones, religious schedule…")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField(
                "Optional",
                text: Binding(
                    get: { answers.scheduleException ?? "" },
                    set: { answers.scheduleException = $0 }
                ),
                axis: .vertical
            )
            .lineLimit(3...6)
            .textInputAutocapitalization(.sentences)
            .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: TempoSpacing.sm) {
            Button(currentQuestion == totalQuestions ? "Start Chat" : "Continue") {
                if currentQuestion == totalQuestions {
                    saveAndComplete()
                } else {
                    currentQuestion += 1
                }
            }
            .buttonStyle(.tempoPrimary)
            .disabled(isSaving)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.bottom, TempoSpacing.bottomSafe)
    }

    // MARK: - Helpers

    private func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(.tempoTitle2)
            .foregroundStyle(Color.tempoTextPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func radioRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextTertiary)
                    .imageScale(.large)
                Text(label)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
            }
            .padding(.vertical, TempoSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func multiSelectRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.tempoSignal : Color.tempoTextTertiary)
                    .imageScale(.large)
                Text(label)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
            }
            .padding(.vertical, TempoSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func advanceWithoutAnswer() {
        clearAnswerForCurrentQuestion()
        if currentQuestion < totalQuestions {
            currentQuestion += 1
        } else {
            saveAndComplete()
        }
    }

    private func clearAnswerForCurrentQuestion() {
        switch currentQuestion {
        case 1: answers.tiredMode = nil
        case 2: answers.tonePreference = nil
        case 3: answers.silentTrack.removeAll()
        case 4: answers.failedHabit = nil
        case 5: answers.hardDayNeverSuggest = nil
        case 6: answers.scheduleException = nil
        default: break
        }
    }

    private func skipRest() {
        // "Skip rest" closes immediately. Whatever's already been answered
        // (in `answers`) is persisted; if nothing answered, the persist
        // call records the skip flag instead.
        saveAndComplete()
    }

    private func saveAndComplete() {
        isSaving = true
        defer { isSaving = false }
        do {
            let report = try CoachInterviewService.persist(answers: answers, in: modelContext)
            onComplete(report)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
