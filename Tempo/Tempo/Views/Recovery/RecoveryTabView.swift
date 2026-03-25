import SwiftUI

struct RecoveryTabView: View {

    var body: some View {
        NavigationStack {
            Text("Recovery")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tempoBgPrimary)
                .navigationTitle("Recovery")
        }
    }
}
