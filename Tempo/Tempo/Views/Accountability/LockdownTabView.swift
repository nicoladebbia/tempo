import SwiftUI

struct LockdownTabView: View {

    var body: some View {
        NavigationStack {
            Text("Lockdown")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tempoBgPrimary)
                .navigationTitle("Lockdown")
        }
    }
}
