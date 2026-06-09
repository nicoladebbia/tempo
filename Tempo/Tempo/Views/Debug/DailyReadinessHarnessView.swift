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

    @State private var running = false
    @State private var output = "Tap Run to fire ~20 synthetic pictures through the real Haiku endpoint.\n\nThis spends up to 20 Haiku calls. Read the verdict before starting D1."
    @State private var verdict = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("D0 Prompt Harness")
                .font(.title2.bold())
            Text("Proves Haiku returns sensible, parseable sessions before D1 is built. ≤20 Haiku calls/run.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task { await run() }
            } label: {
                HStack {
                    if running { ProgressView().padding(.trailing, 4) }
                    Text(running ? "Running…" : "Run harness (≤20 Haiku calls)")
                }
            }
            .disabled(running)
            .buttonStyle(.borderedProminent)

            if !verdict.isEmpty {
                Text(verdict)
                    .font(.headline)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(verdictColor.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            ScrollView {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .navigationTitle("D0 Harness")
    }

    private var verdictColor: Color {
        if verdict.contains("PASS") { return .green }
        if verdict.contains("FAIL") { return .red }
        return .orange
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
        lines.append("Longest shortWhy:                 \(result.maxShortWhyLen)/120 chars (now coerced if over)")
        lines.append("Anti-patterns passed:             \(result.antiPatternPassed)/\(result.antiPatternTotal)")
        lines.append("  └ PROMPT-ONLY gate (the real one): \(result.promptOnlyAntiPatternPassed)/\(result.promptOnlyAntiPatternTotal)  (floor-caught misses are safe by design)")
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
