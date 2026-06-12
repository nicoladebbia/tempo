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

struct MonthlyReviewView: View {
    let monthKey: String
    var viewModel: TrainingViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var wentWell = ""
    @State private var struggles = ""
    @State private var niggles = ""
    @State private var subjectiveProgress = ""
    @State private var goalsNextMonth = ""
    @State private var chosenEmphasis: BlockEmphasis?
    @State private var isGenerating = false
    @State private var summaryText: String?
    @State private var generationFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xl) {
                    if let summary = summaryText {
                        reportSection(summary)
                    } else {
                        interviewSection
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.vertical, TempoSpacing.lg)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle(monthDisplayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.tempoCallout)
                        .foregroundStyle(Color.tempoSignal)
                }
            }
            .onAppear(perform: seedFromExisting)
        }
    }

    // MARK: - Interview (§17.1)

    private var interviewSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            Text("MONTH'S OVER. DEBRIEF.")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            question("What went well?", text: $wentWell,
                     placeholder: "Streaks, sessions that clicked, habits that held…")
            question("What did you skip — and why?", text: $struggles,
                     placeholder: "The honest version. PS5 nights count.")
            question("Injuries or niggles?", text: $niggles,
                     placeholder: "Anything next month's plan should route around.")
            question("Feel different?", text: $subjectiveProgress,
                     placeholder: "Faster, stronger, leaner — what no sensor sees.")
            question("Goals for next month?", text: $goalsNextMonth,
                     placeholder: "Concrete beats vague.")

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("Next month's emphasis")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                HStack(spacing: TempoSpacing.sm) {
                    emphasisButton(nil, label: "Keep current")
                    ForEach(BlockEmphasis.allCases, id: \.self) { e in
                        emphasisButton(e, label: e.displayName)
                    }
                }
            }

            if generationFailed {
                Text("Interview saved. Report generation failed — it'll retry next time you open the app.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoWarning)
            }

            Button {
                Task { await submit() }
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView().tint(.white)
                    }
                    Text(isGenerating ? "WRITING YOUR REPORT…" : "FILE THE REPORT")
                        .font(.tempoHeadline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .disabled(isGenerating)
        }
    }

    private func question(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(title)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2 ... 4)
                .padding(TempoSpacing.cardPadding)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
    }

    private func emphasisButton(_ value: BlockEmphasis?, label: String) -> some View {
        Button {
            chosenEmphasis = value
            HapticManager.selection()
        } label: {
            Text(label)
                .font(.tempoCallout)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(chosenEmphasis == value ? Color.tempoSignal : Color.tempoSurfaceCard)
                .foregroundStyle(chosenEmphasis == value ? .white : Color.tempoTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
        }
    }

    // MARK: - Report (§17.2)

    private func reportSection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.lg) {
            Text("THE REPORT")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            Text(summary)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
                .padding(TempoSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
    }

    // MARK: - Actions

    private func seedFromExisting() {
        guard let review = viewModel.fetchMonthlyReview(monthKey: monthKey, modelContext: modelContext) else { return }
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
        try? modelContext.save()

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
        guard let interval = MonthlyReviewSchedule.monthInterval(forKey: monthKey) else { return monthKey }
        return interval.start.formatted(.dateTime.month(.wide).year())
    }
}
