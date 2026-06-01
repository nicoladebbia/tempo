//
// RecoveryAIInsightView.swift
// Tempo
//
// Renders the AI-generated personalised daily recovery paragraph (Haiku),
// replacing the old static 2-day prescription text. Shows a loading skeleton
// while the proxy call is in flight; the result is cached per calendar day by
// RecoveryAIInsightService so re-appearances do not re-call the API.
//

import SwiftData
import SwiftUI

struct RecoveryAIInsightView: View {
    let recovery: DailyRecovery?

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    // Shared, long-lived instance from the container — NOT per-view. Its
    // per-day single-flight dedup must survive this view's remounts.
    private var service: RecoveryAIInsightService { services.recoveryInsight }
    @State private var paragraph: String?
    @State private var isLoading = false
    @State private var errorText: String?

    // Weekly recap (Mondays only). nil until loaded / not Monday.
    @State private var weeklyRecap: String?
    @State private var isLoadingWeekly = false

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xl) {
            // Weekly recap first (reflection on last week), Mondays only.
            if isLoadingWeekly || weeklyRecap != nil {
                VStack(alignment: .leading, spacing: TempoSpacing.md) {
                    TempoSectionHeader("Last Week", accentColor: Color.tempoSignal)
                    insightCard {
                        if isLoadingWeekly {
                            loadingSkeleton
                        } else if let weeklyRecap {
                            Text(weeklyRecap)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Daily read (action for today).
            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                HStack {
                    TempoSectionHeader("Today's Read", accentColor: Color.tempoSignal)
                    #if DEBUG
                    // DEBUG-only: each tap is a paid Haiku call. Never ship
                    // to users — they'd spam it and drive API cost up. The
                    // per-day cache is the cost control in release builds.
                    Spacer()
                    if let state = service.lastFinalState {
                        Text(state.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(badgeColor(for: state))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: state).opacity(0.15))
                            .clipShape(Capsule())
                            .accessibilityLabel("Insight state: \(state.rawValue)")
                    }
                    Button {
                        Task { await regenerate() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.tempoFootnote)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Regenerate today's read")
                    #endif
                }
                insightCard {
                    if isLoading {
                        loadingSkeleton
                    } else if let paragraph {
                        Text(paragraph)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let errorText {
                        Text(errorText)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    } else {
                        Text("Connect WHOOP to get today's personalised read.")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
            }
        }
        .task(id: recovery?.id) {
            // Sequential, not concurrent — avoids two Haiku calls racing in
            // the same task on a Monday cache-miss.
            await loadWeeklyRecap()
            await load()
        }
    }

    #if DEBUG
    // Pure UI helper for the DEBUG-only final-state badge. Keeping it inside
    // an #if guard so it doesn't ship to release builds.
    private func badgeColor(for state: RecoveryAIInsightService.FinalState) -> Color {
        switch state {
        case .cacheHit: return Color.tempoTextSecondary
        case .apiSuccess: return Color.tempoSignal
        case .cancelled: return Color.tempoWarning
        case .failed: return Color.tempoError
        }
    }
    #endif

    @ViewBuilder
    private func insightCard(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(TempoSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            .tempoShadow(.card)
    }

    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            ForEach(0 ..< 4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.tempoTextTertiary.opacity(0.18))
                    .frame(height: 12)
                    .frame(maxWidth: i == 3 ? 180 : .infinity)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Generating today's recovery insight")
    }

    @MainActor
    private func load() async {
        guard let recovery else { return }

        let svc = service

        // Cache hit → no spinner, no API call.
        if let cached = svc.cachedParagraph(modelContext: modelContext) {
            paragraph = cached
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            paragraph = try await svc.paragraph(for: recovery, modelContext: modelContext)
        } catch is CancellationError {
            // View was torn down or task replaced — a fresh call will run
            // on re-appear. Don't surface a stale "cancelled" error.
        } catch {
            errorText = (error as? RecoveryAIInsightError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    @MainActor
    private func regenerate() async {
        guard let recovery, !isLoading else { return }

        let svc = service

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            paragraph = try await svc.regenerateToday(for: recovery, modelContext: modelContext)
        } catch is CancellationError {
            // Same suppression as load() — the successor call (if any) will
            // populate paragraph; no need to show a transient error.
        } catch {
            errorText = (error as? RecoveryAIInsightError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    @MainActor
    private func loadWeeklyRecap() async {
        let svc = service

        isLoadingWeekly = true
        defer { isLoadingWeekly = false }

        // Returns nil when it isn't Monday or there's <3 days of data —
        // the card simply doesn't render in that case.
        weeklyRecap = try? await svc.weeklyRecap(modelContext: modelContext)
    }
}
