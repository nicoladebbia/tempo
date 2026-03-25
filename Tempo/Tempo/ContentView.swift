import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "flame.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Tempo")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
