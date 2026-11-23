//
// CoachInterviewView.swift
// Tempo
//
// Coach v2.1 Phase 7.5 — six-question interview that runs once before
// the first Coach chat. Each question is individually skippable; the
// global "Skip rest" closes the interview with whatever priors the user
// has already given.
//
// One question at a time, answers as glass rows, one filled button.
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
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Called after persist completes. Caller decides what to do next —
    /// typically: dismiss the sheet and route to Coach chat.
    let onComplete: (CoachInterviewService.RunReport) -> Void

    @State private var answers = CoachInterviewAnswers()
    @State private var currentQuestion = 1
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var picks = 0

    private let totalQuestions = 6

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s6) {
                    progressBar
                    questionBlock
                        .id(currentQuestion)
                        .transition(questionTransition)
                }
                .animation(reduceMotion ? nil : Tide.snap, value: currentQuestion)
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .safeAreaBar(edge: .top, spacing: 0) {
                header
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                footer
            }
            .tidePage()
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sensoryFeedback(.selection, trigger: picks)
        }
        .alert("Couldn't save", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var questionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .offset(x: Tide.s6)), removal: .opacity)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            skipButton("Skip rest") { skipRest() }
            Spacer(minLength: Tide.s2)
            if currentQuestion < totalQuestions {
                skipButton("Skip this") { advanceWithoutAnswer() }
            }
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s4)
    }

    private func skipButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text2)
                .frame(minWidth: Tide.hit, minHeight: Tide.hit)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Progress

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Question \(currentQuestion) of \(totalQuestions)").tideLabel()
            TideLevelBar(progress: Double(currentQuestion) / Double(totalQuestions), height: Tide.bar)
                .animation(reduceMotion ? nil : Tide.settle, value: currentQuestion)
        }
        .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: Tide.s3) {
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
        VStack(alignment: .leading, spacing: Tide.s3) {
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
        VStack(alignment: .leading, spacing: Tide.s3) {
            questionTitle("What should I track silently?")
            hint("Choose any that apply.")
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
        VStack(alignment: .leading, spacing: Tide.s3) {
            questionTitle("What's a habit you've tried and failed at?")
            hint("Optional. I'll never suggest it.")
            TextField(
                text: Binding(
                    get: { answers.failedHabit ?? "" },
                    set: { answers.failedHabit = $0 }
                ),
                prompt: Text("e.g. intermittent fasting").foregroundStyle(Tide.text3)
            ) {
                Text("A habit you tried and failed at")
            }
            .textInputAutocapitalization(.sentences)
            .tideCoachField()
        }
    }

    // MARK: - Q5

    private var hardDayQuestion: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            questionTitle("On a hard day, what should I never suggest?")
            hint("Optional.")
            TextField(
                text: Binding(
                    get: { answers.hardDayNeverSuggest ?? "" },
                    set: { answers.hardDayNeverSuggest = $0 }
                ),
                prompt: Text("e.g. cold showers, big breakfasts").foregroundStyle(Tide.text3)
            ) {
                Text("What to never suggest on a hard day")
            }
            .textInputAutocapitalization(.sentences)
            .tideCoachField()
        }
    }

    // MARK: - Q6

    private var scheduleQuestion: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            questionTitle("Anything weird about your schedule?")
            hint("e.g. shift work, fasting on Fridays, dual time zones, religious schedule…")
            TextField(
                text: Binding(
                    get: { answers.scheduleException ?? "" },
                    set: { answers.scheduleException = $0 }
                ),
                prompt: Text("Optional").foregroundStyle(Tide.text3),
                axis: .vertical
            ) {
                Text("Anything unusual about your schedule")
            }
            .lineLimit(3 ... 6)
            .textInputAutocapitalization(.sentences)
            .tideCoachField()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        Button(currentQuestion == totalQuestions ? "Start chat" : "Continue") {
            if currentQuestion == totalQuestions {
                saveAndComplete()
            } else {
                currentQuestion += 1
            }
        }
        .buttonStyle(.tidePrimary)
        .disabled(isSaving)
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s2)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Helpers

    private func questionTitle(_ text: String) -> some View {
        Text(text)
            .font(Tide.title)
            .foregroundStyle(Tide.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .padding(.bottom, Tide.s1)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(Tide.body)
            .foregroundStyle(Tide.text2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func radioRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        TideCoachOptionRow(label: label, isSelected: isSelected, mark: .radio) {
            picks += 1
            action()
        }
    }

    private func multiSelectRow(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        TideCoachOptionRow(label: label, isSelected: isSelected, mark: .check) {
            picks += 1
            action()
        }
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
