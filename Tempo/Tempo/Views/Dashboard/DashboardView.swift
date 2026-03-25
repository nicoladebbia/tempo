import SwiftUI

struct DashboardView: View {

    var body: some View {
        NavigationStack {
            Text("Dashboard")
                .font(.tempoLargeTitle)
                .foregroundStyle(Color.tempoTextPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tempoBgPrimary)
                .navigationTitle("Dashboard")
        }
    }
}
