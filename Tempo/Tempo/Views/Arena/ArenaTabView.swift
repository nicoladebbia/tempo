import SwiftUI

struct ArenaTabView: View {

    var body: some View {
        NavigationStack {
            Text("Arena")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tempoBgPrimary)
                .navigationTitle("Arena")
        }
    }
}
