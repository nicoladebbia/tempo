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
        VStack(alignment: .leading, spacing: Tide.s1) {
            Text("Session notes").tideLabel(Tide.text3)
            TextField(
                "Crowded gym, tight shoulder, felt strong…",
                text: text,
                axis: .vertical
            )
            .lineLimit(2 ... 6)
            .font(Tide.body)
            .foregroundStyle(Tide.text)
            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
