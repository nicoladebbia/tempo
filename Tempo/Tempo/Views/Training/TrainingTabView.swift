import SwiftUI

struct TrainingTabView: View {

    var body: some View {
        NavigationStack {
            Text("Training")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tempoBgPrimary)
                .navigationTitle("Training")
        }
    }
}
