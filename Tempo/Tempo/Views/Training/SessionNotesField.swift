//
// SessionNotesField.swift
// Tempo
//
// The athlete's own free-text notes on a workout (WorkoutPlan.userNotes) —
// entered on the summary or mid-session, shown in History. Writes straight
// to the model; the surrounding save (summary SAVE / active-session saves)
// persists it.
//

import SwiftUI

struct SessionNotesField: View {
    @Bindable
    var plan: WorkoutPlan

    private var text: Binding<String> {
        Binding(
            get: { plan.userNotes ?? "" },
            set: { plan.userNotes = $0.isEmpty ? nil : $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            Text("SESSION NOTES")
                .font(.tempoCaption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.tempoTextTertiary)
            TextField(
                "Crowded gym, tight shoulder, felt strong…",
                text: text,
                axis: .vertical
            )
            .lineLimit(2 ... 6)
            .font(.tempoBody)
            .foregroundStyle(Color.tempoTextPrimary)
            .padding(TempoSpacing.md)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
