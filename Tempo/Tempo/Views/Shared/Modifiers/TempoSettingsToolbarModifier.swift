import SwiftUI

enum TempoSymbols {
    static let settings = "gearshape"
}

struct TempoSettingsToolbarModifier: ViewModifier {

    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresented = true
                        HapticManager.lightImpact()
                    } label: {
                        Image(systemName: TempoSymbols.settings)
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextSecondary)
                            .frame(width: 44, height: 44, alignment: .trailing)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $isPresented) {
                NavigationStack {
                    DashboardSettingsView()
                }
            }
    }
}

private struct TempoSettingsToolbarStandalone: ViewModifier {

    @State private var isPresented = false

    func body(content: Content) -> some View {
        content.modifier(TempoSettingsToolbarModifier(isPresented: $isPresented))
    }
}

extension View {

    func tempoSettingsToolbar(isPresented: Binding<Bool>) -> some View {
        modifier(TempoSettingsToolbarModifier(isPresented: isPresented))
    }

    func tempoSettingsToolbar() -> some View {
        modifier(TempoSettingsToolbarStandalone())
    }
}
