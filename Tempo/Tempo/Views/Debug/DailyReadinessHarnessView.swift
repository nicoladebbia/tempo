//
// DailyReadinessHarnessView.swift
// Tempo
//
// DEBUG-only host for the D0 prompt-harness spike (docs/INTELLIGENT_TRAINING_SYSTEM.md §5.2-FIX).
// Runs ~20 synthetic ReadinessPictures through the REAL Haiku proxy using the
// running app's authed APIClient (the harness CANNOT run from an XCTest — no
// Pro-authed token on the sim → every call 402s, which would be misread as a
// prompt failure). One button → run → scrollable verdict + per-fixture failures.
//
// COST CEILING (§10): one run = at most 20 Haiku calls, DEBUG-only, manual trigger.
// Never wired to a render loop, never ships to release.
//
// READ THE VERDICT HONESTLY:
//   • If the FIRST call doesn't parse → STOP, it's environment (auth/consent/402),
//     not the prompt.
//   • PASS = ≥19/20 sensible-unaided AND all anti-patterns clean.
//   • 16–18 = borderline, re-run (Haiku is nondeterministic).
//   • ≤15 or any anti-pattern fail = architecture in question, STOP, do not start D1.
//

#if DEBUG
    import SwiftUI

    struct DailyReadinessHarnessView: View {
        @Environment(ServiceContainer.self) private var services
        @Environment(\.tideMood) private var mood

        @State private var running = false
        @State private var output = "Tap Run to fire ~20 synthetic pictures through the real Haiku endpoint.\n\nThis spends up to 20 Haiku calls. Read the verdict before starting D1."
        @State private var verdict = ""

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Tide.s4) {
                    VStack(alignment: .leading, spacing: Tide.s1) {
                        Text("D0 prompt harness")
                            .font(Tide.title)
                            .foregroundStyle(Tide.text)
                            .accessibilityAddTraits(.isHeader)
                        Text("Proves Haiku returns sensible, parseable sessions before D1 is built. Up to 20 Haiku calls per run.")
                            .font(Tide.body)
                            .foregroundStyle(Tide.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        Task { await run() }
                    } label: {
                        HStack(spacing: Tide.s2) {
                            if running {
                                ProgressView().tint(Tide.ink)
                            }
                            Text(running ? "Running…" : "Run harness (≤20 Haiku calls)")
                        }
                    }
                    .disabled(running)
                    .buttonStyle(.tidePrimary)

                    if !verdict.isEmpty {
                        Text(verdict)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Tide.s4)
                            .glassEffect(.regular.tint(verdictColor.opacity(0.28)), in: .rect(cornerRadius: Tide.tileRadius))
                    }

                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Tide.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
                }
                .padding(.horizontal, Tide.edge)
                .padding(.top, Tide.s2)
                .padding(.bottom, Tide.s8)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .tidePage()
            .navigationTitle("D0 Harness")
            .navigationBarTitleDisplayMode(.inline)
        }

        private var verdictColor: Color {
            if verdict.contains("PASS") {
                return mood.accent
            }
            if verdict.contains("FAIL") {
                return Tide.danger
            }
            return Tide.streak
        }

        @MainActor
        private func run() async {
            running = true
            defer { running = false }
            verdict = ""
            output = "Running…"

            let result = await DailyReadinessHarness.run(apiClient: services.apiClient)

            verdict = result.verdict
            var lines: [String] = []
            lines.append("PROMPT QUALITY (sensible unaided): \(result.sensibleUnaided)/\(result.total)")
            lines.append("Parsed cleanly:                   \(result.parsed)/\(result.total)")
            lines.append("Floor had to rescue:              \(result.floorRescued) (high = unsafe prompt)")
            lines.append("Longest shortWhy:                 \(result.maxShortWhyLen)/120 budget (shown in full; word-cut only past 240)")
            lines.append("Anti-patterns passed:             \(result.antiPatternPassed)/\(result.antiPatternTotal)")
            lines
                .append(
                    "  └ PROMPT-ONLY gate (the real one): \(result.promptOnlyAntiPatternPassed)/\(result.promptOnlyAntiPatternTotal)  (floor-caught misses are safe by design)"
                )
            lines.append("")
            if result.failures.isEmpty {
                lines.append("No failures. 🎯")
            } else {
                lines.append("FAILURES (triage: prompt-fail vs too-strict-judge):")
                lines.append(contentsOf: result.failures)
            }
            output = lines.joined(separator: "\n")
        }
    }
#endif
