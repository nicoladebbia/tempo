//
// MonthlyReviewView.swift
// Tempo
//
// D4 §17.1/§17.2 — the end-of-month ritual, as a sheet off the Training tab's
// due-card. Two states:
//   • Interview: the 5 questions + optional next-month emphasis (§14 manual
//     block choice — answered here because this is where he'd naturally set
//     it). Submit saves the row, applies the emphasis block, then fires the
//     once-a-month Sonnet summary.
//   • Report: the generated summary text (re-opened any time in the window).
// A failed summary call leaves the interview saved and the month still due —
// the next open retries without re-asking the questions.
//

import SwiftData
import SwiftUI

// MARK: - MonthlyReviewView

struct MonthlyReviewView: View {
    let monthKey: String
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var wentWell = ""
    @State
    private var struggles = ""
    @State
    private var niggles = ""
    @State
    private var subjectiveProgress = ""
    @State
    private var goalsNextMonth = ""
    @State
    private var chosenEmphasis: BlockEmphasis?
    @State
    private var isGenerating = false
    @State
    private var summaryText: String?
    @State
    private var generationFailed = false
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @ScaledMetric(relativeTo: .title)
    private var scaledRing = TideTrain.debriefRing

    /// The ring grows with the text in it, but not past a third more.
    private var ringSize: CGFloat {
        min(scaledRing, TideTrain.debriefRing * 1.4)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    if let summary = summaryText {
                        reportSection(summary)
                    } else {
                        interviewSection
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                if summaryText == nil {
                    submitButton
                        .padding(.horizontal, Tide.edge)
                        .padding(.bottom, Tide.s3)
                }
            }
            .trainSheetRoot()
            .navigationTitle(monthDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Tide.body)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .onAppear(perform: seedFromExisting)
        }
    }

    // MARK: - Interview (§17.1)

    private var interviewSection: some View {
        VStack(alignment: .leading, spacing: Tide.s5) {
            debriefHero

            MonthlyReviewQuestion(
                number: 1,
                title: String(localized: "What went well?"),
                text: $wentWell,
                placeholder: String(localized: "Streaks, sessions that clicked, habits that held…")
            )
            MonthlyReviewQuestion(
                number: 2,
                title: String(localized: "What did you skip — and why?"),
                text: $struggles,
                placeholder: String(localized: "The honest version. PS5 nights count.")
            )
            MonthlyReviewQuestion(
                number: 3,
                title: String(localized: "Injuries or niggles?"),
                text: $niggles,
                placeholder: String(localized: "Anything next month's plan should route around.")
            )
            MonthlyReviewQuestion(
                number: 4,
                title: String(localized: "Feel different?"),
                text: $subjectiveProgress,
                placeholder: String(localized: "Faster, stronger, leaner — what no sensor sees.")
            )
            MonthlyReviewQuestion(
                number: 5,
                title: String(localized: "Goals for next month?"),
                text: $goalsNextMonth,
                placeholder: String(localized: "Concrete beats vague.")
            )

            VStack(alignment: .leading, spacing: Tide.s3) {
                HStack(spacing: Tide.s3) {
                    TideIconTile(systemName: "flag.fill", tint: TideTrain.violet)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text("Next month's emphasis")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Optional. The plan leans this way.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }
                // Two across (one at the accessibility sizes) so no name has to shrink.
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: Tide.s2),
                        count: typeSize.isAccessibilitySize ? 1 : 2
                    ),
                    spacing: Tide.s2
                ) {
                    emphasisButton(nil, label: String(localized: "Keep current"))
                    ForEach(BlockEmphasis.allCases, id: \.self) { e in
                        emphasisButton(e, label: e.displayName)
                    }
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

            if generationFailed {
                TrainBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    label: String(localized: "Saved"),
                    tint: TideTrain.caution,
                    message: String(localized: "Interview saved. Report generation failed — it'll retry next time you open the app.")
                ) {}
            }
        }
    }

    /// The ring fills as the five questions get answered.
    private var debriefHero: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s4))
            : AnyLayout(HStackLayout(spacing: Tide.s5))
        return layout {
            TrainRing(progress: Double(answeredCount) / 5, tint: TideTrain.violet, diameter: ringSize) {
                VStack(spacing: Tide.hair) {
                    TideNumber("\(answeredCount)/5", size: Tide.numeralS, relativeTo: .title2)
                        .contentTransition(.numericText())
                    if !typeSize.isAccessibilitySize {
                        Text("answered").tideLabel()
                            .lineLimit(1)
                            .minimumScaleFactor(Tide.labelShrink)
                    }
                }
            }
            VStack(alignment: .leading, spacing: Tide.s2) {
                Text("Month's over. debrief.").tideLabel(Tide.text3)
                Text(monthDisplayName)
                    .font(Tide.title)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(typeSize.isAccessibilitySize
                    ? String(localized: "\(answeredCount) of 5 answered")
                    : String(localized: "Five honest answers. The plan reads them."))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
                TrainSetTicks(done: answeredCount, total: 5, label: String(localized: "Questions"))
                    .padding(.top, Tide.s1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Tide.snap, value: answeredCount)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Month's over. debrief.")
        .accessibilityValue("\(answeredCount) of 5 answered")
    }

    /// File the report sits in the thumb zone and shows its own progress.
    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: Tide.s2) {
                if isGenerating {
                    ProgressView().tint(Tide.ink)
                }
                Text(isGenerating ? String(localized: "Writing your report…") : String(localized: "File the report"))
            }
            .frame(maxWidth: .infinity, minHeight: TideTrain.bigButton - Tide.s2)
        }
        .buttonStyle(.tidePrimary)
        .disabled(isGenerating)
    }

    private func emphasisButton(_ value: BlockEmphasis?, label: String) -> some View {
        Button {
            chosenEmphasis = value
            HapticManager.selection()
        } label: {
            Text(label)
                .font(Tide.bodyStrong)
                .lineLimit(1)
                .minimumScaleFactor(Tide.labelShrink)
                .frame(maxWidth: .infinity, minHeight: TideTrainSession.choiceHeight)
        }
        .buttonStyle(.trainChoice(isSelected: chosenEmphasis == value))
    }

    // MARK: - Report (§17.2)

    private func reportSection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(spacing: Tide.s3) {
                TideIconTile(systemName: "doc.text.fill", tint: TideTrain.violet, size: TideTrain.thumb)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("The report").tideLabel(Tide.text3)
                    Text(monthDisplayName)
                        .font(Tide.title)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            // Paragraph by paragraph, so a long report breathes.
            VStack(alignment: .leading, spacing: Tide.s3) {
                ForEach(Array(paragraphs(of: summary).enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private func paragraphs(of text: String) -> [String] {
        let parts = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? [text] : parts
    }

    /// How many of the five questions have an answer.
    private var answeredCount: Int {
        [wentWell, struggles, niggles, subjectiveProgress, goalsNextMonth]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count
    }

    // MARK: - Actions

    private func seedFromExisting() {
        guard let review = viewModel.fetchMonthlyReview(monthKey: monthKey, modelContext: modelContext) else {
            return
        }
        wentWell = review.wentWell ?? ""
        struggles = review.struggles ?? ""
        niggles = review.niggles ?? ""
        subjectiveProgress = review.subjectiveProgress ?? ""
        goalsNextMonth = review.goalsNextMonth ?? ""
        chosenEmphasis = review.chosenEmphasis
        summaryText = review.summaryText
    }

    private func submit() async {
        isGenerating = true
        generationFailed = false
        defer { isGenerating = false }

        let review = viewModel.fetchOrCreateMonthlyReview(monthKey: monthKey, modelContext: modelContext)
        review.wentWell = blankToNil(wentWell)
        review.struggles = blankToNil(struggles)
        review.niggles = blankToNil(niggles)
        review.subjectiveProgress = blankToNil(subjectiveProgress)
        review.goalsNextMonth = blankToNil(goalsNextMonth)
        review.chosenEmphasis = chosenEmphasis
        modelContext.saveOrAlert("monthly review")

        viewModel.applyMonthlyEmphasisChoice(review, modelContext: modelContext)

        if await viewModel.generateMonthlySummary(for: review, modelContext: modelContext) {
            summaryText = review.summaryText
        } else {
            generationFailed = true
        }
    }

    private func blankToNil(_ s: String) -> String? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var monthDisplayName: String {
        guard let interval = MonthlyReviewSchedule.monthInterval(forKey: monthKey) else {
            return monthKey
        }
        return interval.start.formatted(.dateTime.month(.wide).year())
    }
}

// MARK: - MonthlyReviewQuestion

/// One interview question: a numbered card with a Tide text field that rings
/// up while focused. The number turns into a tick once there is an answer.
private struct MonthlyReviewQuestion: View {
    let number: Int
    let title: String
    @Binding
    var text: String
    let placeholder: String

    @FocusState
    private var focused: Bool
    @Environment(\.tideMood)
    private var mood

    private var isAnswered: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                Image(systemName: isAnswered ? "checkmark.circle.fill" : "\(number).circle")
                    .font(Tide.headline)
                    .foregroundStyle(isAnswered ? mood.accent : Tide.text3)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(2 ... 4)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .focused($focused)
                .tideFieldSurface(focused: focused)
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .animation(Tide.snap, value: isAnswered)
    }
}
